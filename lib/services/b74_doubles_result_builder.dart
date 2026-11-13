import 'b74_doubles_701.dart';
import 'b74_doubles_live_stats.dart';
import 'b74_doubles_result_contract.dart';
import 'b74_team_match_contract.dart';
import 'competition_dummy_identity.dart';

/// Pure 701 result serialization. Input is the persisted match packet and the
/// correction-aware replay of its journal; no UI counters are trusted.
class B74DoublesResultBuilder {
  static String build({
    required Map<String, dynamic> packet,
    required B74Doubles701 engine,
    required B74DoublesLiveStats stats,
  }) {
    B74TeamMatchContract.validate(packet);
    if (!{'doubles701', 'beer1001'}.contains(packet['kind']) || engine.winner == null) {
      throw StateError('Alleen een uitgespeelde 701-koppelwedstrijd');
    }
    if (engine.bestOf != packet['bestOf']) {
      throw StateError('Best-of wijkt af van het wedstrijdformulier');
    }
    final home = packet['home'] as Map<String, dynamic>;
    final away = packet['away'] as Map<String, dynamic>;
    final sides = [home, away];
    final players = <Map<String, dynamic>>[];
    for (var team = 0; team < 2; team++) {
      final side = sides[team];
      final teamId = side['teamId'] as String;
      final members = side['players'] as List;
      for (var index = 0; index < (packet['kind'] == 'beer1001' ? 4 : 2); index++) {
        final player = members[index] as Map<String, dynamic>;
        final dummy = CompetitionDummyIdentity.isDummyBond(
          player['bondNumber'] as String?,
        );
        final stat = stats.player(team, index);
        players.add({
          'playerId': player['playerId'],
          'teamId': teamId,
          if (dummy) 'officialStatisticsEligible': false,
          'statistics': dummy ? <String, dynamic>{} : {
            'visits': stat.visits,
            'darts': stat.dartsThrown,
            'scored': stat.points,
            'average3Dart': stat.threeDartAverage,
            'firstNineAverage': stat.firstNineAverage,
            'highestVisit': stat.bestVisit,
            'hundreds': stat.hundreds,
            'oneForties': stat.oneForties,
            'oneEighties': stat.oneEighties,
          },
        });
      }
    }
    final matchId = packet['matchId'] as String;
    final slot = packet['slot'] as int;
    return B74DoublesResultContract.encode({
      'type': B74DoublesResultContract.type,
      'version': B74DoublesResultContract.version,
      'resultId': B74DoublesResultContract.resultId(matchId, slot, kind: packet['kind'] as String),
      'kind': packet['kind'],
      'matchId': matchId,
      'gameId': packet['gameId'],
      'slot': slot,
      'revision': packet['revision'],
      'homeTeamId': home['teamId'],
      'awayTeamId': away['teamId'],
      'bestOf': engine.bestOf,
      'homeLegs': engine.legsWon[0],
      'awayLegs': engine.legsWon[1],
      'winnerTeamId': sides[engine.winner!]['teamId'],
      'players': players,
    });
  }
}
