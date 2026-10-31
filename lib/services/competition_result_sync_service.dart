import 'dart:async';

import '../database/db_helper.dart';
import 'b74_session_manager.dart';
import 'competition_match_catalog.dart';
import 'competition_single_result_builder.dart';
import 'competition_single_result_sender.dart';

/// App-wide, non-blocking store-and-forward for official singles.
/// Scoring never awaits this service. The SQLite outbox is authoritative.
class CompetitionResultSyncService {
  CompetitionResultSyncService({
    DbHelper? database,
    CompetitionMatchCatalog? catalog,
    CompetitionSingleResultBuilder? builder,
    CompetitionSingleResultSender? sender,
    this._interval = const Duration(seconds: 12),
  }) : _db = database ?? DbHelper.instance,
       _catalog = catalog ?? CompetitionMatchCatalog(),
       _builder = builder ?? CompetitionSingleResultBuilder(),
       _sender = sender ?? CompetitionSingleResultSender();

  final DbHelper _db;
  final CompetitionMatchCatalog _catalog;
  final CompetitionSingleResultBuilder _builder;
  final CompetitionSingleResultSender _sender;
  final Duration _interval;
  Timer? _timer;
  bool _busy = false;
  bool _started = false;
  bool _recovered = false;

  void start() {
    if (_started) return;
    _started = true;
    b74Session.addListener(_onSessionChanged);
    _timer = Timer.periodic(_interval, (_) => unawaited(syncOnce()));
    unawaited(syncOnce());
  }

  void _onSessionChanged() {
    if (b74Session.peerHost != null && b74Session.peerPort != null) {
      unawaited(syncOnce());
    }
  }

  /// Reconcile a process interrupted while status='sending'. Never discard
  /// payloads. Repeating a committed result is safe via stable resultId.
  Future<void> _recoverInterruptedSends() async {
    final db = await _db.db;
    await db.update('competition_single_results', {
      'status': 'completed',
    }, where: "status = 'sending'");
  }

  Future<void> syncOnce() async {
    if (!_started || _busy) return;
    _busy = true;
    try {
      if (!_recovered) {
        await _recoverInterruptedSends();
        _recovered = true;
      }
      final matches = await _catalog.load();
      for (final match in matches) {
        for (final single in match.singles) {
          try {
            final current = await _db.competitionSingleResult(
              match.id,
              single.slot,
            );
            if (current?['status'] == 'archived') continue;
            if (current == null) {
              final gameId = await _db.competitionGameId(match.id, single.slot);
              if (gameId == null) continue;
              final game = await _db.getGame(gameId);
              if (game?.finishedAt == null) continue;
              // Prepare durable payload even when Dashboard is offline.
              await _builder.prepare(match, single);
            }
            if (b74Session.peerHost == null || b74Session.peerPort == null) {
              continue;
            }
            await _sender.sendPaired(matchId: match.id, slot: single.slot);
          } catch (_) {
            // Keep the durable outbox retryable; one failed single must not
            // block the next single or the scoring UI.
          }
        }
      }
    } catch (_) {
      // Startup/migration or transient database errors are retried later.
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    b74Session.removeListener(_onSessionChanged);
    _sender.close();
    _started = false;
  }
}

final competitionResultSync = CompetitionResultSyncService();
