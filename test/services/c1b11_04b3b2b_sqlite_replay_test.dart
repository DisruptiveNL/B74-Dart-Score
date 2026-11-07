import 'dart:convert';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/services/b74_doubles_session.dart';
import 'package:dartscore_app/services/b74_match_rules_contract.dart';
import 'package:dartscore_app/services/b74_team_match_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

Map<String, dynamic> _group(
  String kind, {
  required int startingScore,
  String checkIn = 'straight',
  String checkOut = 'double',
}) => {
  'startingScore': startingScore,
  'bestOf': kind == 'beer' ? 1 : 3,
  'checkIn': checkIn,
  'checkOut': checkOut,
  'startPolicy': 'fixedHome',
  'bullDecidingLeg': false,
  'winPoints': 1,
};

Map<String, dynamic> _side(String side, int count, int base) => {
  'teamId': side,
  'teamName': side,
  'players': List.generate(count, (i) => {
    'playerId': '$side-$i',
    'name': '$side speler $i',
    'bondNumber': '${base + i}',
    'position': i + 1,
  }),
};

Map<String, dynamic> _packet(
  String gameId, {
  required bool beer,
  required int score,
  String checkIn = 'straight',
  String checkOut = 'double',
}) {
  return {
    'type': B74TeamMatchContract.type,
    'version': B74TeamMatchContract.version,
    'matchId': 'match-$gameId',
    'gameId': gameId,
    'revision': 1,
    'kind': beer ? 'beer1001' : 'doubles701',
    'slot': 1,
    'startingScore': score,
    'bestOf': beer ? 1 : 3,
    'checkIn': checkIn,
    'startPolicy': 'home',
    'home': _side('home', beer ? 4 : 2, 100),
    'away': _side('away', beer ? 4 : 2, 200),
    'matchRules': B74MatchRulesContract.create(
      matchId: 'match-$gameId',
      matchType: 'regular',
      snapshot: {
        'version': 1,
        'singles': _group('singles', startingScore: 501),
        'doubles': _group(
          'doubles',
          startingScore: beer ? 701 : score,
          checkIn: beer ? 'straight' : checkIn,
          checkOut: beer ? 'double' : checkOut,
        ),
        'beer': _group(
          'beer',
          startingScore: beer ? score : 1001,
          checkIn: beer ? checkIn : 'straight',
          checkOut: beer ? checkOut : 'double',
        ),
      },
    ),
  };
}

Future<B74DoublesSession> _seed(
  String gameId, {
  required bool beer,
  required int score,
  String checkIn = 'straight',
  String checkOut = 'double',
}) async {
  final raw = B74TeamMatchContract.encode(_packet(
    gameId, beer: beer, score: score, checkIn: checkIn, checkOut: checkOut,
  ));
  await DbHelper.instance.receiveCompetitionTeamMatch(raw);
  final session = await B74DoublesSession.load(gameId);
  await session.confirmStarter(0);
  return B74DoublesSession.load(gameId);
}

void main() {
  group('C1B11 04B.3B2B: SQLite-herstel teamwedstrijden', () {
    useInMemoryDatabase();

    test('koppels: 301, Double In en Master Out blijven na replay behouden', () async {
      final session = await _seed(
        'doubles-restore', beer: false, score: 301,
        checkIn: 'double', checkOut: 'master',
      );
      expect(session.startingScore, 301);
      expect(session.checkIn, 'double');
      expect(session.checkOut, 'master');
      await session.completeVisit(
        score: 52, openingDouble: 32, openingDart: 2,
      );

      final restored = await B74DoublesSession.load('doubles-restore');
      expect(restored.startingScore, 301);
      expect(restored.checkIn, 'double');
      expect(restored.checkOut, 'master');
      expect(restored.engine.remaining[0], 249);
      expect(restored.engine.opened[0], isTrue);
      expect(restored.engine.opened[1], isFalse);
      expect(restored.engine.currentVisit.team, 1);
      expect(restored.correctableVisits.single.score, 52);
    });

    test('biergame: 501 en Straight Out overleven replay en undo', () async {
      final session = await _seed(
        'beer-restore', beer: true, score: 501, checkOut: 'straight',
      );
      expect(session.playersPerTeam, 4);
      await session.completeVisit(score: 60);
      final restored = await B74DoublesSession.load('beer-restore');
      expect(restored.startingScore, 501);
      expect(restored.checkOut, 'straight');
      expect(restored.engine.remaining[0], 441);
      expect(restored.engine.currentVisit.team, 1);
      await restored.undoLastVisit();
      final undone = await B74DoublesSession.load('beer-restore');
      expect(undone.engine.remaining, [501, 501]);
      expect(undone.engine.currentVisit.team, 0);
      expect(undone.correctableVisits, isEmpty);
      expect(
        (await DbHelper.instance.competitionDoublesEvents('beer-restore'))
            .map((raw) => (jsonDecode(raw) as Map)['type'])
            .toList(),
        ['starter', 'visit', 'undoVisit'],
      );
    });

    test('koppels: drie beurten corrigeerbaar na SQLite-replay', () async {
      var session = await _seed('undo-restore', beer: false, score: 701);
      for (final score in [60, 45, 26, 41]) {
        await session.completeVisit(score: score);
        session = await B74DoublesSession.load('undo-restore');
      }
      expect(session.correctableVisits.map((v) => v.score).toList(), [41, 26, 45]);
      await session.undoLastVisit();
      final restored = await B74DoublesSession.load('undo-restore');
      expect(restored.correctableVisits.map((v) => v.score).toList(), [26, 45, 60]);
      expect(restored.engine.remaining, [615, 656]);
      expect(restored.engine.currentVisit.team, 1);
    });
  });
}
