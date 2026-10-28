import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// A single-use QR bootstrap challenge. This is NOT a trusted pairing until
/// the peer has been confirmed and a device secret has been securely stored.
class B74PairingChallenge {
  B74PairingChallenge({
    required this.deviceId,
    required this.host,
    required this.port,
    required this.nonce,
    required this.issuedAtUtc,
  });

  final String deviceId;
  final String host;
  final int port;
  final String nonce;
  final DateTime issuedAtUtc;
  static const ttl = Duration(minutes: 2);

  factory B74PairingChallenge.generate({
    required String deviceId,
    required String host,
    required int port,
    DateTime? now,
  }) {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return B74PairingChallenge(
      deviceId: deviceId,
      host: host,
      port: port,
      nonce: base64Url.encode(bytes),
      issuedAtUtc: (now ?? DateTime.now()).toUtc(),
    );
  }

  bool validAt(DateTime now) {
    final elapsed = now.toUtc().difference(issuedAtUtc);
    return deviceId.isNotEmpty &&
        host.isNotEmpty &&
        port > 0 &&
        port <= 65535 &&
        nonce.isNotEmpty &&
        !elapsed.isNegative &&
        elapsed < ttl;
  }

  String encode() => jsonEncode({
    'protocol': 'b74-pairing-v1',
    'deviceId': deviceId,
    'host': host,
    'port': port,
    'nonce': nonce,
    'issuedAtUtc': issuedAtUtc.toIso8601String(),
  });

  factory B74PairingChallenge.decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value['protocol'] != 'b74-pairing-v1' ||
        value['deviceId'] is! String ||
        value['host'] is! String ||
        value['port'] is! int ||
        value['nonce'] is! String ||
        value['issuedAtUtc'] is! String) {
      throw const FormatException('Ongeldige B74-koppelcode');
    }
    final challenge = B74PairingChallenge(
      deviceId: value['deviceId'] as String,
      host: value['host'] as String,
      port: value['port'] as int,
      nonce: value['nonce'] as String,
      issuedAtUtc: DateTime.parse(value['issuedAtUtc'] as String).toUtc(),
    );
    if (!challenge.validAt(DateTime.now().toUtc())) {
      throw const FormatException('Koppelcode is verlopen of ongeldig');
    }
    return challenge;
  }
}

/// Tracks bootstrap challenges already consumed. Persist this state before
/// accepting a pairing: an in-memory set alone is not reboot-safe.
class B74ChallengeReplayGuard {
  final Set<String> _consumed = {};
  bool consume(B74PairingChallenge challenge, DateTime now) {
    if (!challenge.validAt(now)) return false;
    return _consumed.add('${challenge.deviceId}:${challenge.nonce}');
  }
}

/// Message MAC for an already established shared key. Never send the key on
/// the network or persist it in plaintext SQLite.
class B74MessageAuthenticator {
  static String sign({
    required List<int> key,
    required String method,
    required String path,
    required String timestamp,
    required String requestNonce,
    required List<int> body,
  }) {
    if (key.length < 32) throw ArgumentError('Key must be >= 256 bits');
    final bodyHash = sha256.convert(body).toString();
    final canonical = '$method\n$path\n$timestamp\n$requestNonce\n$bodyHash';
    return Hmac(sha256, key).convert(utf8.encode(canonical)).toString();
  }

  static bool verify({
    required List<int> key,
    required String method,
    required String path,
    required String timestamp,
    required String requestNonce,
    required List<int> body,
    required String suppliedMac,
  }) {
    final expected = sign(
      key: key, method: method, path: path, timestamp: timestamp,
      requestNonce: requestNonce, body: body,
    );
    if (suppliedMac.length != expected.length) return false;
    var mismatch = 0;
    for (var i = 0; i < expected.length; i++) {
      mismatch |= expected.codeUnitAt(i) ^ suppliedMac.codeUnitAt(i);
    }
    return mismatch == 0;
  }
}
