import 'dart:convert';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/services/b74_team_revision_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

Map<String, dynamic> packet(int revision, {String name = 'Thuis A', String gameId = 'game-5', int slot = 1}) => {
  'type': 'b74.competition.team-match.v1',
  'version': 1,
  'matchId': 'match-1',
  'gameId': gameId,
  'revision': revision,
  'kind': 'doubles701',
  'slot': slot,
  'startingScore': 701,
  'bestOf': 3,
  'startPolicy': 'home',
  'home': {
    'teamId': 'home', 'teamName': 'Steady',
    'players': [
      {'playerId': 'a', 'name': name, 'bondNumber': '101', 'position': 1},
      {'playerId': 'b', 'name': 'Thuis B', 'bondNumber': '102', 'position': 2},
    ],
  },
  'away': {
    'teamId': 'away', 'teamName': 'Testteam',
    'players': [
      {'playerId': 'c', 'name': 'Uit A', 'bondNumber': '201', 'position': 1},
      {'playerId': 'd', 'name': 'Uit B', 'bondNumber': '202', 'position': 2},
    ],
  },
};

void main() {
  group('C1B4 durable team inbox', () {
    useInMemoryDatabase();

    test('new packet persists and identical retry is idempotent', () async {
      final helper = DbHelper.instance;
      final raw = jsonEncode(packet(1));
      expect(await helper.receiveCompetitionTeamMatch(raw), B74TeamRevisionDecision.create);
      expect(await helper.receiveCompetitionTeamMatch(raw), B74TeamRevisionDecision.unchanged);
      final stored = await helper.competitionTeamMatch('game-5');
      expect(stored!['revision'], 1);
      expect(stored['payload'], raw);
      final db = await helper.db;
      expect((await db.query('competition_team_inbox')).length, 1);
    });

    test('sequential revision replaces only before start', () async {
      final helper = DbHelper.instance;
      await helper.receiveCompetitionTeamMatch(jsonEncode(packet(1)));
      expect(await helper.receiveCompetitionTeamMatch(jsonEncode(packet(2, name: 'Nieuw'))),
          B74TeamRevisionDecision.replace);
      expect((await helper.competitionTeamMatch('game-5'))!['revision'], 2);
    });

    test('stale, skipped and conflicting revisions do not change storage', () async {
      final helper = DbHelper.instance;
      final raw = jsonEncode(packet(1));
      await helper.receiveCompetitionTeamMatch(raw);
      for (final candidate in [packet(1, name: 'Conflict'), packet(3)]) {
        expect(await helper.receiveCompetitionTeamMatch(jsonEncode(candidate)),
            B74TeamRevisionDecision.reject);
      }
      expect(
        () => helper.receiveCompetitionTeamMatch(jsonEncode(packet(0))),
        throwsFormatException,
      );
      expect((await helper.competitionTeamMatch('game-5'))!['payload'], raw);
    });

    test('started match refuses replacement but identical retry remains idempotent', () async {
      final helper = DbHelper.instance;
      final raw = jsonEncode(packet(1));
      await helper.receiveCompetitionTeamMatch(raw);
      await helper.debugMarkCompetitionTeamStarted('game-5');
      expect(await helper.receiveCompetitionTeamMatch(jsonEncode(packet(2, name: 'Nieuw'))),
          B74TeamRevisionDecision.reject);
      expect(await helper.receiveCompetitionTeamMatch(raw),
          B74TeamRevisionDecision.unchanged);
      expect((await helper.competitionTeamMatch('game-5'))!['revision'], 1);
    });

    test('same match and slot cannot be hijacked by another game id', () async {
      final helper = DbHelper.instance;
      await helper.receiveCompetitionTeamMatch(jsonEncode(packet(1)));
      expect(await helper.receiveCompetitionTeamMatch(jsonEncode(packet(1, gameId: 'other'))),
          B74TeamRevisionDecision.reject);
    });

    test('deletion tombstone blocks delayed doubles and beer imports', () async {
      final helper = DbHelper.instance;
      expect(await helper.receiveCompetitionDeletion(
        matchId: 'match-1', revision: 1, division: 'test',
        retainOfficialStatistics: false,
      ), 'stored');
      expect(await helper.receiveCompetitionTeamMatch(jsonEncode(packet(1))),
          B74TeamRevisionDecision.reject);
      final beer = packet(1, gameId: 'beer-1');
      beer['kind'] = 'beer1001';
      beer['startingScore'] = 1001;
      beer['bestOf'] = 1;
      for (final side in ['home', 'away']) {
        final team = beer[side] as Map<String, dynamic>;
        final prefix = side == 'home' ? 'h' : 'a';
        final bondPrefix = side == 'home' ? '10' : '20';
        team['players'] = <dynamic>[
          ...(team['players'] as List),
          {'playerId': '${prefix}3', 'name': 'Speler 3', 'bondNumber': '${bondPrefix}3', 'position': 3},
          {'playerId': '${prefix}4', 'name': 'Speler 4', 'bondNumber': '${bondPrefix}4', 'position': 4},
        ];
      }
      expect(await helper.receiveCompetitionTeamMatch(jsonEncode(beer)),
          B74TeamRevisionDecision.reject);
      final db = await helper.db;
      expect(await db.query('competition_team_inbox'), isEmpty);
    });

    test('deletion tombstone also blocks replay of existing team match', () async {
      final helper = DbHelper.instance;
      final raw = jsonEncode(packet(1));
      expect(await helper.receiveCompetitionTeamMatch(raw),
          B74TeamRevisionDecision.create);
      await helper.receiveCompetitionDeletion(
        matchId: 'match-1', revision: 1, division: 'test',
        retainOfficialStatistics: false,
      );
      expect(await helper.receiveCompetitionTeamMatch(raw),
          B74TeamRevisionDecision.reject);
      expect((await helper.competitionTeamMatch('game-5'))!['payload'], raw);
    });

    test('different slots coexist without modifying singles tables', () async {
      final helper = DbHelper.instance;
      await helper.receiveCompetitionTeamMatch(jsonEncode(packet(1)));
      expect(await helper.receiveCompetitionTeamMatch(jsonEncode(packet(1, gameId: 'game-6', slot: 2))),
          B74TeamRevisionDecision.create);
      final db = await helper.db;
      expect((await db.query('competition_team_inbox')).length, 2);
      expect(await db.query('competition_inbox'), isEmpty);
      expect(await db.query('competition_game_links'), isEmpty);
    });
  });
}
