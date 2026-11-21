import 'dart:convert';

import '../database/db_helper.dart';
import 'competition_match_catalog.dart';
import 'competition_single_publish_mapper.dart';
import 'competition_single_result_contract.dart';
import 'competition_statistics_policy.dart';

/// P1.4b.3a: local-only reconciliation of completed official singles.
///
/// No HTTP, no Dashboard coupling, and no changes to the competition result
/// lifecycle. A separate, explicitly approved step may activate delivery.
class StatisticsSinglePublishCoordinator {
  StatisticsSinglePublishCoordinator({
    DbHelper? database,
    CompetitionMatchCatalog? catalog,
  }) : _db = database ?? DbHelper.instance,
       _catalog = catalog ?? CompetitionMatchCatalog();

  final DbHelper _db;
  final CompetitionMatchCatalog _catalog;
  bool _running = false;

  /// Returns the number of eligible singles examined and queued.
  /// Already-queued identical revisions remain unchanged.
  Future<int> reconcileOnce() async {
    if (_running) return 0;
    _running = true;
    var queued = 0;
    try {
      // Inspect both active and archived matches. In addition,
      // inspect deletion receipts so an in-progress REMOVE/RETAIN cannot race
      // with new local publication. Do not delete any existing outbox entries.
      final matches = [
        ...await _catalog.load(),
        ...await _catalog.load(archived: true),
      ];
      final database = await _db.db;
      for (final match in matches) {
        if (!CompetitionStatisticsPolicy.eligibleForStatisticsPublication(
          match.division,
        ))
          continue;
        if (match.matchType != 'regular' && match.matchType != 'cup') continue;
        final tombstones = await database.query(
          'competition_deletion_tombstones',
          columns: ['match_id', 'retain_official_statistics'],
          where: 'match_id = ?',
          whereArgs: [match.id],
          limit: 1,
        );
        if (tombstones.isNotEmpty &&
            tombstones.single['retain_official_statistics'] != 1)
          continue;

        for (final single in match.singles) {
          try {
            final stored = await _db.competitionSingleResult(
              match.id,
              single.slot,
            );
            if (stored == null) continue;
            // ACKed competition results are still legitimate completed games.
            if (stored['status'] != 'completed' &&
                stored['status'] != 'archived')
              continue;
            final result = CompetitionSingleResultContract.decode(
              stored['payload'] as String,
            );
            if (result['matchId'] != match.id ||
                result['slot'] != single.slot ||
                result['homePlayerId'] != single.homeId ||
                result['awayPlayerId'] != single.awayId)
              continue;
            final mapped = CompetitionSinglePublishMapper.map(
              completedResult: result,
              division: match.division,
              matchType: match.matchType,
              homeBondNumber: single.homeBond,
              awayBondNumber: single.awayBond,
              // The catalog has validated the durable competition import.
              // This does not constitute external federation verification.
              officialMatchVerified: true,
            );
            if (mapped == null) continue;
            // The mapper creates a JSON-compatible object; encode it exactly
            // once for durable, byte-stable retries.
            await _db.enqueueStatisticsSingle(
              matchId: match.id,
              slot: single.slot,
              revision: mapped['revision'] as int,
              payload: jsonEncode(mapped),
            );
            queued++;
          } catch (_) {
            // One malformed/unsupported single must not block the next.
            // No network activity is initiated by this coordinator.
          }
        }
      }
      return queued;
    } finally {
      _running = false;
    }
  }
}
