import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_session_manager.dart';
import 'package:dartscore_app/services/competition_sync_receiver.dart';

void main() {
  late CompetitionSyncReceiver receiver;
  late HttpClient client;

  setUp(() async {
    b74Session.revoke();
    receiver = CompetitionSyncReceiver();
    await receiver.start(bindAddress: InternetAddress.loopbackIPv4);
    client = HttpClient();
    b74Session.activateVerified(
      peerId: 'dashboard-1',
      sessionKey: List<int>.filled(32, 23),
      verifiedAtUtc: DateTime.now().toUtc(),
    );
  });

  tearDown(() async {
    client.close(force: true);
    await receiver.stop();
  });

  Future<(int, Map<String, dynamic>?)> send(String nonce, String? proof) async {
    final request = await client.post(
      InternetAddress.loopbackIPv4.address,
      receiver.port!,
      '/b74/session/heartbeat',
    );
    request.headers.set('x-b74-heartbeat-nonce', nonce);
    if (proof != null) request.headers.set('x-b74-session-proof', proof);
    final response = await request.close();
    final raw = await utf8.decoder.bind(response).join();
    return (
      response.statusCode,
      raw.isEmpty ? null : jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  test(
    'valid authenticated heartbeat restores offline and returns proof',
    () async {
      b74Session.markReachable(false);
      const nonce = 'test_nonce_12345678901234567890';
      final proof = b74Session.operationProof(
        'dashboard',
        'b74-heartbeat-request-v1:$nonce',
      );
      final (status, body) = await send(nonce, proof);
      expect(status, HttpStatus.ok);
      expect(body?['nonce'], nonce);
      expect(
        b74Session.verifyOperation(
          'tablet',
          'b74-heartbeat-response-v1:$nonce',
          body!['proof'] as String,
        ),
        isTrue,
      );
      expect(b74Session.phase, B74ConnectionPhase.connected);
    },
  );

  test('replay and invalid proof are rejected', () async {
    const nonce = 'test_nonce_12345678901234567890';
    final proof = b74Session.operationProof(
      'dashboard',
      'b74-heartbeat-request-v1:$nonce',
    );
    expect((await send(nonce, proof)).$1, HttpStatus.ok);
    expect((await send(nonce, proof)).$1, HttpStatus.forbidden);
    expect(
      (await send('different_nonce_1234567890123456', 'invalid')).$1,
      HttpStatus.forbidden,
    );
  });

  test('revoked session rejects old heartbeat', () async {
    const nonce = 'test_nonce_12345678901234567890';
    final proof = b74Session.operationProof(
      'dashboard',
      'b74-heartbeat-request-v1:$nonce',
    );
    b74Session.revoke();
    expect((await send(nonce, proof)).$1, HttpStatus.forbidden);
    expect(b74Session.hasKey, isFalse);
  });
}
