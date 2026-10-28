import 'dart:convert';

/// Stable wire format for the B74 48-hour device trust relationship.
/// A network address is a hint, never an identity or authorization proof.
class B74PairingRecord {
  const B74PairingRecord({
    required this.peerId,
    required this.createdAtUtc,
    required this.expiresAtUtc,
    required this.revoked,
    this.lastKnownHost,
    this.lastKnownPort,
  });

  static const maxLifetime = Duration(hours: 48);
  final String peerId;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;
  final bool revoked;
  final String? lastKnownHost;
  final int? lastKnownPort;

  bool validAt(DateTime nowUtc) =>
      !revoked &&
      peerId.isNotEmpty &&
      !createdAtUtc.isAfter(nowUtc.toUtc()) &&
      nowUtc.toUtc().isBefore(expiresAtUtc) &&
      expiresAtUtc.isAfter(createdAtUtc) &&
      expiresAtUtc.difference(createdAtUtc) <= maxLifetime;

  B74PairingRecord withAddress(String host, int port) {
    if (host.trim().isEmpty || port < 1 || port > 65535) {
      throw const FormatException('Invalid network endpoint');
    }
    return B74PairingRecord(
      peerId: peerId,
      createdAtUtc: createdAtUtc,
      expiresAtUtc: expiresAtUtc,
      revoked: revoked,
      lastKnownHost: host.trim(),
      lastKnownPort: port,
    );
  }

  B74PairingRecord revoke() => B74PairingRecord(
    peerId: peerId,
    createdAtUtc: createdAtUtc,
    expiresAtUtc: expiresAtUtc,
    revoked: true,
    lastKnownHost: lastKnownHost,
    lastKnownPort: lastKnownPort,
  );

  Map<String, Object?> toJson() => {
    'peerId': peerId,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'expiresAtUtc': expiresAtUtc.toUtc().toIso8601String(),
    'revoked': revoked,
    'lastKnownHost': lastKnownHost,
    'lastKnownPort': lastKnownPort,
  };

  String encode() => jsonEncode(toJson());

  factory B74PairingRecord.decode(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid pairing record');
    }
    final id = decoded['peerId'];
    final created = decoded['createdAtUtc'];
    final expires = decoded['expiresAtUtc'];
    final revoked = decoded['revoked'];
    if (id is! String ||
        id.isEmpty ||
        created is! String ||
        expires is! String ||
        revoked is! bool) {
      throw const FormatException('Invalid pairing record fields');
    }
    final host = decoded['lastKnownHost'];
    final port = decoded['lastKnownPort'];
    if (host != null && host is! String || port != null && port is! int) {
      throw const FormatException('Invalid endpoint fields');
    }
    return B74PairingRecord(
      peerId: id,
      createdAtUtc: DateTime.parse(created).toUtc(),
      expiresAtUtc: DateTime.parse(expires).toUtc(),
      revoked: revoked,
      lastKnownHost: host as String?,
      lastKnownPort: port as int?,
    );
  }
}
