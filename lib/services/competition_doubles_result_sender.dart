import '../database/db_helper.dart';
import 'b74_doubles_result_contract.dart';
import 'competition_paired_result_transport.dart';

/// Doubles outbox adapter over the SAME singles QR transport and ACK protocol.
class CompetitionDoublesResultSender {
  CompetitionDoublesResultSender({DbHelper? database,
      CompetitionPairedResultTransport? transport})
      : _database = database ?? DbHelper.instance,
        _transport = transport ?? CompetitionPairedResultTransport();

  final DbHelper _database;
  final CompetitionPairedResultTransport _transport;

  Future<String> sendPaired(String gameId) async {
    final row = await _database.competitionDoublesResult(gameId);
    if (row == null || row['status'] != 'completed' || row['payload'] is! String) {
      throw StateError('Geen afgerond, verzendbaar 701-resultaat');
    }
    final payload = row['payload'] as String;
    final result = B74DoublesResultContract.decode(payload);
    if (result['gameId'] != gameId || result['matchId'] != row['match_id'] ||
        result['slot'] != row['slot'] || result['revision'] != row['revision']) {
      throw StateError('701-resultaat hoort niet bij deze wedstrijd');
    }
    if (!await _database.beginCompetitionDoublesResultSend(gameId)) {
      throw StateError('701-resultaat wordt al verzonden');
    }
    try {
      final status = await _transport.deliver(
          payload: payload, resultId: result['resultId'] as String);
      if (!await _database.acknowledgeCompetitionDoublesResult(gameId, payload)) {
        throw StateError('ACK ontvangen, maar 701 archiveren mislukt');
      }
      return status;
    } catch (_) {
      await _database.failCompetitionDoublesResultSend(gameId);
      rethrow;
    }
  }

  void close() => _transport.close();
}
