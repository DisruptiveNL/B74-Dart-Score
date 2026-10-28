import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'competition_match_inbox.dart';
import 'b74_pairing_security.dart';
import 'b74_pairing_proof.dart';
import 'b74_session_manager.dart';

/// Competition-specific, authenticated HTTP entry point. It is intentionally
/// separate from profile/statistics sync, which has a different wire contract.
/// A 200 response means the database transaction has committed.
class CompetitionSyncReceiver {
  CompetitionSyncReceiver({CompetitionMatchInbox? inbox})
    : _inbox = inbox ?? CompetitionMatchInbox();

  final CompetitionMatchInbox _inbox;
  HttpServer? _server;
  String? _token;
  bool _approved = false;
  B74PairingChallenge? _probeChallenge;
  String? _pendingDashboardNonce;
  String? _pendingTabletNonce;
  List<int>? _pendingKey;
  final B74PairingNonceRegistry _pairingUsed = B74PairingNonceRegistry();
  static const int maxPayloadBytes = 256 * 1024;

  int? get port => _server?.port;
  bool get isApproved => _approved;

  /// Only a connectivity check. A successful probe never grants permission
  /// to import a match or creates a trusted device.
  void setProbeChallenge(B74PairingChallenge challenge) {
    if (_server == null || challenge.port != _server!.port ||
        !challenge.validAt(DateTime.now().toUtc())) {
      throw StateError('Ongeldige of verlopen QR-code');
    }
    _probeChallenge = challenge;
    _pendingDashboardNonce = null;
    _pendingTabletNonce = null;
    _pendingKey = null;
  }

  String? get token => _token;

