import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/services/b74_match_locked_contract.dart';
import 'package:dartscore_app/services/b74_session_manager.dart';
import 'package:dartscore_app/services/competition_sync_receiver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

// Flutter's test binding overrides HttpClient. Use a real loopback client.
class _LoopbackHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  useInMemoryDatabase();
  late CompetitionSyncReceiver receiver;
  final sessionKey = List<int>.filled(32, 17);
  final packet = <String, dynamic>{
    'type': B74MatchLockedContract.type,
    'version': 1,
    'matchId': 'c1b11-04c3c1-match',
    'closedAt': 1793548800000,
    'homeWins': 5,
    'awayWins': 4,
  };

  Future<(int, Map<String, dynamic>?)> send(
    String nonce,
    Map<String, dynamic> message, {
    bool invalidProof = false,
  }) async {
    return HttpOverrides.runWithHttpOverrides(() async {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse(
            'http://127.0.0.1:${receiver.port}/b74/competition/match-locked',
          ),
        );
        final body = jsonEncode(message);
        final digest = sha256.convert(utf8.encode(body)).toString();
        final proof = b74Session.operationProof(
          'dashboard',
          'competition-match-locked-v1\n$nonce\n$digest',
        )!;
        request.headers.set('x-b74-lock-nonce', nonce);
        request.headers.set(
          'x-b74-lock-proof',
          invalidProof ? 'invalid' : proof,
        );
        request.write(body);
        final response = await request.close();
        final raw = await utf8.decoder.bind(response).join();
        return (
          response.statusCode,
          raw.isEmpty ? null : jsonDecode(raw) as Map<String, dynamic>,
        );
      } finally {
        client.close(force: true);
      }
    }, _LoopbackHttpOverrides());
  }

  void expectAuthenticatedAck(
    Map<String, dynamic>? ack,
    String nonce,
    String expectedStatus,
  ) {
    expect(ack, isNotNull);
    final deliveryId = B74MatchLockedContract.deliveryId(packet);
    expect(ack!['status'], expectedStatus);
    expect(ack['nonce'], nonce);
    expect(ack['deliveryId'], deliveryId);
    expect(
      b74Session.verifyOperation(
        'tablet',
        'competition-match-locked-ack-v1\n$nonce\n$deliveryId\n$expectedStatus',
        ack['proof'] as String,
      ),
      isTrue,
    );
  }

  setUp(() async {
    b74Session.revoke();
    receiver = CompetitionSyncReceiver();
    await receiver.start(bindAddress: InternetAddress.loopbackIPv4);
    b74Session.activateVerified(
      peerId: 'b74-dashboard',
      sessionKey: sessionKey,
      verifiedAtUtc: DateTime.now().toUtc(),
    );
  });

  tearDown(() async {
    await receiver.stop();
    b74Session.revoke();
  });

  test(
    'signed LOCKED is durable and lost-ACK retry returns authenticated unchanged',
    () async {
      const firstNonce = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      const retryNonce = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
      final first = await send(firstNonce, packet);
      expect(first.$1, HttpStatus.ok);
      expectAuthenticatedAck(first.$2, firstNonce, 'stored');
      expect(
        await DbHelper.instance.isCompetitionMatchLocked(
          packet['matchId'] as String,
        ),
        isTrue,
      );

      // Simulate a lost response: retry the same closure with a fresh nonce.
      final retry = await send(retryNonce, packet);
      expect(retry.$1, HttpStatus.ok);
      expectAuthenticatedAck(retry.$2, retryNonce, 'unchanged');
      final rows = await (await DbHelper.instance.db).query(
        'competition_match_locks',
      );
      expect(rows, hasLength(1));
    },
  );

  test(
    'replayed nonce and invalid proof cannot acknowledge or change LOCKED',
    () async {
      const nonce = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
      expect(
        (await send(nonce, packet, invalidProof: true)).$1,
        HttpStatus.forbidden,
      );
      expect(
        await DbHelper.instance.isCompetitionMatchLocked(
          packet['matchId'] as String,
        ),
        isFalse,
      );
      expect((await send(nonce, packet)).$1, HttpStatus.ok);
      expect((await send(nonce, packet)).$1, HttpStatus.forbidden);
      expect(
        (await (await DbHelper.instance.db).query('competition_match_locks')),
        hasLength(1),
      );
    },
  );

  test('completed REMOVE and RETAIN return signed terminal removed ACK', () async {
    final database = await DbHelper.instance.db;
    for (final mode in ['remove', 'retain']) {
      final matchId = '${packet['matchId']}-$mode';
      final message = {...packet, 'matchId': matchId};
      await database.insert('competition_deletion_tombstones', {
        'match_id': matchId,
        'revision': 1,
        'division': 'Eredivisie',
        'retain_official_statistics': mode == 'retain' ? 1 : 0,
        'received_at': 100,
        'cleaned_at': 101,
      });
      final invalidNonce = mode == 'remove'
          ? 'LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL'
          : 'MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM';
      expect((await send(invalidNonce, message, invalidProof: true)).$1,
          HttpStatus.forbidden);
      for (final nonce in [
        mode == 'remove' ? 'GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG' :
          'IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII',
        mode == 'remove' ? 'HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH' :
          'JJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJ',
      ]) {
        final response = await send(nonce, message);
        expect(response.$1, HttpStatus.ok);
        final deliveryId = B74MatchLockedContract.deliveryId(message);
        expect(response.$2!['status'], 'removed');
        expect(response.$2!['nonce'], nonce);
        expect(response.$2!['deliveryId'], deliveryId);
        expect(b74Session.verifyOperation('tablet',
          'competition-match-locked-ack-v1\n$nonce\n$deliveryId\nremoved',
          response.$2!['proof'] as String), isTrue);
      }
      expect(await DbHelper.instance.isCompetitionMatchLocked(matchId), isFalse);
      expect(await database.query('competition_deletion_tombstones',
        where: 'match_id = ?', whereArgs: [matchId]), hasLength(1));
    }
  });

  test('pending deletion cannot yield terminal ACK', () async {
    final database = await DbHelper.instance.db;
    await database.insert('competition_deletion_tombstones', {
      'match_id': packet['matchId'],
      'revision': 1,
      'division': 'test',
      'retain_official_statistics': 0,
      'received_at': 100,
    });
    const nonce = 'KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK';
    final response = await send(nonce, packet);
    expect(response.$1, HttpStatus.conflict);
    expect(response.$2, isNull);
    expect(await DbHelper.instance.isCompetitionMatchLocked(
      packet['matchId'] as String), isFalse);
  });

  test(
    'conflicting LOCKED rejected; restart receiver preserves durable closure',
    () async {
      const firstNonce = 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
      const conflictNonce = 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';
      expect((await send(firstNonce, packet)).$1, HttpStatus.ok);
      final changed = {...packet, 'homeWins': 6, 'awayWins': 3};
      expect((await send(conflictNonce, changed)).$1, HttpStatus.conflict);

      await receiver.stop();
      receiver = CompetitionSyncReceiver();
      await receiver.start(bindAddress: InternetAddress.loopbackIPv4);
      // stop() revokes the process-local session. Simulate a newly verified
      // pairing before retrying the durable MATCH_LOCKED delivery.
      b74Session.activateVerified(
        peerId: 'b74-dashboard',
        sessionKey: sessionKey,
        verifiedAtUtc: DateTime.now().toUtc(),
      );
      const retryNonce = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
      final retry = await send(retryNonce, packet);
      expect(retry.$1, HttpStatus.ok);
      expectAuthenticatedAck(retry.$2, retryNonce, 'unchanged');
      final rows = await (await DbHelper.instance.db).query(
        'competition_match_locks',
      );
      expect(rows, hasLength(1));
      final stored =
          jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>;
      expect(stored, packet);
    },
  );
}
