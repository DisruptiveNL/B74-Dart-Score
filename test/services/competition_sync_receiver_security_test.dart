import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartscore_app/services/b74_session_manager.dart';
import 'package:dartscore_app/services/competition_match_inbox.dart';
import 'package:dartscore_app/services/competition_sync_receiver.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInbox extends CompetitionMatchInbox {
  final List<String> received = <String>[];

  @override
  Future<bool> receive(String json) async {
    received.add(json);
    return true;
  }
}

void main() {
  late CompetitionSyncReceiver receiver;
  late _FakeInbox inbox;
  final key = List<int>.filled(32, 7);
  const payload = '{"matchId":"test-1"}';

  Future<int> send({
    required String nonce,
    required String body,
    String? proof,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${receiver.port}/b74/competition/import'),
      );
      request.headers.set('x-b74-import-nonce', nonce);
      if (proof != null) request.headers.set('x-b74-import-proof', proof);
      request.write(body);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  String signedProof(String nonce, String body) {
    final digest = sha256.convert(utf8.encode(body)).toString();
    return b74Session.operationProof(
      'dashboard',
      'competition-import-v1\n$nonce\n$digest',
    )!;
  }

  void authenticate() {
    b74Session.activateVerified(
      peerId: 'b74-dashboard',
      sessionKey: key,
      verifiedAtUtc: DateTime.now().toUtc(),
    );
  }

  setUp(() async {
    b74Session.revoke();
    inbox = _FakeInbox();
    receiver = CompetitionSyncReceiver(inbox: inbox);
    await receiver.start(bindAddress: InternetAddress.loopbackIPv4);
  });

  tearDown(() async {
    await receiver.stop();
    b74Session.revoke();
  });

  test('rejects import without verified session', () async {
    const nonce = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    expect(
      await send(nonce: nonce, body: payload, proof: 'invalid'),
      HttpStatus.forbidden,
    );
    expect(inbox.received, isEmpty);
  });

  test('accepts valid signed import', () async {
    authenticate();
    const nonce = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
    expect(
      await send(
        nonce: nonce,
        body: payload,
        proof: signedProof(nonce, payload),
      ),
      HttpStatus.ok,
    );
    expect(inbox.received, <String>[payload]);
  });

  test('rejects invalid signature', () async {
    authenticate();
    const nonce = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
    expect(
      await send(nonce: nonce, body: payload, proof: 'not-a-valid-mac'),
      HttpStatus.forbidden,
    );
    expect(inbox.received, isEmpty);
  });

  test('rejects tampered payload', () async {
    authenticate();
    const nonce = 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
    expect(
      await send(
        nonce: nonce,
        body: '{"matchId":"tampered"}',
        proof: signedProof(nonce, payload),
      ),
      HttpStatus.forbidden,
    );
    expect(inbox.received, isEmpty);
  });

  test('rejects replay of an accepted nonce', () async {
    authenticate();
    const nonce = 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';
    final proof = signedProof(nonce, payload);
    expect(
      await send(nonce: nonce, body: payload, proof: proof),
      HttpStatus.ok,
    );
    expect(
      await send(nonce: nonce, body: payload, proof: proof),
      HttpStatus.forbidden,
    );
    expect(inbox.received, hasLength(1));
  });

  test('accepts same nonce after receiver restart and new session', () async {
    authenticate();
    const nonce = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
    final proof = signedProof(nonce, payload);
    expect(
      await send(nonce: nonce, body: payload, proof: proof),
      HttpStatus.ok,
    );

    await receiver.stop();
    await receiver.start(bindAddress: InternetAddress.loopbackIPv4);
    authenticate();

    expect(
      await send(
        nonce: nonce,
        body: payload,
        proof: signedProof(nonce, payload),
      ),
      HttpStatus.ok,
    );
    expect(inbox.received, hasLength(2));
  });
}