  Future<void> start({InternetAddress? bindAddress}) async {
    if (_server != null) throw StateError('Receiver is already running');
    final random = Random.secure();
    _token = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    _approved = false;
    _probeChallenge = null;
    _server = await HttpServer.bind(bindAddress ?? InternetAddress.anyIPv4, 0);
    _server!.listen((request) async {
      try {
        await _handle(request);
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  /// Call only after the user has explicitly approved the pairing.
  void approve() => _approved = true;
  void reject() => _approved = false;

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    if (request.uri.path == '/b74/session/revoke' &&
        request.method == 'POST') {
      // Fixed-operation MAC is sufficient for revocation: successful replay
      // after revocation is impossible because the session key is erased.
      final proof = request.headers.value('x-b74-session-proof');
      if (proof == null || !b74Session.verifyOperation(
          'dashboard', 'b74-session-revoke-v1', proof)) {
        response.statusCode = HttpStatus.forbidden;
      } else {
        b74Session.revoke();
        response.statusCode = HttpStatus.ok;
        response.write(jsonEncode({'status': 'revoked'}));
      }
    } else if (request.uri.path == '/b74/pairing/start' &&
        request.method == 'POST') {
      final challenge = _probeChallenge;
      if (challenge == null || !challenge.validAt(DateTime.now().toUtc()) ||
          _pendingKey != null) {
        response.statusCode = HttpStatus.gone;
      } else {
        try {
          final raw = await utf8.decoder.bind(request).join();
          if (raw.length > 4096) throw const FormatException('Te groot');
          final body = jsonDecode(raw);
          if (body is! Map || body['deviceId'] != challenge.deviceId ||
              body['dashboardNonce'] is! String ||
              (body['dashboardNonce'] as String).length < 24) {
            throw const FormatException('Ongeldige start');
          }
          final dashboardNonce = body['dashboardNonce'] as String;
          final tabletNonce = B74PairingProof.newNonce();
          final key = B74PairingProof.deriveKey(
              challenge.nonce, dashboardNonce, tabletNonce);
          _pendingDashboardNonce = dashboardNonce;
          _pendingTabletNonce = tabletNonce;
          _pendingKey = key;
          response.statusCode = HttpStatus.ok;
          response.write(jsonEncode({
            'tabletNonce': tabletNonce,
            'tabletProof': B74PairingProof.proof(
                key, 'tablet', challenge.deviceId),
          }));
        } catch (_) {
          response.statusCode = HttpStatus.badRequest;
        }
      }
    } else if (request.uri.path == '/b74/pairing/finish' &&
        request.method == 'POST') {
      final challenge = _probeChallenge;
      final key = _pendingKey;
      if (challenge == null || key == null ||
          !challenge.validAt(DateTime.now().toUtc())) {
        response.statusCode = HttpStatus.gone;
      } else {
        try {
          final raw = await utf8.decoder.bind(request).join();
          if (raw.length > 4096) throw const FormatException('Te groot');
          final body = jsonDecode(raw);
          if (body is! Map ||
              body['dashboardNonce'] != _pendingDashboardNonce ||
              body['tabletNonce'] != _pendingTabletNonce ||
              body['dashboardProof'] is! String ||
              !B74PairingProof.verify(key, 'dashboard', 'b74-dashboard',
                  body['dashboardProof'] as String) ||
              !_pairingUsed.consume(challenge.nonce)) {
            response.statusCode = HttpStatus.forbidden;
          } else {
            b74Session.activateVerified(
                peerId: 'b74-dashboard',
                sessionKey: key,
                verifiedAtUtc: DateTime.now().toUtc());
            _probeChallenge = null;
            response.statusCode = HttpStatus.ok;
            response.write(jsonEncode({
              'status': 'paired',
              'ack': B74PairingProof.proof(
                  key, 'tablet', 'b74-pairing-complete'),
            }));
          }
        } catch (_) {
          response.statusCode = HttpStatus.badRequest;
        } finally {
          _pendingKey = null;
          _pendingDashboardNonce = null;
          _pendingTabletNonce = null;
        }
      }
    } else if (request.uri.path == '/b74/pairing/probe' &&
        request.method == 'POST') {
      final challenge = _probeChallenge;
      // Never echo a secret, never accept arbitrary JSON and never grant trust.
      // Single-use and a strict 2-minute expiry. QR nonce is a bearer
      // capability for this harmless reachability test ONLY.
      if (challenge == null ||
          !challenge.validAt(DateTime.now().toUtc())) {
        response.statusCode = HttpStatus.gone;
      } else {
        final raw = await utf8.decoder.bind(request).join();
        if (raw.length > 4096) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
        } else {
          try {
            final payload = jsonDecode(raw);
            if (payload is Map &&
                payload['nonce'] == challenge.nonce &&
                payload['deviceId'] == challenge.deviceId) {
              _probeChallenge = null;
              response.statusCode = HttpStatus.ok;
              response.write(jsonEncode({
                'status': 'reachable',
                'deviceId': challenge.deviceId,
                'trusted': false,
              }));
            } else {
              response.statusCode = HttpStatus.forbidden;
            }
          } on FormatException {
            response.statusCode = HttpStatus.badRequest;
          }
        }
      }
    } else if (request.uri.path != '/competition/$_token' ||
        request.method != 'POST') {
      response.statusCode = HttpStatus.forbidden;
    } else if (!_approved) {
      response.statusCode = HttpStatus.forbidden;
    } else {
      try {
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in request) {
          if (bytes.length + chunk.length > maxPayloadBytes) {
            throw const _PayloadTooLarge();
          }
          bytes.add(chunk);
        }
        final created = await _inbox.receive(utf8.decode(bytes.takeBytes()));
        response.statusCode = HttpStatus.ok;
        response.write(
          jsonEncode({'status': created ? 'stored' : 'already_stored'}),
        );
      } on _PayloadTooLarge {
        response.statusCode = HttpStatus.requestEntityTooLarge;
      } on FormatException {
        response.statusCode = HttpStatus.badRequest;
      } on StateError catch (error) {
        response.statusCode = HttpStatus.conflict;
        // The inbox uses StateError for expected import conflicts. Returning
        // the reason lets the sender distinguish a player-link conflict from
        // a changed match snapshot without weakening the rejection rule.
        response.write(
          jsonEncode({
            'error': 'competition_import_conflict',
            'message': error.message.toString(),
          }),
        );
      }
    }
    await response.close();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = null;
    _approved = false;
    _probeChallenge = null;
    b74Session.revoke();
    await server?.close(force: true);
  }
}

class _PayloadTooLarge implements Exception {
  const _PayloadTooLarge();
}
