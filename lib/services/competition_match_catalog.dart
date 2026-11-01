import '../database/db_helper.dart';
import 'competition_sync_contract.dart';
import 'b74_team_match_contract.dart';

/// Read-only projection of durable, validated competition imports.
class CompetitionMatchCatalog {
  CompetitionMatchCatalog({DbHelper? helper})
    : _helper = helper ?? DbHelper.instance;
  final DbHelper _helper;

  /// Ontvangen 701-opdrachten, los van de bestaande singles-inbox.
  Future<List<CompetitionDoublesSummary>> loadDoubles() async {
    final database = await _helper.db;
    final rows = await database.query(
      'competition_team_inbox',
      columns: [
        'game_id',
        'match_id',
        'slot',
        'revision',
        'payload',
        'started',
      ],
      where: 'kind = ?',
      whereArgs: ['doubles701'],
      orderBy: 'received_at DESC',
    );
    final visible = <CompetitionDoublesSummary>[];
    for (final row in rows) {
      final match = CompetitionDoublesSummary.fromRow(row);
      if (!await _helper.isCompetitionMatchLocked(match.matchId)) {
        visible.add(match);
      }
    }
    return visible;
  }

  /// Biergame-opdrachten uit dezelfde beveiligde team-inbox.
  Future<List<CompetitionDoublesSummary>> loadBeers() async {
    final database = await _helper.db;
    final rows = await database.query(
      'competition_team_inbox',
      columns: ['game_id', 'match_id', 'slot', 'revision', 'payload', 'started'],
      where: 'kind = ?',
      whereArgs: ['beer1001'],
      orderBy: 'received_at DESC',
    );
    final visible = <CompetitionDoublesSummary>[];
    for (final row in rows) {
      final match = CompetitionDoublesSummary.fromRow(row);
      if (!await _helper.isCompetitionMatchLocked(match.matchId)) {
        visible.add(match);
      }
    }
    return visible;
  }

  Future<List<CompetitionMatchSummary>> load() async {
    final db = await _helper.db;
    final rows = await db.query(
      'competition_inbox',
      columns: ['payload', 'received_at'],
      orderBy: 'received_at DESC',
    );
    final visible = <CompetitionMatchSummary>[];
    for (final row in rows) {
      final match = CompetitionMatchSummary.fromPacket(
        CompetitionSyncContract.decode(row['payload'] as String),
        receivedAt: row['received_at'] as int,
      );
      if (!await _helper.isCompetitionMatchLocked(match.id)) {
        visible.add(match);
      }
    }
    return visible;
  }
}

class CompetitionMatchSummary {
  final String id;
  final String home;
  final String away;
  final int receivedAt;
  final List<CompetitionSingleSummary> singles;
  final Map<String, dynamic> rules;

  CompetitionMatchSummary._(
    this.id,
    this.home,
    this.away,
    this.receivedAt,
    this.singles,
    this.rules,
  );

  factory CompetitionMatchSummary.fromPacket(
    Map<String, dynamic> packet, {
    required int receivedAt,
  }) {
    CompetitionSyncContract.validate(packet);
    final singles =
        (packet['singles'] as List)
            .map(
              (entry) => CompetitionSingleSummary.fromPacket(
                entry as Map<String, dynamic>,
              ),
            )
            .toList()
          ..sort((a, b) => a.slot.compareTo(b.slot));
    return CompetitionMatchSummary._(
      packet['matchId'] as String,
      (packet['home'] as Map)['name'] as String,
      (packet['away'] as Map)['name'] as String,
      receivedAt,
      singles,
      Map<String, dynamic>.from(
        packet['x01Rules'] as Map? ?? CompetitionX01Rules.defaults(),
      ),
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

  CompetitionSingleSummary._(
    this.slot,
    this.homeId,
    this.awayId,
    this.homePlayer,
    this.awayPlayer,
    this.homeBond,
    this.awayBond,
  );

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

/// Read-only samenvatting van een ontvangen 701-opdracht.
class CompetitionDoublesSummary {
  const CompetitionDoublesSummary({
    required this.gameId,
    required this.matchId,
    required this.slot,
    required this.revision,
    required this.bestOf,
    required this.homeTeam,
    required this.awayTeam,
    required this.homePlayers,
    required this.awayPlayers,
    required this.started,
  });

  final String gameId;
  final String matchId;
  final int slot;
  final int revision;
  final int bestOf;
  final String homeTeam;
  final String awayTeam;
  final List<String> homePlayers;
  final List<String> awayPlayers;
  final bool started;

  factory CompetitionDoublesSummary.fromRow(Map<String, Object?> row) {
    final packet = B74TeamMatchContract.decode(row['payload'] as String);
    final home = packet['home'] as Map<String, dynamic>;
    final away = packet['away'] as Map<String, dynamic>;
    List<String> names(Map<String, dynamic> side) => (side['players'] as List)
        .map((p) => (p as Map)['name'] as String)
        .toList();
    return CompetitionDoublesSummary(
      gameId: row['game_id'] as String,
      matchId: row['match_id'] as String,
      slot: row['slot'] as int,
      revision: row['revision'] as int,
      bestOf: packet['bestOf'] as int,
      homeTeam: home['teamName'] as String,
      awayTeam: away['teamName'] as String,
      homePlayers: names(home),
      awayPlayers: names(away),
      started: row['started'] == 1,
    );
  }
}
