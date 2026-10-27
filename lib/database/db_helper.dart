import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/player.dart';
import '../models/game.dart';
import '../models/dart_throw.dart';
import '../models/cricket_game.dart';
import '../models/shanghai_game.dart';
import '../models/around_the_clock_game.dart';
import '../models/checkout_ladder_game.dart' show CheckoutLadderGame, CheckoutLadderThrow;
import '../services/sync_service.dart' show SyncOrigin, kLegacyOrigin;
import '../utils/finish_calculator.dart';
import '../utils/game_winner.dart';
import '../utils/throw_stats.dart';

/// Singleton SQLite wrapper and the single point of database access for the app.
///
/// Holds all schema definitions and migrations and exposes typed CRUD methods
/// for players, X01 games/throws, the three extra game modes, and sync support.
/// No widget or provider should query SQLite directly; everything goes through
/// this class.
class DbHelper {
  static final DbHelper instance = DbHelper._();
  static Database? _db;

  /// Schema version this build knows how to open. A backup written at a higher
  /// version is refused rather than opened, see [inspectBackup].
  static const int schemaVersion = 27;

  /// Where the database file lives, overriding the platform default. Only set
  /// by tests, which point it at an in-memory database so each case starts on
  /// a fresh schema.
  @visibleForTesting
  static String? debugDatabasePath;

  DbHelper._();

  /// Closes the cached connection so the next access opens a new one. Only
  /// used by tests between cases; the app keeps one connection for its lifetime.
  @visibleForTesting
  static Future<void> debugReset() async {
    await _db?.close();
    _db = null;
  }

  /// The lazily-opened database instance, created on first access.
  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  /// Where the `dartscore.db` file lives on this device.
  Future<String> get databasePath async =>
      debugDatabasePath ?? join(await getDatabasesPath(), 'dartscore.db');

