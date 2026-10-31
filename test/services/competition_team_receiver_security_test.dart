import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/services/b74_session_manager.dart';
import 'package:dartscore_app/services/competition_sync_receiver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

// Creates a real dart:io client, bypassing Flutter Test's zone-local
// HTTP 400 stub only inside this integration test's loopback request.
class _LoopbackHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  useInMemoryDatabase();
  late CompetitionSyncReceiver receiver;
  final key = List<int>.filled(32, 7);
  final payload = jsonEncode({
    'type': 'b74.competition.team-match.v1', 'version': 1,
    'matchId': 'match-1', 'gameId': 'game-1', 'revision': 1,
    'kind': 'doubles701', 'slot': 1, 'startingScore': 701,
    'bestOf': 3, 'startPolicy': 'home',
    'home': {'teamId': 'home', 'teamName': 'Home', 'players': [
      {'playerId': 'a', 'name': 'A', 'bondNumber': '101', 'position': 1},
      {'playerId': 'b', 'name': 'B', 'bondNumber': '102', 'position': 2},
    ]},
    'away': {'teamId': 'away', 'teamName': 'Away', 'players': [
      {'playerId': 'c', 'name': 'C', 'bondNumber': '201', 'position': 1},
      {'playerId': 'd', 'name': 'D', 'bondNumber': '202', 'position': 2},
    ]},
  });

  Future<int> send(String nonce, String body, {bool valid = true}) async {
    return HttpOverrides.runWithHttpOverrides(() async {
      final client = HttpClient();
      try {
      final req = await client.postUrl(Uri.parse(
        'http://127.0.0.1:${receiver.port}/b74/competition/team-import'));
      req.headers.set('x-b74-team-nonce', nonce);
      final digest = sha256.convert(utf8.encode(body)).toString();
      final proof = b74Session.operationProof('dashboard',
          'competition-team-import-v1\n$nonce\n$digest')!;
      req.headers.set('x-b74-team-proof', valid ? proof : 'bad-proof');
      req.write(body);
      final response = await req.close();
      await response.drain<void>();
      return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }, _LoopbackHttpOverrides());
  }

  setUp(() async {
    b74Session.revoke();
    receiver = CompetitionSyncReceiver();
    await receiver.start(bindAddress: InternetAddress.loopbackIPv4);
    b74Session.activateVerified(peerId: 'b74-dashboard',
      sessionKey: key, verifiedAtUtc: DateTime.now().toUtc());
  });
  tearDown(() async {
    await receiver.stop();
    b74Session.revoke();
  });

  test('authenticated team import commits and new nonce retries safely', () async {
    expect(await send('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', payload), HttpStatus.ok);
    expect((await DbHelper.instance.competitionTeamMatch('game-1'))!['revision'], 1);
    expect(await send('BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', payload), HttpStatus.ok);
    expect((await (await DbHelper.instance.db).query('competition_team_inbox')).length, 1);
  });
  test('rejects invalid signature and nonce replay', () async {
    expect(await send('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', payload, valid: false), HttpStatus.forbidden);
    expect(await DbHelper.instance.competitionTeamMatch('game-1'), isNull);
    expect(await send('DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD', payload), HttpStatus.ok);
    expect(await send('DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD', payload), HttpStatus.forbidden);
  });
  test('malformed signed packet rejected without storing', () async {
    expect(await send('EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE', '{broken'), HttpStatus.badRequest);
    expect((await (await DbHelper.instance.db).query('competition_team_inbox')), isEmpty);
  });
}
