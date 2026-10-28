import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/player.dart';

/// Owns the in-memory list of players and mediates all player CRUD between the
/// UI and the database. Keeps the list sorted (primary user first, then
/// alphabetical) and notifies listeners on every change.
///
/// Computer opponents are kept apart in [bots]: [players] is the roster of
/// people, which is what every list in the app shows, and a bot row only comes
/// into being through [botFor] when a game against that tier is set up.
class PlayersProvider extends ChangeNotifier {
  final DbHelper _db = DbHelper.instance;
  List<Player> _players = [];
  List<Player> _bots = [];
  bool _loaded = false;

  /// The current human players, sorted with the primary user first.
  List<Player> get players => _players;

  /// The computer opponents that have been played against so far, weakest
  /// tier first. A tier nobody has picked yet has no row and is not listed.
  List<Player> get bots => _bots;

  /// Whether the initial load from the database has completed.
  bool get loaded => _loaded;

  /// The device's primary user, or null if none set yet.
  Player? get primaryPlayer => _players.where((p) => p.isPrimary).firstOrNull;

  /// Loads all players from the database and marks the provider as loaded.
  Future<void> load() async {
    _players = await _db.getPlayers();
    _bots = await _db.getBots();
    _sort();
    _loaded = true;
    notifyListeners();
  }

  /// Creates and persists a new player, optionally making them the primary
  /// user, and returns the saved record with its assigned id.
  Future<Player> addPlayer(String name, {bool isPrimary = false}) async {
    final player = Player(name: name, isPrimary: isPrimary);
    final id = await _db.insertPlayer(player);
    if (isPrimary) await _db.setPrimaryPlayer(id);
    final saved = Player(id: id, name: name, isPrimary: isPrimary);
    // setPrimaryPlayer cleared the flag on every other row, so the list has to
    // follow or primaryPlayer keeps returning the old one until the next load.
    final existing = isPrimary
        ? _players.map((p) => p.copyWith(isPrimary: false)).toList()
        : _players;
    _players = [...existing, saved];
    _sort();
    notifyListeners();
    return saved;
  }

  /// Persists changes to [player] and refreshes it in the in-memory list.
  Future<void> updatePlayer(Player player) async {
    await _db.updatePlayer(player);
    _players = _players.map((p) => p.id == player.id ? player : p).toList();
    _sort();
    notifyListeners();
  }

  /// Makes [player] the primary user, clearing the flag on all others.
  Future<void> setPrimary(Player player) async {
    await _db.setPrimaryPlayer(player.id!);
    _players = _players
        .map((p) => p.copyWith(isPrimary: p.id == player.id))
        .toList();
    _sort();
    notifyListeners();
  }

  /// Deletes the player with [id] (soft-delete in the DB) and drops it from the list.
  Future<void> deletePlayer(int id) async {
    await _db.deletePlayer(id);
    _players = _players.where((p) => p.id != id).toList();
    notifyListeners();
  }

  /// The player row of the computer opponent numbered [ordinal] at [level],
  /// created on first use.
  ///
  /// One row per bot, shared by every game it plays in, so the second call
  /// returns the row the first one made rather than a twin. The ordinal
  /// counts from one; a game that wants two bots of one tier asks for one
  /// and two.
  Future<Player> botFor(BotLevel level, {int ordinal = 1}) async {
    assert(ordinal >= 1, 'bots are numbered from one');
    final existing = _bots
        .where((b) => b.botLevel == level && b.botOrdinal == ordinal)
        .firstOrNull;
    if (existing != null) return existing;
    final bot = Player(
      name: level.storedNameFor(ordinal),
      uuid: level.uuidFor(ordinal),
      botLevel: level,
      botOrdinal: ordinal,
    );
    final id = await _db.insertPlayer(bot);
    final saved = bot.copyWith(id: id);
    _bots = [..._bots, saved]..sort(_byTierAndNumber);
    notifyListeners();
    return saved;
  }

  /// Weakest tier first, numbered within it.
  static int _byTierAndNumber(Player a, Player b) {
    final byTier = a.botLevel!.index.compareTo(b.botLevel!.index);
    return byTier != 0 ? byTier : a.botOrdinal!.compareTo(b.botOrdinal!);
  }

  /// Returns the loaded player or bot with [id], or null if not present.
  Player? getById(int id) {
    try {
      return [..._players, ..._bots].firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Primary user always first, then alphabetical.
  void _sort() {
    _players.sort((a, b) {
      if (a.isPrimary && !b.isPrimary) return -1;
      if (!a.isPrimary && b.isPrimary) return 1;
      return comparePlayerNames(a.name, b.name);
    });
  }
}

/// Compares two player names the way a reader expects to find them in a list.
///
/// Not `String.compareTo`, which orders by code unit: that puts every capital
/// ahead of every lower case letter, so "anna" lands behind "Zoe", and sorts
/// the umlauts after "z" because they sit far up in the code space. Both are
/// wrong in a list of names, and both are common in German ones.
///
/// Umlauts are folded to their base letter (DIN 5007 variant 1, the ordering
/// used in dictionaries) and "ß" to "ss". The raw names decide any remaining
/// tie, so that two names differing only in case keep a stable order rather
/// than swapping around on every reload.
int comparePlayerNames(String a, String b) {
  final folded = _foldForSort(a).compareTo(_foldForSort(b));
  return folded != 0 ? folded : a.compareTo(b);
}

/// Lower cases [name] and folds the German letters that would otherwise sort
/// outside the alphabet.
String _foldForSort(String name) {
  const replacements = {
    'ä': 'a',
    'ö': 'o',
    'ü': 'u',
    'ß': 'ss',
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'å': 'a',
    'ã': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ø': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ñ': 'n',
    'ç': 'c',
  };
  final buffer = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString();
}
