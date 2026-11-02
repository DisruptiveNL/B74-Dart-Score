import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_admin_deletion_wire_contract.dart';

void main() {
  Map<String, Object> valid({String scope = 'official', String stats = 'remove'}) =>
      B74AdminDeletionWireContract.request(
        matchId: 'match-1', revision: 1, scope: scope,
        statisticsMode: stats, authorizationId: 'auth-1');

  test('officiele en historische scope, statistiekmodus blijven expliciet', () {
    for (final scope in ['official', 'historical_development']) {
      for (final stats in ['retain', 'remove']) {
        final request = valid(scope: scope, stats: stats);
        expect(B74AdminDeletionWireContract.decode(
          B74AdminDeletionWireContract.encode(request)), request);
      }
    }
  });

  test('onbekende scope, statistiekmodus en lege autorisatie geweigerd', () {
    expect(() => valid(scope: 'test'), throwsFormatException);
    expect(() => valid(stats: 'maybe'), throwsFormatException);
    expect(() => B74AdminDeletionWireContract.request(
      matchId: 'match-1', revision: 1, scope: 'official',
      statisticsMode: 'remove', authorizationId: ''), throwsFormatException);
  });

  test('v1 TEST-verwijderverzoek is geen admin-opdracht', () {
    expect(() => B74AdminDeletionWireContract.decode(jsonEncode({
      'type': 'b74.match.deletion.request', 'version': 1,
      'matchId': 'match-1', 'division': 'test', 'revision': 1,
      'retainOfficialStatistics': false,
    })), throwsFormatException);
  });

  test('onbekende velden en ongeldige revisie worden geweigerd', () {
    final extra = {...valid(), 'adminPin': '123456'};
    expect(() => B74AdminDeletionWireContract.decode(jsonEncode(extra)),
        throwsFormatException);
    expect(() => B74AdminDeletionWireContract.request(
      matchId: 'match-1', revision: 0, scope: 'official',
      statisticsMode: 'remove', authorizationId: 'auth-1'),
        throwsFormatException);
  });
}
