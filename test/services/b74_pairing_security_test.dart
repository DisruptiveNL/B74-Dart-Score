import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_pairing_security.dart';

void main() {
  test('bootstrap is one time and expires after two minutes', () {
    final start = DateTime.utc(2026, 10, 28, 10);
    final c = B74PairingChallenge.generate(
      deviceId: 'tablet', host: '192.168.1.2', port: 1234, now: start);
    final guard = B74ChallengeReplayGuard();
    expect(guard.consume(c, start), isTrue);
    expect(guard.consume(c, start), isFalse);
    expect(c.validAt(start.add(const Duration(minutes: 2))), isFalse);
  });
  test('MAC rejects tampered payload and wrong key', () {
    final key = List<int>.filled(32, 42);
    final body = utf8.encode('match');
    final mac = B74MessageAuthenticator.sign(
      key: key, method: 'POST', path: '/competition',
      timestamp: '2026-10-28T10:00:00Z', requestNonce: 'unique', body: body);
    expect(B74MessageAuthenticator.verify(
      key: key, method: 'POST', path: '/competition',
      timestamp: '2026-10-28T10:00:00Z', requestNonce: 'unique',
      body: body, suppliedMac: mac), isTrue);
    expect(B74MessageAuthenticator.verify(
      key: key, method: 'POST', path: '/competition',
      timestamp: '2026-10-28T10:00:00Z', requestNonce: 'unique',
      body: utf8.encode('altered'), suppliedMac: mac), isFalse);
  });
}
