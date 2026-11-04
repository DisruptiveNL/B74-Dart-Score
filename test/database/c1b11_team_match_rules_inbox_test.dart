import 'dart:convert';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/services/b74_match_rules_contract.dart';
import 'package:dartscore_app/services/b74_team_revision_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

Map<String, dynamic> _group(int score, int bestOf) => {
  'startingScore': score,
  'bestOf': bestOf,
  'checkIn': 'straight',
  'checkOut': 'double',
  'startPolicy': 'fixedHome',
  'bullDecidingLeg': false,
  'winPoints': 1,
};

Map<String, dynamic> _packet(int revision, {bool withRules = true}) {
  final packet = <String, dynamic>{
    'type': 'b74.competition.team-match.v1',
    'version': 1,
    'matchId': 'match-1',
    'gameId': 'match-1:doubles701:1',
    'revision': revision,
    'kind': 'doubles701',
    'slot': 1,
    'startingScore': 701,
    'bestOf': 5,
    'startPolicy': 'home',
    'home': {
      'teamId': 'home', 'teamName': 'Thuis',
      'players': [
        {'playerId': 'h1', 'name': 'A', 'bondNumber': '101', 'position': 1},
        {'playerId': 'h2', 'name': 'B', 'bondNumber': '102', 'position': 2},
      ],
    },
    'away': {
      'teamId': 'away', 'teamName': 'Uit',
      'players': [
        {'playerId': 'a1', 'name': 'C', 'bondNumber': '201', 'position': 1},
        {'playerId': 'a2', 'name': 'D', 'bondNumber': '202', 'position': 2},
      ],
    },
  };
  if (withRules) {
    packet['matchRules'] = B74MatchRulesContract.create(
      matchId: 'match-1', matchType: 'cup', snapshot: {
        'version': 1,
        'singles': _group(501, 5),
        'doubles': _group(701, 5),
        'beer': _group(1001, 1),
      },
    );
  }
  return packet;
}

void main() {
  group('C1B11 durable team rules inbox', () {
    useInMemoryDatabase();

    test('ontvangen Bekerreglement is duurzaam terug te lezen', () async {
      final helper = DbHelper.instance;
      expect(await helper.receiveCompetitionTeamMatch(jsonEncode(_packet(1))),
          B74TeamRevisionDecision.create);
      final rules = await helper.competitionTeamMatchRules('match-1:doubles701:1');
      expect(rules!['matchType'], 'cup');
      expect(B74MatchRulesContract.forGame(rules, 'beer')['startingScore'], 1001);
      (rules['rules'] as Map<String, dynamic>)['version'] = 999;
      final reread = await helper.competitionTeamMatchRules('match-1:doubles701:1');
      expect((reread!['rules'] as Map<String, dynamic>)['version'], 1);
    });

    test('oude teamberichten krijgen geen verzonnen reglement', () async {
      final helper = DbHelper.instance;
      expect(await helper.competitionTeamMatchRules('onbekend'), isNull);
      await helper.receiveCompetitionTeamMatch(jsonEncode(_packet(1, withRules: false)));
      expect(await helper.competitionTeamMatchRules('match-1:doubles701:1'), isNull);
    });

    test('afgewezen revisie verandert opgeslagen reglement niet', () async {
      final helper = DbHelper.instance;
      await helper.receiveCompetitionTeamMatch(jsonEncode(_packet(1)));
      await helper.debugMarkCompetitionTeamStarted('match-1:doubles701:1');
      final replacement = _packet(2, withRules: false);
      expect(await helper.receiveCompetitionTeamMatch(jsonEncode(replacement)),
          B74TeamRevisionDecision.reject);
      expect((await helper.competitionTeamMatchRules('match-1:doubles701:1'))!['matchType'], 'cup');
    });
  });
}
