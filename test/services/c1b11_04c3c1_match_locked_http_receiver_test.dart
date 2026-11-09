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