  /// Opens (creating if needed) the `dartscore.db` database with foreign keys on.
  Future<Database> _initDb() async {
    return openDatabase(
      await databasePath,
      version: schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Applies incremental schema migrations from [oldVersion] up to [newVersion].
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE players ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute(
          "ALTER TABLE players ADD COLUMN uuid TEXT NOT NULL DEFAULT ''");
      await db.execute(
          'ALTER TABLE players ADD COLUMN last_synced_at INTEGER');
      final players = await db.query('players');
      for (final p in players) {
        final uuid = _generateUuid();
        await db.update('players', {'uuid': uuid},
            where: 'id = ?', whereArgs: [p['id']]);
      }
    }
    if (oldVersion < 4) {
      await db.execute(
          'ALTER TABLE games ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 5) {
      await db.execute(
          'ALTER TABLE players ADD COLUMN synced_stats TEXT');
    }
    if (oldVersion < 6) {
      await db.execute(
          'ALTER TABLE players ADD COLUMN is_primary INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 7) {
      await db.execute(
          'ALTER TABLE games ADD COLUMN team_config_json TEXT');
    }
    if (oldVersion < 8) {
      await db.execute(
          'ALTER TABLE players ADD COLUMN local_stats_json TEXT');
    }
    if (oldVersion < 9) {
      await db.execute(
          'ALTER TABLE dart_throws ADD COLUMN hits_json TEXT');
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cricket_games (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          variant INTEGER NOT NULL,
          scoring_mode INTEGER NOT NULL,
          legs INTEGER NOT NULL,
          sets INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          finished_at INTEGER,
          player_ids TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cricket_throws (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          game_id INTEGER NOT NULL,
          player_id INTEGER NOT NULL,
          field INTEGER NOT NULL,
          multiplier INTEGER NOT NULL,
          leg INTEGER NOT NULL,
          set_ INTEGER NOT NULL,
          thrown_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS shanghai_games (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          variant INTEGER NOT NULL,
          legs INTEGER NOT NULL,
          sets INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          finished_at INTEGER,
          player_ids TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS shanghai_throws (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          game_id INTEGER NOT NULL,
          player_id INTEGER NOT NULL,
          target INTEGER NOT NULL,
          multiplier INTEGER NOT NULL,
          round INTEGER NOT NULL,
          leg INTEGER NOT NULL,
          set_ INTEGER NOT NULL,
          thrown_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 12) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS around_the_clock_games (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          variant INTEGER NOT NULL,
          legs INTEGER NOT NULL,
          sets INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          finished_at INTEGER,
          player_ids TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS around_the_clock_throws (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          game_id INTEGER NOT NULL,
          player_id INTEGER NOT NULL,
          field INTEGER NOT NULL,
          multiplier INTEGER NOT NULL,
          leg INTEGER NOT NULL,
          set_ INTEGER NOT NULL,
          thrown_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 13) {
      await db.execute(
          'ALTER TABLE cricket_games ADD COLUMN team_config_json TEXT');
    }
    if (oldVersion < 14) {
      await db.execute(
          'ALTER TABLE shanghai_games ADD COLUMN team_config_json TEXT');
    }
    if (oldVersion < 15) {
      await db.execute(
          'ALTER TABLE around_the_clock_games ADD COLUMN team_config_json TEXT');
    }
    if (oldVersion < 16) {
      await db.execute(
          'ALTER TABLE games ADD COLUMN placement_mode INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 17) {
      await db.execute('ALTER TABLE games ADD COLUMN handicap_json TEXT');
    }
    if (oldVersion < 18) {
      // Default 0 = StartingOrder.random, which is how every game up to here
      // was played: the setup screens always shuffled.
      for (final table in const [
        'games',
        'cricket_games',
        'shanghai_games',
        'around_the_clock_games',
      ]) {
        await db.execute(
            'ALTER TABLE $table ADD COLUMN starting_order INTEGER NOT NULL DEFAULT 0');
      }
    }
    if (oldVersion < 19) {
      await _createIndexes(db);
    }
    if (oldVersion < 20) {
      await db.execute('ALTER TABLE games ADD COLUMN origin_device TEXT');
      await db.execute(_kCreatePlayerOriginStats);

      // Everything a sync brought in so far came from an unnamed device, so it
      // all goes into the legacy bucket, throws and snapshot alike.
      await db.update('games', {'origin_device': kLegacyOrigin},
          where: 'is_synced = 1');

      // For a player that was ever imported, `local_stats_json` is whatever the
      // last packet carried: the import overwrote the column outright. Moving
      // it to the legacy origin says so, and frees the column to mean what it
      // says from here on, this device's own cleared games. A player that was
      // never synced keeps their column untouched.
      final synced = await db.query('players',
          columns: ['id', 'local_stats_json'],
          where: 'last_synced_at IS NOT NULL '
              "AND local_stats_json IS NOT NULL AND local_stats_json != ''");

      for (final row in synced) {
        await db.insert('player_origin_stats', {
          'player_id':     row['id'],
          'origin_device': kLegacyOrigin,
          'snapshot_json': row['local_stats_json'],
        });
        await db.update('players', {'local_stats_json': null},
            where: 'id = ?', whereArgs: [row['id']]);
      }
    }
    if (oldVersion < 21) {
      await db.execute(_kCreateAppMeta);
    }
    if (oldVersion < 22) {
      await db.execute(
          'ALTER TABLE dart_throws ADD COLUMN checkout_darts INTEGER NOT NULL DEFAULT 0');
      await _backfillCheckoutDarts(db);
    }
    if (oldVersion < 23) {
      await db.execute('ALTER TABLE players ADD COLUMN bot_level INTEGER');
    }
    if (oldVersion < 24) {
      await db.execute('ALTER TABLE players ADD COLUMN bot_ordinal INTEGER');
      await db.execute(
          'UPDATE players SET bot_ordinal = 1 WHERE bot_level IS NOT NULL');
    }
    if (oldVersion < 25) {
      await _createCheckoutLadder(db);
    }
    if (oldVersion < 26) {
      await _createCompetitionInbox(db);
    }
    if (oldVersion < 27) {
      await _createCompetitionGameLinks(db);
    }
  }

  /// Recomputes `dart_throws.checkout_darts` for every visit already on the
  /// device, so the lifetime numbers stop mixing the old "was in checkout
  /// range" rule with the new "a dart could have finished" one.
  ///
  /// A visit whose individual darts were recorded is replayed exactly. For the
  /// rest, throws that arrived over sync and rows from before `hits_json`
  /// existed, only the remaining the visit started on is known, so the best
  /// available reading is one dart when that remaining was already a one-dart
  /// finish or the leg was taken out, and none otherwise. That undercounts both
  /// a visit that worked its way into range and every second and third dart at
  /// a double, which cannot be helped: the darts that would prove them were
  /// never stored.
  ///
  /// Synced throws all hang off one hidden game whose check-out rule says
  /// nothing about how they were really played, so they fall back to
  /// double-out, the app default.
  static Future<void> _backfillCheckoutDarts(Database db) async {
    final gameRows = await db.query('games',
        columns: ['id', 'checkout_mode', 'handicap_json']);
    final modes = <int, CheckoutMode>{};
    final handicaps = <int, Map<int, PlayerHandicap>>{};
    for (final g in gameRows) {
      final id = g['id'] as int;
      modes[id] = CheckoutMode.values[g['checkout_mode'] as int? ?? 1];
      try {
        final parsed = decodePlayerHandicaps(g['handicap_json'] as String?);
        if (parsed != null) handicaps[id] = parsed;
      } catch (_) {}
    }

    const chunk = 500;
    var offset = 0;
    while (true) {
      final rows = await db.query('dart_throws',
          columns: [
            'id', 'game_id', 'player_id', 'score', 'remaining_before', 'bust',
            'hits_json',
          ],
          orderBy: 'id ASC',
          limit: chunk,
          offset: offset);
      if (rows.isEmpty) break;
      offset += rows.length;

      final batch = db.batch();
      for (final r in rows) {
        final gameId    = r['game_id'] as int;
        final playerId  = r['player_id'] as int;
        final remaining = r['remaining_before'] as int;
        final score     = r['score'] as int;
        final bust      = (r['bust'] as int? ?? 0) == 1;
        final mode      = handicaps[gameId]?[playerId]?.checkOut ??
            modes[gameId] ??
            CheckoutMode.doubleOut;
        final checkedOut = !bust && remaining - score == 0;

        final darts = _dartScoresOf(r['hits_json'] as String?);
        final atFinish = darts != null
            ? checkoutDartsInVisit(remaining, darts, mode,
                checkedOut: checkedOut)
            : (checkedOut ||
                    FinishCalculator.canFinishWithOneDart(remaining, mode))
                ? 1
                : 0;

        if (atFinish == 0) continue;
        batch.update('dart_throws', {'checkout_darts': atFinish},
            where: 'id = ?', whereArgs: [r['id']]);
      }
      await batch.commit(noResult: true);
    }
  }

  /// The points of the individual darts of a visit, decoded from its
  /// [hitsJson], or null when the visit was stored without them.
  static List<int>? _dartScoresOf(String? hitsJson) {
    if (hitsJson == null) return null;
    try {
      return [
        for (final h in jsonDecode(hitsJson) as List<dynamic>)
          _dartValue(h['f'] as int, h['m'] as int),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Points a single dart on [field] (0=miss, 1-20, 25=bull) with [multiplier]
  /// is worth. Mirrors the scoring in `GameProvider._addDart`.
  static int _dartValue(int field, int multiplier) {
    if (field == 0) return 0;
    if (field == 25) return multiplier == 2 ? 50 : 25;
    return field * multiplier;
  }

  /// Free-form key/value rows that describe the database file itself rather
  /// than anything in the app.
  ///
  /// A backup is the plain database file, so whatever has to travel with it has
  /// to live inside it. That is what this table is for: the marker that
  /// identifies the file as a DartScore backup, and the id of the device that
  /// wrote it. See [writeBackupMarkers].
  static const String _kCreateAppMeta = '''
      CREATE TABLE IF NOT EXISTS app_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''';

  /// The Checkout Ladder games, created by [_createCheckoutLadder].
  static const String _kCreateCheckoutLadderGames = '''
      CREATE TABLE IF NOT EXISTS checkout_ladder_games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        variant INTEGER NOT NULL,
        start_number INTEGER NOT NULL,
        target_number INTEGER,
        darts_per_attempt INTEGER NOT NULL,
        step_from INTEGER,
        step_darts INTEGER,
        checkout_mode INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        finished_at INTEGER,
        player_ids TEXT NOT NULL,
        team_config_json TEXT,
        starting_order INTEGER NOT NULL DEFAULT 0
      )
    ''';

  /// The darts of the Checkout Ladder games, one row per dart. Nothing but the
  /// hit is stored: number, rest, attempt and floor are replayed from them.
  static const String _kCreateCheckoutLadderThrows = '''
      CREATE TABLE IF NOT EXISTS checkout_ladder_throws (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id INTEGER NOT NULL,
        player_id INTEGER NOT NULL,
        field INTEGER NOT NULL,
        multiplier INTEGER NOT NULL,
        thrown_at INTEGER NOT NULL
      )
    ''';

  /// Per-device stats snapshots for one player.
  ///
  /// The column on `players` holds only what this device produced itself.
  /// Everything a sync brought in lives here, one row per device it came from,
  /// so that a device can recognise and drop its own data when it comes back
  /// around, and so that importing from one device leaves what another sent
  /// alone.
  static const String _kCreatePlayerOriginStats = '''
      CREATE TABLE IF NOT EXISTS player_origin_stats (
        player_id INTEGER NOT NULL,
        origin_device TEXT NOT NULL,
        snapshot_json TEXT NOT NULL,
        PRIMARY KEY (player_id, origin_device)
      )
    ''';

  /// Creates the indexes behind the three lookups the app repeats most: every
  /// throw of one game, every throw of one player, and the games a player took
  /// part in.
  ///
  /// Without them SQLite reads the whole throw table for each of those, which
  /// is what opening a statistics or a history screen costs. The column order
  /// is chosen so one index serves several queries: `thrown_at` trails
  /// `player_id` because the player lookups also sort by it, and SQLite still
  /// uses the leftmost prefix for the plain `player_id = ?` case. The same
  /// holds for `player_id` behind `game_id`.
  ///
  /// `game_players` already has an index over `(game_id, player_id)` from its
  /// primary key, but a prefix index cannot answer a lookup by `player_id`
  /// alone, so that one gets its own.
  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dart_throws_player '
        'ON dart_throws(player_id, thrown_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dart_throws_game '
        'ON dart_throws(game_id, player_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_game_players_player '
        'ON game_players(player_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cricket_throws_game '
        'ON cricket_throws(game_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_shanghai_throws_game '
        'ON shanghai_throws(game_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_atc_throws_game '
        'ON around_the_clock_throws(game_id)');
  }

  /// Creates the Checkout Ladder tables and their index, for a fresh install
  /// and for the upgrade to version 25 alike.
  ///
  /// The index is created here rather than in [_createIndexes], because the
  /// upgrade to version 19 runs that one long before these tables exist.
  Future<void> _createCheckoutLadder(Database db) async {
    await db.execute(_kCreateCheckoutLadderGames);
    await db.execute(_kCreateCheckoutLadderThrows);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ladder_throws_game '
        'ON checkout_ladder_throws(game_id)');
  }

  /// Competition imports are isolated from legacy player/statistics sync.
  Future<void> _createCompetitionInbox(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS competition_inbox ('
        'match_id TEXT PRIMARY KEY, payload TEXT NOT NULL, '
        'received_at INTEGER NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS competition_player_links ('
        'external_player_id TEXT PRIMARY KEY, player_id INTEGER NOT NULL, '
        'bond_number TEXT UNIQUE, source TEXT NOT NULL, '
        'FOREIGN KEY(player_id) REFERENCES players(id))');
  }

  /// Each official single owns at most one X01 game; game creation and
  /// linking are committed in the same SQLite transaction.
  Future<void> _createCompetitionGameLinks(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS competition_game_links ('
        'match_id TEXT NOT NULL, slot INTEGER NOT NULL, game_id INTEGER NOT NULL UNIQUE, '
        'starter_external_id TEXT NOT NULL, '
        'PRIMARY KEY(match_id, slot), '
        'FOREIGN KEY(match_id) REFERENCES competition_inbox(match_id), '
        'FOREIGN KEY(game_id) REFERENCES games(id))');
  }

  /// Generates a random RFC 4122 version-4 UUID for migrating rows that predate
  /// the uuid column.
  static String _generateUuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(List<int> b) =>
        b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(bytes.sublist(0, 4))}-${hex(bytes.sublist(4, 6))}'
        '-${hex(bytes.sublist(6, 8))}-${hex(bytes.sublist(8, 10))}'
        '-${hex(bytes.sublist(10, 16))}';
  }

  /// Creates the full schema (all tables and indexes) for a fresh install.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE players (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        favorite_doubles TEXT NOT NULL DEFAULT '',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        is_primary INTEGER NOT NULL DEFAULT 0,
        uuid TEXT NOT NULL DEFAULT '',
        last_synced_at INTEGER,
        synced_stats TEXT,
        local_stats_json TEXT,
        bot_level INTEGER,
        bot_ordinal INTEGER
      )
    ''');
    await _createCompetitionInbox(db);
    await _createCompetitionGameLinks(db);
    await db.execute('''
      CREATE TABLE games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_score INTEGER NOT NULL,
        game_mode INTEGER NOT NULL DEFAULT 0,
        checkout_mode INTEGER NOT NULL DEFAULT 1,
        legs INTEGER NOT NULL DEFAULT 3,
        sets INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        finished_at INTEGER,
        is_synced INTEGER NOT NULL DEFAULT 0,
        origin_device TEXT,
        team_config_json TEXT,
        handicap_json TEXT,
        placement_mode INTEGER NOT NULL DEFAULT 0,
        starting_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(_kCreatePlayerOriginStats);
    await db.execute('''
      CREATE TABLE game_players (
        game_id INTEGER NOT NULL,
        player_id INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (game_id, player_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE dart_throws (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id INTEGER NOT NULL,
        player_id INTEGER NOT NULL,
        score INTEGER NOT NULL,
        darts_used INTEGER NOT NULL DEFAULT 3,
        leg INTEGER NOT NULL DEFAULT 1,
        set_ INTEGER NOT NULL DEFAULT 1,
        remaining_before INTEGER NOT NULL,
        thrown_at INTEGER NOT NULL,
        bust INTEGER NOT NULL DEFAULT 0,
        hits_json TEXT,
        checkout_darts INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE cricket_games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        variant INTEGER NOT NULL,
        scoring_mode INTEGER NOT NULL,
        legs INTEGER NOT NULL,
        sets INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        finished_at INTEGER,
        player_ids TEXT NOT NULL,
        team_config_json TEXT,
        starting_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE cricket_throws (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id INTEGER NOT NULL,
        player_id INTEGER NOT NULL,
        field INTEGER NOT NULL,
        multiplier INTEGER NOT NULL,
        leg INTEGER NOT NULL,
        set_ INTEGER NOT NULL,
        thrown_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE shanghai_games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        variant INTEGER NOT NULL,
        legs INTEGER NOT NULL,
        sets INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        finished_at INTEGER,
        player_ids TEXT NOT NULL,
        team_config_json TEXT,
        starting_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE shanghai_throws (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id INTEGER NOT NULL,
        player_id INTEGER NOT NULL,
        target INTEGER NOT NULL,
        multiplier INTEGER NOT NULL,
        round INTEGER NOT NULL,
        leg INTEGER NOT NULL,
        set_ INTEGER NOT NULL,
        thrown_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE around_the_clock_games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        variant INTEGER NOT NULL,
        legs INTEGER NOT NULL,
        sets INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        finished_at INTEGER,
        player_ids TEXT NOT NULL,
        team_config_json TEXT,
        starting_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE around_the_clock_throws (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id INTEGER NOT NULL,
        player_id INTEGER NOT NULL,
        field INTEGER NOT NULL,
        multiplier INTEGER NOT NULL,
        leg INTEGER NOT NULL,
        set_ INTEGER NOT NULL,
        thrown_at INTEGER NOT NULL
      )
    ''');
    await db.execute(_kCreateAppMeta);
    await _createIndexes(db);
    await _createCheckoutLadder(db);
  }

  // Players

  /// The primary (non-deleted) player, or null if none is set.
  Future<Player?> getPrimaryPlayer() async {
    final d = await db;
    final rows = await d.query('players',
        where: 'is_primary = 1 AND is_deleted = 0');
    return rows.isEmpty ? null : Player.fromMap(rows.first);
  }

  /// Sets one player as primary, clears the flag on all others.
  Future<void> setPrimaryPlayer(int id) async {
    final d = await db;
    // Atomic: clear all, then set one, which prevents a crash window
    await d.transaction((txn) async {
      await txn.update('players', {'is_primary': 0});
      await txn.update('players', {'is_primary': 1},
          where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Inserts a new player and returns its assigned id.
  Future<int> insertPlayer(Player p) async {
    final d = await db;
    return d.insert('players', p.toMap()..remove('id'));
  }

  /// All non-deleted human players ordered by name.
  ///
  /// Bots are left out on purpose: this is the roster the setup screens, the
  /// player list and the sync sender offer, and a bot belongs in none of them.
  /// [getBots] holds the rest and [getPlayersById] both.
  Future<List<Player>> getPlayers() async {
    final d = await db;
    final rows = await d.query('players',
        where: 'is_deleted = 0 AND bot_level IS NULL', orderBy: 'name ASC');
    return rows.map(Player.fromMap).toList();
  }

  /// All non-deleted computer opponents, weakest tier first and numbered
  /// within it.
  Future<List<Player>> getBots() async {
    final d = await db;
    final rows = await d.query('players',
        where: 'is_deleted = 0 AND bot_level IS NOT NULL',
        orderBy: 'bot_level ASC, bot_ordinal ASC');
    return rows.map(Player.fromMap).toList();
  }

  /// The player with [id] regardless of deleted status (for history/stats), or null.
  Future<Player?> getPlayer(int id) async {
    final d = await db;
    // Returns player regardless of deleted status (for history/stats)
    final rows = await d.query('players', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Player.fromMap(rows.first);
  }

  /// Every player keyed by id, deleted ones included, for callers that resolve
  /// many ids at once. The history would otherwise run one query per player per
  /// game.
  Future<Map<int, Player>> getPlayersById() async {
    final d = await db;
    final rows = await d.query('players');
    return {
      for (final row in rows.map(Player.fromMap))
        if (row.id != null) row.id!: row,
    };
  }

  /// Updates the stored row for [p].
  Future<void> updatePlayer(Player p) async {
    final d = await db;
    await d.update('players', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  /// Soft-deletes the player with [id], keeping the name visible in history/stats.
  Future<void> deletePlayer(int id) async {
    final d = await db;
    // Soft delete: keeps name visible in history/stats
    await d.update('players', {'is_deleted': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  // Games

  /// Inserts an X01 game and its ordered player list, returning the game id.
  Future<int> insertGame(Game g, List<int> playerIds, {
    String? competitionMatchId,
    int? competitionSlot,
    String? starterExternalId,
  }) async {
    final d = await db;
    return d.transaction((txn) async {
      if (competitionMatchId != null) {
        if (competitionSlot == null || starterExternalId == null) {
          throw ArgumentError('Incomplete competition game link');
        }
        final existing = await txn.query('competition_game_links',
            where: 'match_id = ? AND slot = ?',
            whereArgs: [competitionMatchId, competitionSlot]);
        if (existing.isNotEmpty) {
          throw StateError('Deze competitiesingle heeft al een X01-game');
        }
      }
      final map = g.toMap()..remove('id');
      final gameId = await txn.insert('games', map);
      for (var i = 0; i < playerIds.length; i++) {
        await txn.insert('game_players', {
          'game_id': gameId,
          'player_id': playerIds[i],
          'sort_order': i,
        });
      }
      if (competitionMatchId != null) {
        await txn.insert('competition_game_links', {
          'match_id': competitionMatchId,
          'slot': competitionSlot,
          'game_id': gameId,
          'starter_external_id': starterExternalId,
        });
      }
      return gameId;
    });
  }

  /// True only for games linked to an official competition single.
  Future<bool> isCompetitionGame(int gameId) async {
    final d = await db;
    final rows = await d.query('competition_game_links',
        columns: ['game_id'], where: 'game_id = ?',
        whereArgs: [gameId], limit: 1);
    return rows.isNotEmpty;
  }

  Future<int?> competitionGameId(String matchId, int slot) async {
    final d = await db;
    final rows = await d.query('competition_game_links',
        columns: ['game_id'], where: 'match_id = ? AND slot = ?',
        whereArgs: [matchId, slot]);
    return rows.isEmpty ? null : rows.single['game_id'] as int;
  }

  Future<Game?> getGame(int id) async {
    final d = await db;
    final rows = await d.query('games', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Game.fromMap(rows.single);
  }


  /// The ids of the finished games [playerId] won, their team games included.
  ///
  /// No column holds a winner, so each game is decided from its throws by
  /// [winningPlayerIds]. Only a placement game needs all of them; every other
  /// game is decided by its last checkout, so those are asked for the checkout
  /// visits alone.
  Future<Set<int>> getWonGameIds(int playerId) async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT g.* FROM games g '
      'JOIN game_players gp ON gp.game_id = g.id '
      'WHERE gp.player_id = ? AND g.finished_at IS NOT NULL',
      [playerId],
    );

    // One read for every line-up rather than one per game: a placement game is
    // scored against how many took part, and that count cannot be read off the
    // throws of a game somebody sat out.
    final lineUps = await getGamePlayerIdsByGame();

    final won = <int>{};
    for (final row in rows) {
      final game = Game.fromMap(row);
      final throws = game.placementMode
          ? await getThrowsForGame(game.id!)
          : await _checkoutThrowsOfGame(game.id!);
      if (winningPlayerIds(game, throws,
              participantIds: lineUps[game.id!] ?? const [])
          .contains(playerId)) {
        won.add(game.id!);
      }
    }
    return won;
  }

  /// The visits of [gameId] that took a player to zero, in the order they were
  /// thrown.
  Future<List<DartThrow>> _checkoutThrowsOfGame(int gameId) async {
    final d = await db;
    final rows = await d.query(
      'dart_throws',
      where: 'game_id = ? AND bust = 0 AND remaining_before = score',
      whereArgs: [gameId],
      orderBy: 'thrown_at ASC, id ASC',
    );
    return rows.map(_throwFromMap).toList();
  }

  /// Permanently deletes an X01 game and its throws and player links.
  Future<void> deleteGame(int gameId) async {
    final d = await db;
    await d.delete('dart_throws', where: 'game_id = ?', whereArgs: [gameId]);
    await d.delete('game_players', where: 'game_id = ?', whereArgs: [gameId]);
    await d.delete('games', where: 'id = ?', whereArgs: [gameId]);
  }

  // Minimum darts to finish from a given start score (double-out).
  // Mirrors game_provider.dart: kept local to avoid circular import.
  static const _kMinDarts = {101: 2, 170: 3, 201: 4, 301: 6, 501: 9, 701: 12, 1001: 17};


  /// Counts perfect legs in [throws], all of which come from one game and so
  /// share the same [minDarts].
  static int _perfectLegsFor(List<DartThrow> throws, int? minDarts) =>
      perfectLegsFromThrows(throws, (_) => minDarts);

  /// Snapshots one game's throws into each involved player's persistent
  /// `local_stats_json`, so lifetime stats survive deleting the game. Call this
  /// BEFORE [deleteGame].
  Future<void> snapshotGameStats(int gameId) async {
    final d      = await db;
    final throws = await getThrowsForGame(gameId);
    if (throws.isEmpty) return;

    // Fetch the game to compute perfect legs and to name its winner.
    final gameRows  = await d.query('games', where: 'id = ?', whereArgs: [gameId]);
    final game       = gameRows.isEmpty ? null : Game.fromMap(gameRows.first);
    final minDarts   = game != null ? _kMinDarts[game.startScore] : null;
    final winners    = game == null
        ? const <int>{}
        : winningPlayerIds(game, throws,
            participantIds: await getGamePlayerIds(gameId));

    final byPlayer = <int, List<DartThrow>>{};
    for (final t in throws) {
      byPlayer.putIfAbsent(t.playerId, () => []).add(t);
    }

    final isFinished = gameRows.isNotEmpty && gameRows.first['finished_at'] != null ? 1 : 0;

    for (final entry in byPlayer.entries) {
      final playerId     = entry.key;
      final playerThrows = entry.value;

      final stats = <String, dynamic>{
        ..._computeStatsFromThrows(playerThrows),
        'perfect_legs':    _perfectLegsFor(playerThrows, minDarts),
        'games_finished':  isFinished,
        'games_won':       isFinished == 1 && winners.contains(playerId) ? 1 : 0,
      };

      final rows = await d.query('players', where: 'id = ?', whereArgs: [playerId]);
      if (rows.isEmpty) continue;
      final existing = rows.first['local_stats_json'] as String?;

      final merged = (existing != null && existing.isNotEmpty)
          ? _mergeStats(jsonDecode(existing) as Map<String, dynamic>, stats)
          : stats;

      await d.update('players', {'local_stats_json': jsonEncode(merged)},
          where: 'id = ?', whereArgs: [playerId]);
    }
  }

  /// Folds [excluded] into the snapshot [snapshotJson] and returns the result,
  /// or null when there is nothing to carry.
  ///
  /// A sync can be limited to the last few days, in which case only those
  /// throws travel as individual throws. Everything older still has to reach
  /// the other device, just as aggregated numbers, otherwise its lifetime
  /// totals silently read low and nobody can tell. Grouping by game mirrors
  /// [snapshotGameStats]: perfect legs and the finished-game count are
  /// properties of a game, not of a single throw.
  /// [gameFacts] must be false for throws that arrived from another device.
  /// They all share one hidden sync-game, so what looks like a game here is a
  /// whole history in one heap: counting it as one game played, or reading a
  /// best-game average off it, describes something that was never played that
  /// way. Those numbers already travelled as part of the sending device's
  /// snapshot, so they are simply left out here.
  Future<Map<String, dynamic>?> foldThrowsIntoSnapshot(
      String? snapshotJson, List<DartThrow> excluded,
      {bool gameFacts = true}) async {
    var merged = (snapshotJson != null && snapshotJson.isNotEmpty)
        ? jsonDecode(snapshotJson) as Map<String, dynamic>
        : null;
    if (excluded.isEmpty) return merged;

    final byGame = <int, List<DartThrow>>{};
    for (final t in excluded) {
      byGame.putIfAbsent(t.gameId, () => []).add(t);
    }

    for (final entry in byGame.entries) {
      final stats = <String, dynamic>{
        ..._computeStatsFromThrows(entry.value),
        if (gameFacts) ...await _gameFactsOf(entry.key, entry.value),
      };
      if (!gameFacts) {
        for (final key in _kGameFactKeys) {
          stats.remove(key);
        }
      }

      merged = merged == null ? stats : _mergeStats(merged, stats);
    }

    return merged;
  }

  /// Snapshot counters that describe a game rather than a throw, and so cannot
  /// be recomputed from throws once they have left the device they were played
  /// on.
  static const _kGameFactKeys = [
    'perfect_legs',
    'games_played',
    'games_finished',
    'games_won',
    'highest_game_avg',
  ];

  /// What game [gameId] contributes about itself, given the [throws] of it that
  /// are being accounted for.
  ///
  /// Those throws are one player's, which is the player the win is counted
  /// for: a snapshot is folded per player.
  Future<Map<String, dynamic>> _gameFactsOf(
      int gameId, List<DartThrow> throws) async {
    final d = await db;
    final rows = await d.query('games', where: 'id = ?', whereArgs: [gameId]);

    final game     = rows.isEmpty ? null : Game.fromMap(rows.first);
    final minDarts = game != null ? _kMinDarts[game.startScore] : null;
    final finished = game?.finishedAt != null;
    // Who won needs every throw of the game, not only the ones being accounted
    // for here: the deciding checkout may well be the opponent's.
    final won = finished &&
        throws.isNotEmpty &&
        winningPlayerIds(game!, await getThrowsForGame(gameId),
                participantIds: await getGamePlayerIds(gameId))
            .contains(throws.first.playerId);

    return {
      'perfect_legs':     _perfectLegsFor(throws, minDarts),
      'games_played':     1,
      'games_finished':   finished ? 1 : 0,
      'games_won':        won ? 1 : 0,
      'highest_game_avg': bestGameAverage(throws),
    };
  }

  /// Adds what the games behind [throws] say about themselves to [snapshot],
  /// for throws that are travelling as throws rather than as aggregates.
  ///
  /// A synced throw arrives without its game: every one of them lands in a
  /// single hidden sync-game on the other device, which has no start score of
  /// its own and counts for no game played. So the receiver reads no perfect
  /// leg off it, no game average worth the name, and no dartboard segment,
  /// because the wire format carries a visit's score but not the three darts
  /// behind it. Everything a game knows about itself has to travel here or not
  /// at all.
  ///
  /// This cannot double count. On the other side these throws contribute
  /// nothing to any of it: the sync-game is left out of the games a player has
  /// played, its start score never reaches the perfect-leg count, and a best
  /// game average taken over one heap of every game at once can only come out
  /// below the real one, which the merge then discards in favour of this.
  Future<Map<String, dynamic>?> addTravellingGameFacts(
      Map<String, dynamic>? snapshot, List<DartThrow> throws) async {
    if (throws.isEmpty) return snapshot;

    final byGame = <int, List<DartThrow>>{};
    for (final t in throws) {
      byGame.putIfAbsent(t.gameId, () => []).add(t);
    }

    var merged = snapshot;
    for (final entry in byGame.entries) {
      final facts = <String, dynamic>{
        ...await _gameFactsOf(entry.key, entry.value),
        'segment_hits': segmentHitsOf(entry.value),
      };
      merged = merged == null ? facts : _mergeStats(merged, facts);
    }

    return merged;
  }

  /// Computes an aggregate stats map (darts, scored, averages, highs, counts)
  /// from a list of throws.
  ///
  /// The counters that also matter while a game is running come from
  /// [ThrowStats], so a number shown live and the same number read back
  /// from a snapshot can never drift apart. Only what the persisted stats need
  /// on top of that is aggregated here: the segment heatmap, the score
  /// distribution, the per-day buckets behind the week comparison, and the
  /// recent-throws tail.
  static Map<String, dynamic> _computeStatsFromThrows(List<DartThrow> throws) {
    final stats = ThrowStats.fromThrows(throws);

    final segmentHits  = segmentHitsOf(throws);
    final scoreDistrib = <String, int>{};
    // date → {scored, darts, visits, s180} for week-comparison reconstruction
    final dailyStats   = <String, Map<String, int>>{};
    final gameIds = throws.map((t) => t.gameId).toSet();

    for (final t in throws) {
      // Daily stats (all throws, bust or not, for activity heat and week windows)
      final day = '${t.thrownAt.year}-'
          '${t.thrownAt.month.toString().padLeft(2, '0')}-'
          '${t.thrownAt.day.toString().padLeft(2, '0')}';
      final ds = dailyStats.putIfAbsent(day, () => {'scored': 0, 'darts': 0, 'visits': 0, 's180': 0});
      ds['darts'] = (ds['darts'] ?? 0) + t.dartsUsed;

      if (!t.bust) {
        final bucket = ((t.score ~/ 20) * 20).toString();
        scoreDistrib[bucket] = (scoreDistrib[bucket] ?? 0) + 1;

        ds['scored']  = (ds['scored']  ?? 0) + t.score;
        ds['visits']  = (ds['visits']  ?? 0) + 1;
        if (t.score == 180) ds['s180'] = (ds['s180'] ?? 0) + 1;
      }
    }

    // Recent throws: last 20, newest first, as compact maps
    final sortedThrows = [...throws]
      ..sort((a, b) => b.thrownAt.compareTo(a.thrownAt));
    final recentThrows = sortedThrows.take(20).map((t) => {
      'score':            t.score,
      'darts_used':       t.dartsUsed,
      'bust':             t.bust ? 1 : 0,
      'remaining_before': t.remainingBefore,
      'thrown_at':        t.thrownAt.millisecondsSinceEpoch,
    }).toList();

    return {
      'total_darts':        stats.totalDarts,
      'total_scored':       stats.totalScored,
      'total_visits':       stats.totalVisits,
      // A leg is won by finishing it, so every successful checkout is a leg.
      'legs_won':           stats.checkoutSuccesses,
      'busts':              stats.busts,
      'highest_visit':      stats.highestVisit,
      'highest_checkout':   stats.highestCheckout,
      'count_180':          stats.count180,
      'count_140_plus':     stats.count140plus,
      'count_100_plus':     stats.count100plus,
      'checkout_attempts':  stats.checkoutAttempts,
      'checkout_successes': stats.checkoutSuccesses,
      'checkout_darts':     stats.checkoutDarts,
      'games_played':       gameIds.length,
      'score_sum_squares':  stats.scoreSumSquares,
      'highest_game_avg':   bestGameAverage(throws),
      'co_at_sub40':  stats.coAttemptSub40,  'co_ok_sub40':  stats.coSuccessSub40,
      'co_at_sub60':  stats.coAttemptSub60,  'co_ok_sub60':  stats.coSuccessSub60,
      'co_at_sub100': stats.coAttemptSub100, 'co_ok_sub100': stats.coSuccessSub100,
      'co_at_sub170': stats.coAttemptSub170, 'co_ok_sub170': stats.coSuccessSub170,
      'segment_hits':       segmentHits,
      'score_distribution': scoreDistrib,
      'daily_stats':        dailyStats,
      'recent_throws':      recentThrows,
    };
  }

  /// Counts the dartboard segments [throws] hit, as field to multiplier to
  /// count, skipping the throws that were entered as a plain score.
  static Map<String, Map<String, int>> segmentHitsOf(List<DartThrow> throws) {
    final hits = <String, Map<String, int>>{};

    for (final t in throws) {
      if (t.hitsJson == null) continue;
      try {
        for (final h in jsonDecode(t.hitsJson!) as List<dynamic>) {
          final field = (h['f'] as int).toString();
          final mul   = (h['m'] as int).toString();
          hits.putIfAbsent(field, () => {});
          hits[field]![mul] = (hits[field]![mul] ?? 0) + 1;
        }
      } catch (_) {}
    }

    return hits;
  }

  /// Merges two stats maps, summing counts and recomputing maxima/averages, so
  /// snapshots accumulate across games.
  static Map<String, dynamic> _mergeStats(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    int add(String k) => (a[k] as int? ?? 0) + (b[k] as int? ?? 0);
    int mx(String k)  => max(a[k] as int? ?? 0, b[k] as int? ?? 0);
    double mxd(String k) =>
        max((a[k] as num? ?? 0).toDouble(), (b[k] as num? ?? 0).toDouble());

    // segment_hits: field → multiplier → count
    final aHits = (a['segment_hits'] as Map?)?.cast<String, dynamic>() ?? {};
    final bHits = (b['segment_hits'] as Map?)?.cast<String, dynamic>() ?? {};
    final mergedHits = <String, Map<String, int>>{};
    for (final f in {...aHits.keys, ...bHits.keys}) {
      final aM = (aHits[f] as Map?)?.cast<String, dynamic>() ?? {};
      final bM = (bHits[f] as Map?)?.cast<String, dynamic>() ?? {};
      final m  = <String, int>{};
      for (final mul in {...aM.keys, ...bM.keys}) {
        m[mul] = (aM[mul] as int? ?? 0) + (bM[mul] as int? ?? 0);
      }
      mergedHits[f] = m;
    }

    // score_distribution: bucket → count
    final aDist = (a['score_distribution'] as Map?)?.cast<String, dynamic>() ?? {};
    final bDist = (b['score_distribution'] as Map?)?.cast<String, dynamic>() ?? {};
    final mergedDist = <String, int>{};
    for (final k in {...aDist.keys, ...bDist.keys}) {
      mergedDist[k] = (aDist[k] as int? ?? 0) + (bDist[k] as int? ?? 0);
    }

    // daily_stats: date → {scored, darts, visits, s180}
    final aDs = (a['daily_stats'] as Map?)?.cast<String, dynamic>() ?? {};
    final bDs = (b['daily_stats'] as Map?)?.cast<String, dynamic>() ?? {};
    final mergedDs = <String, Map<String, int>>{};
    for (final day in {...aDs.keys, ...bDs.keys}) {
      final aD = (aDs[day] as Map?)?.cast<String, dynamic>() ?? {};
      final bD = (bDs[day] as Map?)?.cast<String, dynamic>() ?? {};
      mergedDs[day] = {
        'scored':  (aD['scored']  as int? ?? 0) + (bD['scored']  as int? ?? 0),
        'darts':   (aD['darts']   as int? ?? 0) + (bD['darts']   as int? ?? 0),
        'visits':  (aD['visits']  as int? ?? 0) + (bD['visits']  as int? ?? 0),
        's180':    (aD['s180']    as int? ?? 0) + (bD['s180']    as int? ?? 0),
      };
    }

    // recent_throws: combine, sort newest-first, keep 20
    final aRt = (a['recent_throws'] as List?)?.cast<dynamic>() ?? [];
    final bRt = (b['recent_throws'] as List?)?.cast<dynamic>() ?? [];
    final combined = [...aRt, ...bRt]
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort((x, y) => ((y['thrown_at'] as int? ?? 0)
          .compareTo(x['thrown_at'] as int? ?? 0)));
    final mergedRt = combined.take(20).toList();

    return {
      'total_darts':        add('total_darts'),
      'total_scored':       add('total_scored'),
      'total_visits':       add('total_visits'),
      'legs_won':           add('legs_won'),
      'busts':              add('busts'),
      'highest_visit':      mx('highest_visit'),
      'highest_checkout':   mx('highest_checkout'),
      'highest_game_avg':   mxd('highest_game_avg'),
      'count_180':          add('count_180'),
      'count_140_plus':     add('count_140_plus'),
      'count_100_plus':     add('count_100_plus'),
      'checkout_attempts':  add('checkout_attempts'),
      'checkout_darts':     add('checkout_darts'),
      'checkout_successes': add('checkout_successes'),
      'games_played':       add('games_played'),
      'games_finished':     add('games_finished'),
      'games_won':          add('games_won'),
      'score_sum_squares':  add('score_sum_squares'),
      'perfect_legs':       add('perfect_legs'),
      'co_at_sub40':  add('co_at_sub40'),  'co_ok_sub40':  add('co_ok_sub40'),
      'co_at_sub60':  add('co_at_sub60'),  'co_ok_sub60':  add('co_ok_sub60'),
      'co_at_sub100': add('co_at_sub100'), 'co_ok_sub100': add('co_ok_sub100'),
      'co_at_sub170': add('co_at_sub170'), 'co_ok_sub170': add('co_ok_sub170'),
      'segment_hits':       mergedHits,
      'score_distribution': mergedDist,
      'daily_stats':        mergedDs,
      'recent_throws':      mergedRt,
    };
  }

  /// Updates an X01 game row (e.g. to mark it finished).
  Future<void> updateGame(Game g) async {
    final d = await db;
    await d.update('games', g.toMap(), where: 'id = ?', whereArgs: [g.id]);
  }

  /// All non-sync X01 games, newest first.
  Future<List<Game>> getGames() async {
    final d = await db;
    final rows = await d.query('games',
        where: 'is_synced = 0', orderBy: 'created_at DESC');
    return rows.map(Game.fromMap).toList();
  }

  /// The player ids for an X01 game in turn order.
  Future<List<int>> getGamePlayerIds(int gameId) async {
    final d = await db;
    final rows = await d.query(
      'game_players',
      where: 'game_id = ?',
      whereArgs: [gameId],
      orderBy: 'sort_order ASC',
    );
    return rows.map((r) => r['player_id'] as int).toList();
  }

  /// The player ids of every X01 game at once, keyed by game id and each list
  /// in turn order.
  ///
  /// The history screen lists all games, and asking per game turns one read
  /// into one per row. Games without an entry are simply absent from the map.
  Future<Map<int, List<int>>> getGamePlayerIdsByGame() async {
    final d = await db;
    final rows = await d.query('game_players', orderBy: 'sort_order ASC');
    final byGame = <int, List<int>>{};
    for (final r in rows) {
      byGame
          .putIfAbsent(r['game_id'] as int, () => [])
          .add(r['player_id'] as int);
    }
    return byGame;
  }

  // Throws

  /// Inserts an X01 throw and returns its id.
  Future<int> insertThrow(DartThrow t) async {
    final d = await db;
    final map = t.toMap()..remove('id');
    map['set_'] = map.remove('set');
    return d.insert('dart_throws', map);
  }

  /// Deletes the X01 throw with [id] (used by undo).
  Future<void> deleteThrow(int id) async {
    final d = await db;
    await d.delete('dart_throws', where: 'id = ?', whereArgs: [id]);
  }

  /// Atomically updates a numeric visit and its later remaining-before values.
  /// No partial correction is ever visible to the game replay.
  Future<void> correctNumericVisit(
      int gameId, int throwId, int score, int dartsUsed,
      Map<int, int> laterRemainingBefore) async {
    final database = await db;
    await database.transaction((txn) async {
      final changed = await txn.update('dart_throws',
          {'score': score, 'darts_used': dartsUsed},
          where: 'id = ? AND game_id = ?', whereArgs: [throwId, gameId]);
      if (changed != 1) throw StateError('Beurt niet gevonden');
      for (final entry in laterRemainingBefore.entries) {
        await txn.update('dart_throws',
            {'remaining_before': entry.value},
            where: 'id = ? AND game_id = ?',
            whereArgs: [entry.key, gameId]);
      }
    });
  }

  /// Atomically corrects visit kind as well as score and dart count.
  Future<void> correctVisit(int gameId, int throwId, int score,
      int dartsUsed, bool bust, Map<int, int> laterRemainingBefore) async {
    final database = await db;
    await database.transaction((txn) async {
      final changed = await txn.update('dart_throws',
          {'score': score, 'darts_used': dartsUsed, 'bust': bust ? 1 : 0,
           'checkout_darts': 0},
          where: 'id = ? AND game_id = ?', whereArgs: [throwId, gameId]);
      if (changed != 1) throw StateError('Beurt niet gevonden');
      for (final entry in laterRemainingBefore.entries) {
        await txn.update('dart_throws',
            {'remaining_before': entry.value},
            where: 'id = ? AND game_id = ?',
            whereArgs: [entry.key, gameId]);
      }
    });
  }

  /// All throws for an X01 game in chronological order.
  Future<List<DartThrow>> getThrowsForGame(int gameId) async {
    final d = await db;
    final rows = await d.query(
      'dart_throws',
      where: 'game_id = ?',
      whereArgs: [gameId],
      // Ties on the millisecond are possible, so the row id decides. The
      // replay in every provider depends on a stable order.
      orderBy: 'thrown_at ASC, id ASC',
    );
    return rows.map(_throwFromMap).toList();
  }

  /// All X01 throws by a player across all games, in chronological order.
  Future<List<DartThrow>> getThrowsForPlayer(int playerId) async {
    final d = await db;
    final rows = await d.query(
      'dart_throws',
      where: 'player_id = ?',
      whereArgs: [playerId],
      // Ties on the millisecond are possible, so the row id decides. The
      // replay in every provider depends on a stable order.
      orderBy: 'thrown_at ASC, id ASC',
    );
    return rows.map(_throwFromMap).toList();
  }

  /// Returns all game IDs the player participated in, newest first.
  Future<List<int>> getGameIdsForPlayer(int playerId) async {
    final d = await db;
    final rows = await d.query(
      'game_players',
      columns: ['game_id'],
      where: 'player_id = ?',
      whereArgs: [playerId],
    );
    final ids = rows.map((r) => r['game_id'] as int).toList();
    if (ids.isEmpty) return [];
    // sort by created_at desc
    final gameRows = await d.query(
      'games',
      where: 'id IN (${ids.map((_) => '?').join(',')})',
      whereArgs: ids,
      orderBy: 'created_at DESC',
    );
    return gameRows.map((r) => r['id'] as int).toList();
  }

  /// Builds a [DartThrow] from a row, translating the reserved `set_` column
  /// back to `set`.
  DartThrow _throwFromMap(Map<String, dynamic> map) {
    final m = Map<String, dynamic>.from(map);
    m['set'] = m.remove('set_');
    return DartThrow.fromMap(m);
  }

  // ── Sync helpers ────────────────────────────────────────────────────────────

  /// The non-deleted player matching [uuid] (used to merge synced players), or null.
  Future<Player?> getPlayerByUuid(String uuid) async {
    final d = await db;
    final rows = await d.query('players',
        where: 'uuid = ? AND is_deleted = 0', whereArgs: [uuid]);
    return rows.isEmpty ? null : Player.fromMap(rows.first);
  }

  /// Throws since [sinceMs] (exclusive) for a player.
  Future<List<DartThrow>> getThrowsForPlayerSince(
      int playerId, int sinceMs) async {
    final d = await db;
    final rows = await d.query(
      'dart_throws',
      where: 'player_id = ? AND thrown_at > ?',
      whereArgs: [playerId, sinceMs],
      // Ties on the millisecond are possible, so the row id decides. The
      // replay in every provider depends on a stable order.
      orderBy: 'thrown_at ASC, id ASC',
    );
    return rows.map(_throwFromMap).toList();
  }

  /// All known thrown_at timestamps for a player (for dedup).
  Future<Set<int>> getThrowTimestampsForPlayer(int playerId) async {
    final d = await db;
    final rows = await d.query(
      'dart_throws',
      columns: ['thrown_at'],
      where: 'player_id = ?',
      whereArgs: [playerId],
    );
    return rows.map((r) => r['thrown_at'] as int).toSet();
  }

  /// A player's throws grouped by the device they were played on, with null
  /// standing for this one and [kLegacyOrigin] for imports that predate
  /// devices being told apart.
  ///
  /// Sending needs the split: only throws played here may be folded into this
  /// device's snapshot when a range leaves them out. Folding someone else's
  /// into it is how their data comes home to them as part of ours and gets
  /// counted a second time.
  Future<Map<String?, List<DartThrow>>> getThrowsForPlayerByOrigin(
      int playerId) async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT t.*, g.origin_device AS origin_device FROM dart_throws t '
      'JOIN games g ON g.id = t.game_id '
      'WHERE t.player_id = ? '
      // Ties on the millisecond are possible, so the row id decides. The
      // replay in every provider depends on a stable order.
      'ORDER BY t.thrown_at ASC, t.id ASC',
      [playerId],
    );

    final byOrigin = <String?, List<DartThrow>>{};
    for (final row in rows) {
      final origin = row['origin_device'] as String?;
      final map = Map<String, dynamic>.from(row)..remove('origin_device');
      byOrigin.putIfAbsent(origin, () => []).add(_throwFromMap(map));
    }
    return byOrigin;
  }

  /// Creates one hidden sync-game for data received from [originDevice] and
  /// returns its id.
  ///
  /// Call once per import session, then pass the id to [insertSyncedThrows].
  Future<int> createSyncGame(int playerStartScore,
      {String originDevice = kLegacyOrigin}) async {
    final d = await db;
    return d.insert('games', {
      'start_score': playerStartScore,
      'game_mode': 0,
      'checkout_mode': 1,
      'legs': 1,
      'sets': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'finished_at': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 1, // hidden from history
      'origin_device': originDevice,
    });
  }

  /// Removes [playerId]'s throws from earlier imports, dropping any hidden
  /// sync-game left empty by that.
  ///
  /// [origins] names which sending devices to clear out, or every one of them
  /// when it is null. An import passes the device it is reading from, because a
  /// packet is authoritative for everything that came from there: its stats
  /// snapshot may cover throws an earlier sync delivered one by one, and
  /// keeping both would count the same leg twice. What a different device sent
  /// is no longer touched by that, and games played on this device carry
  /// `is_synced = 0` and never were.
  Future<void> deleteSyncedThrowsForPlayer(int playerId,
      {Set<String>? origins}) async {
    final d = await db;

    final filter = origins == null
        ? ''
        : 'AND g.origin_device IN (${origins.map((_) => '?').join(',')}) ';

    final rows = await d.rawQuery(
      'SELECT DISTINCT g.id AS id FROM games g '
      'JOIN dart_throws t ON t.game_id = g.id '
      'WHERE g.is_synced = 1 AND t.player_id = ? $filter',
      [playerId, ...?origins],
    );

    for (final row in rows) {
      final gameId = row['id'] as int;
      await d.delete('dart_throws',
          where: 'game_id = ? AND player_id = ?',
          whereArgs: [gameId, playerId]);

      final remaining = Sqflite.firstIntValue(await d.rawQuery(
          'SELECT COUNT(*) FROM dart_throws WHERE game_id = ?', [gameId]));
      if (remaining == 0) await deleteGame(gameId);
    }
  }

  /// Inserts throws imported during sync into the hidden sync-game.
  ///
  /// One statement per throw would mean a round trip each, and a sync can carry
  /// tens of thousands of them; a batch keeps a large import to a few seconds.
  /// Callers that show progress pass the throws in slices and get a chance to
  /// report between the calls.
  Future<void> insertSyncedThrows(
      int playerId, int gameId, List<DartThrow> throws) async {
    final d = await db;
    final batch = d.batch();

    for (final t in throws) {
      batch.insert('dart_throws', {
        'game_id': gameId,
        'player_id': playerId,
        'score': t.score,
        'darts_used': t.dartsUsed,
        'leg': t.leg,
        'set_': t.set,
        'remaining_before': t.remainingBefore,
        'thrown_at': t.thrownAt.millisecondsSinceEpoch,
        'bust': t.bust ? 1 : 0,
        'checkout_darts': t.checkoutDarts,
      });
    }

    await batch.commit(noResult: true);
  }

  // ── Origin snapshots ────────────────────────────────────────────────────────

  /// The stats snapshots a player carries per sending device, keyed by device
  /// id. What this device produced itself is not in here; it stays in the
  /// player's `local_stats_json`.
  Future<Map<String, String>> getOriginSnapshots(int playerId) async {
    final d = await db;
    final rows = await d.query('player_origin_stats',
        where: 'player_id = ?', whereArgs: [playerId]);
    return {
      for (final r in rows)
        r['origin_device'] as String: r['snapshot_json'] as String,
    };
  }

  /// Writes what an incoming packet knows about each device, replacing the
  /// snapshot per device rather than adding to it.
  ///
  /// [localDevice] is this device's own id, and any origin naming it is
  /// dropped: those numbers were produced here, this device still holds the
  /// throws behind them, and taking them back in would count them twice.
  ///
  /// The caller clears the sending device's row and the legacy one first, so
  /// those two always take what the packet says. The legacy bucket goes along
  /// because it cannot be told apart from the receiver's own, and letting both
  /// stand would count one old sync twice, which is the failure that cannot be
  /// seen afterwards. What that costs is a third device's contribution from
  /// before origins existed, and one sync with that device brings it back.
  ///
  /// A device that is only being passed on keeps whichever snapshot covers
  /// more darts. Its own syncs are the fresher account of it, and a device that
  /// syncs with two others would otherwise have its history set back to
  /// whatever the one in the middle happened to know about it.
  Future<void> replaceOriginSnapshots(
    int playerId,
    List<SyncOrigin> origins, {
    required String localDevice,
  }) async {
    final d = await db;

    for (final origin in origins) {
      if (origin.device == localDevice) continue;
      if (origin.snapshotJson.isEmpty) continue;

      final rows = await d.query('player_origin_stats',
          columns: ['snapshot_json'],
          where: 'player_id = ? AND origin_device = ?',
          whereArgs: [playerId, origin.device]);

      if (rows.isNotEmpty &&
          _dartsIn(rows.first['snapshot_json'] as String) >=
              _dartsIn(origin.snapshotJson)) {
        continue;
      }

      await d.insert(
        'player_origin_stats',
        {
          'player_id':     playerId,
          'origin_device': origin.device,
          'snapshot_json': origin.snapshotJson,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// How many darts a snapshot accounts for, which is what tells two accounts
  /// of the same device apart: a snapshot only ever grows.
  static int _dartsIn(String snapshotJson) {
    try {
      return (jsonDecode(snapshotJson) as Map<String, dynamic>)['total_darts']
              as int? ??
          0;
    } catch (_) {
      return 0;
    }
  }

  /// Drops the snapshots [origins] name for a player, so an import can replace
  /// what a device sent before instead of adding to it.
  Future<void> deleteOriginSnapshots(
      int playerId, Set<String> origins) async {
    if (origins.isEmpty) return;
    final d = await db;
    await d.delete(
      'player_origin_stats',
      where: 'player_id = ? AND origin_device IN '
          '(${origins.map((_) => '?').join(',')})',
      whereArgs: [playerId, ...origins],
    );
  }

  /// Every snapshot a player carries added together: this device's own plus
  /// one per device that ever synced to it.
  ///
  /// This is what the statistics screens read. Keeping the parts separate is
  /// only about being able to replace one of them on the next sync; nothing
  /// that displays a lifetime number cares where it came from.
  Future<String?> combinedSnapshotJson(int playerId) async {
    final d = await db;

    final playerRows = await d.query('players',
        columns: ['local_stats_json'], where: 'id = ?', whereArgs: [playerId]);
    final own = playerRows.isEmpty
        ? null
        : playerRows.first['local_stats_json'] as String?;

    final origins = await getOriginSnapshots(playerId);
    return mergeSnapshots([own, ...origins.values]);
  }

  /// Adds any number of stats snapshots together and returns the result as
  /// JSON, or null when none of them held anything.
  ///
  /// Counters sum and maxima take the larger value, which is what makes this
  /// safe only for snapshots covering different throws. Two snapshots over the
  /// same games would double every count in them.
  static String? mergeSnapshots(Iterable<String?> snapshots) {
    Map<String, dynamic>? merged;

    for (final snapshot in snapshots) {
      if (snapshot == null || snapshot.isEmpty) continue;
      try {
        final decoded = jsonDecode(snapshot) as Map<String, dynamic>;
        merged = merged == null ? decoded : _mergeStats(merged, decoded);
      } catch (_) {
        // A snapshot that will not parse is one device's history lost, not the
        // whole screen: the rest still adds up.
      }
    }

    return merged == null ? null : jsonEncode(merged);
  }

  /// Records the last sync time and optional received stats snapshot for a player.
  Future<void> updatePlayerSyncTime(int playerId, int syncedAt,
      {String? syncedStatsJson}) async {
    final d = await db;
    final map = <String, dynamic>{'last_synced_at': syncedAt};
    if (syncedStatsJson != null) map['synced_stats'] = syncedStatsJson;
    await d.update('players', map,
        where: 'id = ?', whereArgs: [playerId]);
  }

  // ── Cricket ──────────────────────────────────────────────────────────────────

  /// Inserts a Cricket game and returns its id.
  Future<int> insertCricketGame(CricketGame g) async {
    final d = await db;
    final map = g.toMap()..remove('id');
    return d.insert('cricket_games', map);
  }

  /// Updates a Cricket game row (e.g. to mark it finished).
  Future<void> updateCricketGame(CricketGame g) async {
    final d = await db;
    await d.update('cricket_games', g.toMap(),
        where: 'id = ?', whereArgs: [g.id]);
  }

  /// Inserts a Cricket dart and returns its id.
  Future<int> insertCricketThrow(CricketThrow t) async {
    final d = await db;
    final map = t.toMap()..remove('id');
    return d.insert('cricket_throws', map);
  }

  /// Deletes the Cricket dart with [id] (used by undo).
  Future<void> deleteCricketThrow(int id) async {
    final d = await db;
    await d.delete('cricket_throws', where: 'id = ?', whereArgs: [id]);
  }

  /// All Cricket darts for a game in chronological order.
  Future<List<CricketThrow>> getCricketThrowsForGame(int gameId) async {
    final d = await db;
    final rows = await d.query(
      'cricket_throws',
      where: 'game_id = ?',
      whereArgs: [gameId],
      // Ties on the millisecond are possible, so the row id decides. The
      // replay in every provider depends on a stable order.
      orderBy: 'thrown_at ASC, id ASC',
    );
    return rows.map(CricketThrow.fromMap).toList();
  }

  /// All Cricket games, newest first.
  Future<List<CricketGame>> getCricketGames() async {
    final d = await db;
    final rows = await d.query('cricket_games', orderBy: 'created_at DESC');
    return rows.map(CricketGame.fromMap).toList();
  }

  /// Permanently deletes a Cricket game and its darts.
  Future<void> deleteCricketGame(int gameId) async {
    final d = await db;
    await d.delete('cricket_throws', where: 'game_id = ?', whereArgs: [gameId]);
    await d.delete('cricket_games', where: 'id = ?', whereArgs: [gameId]);
  }

  // ── Shanghai ─────────────────────────────────────────────────────────────────

  /// Inserts a Shanghai game and returns its id.
  Future<int> insertShanghaiGame(ShanghaiGame g) async {
    final d = await db;
    final map = g.toMap()..remove('id');
    return d.insert('shanghai_games', map);
  }

  /// Updates a Shanghai game row (e.g. to mark it finished).
  Future<void> updateShanghaiGame(ShanghaiGame g) async {
    final d = await db;
    await d.update('shanghai_games', g.toMap(),
        where: 'id = ?', whereArgs: [g.id]);
  }

  /// Inserts a Shanghai dart and returns its id.
  Future<int> insertShanghaiThrow(ShanghaiThrow t) async {
    final d = await db;
    final map = t.toMap()..remove('id');
    return d.insert('shanghai_throws', map);
  }

  /// Deletes the Shanghai dart with [id] (used by undo).
  Future<void> deleteShanghaiThrow(int id) async {
    final d = await db;
    await d.delete('shanghai_throws', where: 'id = ?', whereArgs: [id]);
  }

  /// All Shanghai darts for a game in chronological order.
  Future<List<ShanghaiThrow>> getShanghaiThrowsForGame(int gameId) async {
    final d = await db;
    final rows = await d.query(
      'shanghai_throws',
      where: 'game_id = ?',
      whereArgs: [gameId],
      // Ties on the millisecond are possible, so the row id decides. The
      // replay in every provider depends on a stable order.
      orderBy: 'thrown_at ASC, id ASC',
    );
    return rows.map(ShanghaiThrow.fromMap).toList();
  }

  /// All Shanghai games, newest first.
  Future<List<ShanghaiGame>> getShanghaiGames() async {
    final d = await db;
    final rows = await d.query('shanghai_games', orderBy: 'created_at DESC');
    return rows.map(ShanghaiGame.fromMap).toList();
  }

  /// Permanently deletes a Shanghai game and its darts.
  Future<void> deleteShanghaiGame(int gameId) async {
    final d = await db;
    await d.delete('shanghai_throws', where: 'game_id = ?', whereArgs: [gameId]);
    await d.delete('shanghai_games', where: 'id = ?', whereArgs: [gameId]);
  }

  // ── Around the Clock ─────────────────────────────────────────────────────────

  /// Inserts an Around the Clock game and returns its id.
  Future<int> insertAroundTheClockGame(AroundTheClockGame g) async {
    final d = await db;
    final map = g.toMap()..remove('id');
    return d.insert('around_the_clock_games', map);
  }

  /// Updates an Around the Clock game row (e.g. to mark it finished).
  Future<void> updateAroundTheClockGame(AroundTheClockGame g) async {
    final d = await db;
    await d.update('around_the_clock_games', g.toMap(),
        where: 'id = ?', whereArgs: [g.id]);
  }

  /// Inserts an Around the Clock dart and returns its id.
  Future<int> insertAroundTheClockThrow(AroundTheClockThrow t) async {
    final d = await db;
    final map = t.toMap()..remove('id');
    return d.insert('around_the_clock_throws', map);
  }

  /// Deletes the Around the Clock dart with [id] (used by undo).
  Future<void> deleteAroundTheClockThrow(int id) async {
    final d = await db;
    await d.delete('around_the_clock_throws', where: 'id = ?', whereArgs: [id]);
  }

  /// All Around the Clock darts for a game in chronological order.
  Future<List<AroundTheClockThrow>> getAroundTheClockThrowsForGame(int gameId) async {
    final d = await db;
    final rows = await d.query(
      'around_the_clock_throws',
      where: 'game_id = ?',
      whereArgs: [gameId],
      // Ties on the millisecond are possible, so the row id decides. The
      // replay in every provider depends on a stable order.
      orderBy: 'thrown_at ASC, id ASC',
    );
    return rows.map(AroundTheClockThrow.fromMap).toList();
  }

  /// All Around the Clock games, newest first.
  Future<List<AroundTheClockGame>> getAroundTheClockGames() async {
    final d = await db;
    final rows = await d.query('around_the_clock_games', orderBy: 'created_at DESC');
    return rows.map(AroundTheClockGame.fromMap).toList();
  }

  /// Permanently deletes an Around the Clock game and its darts.
  Future<void> deleteAroundTheClockGame(int gameId) async {
    final d = await db;
    await d.delete('around_the_clock_throws', where: 'game_id = ?', whereArgs: [gameId]);
    await d.delete('around_the_clock_games', where: 'id = ?', whereArgs: [gameId]);
  }

  // ── Checkout Ladder ──────────────────────────────────────────────────────────

  /// Inserts a Checkout Ladder game and returns its id.
  Future<int> insertCheckoutLadderGame(CheckoutLadderGame g) async {
    final d = await db;
    final map = g.toMap()..remove('id');
    return d.insert('checkout_ladder_games', map);
  }

  /// Updates a Checkout Ladder game row (e.g. to mark it finished).
  Future<void> updateCheckoutLadderGame(CheckoutLadderGame g) async {
    final d = await db;
    await d.update('checkout_ladder_games', g.toMap(),
        where: 'id = ?', whereArgs: [g.id]);
  }

  /// Inserts a Checkout Ladder dart and returns its id.
  Future<int> insertCheckoutLadderThrow(CheckoutLadderThrow t) async {
    final d = await db;
    final map = t.toMap()..remove('id');
    return d.insert('checkout_ladder_throws', map);
  }

  /// Deletes the Checkout Ladder dart with [id] (used by undo).
  Future<void> deleteCheckoutLadderThrow(int id) async {
    final d = await db;
    await d.delete('checkout_ladder_throws', where: 'id = ?', whereArgs: [id]);
  }

  /// All Checkout Ladder darts for a game in chronological order.
  Future<List<CheckoutLadderThrow>> getCheckoutLadderThrowsForGame(int gameId) async {
    final d = await db;
    final rows = await d.query(
      'checkout_ladder_throws',
      where: 'game_id = ?',
      whereArgs: [gameId],
      // Ties on the millisecond are possible, so the row id decides. The
      // replay in every provider depends on a stable order.
      orderBy: 'thrown_at ASC, id ASC',
    );
    return rows.map(CheckoutLadderThrow.fromMap).toList();
  }

  /// All Checkout Ladder games, newest first.
  Future<List<CheckoutLadderGame>> getCheckoutLadderGames() async {
    final d = await db;
    final rows = await d.query('checkout_ladder_games', orderBy: 'created_at DESC');
    return rows.map(CheckoutLadderGame.fromMap).toList();
  }

  /// Permanently deletes a Checkout Ladder game and its darts.
  Future<void> deleteCheckoutLadderGame(int gameId) async {
    final d = await db;
    await d.delete('checkout_ladder_throws', where: 'game_id = ?', whereArgs: [gameId]);
    await d.delete('checkout_ladder_games', where: 'id = ?', whereArgs: [gameId]);
  }

  // ── Backup and restore ───────────────────────────────────────────────────────

  /// Value of the `format` row that marks a file as a DartScore backup.
  static const String kBackupMarker = 'dartscore-backup';

  /// The tables a file must have before it is offered as a restore. A database
  /// picked from anywhere on the device can be anything, and replacing the live
  /// file with it is not undoable.
  static const List<String> _kRequiredTables = [
    'players',
    'games',
    'dart_throws',
  ];

  /// Prepares the live database to be copied out as a backup and returns the
  /// path to copy from.
  ///
  /// Writes the markers a restore reads back, then folds the write-ahead log
  /// into the main file. That checkpoint is the point of this method: in WAL
  /// mode the newest games sit in the companion `-wal` file, so a copy of
  /// `dartscore.db` alone silently misses them, and the resulting backup looks
  /// perfectly fine until someone needs it.
  Future<String> prepareBackup(String deviceId, String deviceLabel) async {
    final d = await db;
    final meta = {
      'format':       kBackupMarker,
      'device_id':    deviceId,
      'device_label': deviceLabel,
      'created_at':   '${DateTime.now().millisecondsSinceEpoch}',
    };
    for (final entry in meta.entries) {
      await d.insert('app_meta', {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await d.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    return databasePath;
  }

  /// Reads what the file at [path] holds, without touching the live database.
  ///
  /// Returns null when it is not a readable SQLite database or does not carry
  /// this app's tables. A file from a newer app version is described rather
  /// than rejected here, so the caller can say so instead of failing blankly.
  Future<BackupInfo?> inspectBackup(String path) async {
    Database? file;
    try {
      file = await openReadOnlyDatabase(path);

      final tables = (await file.query('sqlite_master',
              columns: ['name'], where: "type = 'table'"))
          .map((r) => r['name'] as String)
          .toSet();
      if (!_kRequiredTables.every(tables.contains)) return null;

      final meta = <String, String>{};
      if (tables.contains('app_meta')) {
        for (final row in await file.query('app_meta')) {
          meta[row['key'] as String] = row['value'] as String;
        }
      }

      // The table names above are a weak test: any database that happens to
      // carry them would pass, and what follows a restore is not undoable. The
      // marker is the strong one, and no backup this app ever wrote is without
      // it: [prepareBackup] stamps it on every way out, and the backup feature
      // and the `app_meta` table arrived in the same schema version.
      if (meta['format'] != kBackupMarker) return null;

      final createdAt = int.tryParse(meta['created_at'] ?? '');
      var games = 0;
      for (final table in [
        'games',
        'cricket_games',
        'shanghai_games',
        'around_the_clock_games',
        'checkout_ladder_games',
      ]) {
        if (!tables.contains(table)) continue;
        games += Sqflite.firstIntValue(
                await file.rawQuery('SELECT COUNT(*) FROM $table')) ??
            0;
      }

      return BackupInfo(
        schemaVersion: await file.getVersion(),
        deviceId:      meta['device_id'],
        deviceLabel:   meta['device_label'],
        createdAt:     createdAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(createdAt),
        playerCount: Sqflite.firstIntValue(await file.rawQuery(
                'SELECT COUNT(*) FROM players WHERE is_deleted = 0 AND bot_level IS NULL')) ??
            0,
        gameCount:  games,
        sizeBytes:  await File(path).length(),
      );
    } catch (_) {
      return null;
    } finally {
      await file?.close();
    }
  }

  /// Re-files everything a just-restored database called its own as [source]'s.
  ///
  /// A game played on a device carries no device id at all: `origin_device` is
  /// null, and null means "mine". So a database restored onto a different phone
  /// arrives claiming a history that phone never played, and both devices then
  /// hold the same games as their own. That is what makes a plain copy a
  /// one-way door: two devices claiming one history cannot sync, because each
  /// would take the other's copy of it for a second one.
  ///
  /// Stamping the source's id onto it says what is actually true, and the rest
  /// follows from rules that already exist: the two go on syncing, throws
  /// deduplicate on their timestamps, and a third device sees those games once,
  /// under the device that played them, whichever of the two hands them over.
  ///
  /// Only ever for a backup from another device. Restoring one's own on the
  /// same phone must leave it alone, or the history loses what only a device's
  /// own games carry through a sync: the perfect legs, the best game average
  /// and the games played.
  Future<void> attributeRestoredHistory(String source) async {
    final d = await db;

    await d.update('games', {'origin_device': source},
        where: 'origin_device IS NULL');

    // The snapshot on the player row means "this device's own cleared games",
    // so it has to move into the source's bucket with everything else. Merged
    // rather than overwritten: a backup can already hold a snapshot for the
    // source device if it once received data back from it.
    final players = await d.query('players',
        columns: ['id', 'local_stats_json'],
        where: "local_stats_json IS NOT NULL AND local_stats_json != ''");

    for (final row in players) {
      final playerId = row['id'] as int;
      final own = row['local_stats_json'] as String;

      final existing = await d.query('player_origin_stats',
          columns: ['snapshot_json'],
          where: 'player_id = ? AND origin_device = ?',
          whereArgs: [playerId, source]);

      final merged = mergeSnapshots([
        own,
        if (existing.isNotEmpty) existing.first['snapshot_json'] as String,
      ]);

      if (merged != null) {
        await d.insert(
          'player_origin_stats',
          {
            'player_id':     playerId,
            'origin_device': source,
            'snapshot_json': merged,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await d.update('players', {'local_stats_json': null},
          where: 'id = ?', whereArgs: [playerId]);
    }
  }

  /// Replaces the live database with the file at [sourcePath] and reopens it,
  /// running whatever migration the restored file still needs.
  ///
  /// The current file is only moved aside, not deleted, until the new one is
  /// open, so a failure anywhere in between leaves the device on the data it
  /// already had. The `-wal` and `-shm` companions have to go: they belong to
  /// the old database, and leaving them beside a new file is how a restore ends
  /// up as a mixture of both.
  Future<void> replaceDatabase(String sourcePath) async {
    final path   = await databasePath;
    final target = File(path);
    final aside  = File('$path.replaced');

    await _db?.close();
    _db = null;

    if (await aside.exists()) await aside.delete();
    if (await target.exists()) await target.rename(aside.path);
    for (final companion in ['$path-wal', '$path-shm']) {
      final file = File(companion);
      if (await file.exists()) await file.delete();
    }

    try {
      await File(sourcePath).copy(path);
      await db;
    } catch (_) {
      await _db?.close();
      _db = null;
      if (await target.exists()) await target.delete();
      if (await aside.exists()) await aside.rename(path);
      rethrow;
    }

    await aside.delete();
  }
}

/// What this device would hand over right now, for the screen that is about to
/// offer it: the same summary a receiver reads out of the file, taken from the
/// live database instead.
///
/// Read after [prepareBackup], so the markers it reports are the ones the file
/// will carry.
extension LocalBackupSummary on DbHelper {
  Future<BackupInfo> describeLocal() async {
    final d = await db;
    final meta = {
      for (final row in await d.query('app_meta'))
        row['key'] as String: row['value'] as String,
    };

    var games = 0;
    for (final table in [
      'games',
      'cricket_games',
      'shanghai_games',
      'around_the_clock_games',
      'checkout_ladder_games',
    ]) {
      games +=
          Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM $table')) ??
              0;
    }

    final createdAt = int.tryParse(meta['created_at'] ?? '');
    return BackupInfo(
      schemaVersion: DbHelper.schemaVersion,
      deviceId:      meta['device_id'],
      deviceLabel:   meta['device_label'],
      createdAt:     createdAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdAt),
      playerCount: Sqflite.firstIntValue(await d.rawQuery(
              'SELECT COUNT(*) FROM players WHERE is_deleted = 0 AND bot_level IS NULL')) ??
          0,
      gameCount: games,
      sizeBytes: await File(await databasePath).length(),
    );
  }
}

/// What a candidate backup file was found to hold, read before a restore
/// replaces anything.
class BackupInfo {
  /// Schema version the file was written at. One above this app's own means it
  /// comes from a newer version, which cannot be restored here: the migrations
  /// that would explain the file do not exist in this build yet.
  final int schemaVersion;

  /// Id of the device that wrote the backup. Stamped onto the restored history
  /// when it lands on a different device, so it stays attributed to the one
  /// that played it.
  final String? deviceId;

  /// What that device calls itself, "iPhone" or "Android". For the user to
  /// read, and nothing else: it says nothing about which device it was.
  final String? deviceLabel;

  /// When the backup was written, or null for a file without the marker.
  final DateTime? createdAt;

  /// Players and games the file contains, shown so the user can tell one backup
  /// from another before overwriting anything.
  final int playerCount;
  final int gameCount;

  /// How large the file is, so the user knows what a transfer is in for.
  final int sizeBytes;

  const BackupInfo({
    required this.schemaVersion,
    required this.deviceId,
    required this.deviceLabel,
    required this.createdAt,
    required this.playerCount,
    required this.gameCount,
    required this.sizeBytes,
  });
}
