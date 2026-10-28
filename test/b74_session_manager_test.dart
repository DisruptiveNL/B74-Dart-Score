import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_session_manager.dart';

void main() {
  test('new process starts unpaired', () {
    expect(B74SessionManager().phase, B74ConnectionPhase.unpaired);
  });
  test('authenticated session goes offline without losing trust', () {
    final now = DateTime.utc(2026, 10, 28, 20);
    final session = B74SessionManager(clock: () => now);
    session.activateVerified(
      peerId: 'tablet-1',
      sessionKey: List<int>.filled(32, 7),
      verifiedAtUtc: now,
    );
    session.markReachable(false);
    expect(session.phase, B74ConnectionPhase.offline);
    expect(session.hasKey, isTrue);
    session.markReachable(true);
    expect(session.phase, B74ConnectionPhase.connected);
  });
  test('expires after 48 hours and clears session key', () {
    var now = DateTime.utc(2026, 10, 28, 20);
    final session = B74SessionManager(clock: () => now);
    session.activateVerified(
      peerId: 'tablet-1',
      sessionKey: List<int>.filled(32, 7),
      verifiedAtUtc: now,
    );
    now = now.add(const Duration(hours: 48));
    expect(session.phase, B74ConnectionPhase.expired);
    expect(session.hasKey, isFalse);
  });
  test('invalid handshake result cannot activate', () {
    final session = B74SessionManager();
    expect(
      () => session.activateVerified(
        peerId: 'x', sessionKey: [1, 2],
        verifiedAtUtc: DateTime.now().toUtc(),
      ),
      throwsArgumentError,
    );
  });
}
