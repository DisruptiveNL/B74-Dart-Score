import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Optional, best-effort mirror of the existing TV snapshots.
/// A TV connection is mandatory; this service never initiates TV traffic.
class B74OnlineLive {
  B74OnlineLive._();
  static final instance = B74OnlineLive._();
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'b74_online_live_token_v1';
  static const _endpoint = 'https://api.disruptivesolutions.nl/api/live';
  static const _lane = '1';
  static const _minimumInterval = Duration(seconds: 16);
  static const _heartbeatInterval = Duration(seconds: 60);

  bool enabled = false;
  bool _tvConnected = false;
  String? _token;
  Map<String, dynamic>? _lastSnapshot;
  DateTime? _lastSent;
  Timer? _heartbeat;
  Timer? _pending;
  bool _busy = false;
  bool _urgentPending = false;
  bool _dirty = false;
  int _lastSequence = 0;

  Future<bool> hasToken() async =>
      (await _storage.read(key: _tokenKey))?.isNotEmpty == true;

  Future<void> enable({String? activationCode}) async {
    if (!_tvConnected) throw StateError('TV is niet verbonden');
    final code = activationCode?.trim();
    if (code != null && code.isNotEmpty) {
      await _storage.write(key: _tokenKey, value: code);
      _token = code;
    } else {
      _token = await _storage.read(key: _tokenKey);
    }
    if (_token == null || _token!.isEmpty) {
      throw StateError('Online Live-activatiecode ontbreekt');
    }
    enabled = true;
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) => _schedulePublish());
    _schedulePublish();
  }

  void tvConnectionChanged(bool connected) {
    _tvConnected = connected;
    if (!connected) {
      // Disable immediately; best-effort DELETE, TTL handles lost connectivity.
      unawaited(disable());
    }
  }

  Future<void> disable() async {
    final wasEnabled = enabled;
    enabled = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    _pending?.cancel();
    _pending = null;
    _lastSnapshot = null;
    _lastSent = null;
    _urgentPending = false;
    _dirty = false;
    if (wasEnabled) await _request('DELETE');
  }

  void onTvSnapshot(Map<String, dynamic> snapshot) {
    if (!enabled || !_tvConnected) return;
    _lastSnapshot = Map<String, dynamic>.from(snapshot);
    _dirty = true;
    if (snapshot['payload'] is Map &&
        (snapshot['payload'] as Map)['displayState'] == 'MATCH_COMPLETE') {
      _urgentPending = true;
    }
    _schedulePublish();
  }

  void _schedulePublish() {
    if (!enabled || !_tvConnected || _lastSnapshot == null) return;
    if (_busy) return;
    final urgent = _urgentPending;
    final last = _lastSent;
    final delay = last == null ? Duration.zero :
        _minimumInterval - DateTime.now().difference(last);
    if (!urgent && delay > Duration.zero) {
      _pending ??= Timer(delay, () {
        _pending = null;
        _schedulePublish();
      });
      return;
    }
    _pending?.cancel();
    _pending = null;
    unawaited(_publish());
  }

  Future<void> _publish() async {
    if (_busy || !enabled || !_tvConnected || _lastSnapshot == null) return;
    _busy = true;
    final urgent = _urgentPending;
    _urgentPending = false;
    _dirty = false;
    _lastSent = DateTime.now();
    final snapshot = Map<String, dynamic>.from(_lastSnapshot!);
    // Cloud sequences remain increasing across app/TV reconnects.
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastSequence = now > _lastSequence ? now : _lastSequence + 1;
    snapshot['sequence'] = _lastSequence;
    try {
      final status = await _request('POST', snapshot);
      if ((status == null || status == 429 || status >= 500) &&
          enabled && _tvConnected) {
        // Keep the latest state queued; retry without disturbing TV scoring.
        _dirty = true;
        if (urgent) _urgentPending = true;
        _lastSent = DateTime.now();
      }
    } finally {
      _busy = false;
      if (enabled && _tvConnected && (_dirty || _urgentPending)) {
        // A new score or final state may have arrived during the request.
        // Failed urgent sends retry after a short delay (KV per-key limit).
        if (_urgentPending && _dirty) {
          _pending?.cancel();
          _pending = Timer(const Duration(seconds: 2), () {
            _pending = null;
            _schedulePublish();
          });
        } else {
          _schedulePublish();
        }
      }
    }
  }

  Future<int?> _request(String method, [Map<String, dynamic>? body]) async {
    final token = _token;
    if (token == null || token.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(method, Uri.parse(_endpoint))
          .timeout(const Duration(seconds: 6));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set('X-B74-Lane', _lane);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(const Duration(seconds: 6));
      final status = response.statusCode;
      await response.drain<void>().timeout(const Duration(seconds: 6));
      return status;
    } catch (_) {
      // Offline or rate limited: never interrupt local scoring.
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
