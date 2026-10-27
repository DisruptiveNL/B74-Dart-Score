import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'competition_match_inbox.dart';

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
  static const int maxPayloadBytes = 256 * 1024;

  int? get port => _server?.port;
  String? get token => _token;

  Future<void> start({InternetAddress? bindAddress}) async {
    if (_server != null) throw StateError('Receiver is already running');
    final random = Random.secure();
    _token = List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
    _approved = false;
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
    if (request.uri.path != '/competition/$_token' ||
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
        response.write(jsonEncode({'status': created ? 'stored' : 'already_stored'}));
      } on _PayloadTooLarge {
        response.statusCode = HttpStatus.requestEntityTooLarge;
      } on FormatException {
        response.statusCode = HttpStatus.badRequest;
      } on StateError {
        response.statusCode = HttpStatus.conflict;
      }
    }
    await response.close();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = null;
    _approved = false;
    await server?.close(force: true);
  }
}

class _PayloadTooLarge implements Exception {
  const _PayloadTooLarge();
}
