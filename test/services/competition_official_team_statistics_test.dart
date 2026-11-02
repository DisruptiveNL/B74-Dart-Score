import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_official_team_statistics.dart';

Map<String, Object?> row(String game, String kind, String division,
    {bool reversed = false}) {
  final homeIds = reversed ? ['b', 'a'] : ['a', 'b'];
  final match = {
    'gameId': game, 'matchId': 'm$game', 'revision': 1,
    'kind': kind, 'division': division,
    'home': {
      'teamId': 'home',
      'players': (kind == 'beer1001' ? ['a','b','c','d'] : homeIds)
          .map((id) => {'playerId': id}).toList(),
    },
    'away': {
      'teamId': 'away',
      'players': (kind == 'beer1001' ? ['e','f','g','h'] : ['e','f'])
          .map((id) => {'playerId': id}).toList(),
    },
  };
  final result = {
    'gameId': game, 'matchId': 'm$game', 'revision': 1,
    'kind': kind, 'homeTeamId': 'home', 'awayTeamId': 'away',
    'homeLegs': 3, 'awayLegs': 1, 'winnerTeamId': 'home',
    'players': [
      for (final side in ['home', 'away'])
        for (final p in (match[side] as Map)['players'] as List)
          {'playerId': p['playerId'],
           'teamId': (match[side] as Map)['teamId'],
           'statistics': {'scored': 180, 'darts': 3, 'oneEighties': 1}},
    ],
  };
  return {'game_id': game, 'match_payload': jsonEncode(match),
      'payload': jsonEncode(result)};
}

void main() {
  test('koppelidentiteit is volgorde-onafhankelijk; herhaling telt eenmaal', () {
    final first = row('1', 'doubles701', 'Eredivisie');
    final results = CompetitionOfficialTeamStatistics.aggregate(
        OfficialTeamDiscipline.doubles701,
        [first, first, row('2', 'doubles701', 'Eredivisie', reversed: true)]);
    final home = results.singleWhere((r) => r.identity == 'home:a|b');
    expect(home.games, 2);
    expect(home.wins, 2);
    expect(home.legsWon, 6);
  });

  test('test telt nooit mee, wel andere divisies', () {
    final results = CompetitionOfficialTeamStatistics.aggregate(
        OfficialTeamDiscipline.doubles701, [
      row('1', 'doubles701', ' TEST '),
      row('2', 'doubles701', 'Eredivisie'),
    ]);
    expect(results.singleWhere((r) => r.identity == 'home:a|b').games, 1);
  });

  test('biergame blijft teamdiscipline, niet koppel', () {
    final rows = [row('1', 'beer1001', 'Eredivisie')];
    final beer = CompetitionOfficialTeamStatistics.aggregate(
        OfficialTeamDiscipline.beer1001, rows);
    expect(beer.singleWhere((r) => r.identity == 'home').games, 1);
    expect(CompetitionOfficialTeamStatistics.aggregate(
        OfficialTeamDiscipline.doubles701, rows), isEmpty);
  });

  test('inconsistente uitslag wordt niet officieel verwerkt', () {
    final source = row('1', 'doubles701', 'Eredivisie');
    final payload = jsonDecode(source['payload'] as String) as Map<String,dynamic>;
    payload['winnerTeamId'] = 'away';
    final corrupt = {...source, 'payload': jsonEncode(payload)};
    expect(CompetitionOfficialTeamStatistics.aggregate(
        OfficialTeamDiscipline.doubles701, [corrupt]), isEmpty);
  });
  test('gewogen gemiddelde en 180s blijven bij het koppel', () {
    final standings = CompetitionOfficialTeamStatistics.aggregate(
        OfficialTeamDiscipline.doubles701,
        [row('1', 'doubles701', 'Eredivisie')]);
    final home = standings.singleWhere((s) => s.identity == 'home:a|b');
    expect(home.points, 360);
    expect(home.darts, 6);
    expect(home.average3Dart, 180);
    expect(home.oneEighties, 2);
  });

  test('biergame telt gezamenlijke teamstatistieken', () {
    final standings = CompetitionOfficialTeamStatistics.aggregate(
        OfficialTeamDiscipline.beer1001,
        [row('1', 'beer1001', 'Eredivisie')]);
    final home = standings.singleWhere((s) => s.identity == 'home');
    expect(home.points, 720);
    expect(home.darts, 12);
    expect(home.oneEighties, 4);
  });

  test('testwedstrijden dragen geen punten of 180s bij', () {
    final standings = CompetitionOfficialTeamStatistics.aggregate(
        OfficialTeamDiscipline.doubles701,
        [row('1', 'doubles701', ' test ')]);
    expect(standings, isEmpty);
  });

}
