import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_admin_deletion_authorization.dart';
import 'package:dartscore_app/services/b74_admin_deletion_wire_contract.dart';
import 'package:dartscore_app/services/b74_session_manager.dart';

void main() {
  final at = DateTime.utc(2026, 11, 2, 20);
  B74SessionManager session() {
    final manager = B74SessionManager(clock: () => at);
    manager.activateVerified(peerId: 'dashboard',
      sessionKey: List<int>.generate(32, (i) => i + 1), verifiedAtUtc: at);
    return manager;
  }
  Map<String, Object> request() => B74AdminDeletionWireContract.request(
    matchId: 'official-1', revision: 1, scope: 'official',
    statisticsMode: 'retain', authorizationId: 'unique-1');

  test('paired proof binds every request field', () {
    final sender = session(); final receiver = session();
    final signed = B74AdminDeletionAuthorization.issue(session: sender,
      request: request(), adminPinVerified: true,
      explicitFinalConfirmation: true, now: at);
    expect(B74AdminDeletionAuthorization.verify(session: receiver,
      envelope: signed, now: at)['matchId'], 'official-1');
    for (final field in ['matchId', 'revision', 'scope',
        'statisticsMode', 'authorizationId']) {
      final altered = Map<String, dynamic>.from(signed);
      altered['request'] = <String, Object>{...request(),
        field: field == 'revision' ? 2 : field == 'scope'
          ? 'historical_development' : field == 'statisticsMode'
          ? 'remove' : 'changed'};
      expect(() => B74AdminDeletionAuthorization.verify(
        session: receiver, envelope: altered, now: at), throwsA(anyOf(isA<StateError>(), isA<FormatException>())));
    }
    sender.dispose(); receiver.dispose();
  });

  test('unpaired, missing PIN or confirmation are rejected', () {
    final paired = session(); final unpaired = B74SessionManager(clock: () => at);
    expect(() => B74AdminDeletionAuthorization.issue(session: paired,
      request: request(), adminPinVerified: false,
      explicitFinalConfirmation: true, now: at), throwsStateError);
    expect(() => B74AdminDeletionAuthorization.issue(session: paired,
      request: request(), adminPinVerified: true,
      explicitFinalConfirmation: false, now: at), throwsStateError);
    expect(() => B74AdminDeletionAuthorization.issue(session: unpaired,
      request: request(), adminPinVerified: true,
      explicitFinalConfirmation: true, now: at), throwsStateError);
    paired.dispose(); unpaired.dispose();
  });

  test('expired and different-session proofs fail closed', () {
    final sender = session(); final receiver = session();
    final signed = B74AdminDeletionAuthorization.issue(session: sender,
      request: request(), adminPinVerified: true,
      explicitFinalConfirmation: true, now: at);
    expect(() => B74AdminDeletionAuthorization.verify(session: receiver,
      envelope: signed, now: at.add(const Duration(minutes: 4))),
      throwsStateError);
    receiver.revoke();
    expect(() => B74AdminDeletionAuthorization.verify(session: receiver,
      envelope: signed, now: at), throwsStateError);
    sender.dispose(); receiver.dispose();
  });
}
