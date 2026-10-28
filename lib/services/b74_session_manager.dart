import 'b74_pairing_proof.dart';
import 'package:flutter/foundation.dart';

/// Process-local authenticated session state.
/// A successful QR scan or LAN probe must NEVER call activate().
enum B74ConnectionPhase { unpaired, connected, offline, expired }

class B74SessionSnapshot {
  const B74SessionSnapshot(this.phase, this.peerId, this.expiresAtUtc);
  final B74ConnectionPhase phase;
  final String? peerId;
  final DateTime? expiresAtUtc;
}

/// No disk persistence: Android process death/restart requires a new pairing.
/// Only the verified handshake implementation may invoke activate().
class B74SessionManager extends ChangeNotifier {
  B74SessionManager({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const maxLifetime = Duration(hours: 48);
  final DateTime Function() _clock;
  B74ConnectionPhase _phase = B74ConnectionPhase.unpaired;
  String? _peerId;
  DateTime? _expiresAtUtc;
  List<int>? _sessionKey;

  B74ConnectionPhase get phase {
    _expireIfNeeded();
    return _phase;
  }

  String? get peerId => _peerId;
  DateTime? get expiresAtUtc => _expiresAtUtc;
  bool get hasKey => _sessionKey != null;

  /// Authenticates a fixed protocol operation without exposing the session key.
  /// Do not use this as a substitute for per-message MACs on match traffic.
  String? operationProof(String role, String operation) {
    _expireIfNeeded();
    final key = _sessionKey;
    if (key == null || (_phase != B74ConnectionPhase.connected &&
        _phase != B74ConnectionPhase.offline)) return null;
    return B74PairingProof.proof(key, role, operation);
  }

  bool verifyOperation(String role, String operation, String proof) {
    _expireIfNeeded();
    final key = _sessionKey;
    if (key == null || (_phase != B74ConnectionPhase.connected &&
        _phase != B74ConnectionPhase.offline)) return false;
    return B74PairingProof.verify(key, role, operation, proof);
  }


  B74SessionSnapshot get snapshot {
    _expireIfNeeded();
    return B74SessionSnapshot(_phase, _peerId, _expiresAtUtc);
  }

  /// Caller must have cryptographically verified both peers.
  /// A new key is required for every app process and pairing.
  void activateVerified({
    required String peerId,
    required List<int> sessionKey,
    required DateTime verifiedAtUtc,
  }) {
    if (peerId.trim().isEmpty || sessionKey.length < 32) {
      throw ArgumentError('Invalid authenticated peer or session key');
    }
    final now = _clock().toUtc();
    final verified = verifiedAtUtc.toUtc();
    if (verified.isAfter(now.add(const Duration(seconds: 30))) ||
        now.difference(verified) > const Duration(minutes: 2)) {
      throw ArgumentError('Verification timestamp is stale');
    }
    revoke(notify: false);
    _peerId = peerId;
    _sessionKey = List<int>.from(sessionKey);
    _expiresAtUtc = verified.add(maxLifetime);
    _phase = B74ConnectionPhase.connected;
    notifyListeners();
  }

  void markReachable(bool reachable) {
    _expireIfNeeded();
    if (_phase != B74ConnectionPhase.connected &&
        _phase != B74ConnectionPhase.offline) return;
    final next = reachable
        ? B74ConnectionPhase.connected
        : B74ConnectionPhase.offline;
    if (next != _phase) {
      _phase = next;
      notifyListeners();
    }
  }

  void revoke({bool notify = true}) {
    final hadState = _phase != B74ConnectionPhase.unpaired;
    final key = _sessionKey;
    if (key != null) {
      for (var i = 0; i < key.length; i++) {
        key[i] = 0;
      }
    }
    _sessionKey = null;
    _peerId = null;
    _expiresAtUtc = null;
    _phase = B74ConnectionPhase.unpaired;
    if (notify && hadState) notifyListeners();
  }

  void _expireIfNeeded() {
    final expiry = _expiresAtUtc;
    if (expiry == null || _phase == B74ConnectionPhase.expired) return;
    if (!_clock().toUtc().isBefore(expiry)) {
      final key = _sessionKey;
      if (key != null) {
        for (var i = 0; i < key.length; i++) {
          key[i] = 0;
        }
      }
      _sessionKey = null;
      _phase = B74ConnectionPhase.expired;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    revoke(notify: false);
    super.dispose();
  }
}

/// A process singleton, not backed by preferences, SQLite or secure storage.
final b74Session = B74SessionManager();
