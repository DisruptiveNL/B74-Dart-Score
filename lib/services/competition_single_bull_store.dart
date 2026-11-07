import '../database/db_helper.dart';

/// Durable, idempotent record of a competition Singles deciding-leg bull.
///
/// The record belongs to a specific local game and leg, not to the current
/// in-memory GameProvider. A repeated identical write is harmless; a
/// conflicting winner is rejected rather than silently replacing a result.
class CompetitionSingleBullStore {
  CompetitionSingleBullStore({DbHelper? helper})
      : _helper = helper ?? DbHelper.instance;

  final DbHelper _helper;

  static const String _table = 'competition_single_deciding_bulls';

  Future<int?> winner({required int gameId, required int leg}) async {
    if (gameId <= 0 || leg <= 0) throw ArgumentError('Ongeldige game of leg');
    final db = await _helper.db;
    final rows = await db.query(_table,
        columns: ['winner_player_id'],
        where: 'game_id = ? AND leg = ?',
        whereArgs: [gameId, leg], limit: 1);
    return rows.isEmpty ? null : rows.single['winner_player_id'] as int;
  }

  /// Records exactly one bull winner per leg. Only a player registered in
  /// the given competition game can be selected.
  Future<void> record({
    required int gameId,
    required int leg,
    required int winnerPlayerId,
  }) async {
    if (gameId <= 0 || leg <= 0 || winnerPlayerId <= 0) {
      throw ArgumentError('Ongeldige game, leg of speler');
    }
    final db = await _helper.db;
    await db.transaction((txn) async {
      final linked = await txn.query('competition_game_links',
          columns: ['game_id'], where: 'game_id = ?',
          whereArgs: [gameId], limit: 1);
      if (linked.isEmpty) throw StateError('Geen competitie-Single');
      final players = await txn.query('game_players',
          columns: ['player_id'], where: 'game_id = ? AND player_id = ?',
          whereArgs: [gameId, winnerPlayerId], limit: 1);
      if (players.isEmpty) throw StateError('Bullwinnaar speelt niet mee');
      final existing = await txn.query(_table,
          columns: ['winner_player_id'],
          where: 'game_id = ? AND leg = ?',
          whereArgs: [gameId, leg], limit: 1);
      if (existing.isNotEmpty) {
        if (existing.single['winner_player_id'] != winnerPlayerId) {
          throw StateError('Bullwinnaar is al vastgelegd');
        }
        return;
      }
      await txn.insert(_table, {
        'game_id': gameId,
        'leg': leg,
        'winner_player_id': winnerPlayerId,
        'recorded_at': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }
}

/// Persisted, idempotent confirmation of the starter of each Singles leg.
/// Created lazily to remain compatible with databases from earlier builds.
extension CompetitionSingleStarterStore on CompetitionSingleBullStore {
  Future<int?> starter({required int gameId, required int leg}) async {
    final db = await _helper.db;
    await db.execute('CREATE TABLE IF NOT EXISTS competition_single_leg_starters ('
        'game_id INTEGER NOT NULL, leg INTEGER NOT NULL, '
        'player_id INTEGER NOT NULL, recorded_at INTEGER NOT NULL, '
        'PRIMARY KEY(game_id, leg))');
    final rows = await db.query('competition_single_leg_starters',
        columns: ['player_id'], where: 'game_id = ? AND leg = ?',
        whereArgs: [gameId, leg], limit: 1);
    return rows.isEmpty ? null : rows.single['player_id'] as int;
  }

  Future<void> recordStarter({required int gameId, required int leg,
      required int playerId}) async {
    if (gameId <= 0 || leg <= 0 || playerId <= 0) {
      throw ArgumentError('Ongeldige starterregistratie');
    }
    await starter(gameId: gameId, leg: leg);
    final db = await _helper.db;
    await db.transaction((txn) async {
      final link = await txn.query('competition_game_links',
          where: 'game_id = ?', whereArgs: [gameId], limit: 1);
      final player = await txn.query('game_players',
          where: 'game_id = ? AND player_id = ?',
          whereArgs: [gameId, playerId], limit: 1);
      if (link.isEmpty || player.isEmpty) throw StateError('Geen geldige competitie-starter');
      final existing = await txn.query('competition_single_leg_starters',
          columns: ['player_id'], where: 'game_id = ? AND leg = ?',
          whereArgs: [gameId, leg], limit: 1);
      if (existing.isNotEmpty) {
        if (existing.single['player_id'] != playerId) {
          throw StateError('Starter is al definitief bevestigd');
        }
        return;
      }
      await txn.insert('competition_single_leg_starters', {
        'game_id': gameId, 'leg': leg, 'player_id': playerId,
        'recorded_at': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }
}
