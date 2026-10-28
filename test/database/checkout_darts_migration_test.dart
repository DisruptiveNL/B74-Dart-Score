import 'dart:convert';
import 'dart:io';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Encodes a visit's darts the way `GameProvider` stores them, as field and
/// multiplier pairs.
String _hits(List<(int field, int multiplier)> darts) => jsonEncode([
  for (final d in darts) {'f': d.$1, 'm': d.$2},
]);

void main() {
  group('the checkout attempt backfill', () {
    late Directory dir;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // A file, because the migration has to survive closing the connection and
      // an in-memory database does not.
      dir = await Directory.systemTemp.createTemp('dartscore_checkout_attempt');
      DbHelper.debugDatabasePath = '${dir.path}/dartscore.db';
      await DbHelper.debugReset();
    });

    tearDown(() async {
      await DbHelper.debugReset();
      DbHelper.debugDatabasePath = null;
      await dir.delete(recursive: true);
    });

    /// Winds a current database back to how version 21 left it, so the
    /// backfill runs against rows that never carried the flag.
    Future<void> windBackTo21(Database db) async {
      await db.execute('ALTER TABLE dart_throws DROP COLUMN checkout_darts');
      // Versions 23 and 24 gave players a bot tier and a number within it.
      await db.execute('ALTER TABLE players DROP COLUMN bot_ordinal');
      await db.execute('ALTER TABLE players DROP COLUMN bot_level');
      await db.execute('PRAGMA user_version = 21');
    }

    /// Inserts one visit and returns its id.
    Future<int> insertVisit(
      Database db, {
      required int gameId,
      required int remainingBefore,
      required int score,
      bool bust = false,
      String? hitsJson,
      int playerId = 1,
    }) => db.insert('dart_throws', {
      'game_id': gameId,
      'player_id': playerId,
      'score': score,
      'darts_used': 3,
      'leg': 1,
      'set_': 1,
      'remaining_before': remainingBefore,
      'thrown_at': 1700000000000,
      'bust': bust ? 1 : 0,
      'hits_json': hitsJson,
    });

    /// The stored dart count of the visit with [id], after reopening the
    /// database.
    Future<int> dartsOf(int id) async {
      final rows = await (await DbHelper.instance.db).query(
        'dart_throws',
        columns: ['checkout_darts'],
        where: 'id = ?',
        whereArgs: [id],
      );
      return rows.single['checkout_darts'] as int;
    }

    test('replays the darts of a visit that recorded them', () async {
      final db = await DbHelper.instance.db;
      final game = await db.insert('games', {
        'start_score': 501,
        'checkout_mode': CheckoutMode.doubleOut.index,
        'created_at': 1000,
      });

      // The leg from the bug report: 156 opened with a plain 20, then the 25
      // that the S9 turns into a 16 with darts still in hand.
      final noReach = await insertVisit(
        db,
        gameId: game,
        remainingBefore: 156,
        score: 131,
        hitsJson: _hits(const [(20, 1), (20, 3), (17, 3)]),
      );
      final reached = await insertVisit(
        db,
        gameId: game,
        remainingBefore: 25,
        score: 9,
        hitsJson: _hits(const [(9, 1), (0, 1), (0, 1)]),
      );
      final bustedAfterReaching = await insertVisit(
        db,
        gameId: game,
        remainingBefore: 16,
        score: 0,
        bust: true,
        hitsJson: _hits(const [(14, 1), (3, 1)]),
      );

      await windBackTo21(db);
      await DbHelper.debugReset();

      expect(await dartsOf(noReach), 0);
      expect(
        await dartsOf(reached),
        2,
        reason: 'the S9 leaves 16, and both misses fly at D8',
      );
      expect(
        await dartsOf(bustedAfterReaching),
        2,
        reason: '16 and the 2 the S14 leaves are both one-dart finishes',
      );
    });

    test('reads the check-out rule of the game the visit belongs to', () async {
      final db = await DbHelper.instance.db;
      final master = await db.insert('games', {
        'start_score': 501,
        'checkout_mode': CheckoutMode.masterOut.index,
        'created_at': 1000,
      });
      final double_ = await db.insert('games', {
        'start_score': 501,
        'checkout_mode': CheckoutMode.doubleOut.index,
        'created_at': 1000,
      });

      // 60 finishes on T20 under master-out and on no single dart under
      // double-out. Three misses keep the remaining there for the whole visit.
      final underMaster = await insertVisit(
        db,
        gameId: master,
        remainingBefore: 60,
        score: 0,
        hitsJson: _hits(const [(0, 1), (0, 1), (0, 1)]),
      );
      final underDouble = await insertVisit(
        db,
        gameId: double_,
        remainingBefore: 60,
        score: 0,
        hitsJson: _hits(const [(0, 1), (0, 1), (0, 1)]),
      );

      await windBackTo21(db);
      await DbHelper.debugReset();

      expect(await dartsOf(underMaster), 3);
      expect(await dartsOf(underDouble), 0);
    });

    test('a player handicap beats the game default', () async {
      final db = await DbHelper.instance.db;
      final game = await db.insert('games', {
        'start_score': 501,
        'checkout_mode': CheckoutMode.doubleOut.index,
        'created_at': 1000,
        'handicap_json': encodePlayerHandicaps({
          7: const PlayerHandicap(checkOut: CheckoutMode.straightOut),
        }),
      });

      // 19 is one dart away on S19 for the handicapped player only.
      final handicapped = await insertVisit(
        db,
        gameId: game,
        playerId: 7,
        remainingBefore: 19,
        score: 0,
        hitsJson: _hits(const [(0, 1), (0, 1), (0, 1)]),
      );
      final ordinary = await insertVisit(
        db,
        gameId: game,
        playerId: 8,
        remainingBefore: 19,
        score: 0,
        hitsJson: _hits(const [(0, 1), (0, 1), (0, 1)]),
      );

      await windBackTo21(db);
      await DbHelper.debugReset();

      expect(await dartsOf(handicapped), 3);
      expect(await dartsOf(ordinary), 0);
    });

    test(
      'falls back to the opening remaining when the darts were not stored',
      () async {
        final db = await DbHelper.instance.db;
        final game = await db.insert('games', {
          'start_score': 501,
          'checkout_mode': CheckoutMode.doubleOut.index,
          'created_at': 1000,
        });

        // What a sync leaves behind: a score, a remaining, and nothing else.
        final oneDartAway = await insertVisit(
          db,
          gameId: game,
          remainingBefore: 40,
          score: 0,
        );
        final twoDartsAway = await insertVisit(
          db,
          gameId: game,
          remainingBefore: 41,
          score: 0,
        );
        final finished = await insertVisit(
          db,
          gameId: game,
          remainingBefore: 41,
          score: 41,
        );

        await windBackTo21(db);
        await DbHelper.debugReset();

        expect(
          await dartsOf(oneDartAway),
          1,
          reason: 'one dart is all the remaining alone can prove',
        );
        expect(
          await dartsOf(twoDartsAway),
          0,
          reason: 'without the darts there is nothing to say it got closer',
        );
        expect(
          await dartsOf(finished),
          1,
          reason:
              'a leg that was finished was an attempt whatever else is known',
        );
      },
    );
  });
}
