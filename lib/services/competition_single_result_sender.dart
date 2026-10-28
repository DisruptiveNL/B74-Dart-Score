import 'dart:convert';
import 'dart:io';

import '../database/db_helper.dart';
import 'competition_single_result_contract.dart';

/// Sends a stored completed single to a Dashboard receiver on a trusted LAN.
/// The database is archived only after an exact result-ID acknowledgement.
class CompetitionSingleResultSender {
  CompetitionSingleResultSender({DbHelper? database, HttpClient? client})
    : _database = database ?? DbHelper.instance,
      _client = client ?? HttpClient();

  final DbHelper _database;
  final HttpClient _client;

  /// [host] is an IPv4/hostname, [port] and [token] are shown on Dashboard.
  /// Returns the receiver's durable inbox status (e.g. accepted/duplicate).
  Future<String> send({
    required String matchId,
    required int slot,
    required String host,
    required int port,
    required String token,
  }) async {
    if (host.trim().isEmpty ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(token)) {
      throw const FormatException('Ongeldige Dashboard-verbindingsgegevens');
    }
    final row = await _database.competitionSingleResult(matchId, slot);
    if (row == null || row['status'] != 'completed') {
      throw StateError('Geen afgerond, verzendbaar singleresultaat');
    }
    final payload = row['payload'];
    if (payload is! String) {
      throw StateError('Singleresultaat ontbreekt');
    }
    final result = CompetitionSingleResultContract.decode(payload);
    if (result['matchId'] != matchId || result['slot'] != slot) {
      throw StateError('Singleresultaat hoort bij andere wedstrijd');
    }
    if (!await _database.beginCompetitionSingleResultSend(matchId, slot)) {
      throw StateError('Resultaat wordt al verzonden');
    }
    try {
      final uri = Uri(
        scheme: 'http',
        host: host.trim(),
        port: port,
        pathSegments: ['competition', 'results', token],
      );
      final request = await _client
          .postUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(payload));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Dashboard weigert resultaat (HTTP ${response.statusCode})',
          uri: uri,
        );
      }
      final ack = jsonDecode(body);
      if (ack is! Map<String, dynamic> ||
          ack['resultId'] != result['resultId'] ||
          ack['payload'] != payload ||
          ack['status'] is! String ||
          (ack['status'] as String).isEmpty) {
        throw const FormatException(
          'Dashboard gaf geen geldige ontvangstbevestiging',
        );
      }
      final archived = await _database.acknowledgeCompetitionSingleResult(
        matchId,
        slot,
        payload,
      );
      if (!archived) {
        throw StateError('Ontvangst bevestigd maar lokaal archiveren mislukt');
      }
      return ack['status'] as String;
    } catch (_) {
      // If the server committed but its acknowledgement was lost, the result
      // remains retryable. The receiver deduplicates by stable result ID.
      await _database.failCompetitionSingleResultSend(matchId, slot);
      rethrow;
    }
  }

  void close() => _client.close(force: true);
}
