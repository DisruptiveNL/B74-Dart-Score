import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Independent online publisher using the existing B74 snapshot contract.
/// TV connection state does not control online activation.
class B74OnlineLive {
  B74OnlineLive._();
  static final instance = B74OnlineLive._();
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'b74_online_live_token_v1';
  // Explicit build-time test switch. Default remains the existing production API.
  static const _realtimePoc = bool.fromEnvironment(
    'B74_REALTIME_POC',
    defaultValue: false,
  );
  static const _productionEndpoint =
      'https://api.disruptivesolutions.nl/api/realtime/publish?lane=1';
  static const _productionDeleteEndpoint =
      'https://api.disruptivesolutions.nl/api/realtime/live?lane=1';
  static const _pocEndpoint =
      'https://b74-online-live-realtime-poc.disruptivesolutionsnl.workers.dev/publish?lane=1';
  static const _pocTokenKey = 'b74_online_live_poc_token_v1';
  // Injected by --dart-define-from-file in debug POC builds only.
  // Never use this value in release builds or normal production mode.
  static const _debugPocToken = String.fromEnvironment('B74_POC_PUBLISH_TOKEN');
  static bool get _hasDebugPocToken =>
      kDebugMode && _realtimePoc && _debugPocToken.isNotEmpty;
  static String get _activeTokenKey => _realtimePoc ? _pocTokenKey : _tokenKey;
  static String get _endpoint =>
      _realtimePoc ? _pocEndpoint : _productionEndpoint;
  static const _lane = '1';
  static const _realtimeInterval = Duration(milliseconds: 250);

  bool enabled = false;
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
      _hasDebugPocToken ||
      (await _storage.read(key: _activeTokenKey))?.isNotEmpty == true;

  Future<void> enable({String? activationCode}) async {
    final code = activationCode?.trim();
    if (code != null && code.isNotEmpty) {
      await _storage.write(key: _activeTokenKey, value: code);
      _token = code;
    } else if (_hasDebugPocToken) {
      _token = _debugPocToken;
    } else {
      _token = await _storage.read(key: _activeTokenKey);
    }
    if (_token == null || _token!.isEmpty) {
      throw StateError('Online Live-activatiecode ontbreekt');
    }
    enabled = true;
    _heartbeat?.cancel();

    _schedulePublish();
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
    // The realtime POC has no DELETE endpoint; do not emit an unsupported call.
    if (wasEnabled && !_realtimePoc) await _request('DELETE');
  }

  void onTvSnapshot(Map<String, dynamic> snapshot) {
    if (!enabled) return;
    _lastSnapshot = Map<String, dynamic>.from(snapshot);
    _dirty = true;
    if (snapshot['payload'] is Map &&
        (snapshot['payload'] as Map)['displayState'] == 'MATCH_COMPLETE') {
      _urgentPending = true;
    }
    _schedulePublish();
  }

  void _schedulePublish() {
    if (!enabled || _lastSnapshot == null) return;
    if (_busy) return;
    final urgent = _urgentPending;
    final last = _lastSent;
    final interval = _realtimeInterval;
    final delay = last == null
        ? Duration.zero
        : interval - DateTime.now().difference(last);
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
    if (_busy || !enabled || _lastSnapshot == null) return;
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
      if ((status == null || status == 429 || status == 409 || status >= 500) &&
          enabled) {
        // Keep the latest state queued; retry without disturbing TV scoring.
        _dirty = true;
        if (urgent) _urgentPending = true;
        _lastSent = DateTime.now();
        _pending?.cancel();
        _pending = Timer(const Duration(seconds: 2), () {
          _pending = null;
          _schedulePublish();
        });
      }
    } finally {
      _busy = false;
      if (enabled && _pending == null && (_dirty || _urgentPending)) {
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
      final request = await client
          .openUrl(
            method,
            Uri.parse(
              method == 'DELETE' && !_realtimePoc
                  ? _productionDeleteEndpoint
                  : _endpoint,
            ),
          )
          .timeout(const Duration(seconds: 6));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (!_realtimePoc) request.headers.set('X-B74-Lane', _lane);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
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
