
import '../database/db_helper.dart';
import 'competition_sync_contract.dart';

/// Read-only projection of durable, validated competition imports.
class CompetitionMatchCatalog {
  CompetitionMatchCatalog({DbHelper? helper}) : _helper = helper ?? DbHelper.instance;
  final DbHelper _helper;

  Future<List<CompetitionMatchSummary>> load() async {
    final db = await _helper.db;
    final rows = await db.query('competition_inbox',
        columns: ['payload', 'received_at'], orderBy: 'received_at DESC');
    return rows.map((row) => CompetitionMatchSummary.fromPacket(
        CompetitionSyncContract.decode(row['payload'] as String),
        receivedAt: row['received_at'] as int)).toList();
  }
}

class CompetitionMatchSummary {
  final String id;
  final String home;
  final String away;
  final int receivedAt;
  final List<CompetitionSingleSummary> singles;
  final Map<String, dynamic> rules;

  CompetitionMatchSummary._(this.id, this.home, this.away,
      this.receivedAt, this.singles, this.rules);

  factory CompetitionMatchSummary.fromPacket(Map<String, dynamic> packet,
      {required int receivedAt}) {
    CompetitionSyncContract.validate(packet);
    final singles = (packet['singles'] as List)
        .map((entry) => CompetitionSingleSummary.fromPacket(
            entry as Map<String, dynamic>))
        .toList()..sort((a, b) => a.slot.compareTo(b.slot));
    return CompetitionMatchSummary._(
      packet['matchId'] as String,
      (packet['home'] as Map)['name'] as String,
      (packet['away'] as Map)['name'] as String,
      receivedAt,
      singles,
      Map<String, dynamic>.from(packet['x01Rules'] as Map? ??
          CompetitionX01Rules.defaults()),
    );
  }
}

class CompetitionSingleSummary {
  final int slot;
  final String homeId;
  final String awayId;
  final String homePlayer;
  final String awayPlayer;
  final String? homeBond;
  final String? awayBond;

  CompetitionSingleSummary._(this.slot, this.homeId, this.awayId,
      this.homePlayer, this.awayPlayer, this.homeBond, this.awayBond);

  factory CompetitionSingleSummary.fromPacket(Map<String, dynamic> packet) {
    final home = packet['homePlayer'] as Map<String, dynamic>;
    final away = packet['awayPlayer'] as Map<String, dynamic>;
    return CompetitionSingleSummary._(
      packet['slot'] as int,
      home['id'] as String,
      away['id'] as String,
      home['name'] as String,
      away['name'] as String,
      home['bondNumber'] as String?,
      away['bondNumber'] as String?,
    );
  }
}
