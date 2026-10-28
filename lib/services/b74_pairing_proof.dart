import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// QR possession proof protocol. Not a full pairing or transport integration.
/// The QR nonce is a short-lived secret: never log it or send it as plain HTTP
/// outside the QR. Production use requires a protected pairing transport.
class B74PairingProof {
  static const domain = 'b74-pairing-proof-v1';

  static String newNonce() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  static List<int> deriveKey(String qrNonce, String dashboardNonce,
      String tabletNonce) {
    final secret = base64Url.decode(base64Url.normalize(qrNonce));
    if (secret.length != 32 || dashboardNonce.isEmpty || tabletNonce.isEmpty) {
      throw const FormatException('Invalid pairing material');
    }
    return Hmac(sha256, secret).convert(utf8.encode(
        '$domain\n$dashboardNonce\n$tabletNonce')).bytes;
  }

  static String proof(List<int> key, String role, String deviceId) {
    if (key.length != 32 || !['dashboard', 'tablet'].contains(role) ||
        deviceId.isEmpty) {
      throw ArgumentError('Invalid pairing proof parameters');
    }
    return Hmac(sha256, key)
        .convert(utf8.encode('$domain\n$role\n$deviceId'))
        .toString();
  }

  static bool verify(List<int> key, String role, String deviceId,
      String suppliedProof) {
    final expected = proof(key, role, deviceId);
    if (expected.length != suppliedProof.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ suppliedProof.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// One-use bootstrap nonce registry for the current process.
/// Caller must enforce QR expiration before accepting a nonce.
class B74PairingNonceRegistry {
  final Set<String> _consumed = {};
  bool consume(String nonce) => nonce.isNotEmpty && _consumed.add(nonce);
}
