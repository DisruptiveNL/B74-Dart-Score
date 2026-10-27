import '../database/db_helper.dart';
import '../models/game.dart';
import '../models/player.dart';
import 'competition_match_catalog.dart';
import 'competition_sync_contract.dart';

/// Resolves the frozen roster to locally linked player profiles.
/// Never merges by name or alters a player's existing preferences.
class CompetitionSingleLauncher {
  CompetitionSingleLauncher({DbHelper? helper}) : _db = helper ?? DbHelper.instance;
  final DbHelper _db;

  Future<int?> existingGameId(String matchId, int slot) =>
      _db.competitionGameId(matchId, slot);

  Future<List<Player>> players(CompetitionSingleSummary single,
      {required bool homeStarts}) async {
    final db = await _db.db;
    Future<Player> find(String externalId) async {
      final links = await db.query('competition_player_links',
          columns: ['player_id'], where: 'external_player_id = ?',
          whereArgs: [externalId]);
      if (links.length != 1) {
        throw StateError('Speler $externalId is niet gekoppeld');
      }
      final player = await _db.getPlayer(links.single['player_id'] as int);
      if (player == null || player.isDeleted || player.isBot) {
        throw StateError('Gekoppelde speler is niet beschikbaar');
      }
      return player;
    }
    final home = await find(single.homeId);
    final away = await find(single.awayId);
    if (home.id == away.id) throw StateError('Spelers verwijzen naar hetzelfde profiel');
    return homeStarts ? [home, away] : [away, home];
  }

  static bool? homeStarts(CompetitionMatchSummary match,
      CompetitionSingleSummary single) {
    final side = CompetitionX01Rules.startingTeam(
        match.rules['startPolicy'] as String, single.slot - 1);
    return side == null ? null : side == 'home';
  }

  static Game game(CompetitionMatchSummary match) {
    final rules = match.rules;
    CompetitionX01Rules.validate(rules);
    GameMode inMode(String value) => switch (value) {
      'double' => GameMode.doubleIn,
      'master' => GameMode.masterIn,
      _ => GameMode.straightIn,
    };
    CheckoutMode outMode(String value) => switch (value) {
      'straight' => CheckoutMode.straightOut,
      'master' => CheckoutMode.masterOut,
      _ => CheckoutMode.doubleOut,
    };
    // X01's legs field is first-to-N, not the total Best-of number.
    return Game(
      startScore: rules['startingScore'] as int,
      gameMode: inMode(rules['checkIn'] as String),
      checkoutMode: outMode(rules['checkOut'] as String),
      legs: ((rules['bestOf'] as int) + 1) ~/ 2,
      sets: 1,
      createdAt: DateTime.now(),
      startingOrder: StartingOrder.fixed,
    );
  }
}
