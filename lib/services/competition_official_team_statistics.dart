import 'dart:convert';
import 'competition_statistics_policy.dart';

/// Separate, read-only official projections. No singles statistics are used.
enum OfficialTeamDiscipline { doubles701, beer1001 }

class OfficialTeamStanding {
  const OfficialTeamStanding(this.identity, this.games, this.wins,
      this.legsWon, this.legsLost, this.points, this.darts, this.oneEighties);
  final String identity;
  final int games, wins, legsWon, legsLost, points, darts, oneEighties;
  /// Combined 3-dart average, weighted by actual darts (never player-average mean).
  double get average3Dart => darts == 0 ? 0 : points * 3 / darts;
}

class CompetitionOfficialTeamStatistics {
  /// Outbox rows must contain both payload and match_payload (inbox packet).
  /// Deduplicates by game ID; a pair is identified by team and sorted player IDs.
  static List<OfficialTeamStanding> aggregate(
      OfficialTeamDiscipline discipline, Iterable<Map<String, Object?>> rows) {
    final totals = <String, List<int>>{};
    final seen = <String>{};
    final kind = discipline == OfficialTeamDiscipline.doubles701
        ? 'doubles701' : 'beer1001';
    for (final row in rows) {
      try {
        final id = row['game_id'];
        if (id is! String || id.isEmpty || seen.contains(id)) continue;
        final match = jsonDecode(row['match_payload'] as String);
        final result = jsonDecode(row['payload'] as String);
        if (match is! Map<String, dynamic> || result is! Map<String, dynamic> ||
            match['kind'] != kind || result['kind'] != kind ||
            match['gameId'] != id || result['gameId'] != id ||
            match['matchId'] != result['matchId'] ||
            match['revision'] != result['revision'] ||
            !CompetitionStatisticsPolicy.countsTowardsOfficialStatistics(
                match['division'] as String?)) continue;
        final homeLegs = result['homeLegs'];
        final awayLegs = result['awayLegs'];
        if (homeLegs is! int || awayLegs is! int ||
            homeLegs < 0 || awayLegs < 0 || homeLegs == awayLegs) continue;
        final identities = <String>[];
        final teams = <String>[];
        final performances = <List<int>>[];
        final playerStats = result['players'];
        if (playerStats is! List) continue;
        for (final sideName in ['home', 'away']) {
          final side = match[sideName] as Map<String, dynamic>;
          final teamId = side['teamId'] as String;
          final members = side['players'] as List;
          if (members.length != (kind == 'doubles701' ? 2 : 4)) {
            throw const FormatException('Wrong player count');
          }
          final ids = members.map((p) => (p as Map)['playerId'] as String).toList();
          if (ids.toSet().length != ids.length || ids.any((x) => x.isEmpty)) {
            throw const FormatException('Invalid player IDs');
          }
          final matching = playerStats.where((p) =>
              p is Map && p['teamId'] == teamId).toList();
          if (matching.length != ids.length ||
              matching.map((p) => (p as Map)['playerId']).toSet().length != ids.length ||
              matching.any((p) => !ids.contains((p as Map)['playerId']))) {
            throw const FormatException('Player statistics do not match lineup');
          }
          var points = 0, darts = 0, oneEighties = 0;
          for (final player in matching) {
            final stats = (player as Map)['statistics'];
            if (stats is! Map) throw const FormatException('Missing stats');
            final scored = stats['scored'];
            final thrown = stats['darts'];
            final maximums = stats['oneEighties'];
            if (scored is! int || thrown is! int || maximums is! int ||
                scored < 0 || thrown < 0 || maximums < 0 ||
                maximums * 180 > scored || maximums * 3 > thrown) {
              throw const FormatException('Invalid performance');
            }
            points += scored;
            darts += thrown;
            oneEighties += maximums;
          }
          performances.add([points, darts, oneEighties]);
          ids.sort();
          teams.add(teamId);
          identities.add(kind == 'doubles701' ? '$teamId:${ids.join("|")}' : teamId);
        }
        if (teams[0] == teams[1] ||
            result['homeTeamId'] != teams[0] ||
            result['awayTeamId'] != teams[1] ||
            result['winnerTeamId'] !=
                (homeLegs > awayLegs ? teams[0] : teams[1])) continue;
        seen.add(id);
        for (var i = 0; i < 2; i++) {
          final t = totals.putIfAbsent(identities[i], () => [0, 0, 0, 0, 0, 0, 0]);
          t[0]++;
          if (result['winnerTeamId'] == teams[i]) t[1]++;
          t[2] += i == 0 ? homeLegs : awayLegs;
          t[3] += i == 0 ? awayLegs : homeLegs;
          t[4] += performances[i][0];
          t[5] += performances[i][1];
          t[6] += performances[i][2];
        }
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on NoSuchMethodError {
        continue;
      }
    }
    final result = totals.entries.map((e) => OfficialTeamStanding(
      e.key, e.value[0], e.value[1], e.value[2], e.value[3],
      e.value[4], e.value[5], e.value[6],
    )).toList();
    result.sort((a, b) => a.identity.compareTo(b.identity));
    return result;
  }
}
