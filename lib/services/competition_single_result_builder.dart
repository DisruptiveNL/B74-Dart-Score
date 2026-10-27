import '../database/db_helper.dart';
import '../models/dart_throw.dart';
import 'competition_match_catalog.dart';
import 'competition_single_result_contract.dart';

/// Creates a reproducible result from persisted X01 visits, never from UI
/// counters. Call only after the game has been durably marked finished.
class CompetitionSingleResultBuilder {
  CompetitionSingleResultBuilder({DbHelper? helper})
    : _db = helper ?? DbHelper.instance;

  final DbHelper _db;

  Future<String> prepare(
    CompetitionMatchSummary match,
    CompetitionSingleSummary single,
  ) async {
    final existing = await _db.competitionSingleResult(match.id, single.slot);
    if (existing != null) {
      // Preserve the exact bytes across retries and across process restarts.
      return existing['payload'] as String;
    }

    final gameId = await _db.competitionGameId(match.id, single.slot);
    if (gameId == null) throw StateError('Geen gekoppelde X01-single');
    final game = await _db.getGame(gameId);
    if (game == null || game.finishedAt == null) {
      throw StateError('Single is nog niet definitief uitgespeeld');
    }
    if (game.isTeamGame || game.placementMode || game.sets != 1) {
      throw StateError('Onverwacht wedstrijdformaat voor single');
    }

    final database = await _db.db;
    Future<int> localId(String externalId) async {
      final rows = await database.query(
        'competition_player_links',
        columns: ['player_id'],
        where: 'external_player_id = ?',
        whereArgs: [externalId],
      );
      if (rows.length != 1) {
        throw StateError('Speler $externalId heeft geen lokale koppeling');
      }
      return rows.single['player_id'] as int;
    }

    final home = await localId(single.homeId);
    final away = await localId(single.awayId);
    if (home == away) throw StateError('Identieke lokale spelers');
    final participants = (await _db.getGamePlayerIds(gameId)).toSet();
    if (participants.length != 2 ||
        !participants.contains(home) ||
        !participants.contains(away)) {
      throw StateError('Spelers komen niet overeen met de gespeelde single');
    }

    final throws = await _db.getThrowsForGame(gameId);
    final homeLegs = _countCheckouts(throws, home);
    final awayLegs = _countCheckouts(throws, away);
    final target = game.legs;
    if ((homeLegs != target && awayLegs != target) ||
        (homeLegs == target && awayLegs == target) ||
        homeLegs > target ||
        awayLegs > target) {
      throw StateError('Ongeldige eindstand uit geregistreerde legs');
    }

    Map<String, dynamic> stats(int id) {
      final visits = throws.where((t) => t.playerId == id).toList();
      final darts = visits.fold<int>(0, (sum, t) => sum + t.dartsUsed);
      final scored = visits.fold<int>(
        0,
        (sum, t) => sum + (t.bust ? 0 : t.score),
      );
      return {
        'visits': visits.length,
        'darts': darts,
        'scored': scored,
        'average3Dart': darts == 0 ? 0.0 : scored * 3 / darts,
        'highestVisit': visits.fold<int>(
          0,
          (best, t) => !t.bust && t.score > best ? t.score : best,
        ),
        'checkoutAttempts': visits.fold<int>(
          0,
          (sum, t) => sum + t.checkoutDarts,
        ),
      };
    }

    final result = CompetitionSingleResultContract.encode({
      'type': CompetitionSingleResultContract.type,
      'version': CompetitionSingleResultContract.version,
      'resultId': CompetitionSingleResultContract.resultId(
        match.id,
        single.slot,
      ),
      'matchId': match.id,
      'slot': single.slot,
      'homePlayerId': single.homeId,
      'awayPlayerId': single.awayId,
      'homeLegs': homeLegs,
      'awayLegs': awayLegs,
      'winnerPlayerId': homeLegs > awayLegs ? single.homeId : single.awayId,
      'statistics': {'home': stats(home), 'away': stats(away)},
    });
    await _db.saveCompletedCompetitionSingleResult(
      match.id,
      single.slot,
      result,
    );
    return result;
  }

  static int _countCheckouts(List<DartThrow> throws, int playerId) => throws
      .where((t) => t.playerId == playerId && !t.bust && t.remainingAfter == 0)
      .length;
}
