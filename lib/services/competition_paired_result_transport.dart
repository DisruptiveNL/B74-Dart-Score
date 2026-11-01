import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'b74_session_manager.dart';

/// Shared QR-paired result wire transport. No game-specific knowledge.
/// The caller owns durable outbox state and validates the result contract.
class CompetitionPairedResultTransport {
  CompetitionPairedResultTransport({HttpClient? client})
      : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<String> deliver({
    required String payload,
    required String resultId,
  }) async {
    final host = b74Session.peerHost;
    final port = b74Session.peerPort;
    if (host == null || port == null || !b74Session.hasKey) {
      throw StateError('Geen geregistreerde QR-retourverbinding');
    }
    final random = Random.secure();
    final nonce = List.generate(24, (_) => random.nextInt(256));
    final nonceText = base64UrlEncode(nonce).replaceAll('=', '');
    final digest = sha256.convert(utf8.encode(payload)).toString();
    final operation = 'b74-result-v1\n$nonceText\n$digest';
    final proof = b74Session.operationProof('tablet', operation);
    if (proof == null) throw StateError('QR-sessie verlopen');
    final uri = Uri(scheme: 'http', host: host, port: port,
        path: '/b74/competition/result');
    final request = await _client.postUrl(uri).timeout(const Duration(seconds: 8));
    request.headers.contentType = ContentType.json;
    request.headers.set('x-b74-result-nonce', nonceText);
    request.headers.set('x-b74-result-proof', proof);
    request.add(utf8.encode(payload));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await utf8.decoder.bind(response).join().timeout(
        const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Dashboard weigert resultaat (HTTP ${response.statusCode})', uri: uri);
    }
    final ack = jsonDecode(body);
    if (ack is! Map<String, dynamic> || ack['resultId'] != resultId ||
        ack['payload'] != payload || ack['status'] is! String ||
        (ack['status'] as String).isEmpty || ack['proof'] is! String ||
        !b74Session.verifyOperation('dashboard',
            'b74-result-ack-v1\n$nonceText\n$digest\n${ack['status']}',
            ack['proof'] as String)) {
      throw const FormatException('Geen geauthenticeerde ontvangstbevestiging');
    }
    return ack['status'] as String;
  }

  void close() => _client.close(force: true);
}
