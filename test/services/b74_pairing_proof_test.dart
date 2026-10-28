import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_pairing_proof.dart';

void main() {
  test('both peers derive identical proof key', () {
    final qr = B74PairingProof.newNonce();
    final keyA = B74PairingProof.deriveKey(qr, 'dash-nonce', 'tab-nonce');
    final keyB = B74PairingProof.deriveKey(qr, 'dash-nonce', 'tab-nonce');
    expect(keyA, keyB);
    expect(keyA, hasLength(32));
  });
  test('role-specific proof rejects incorrect role and peer', () {
    final key = B74PairingProof.deriveKey(
        B74PairingProof.newNonce(), 'd', 't');
    final mac = B74PairingProof.proof(key, 'tablet', 'tablet-1');
    expect(B74PairingProof.verify(key, 'tablet', 'tablet-1', mac), isTrue);
    expect(B74PairingProof.verify(key, 'dashboard', 'tablet-1', mac), isFalse);
    expect(B74PairingProof.verify(key, 'tablet', 'tablet-2', mac), isFalse);
  });
  test('fresh nonce changes the derived key', () {
    final qr = B74PairingProof.newNonce();
    expect(B74PairingProof.deriveKey(qr, 'd1', 't'),
        isNot(B74PairingProof.deriveKey(qr, 'd2', 't')));
  });
  test('bootstrap nonce can be consumed once', () {
    final registry = B74PairingNonceRegistry();
    expect(registry.consume('nonce'), isTrue);
    expect(registry.consume('nonce'), isFalse);
  });
}
