import 'dart:async';

import '../database/db_helper.dart';
import 'b74_session_manager.dart';
import 'b74_team_match_contract.dart';
import 'b74_doubles_session.dart';
import 'b74_doubles_live_stats.dart';
import 'b74_doubles_result_builder.dart';
import 'competition_doubles_result_sender.dart';
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
    CompetitionDoublesResultSender? doublesSender,
    this._interval = const Duration(seconds: 12),
  }) : _db = database ?? DbHelper.instance,
       _catalog = catalog ?? CompetitionMatchCatalog(),
       _builder = builder ?? CompetitionSingleResultBuilder(),
       _sender = sender ?? CompetitionSingleResultSender(),
       _doublesSender = doublesSender ?? CompetitionDoublesResultSender();

  final DbHelper _db;
  final CompetitionMatchCatalog _catalog;
  final CompetitionSingleResultBuilder _builder;
  final CompetitionSingleResultSender _sender;
  final CompetitionDoublesResultSender _doublesSender;
  final Duration _interval;
  Timer? _timer;
  bool _busy = false;
  bool _started = false;
  bool _recovered = false;

  /// Latest team delivery/build errors for the recovery UI. Never log tokens.
  final Map<String, String> _teamErrors = {};
  String? teamError(String gameId) => _teamErrors[gameId];
  String? _generalError;
  String? get generalError => _generalError;

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
    await _db.recoverInterruptedCompetitionDoublesSends();
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
      // Doubles share the same session, timer, retries and result endpoint.
      // A failed 701 result never blocks the next match or singles.
      final database = await _db.db;
      final doubles = await database.query('competition_team_inbox',
          where: 'kind IN (?, ?)', whereArgs: ['doubles701', 'beer1001']);
      for (final row in doubles) {
        try {
          final gameId = row['game_id'] as String;
          var result = await _db.competitionDoublesResult(gameId);
          if (result?['status'] == 'archived') {
            _teamErrors.remove(gameId);
            continue;
          }
          if (result == null) {
            final session = await B74DoublesSession.load(gameId);
            if (session.engine.winner == null) continue;
            final packet = B74TeamMatchContract.decode(row['payload'] as String);
            final stats = B74DoublesLiveStats.fromEvents(session.events,
                startTeam: session.startTeam,
                bestOf: session.bestOf,
                openingBullRequired: session.openingBullRequired,
                startingScore: session.startingScore,
                playersPerTeam: session.playersPerTeam);
            final payload = B74DoublesResultBuilder.build(
                packet: packet, engine: session.engine, stats: stats);
            await _db.saveCompletedCompetitionDoublesResult(
                gameId: gameId, matchId: packet['matchId'] as String,
                slot: packet['slot'] as int,
                revision: packet['revision'] as int, payload: payload);
            result = await _db.competitionDoublesResult(gameId);
          }
          if (result?['status'] != 'completed') continue;
          if (b74Session.peerHost == null || b74Session.peerPort == null) continue;
          await _doublesSender.sendPaired(gameId);
          _teamErrors.remove(gameId);
        } catch (error) {
          // Keep the outbox intact and expose the failure for manual recovery.
          _teamErrors[row['game_id'] as String] = error.toString();
        }
      }
    } catch (error) {
      // Startup/migration or transient database errors are retried later.
      _generalError = error.toString();
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    b74Session.removeListener(_onSessionChanged);
    _sender.close();
    _doublesSender.close();
    _started = false;
  }
}

final competitionResultSync = CompetitionResultSyncService();
