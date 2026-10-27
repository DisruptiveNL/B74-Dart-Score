import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

void main() {
  group('Patch 10: numeric correction regression', () {
    useInMemoryDatabase();

    late GameProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = GameProvider();
      players = await insertPlayers(['A', 'B']);
      await provider.startGame(
        Game(
          startScore: 501,
          checkoutMode: CheckoutMode.doubleOut,
          legs: 3,
          sets: 1,
          createdAt: DateTime.now(),
          startingOrder: StartingOrder.random,
        ),
        players,
      );
    });

    test('correcting an earlier visit replays subsequent scores without changing turn', () async {
      await provider.submitNumericVisit(60); // first player
      await provider.submitNumericVisit(45); // second player
      await provider.submitNumericVisit(40); // first player

      final firstSlot = provider.playerStates.indexWhere(
        (s) => s.throws.length == 2,
      );
      expect(firstSlot, isNot(-1));
      final playerId = provider.playerStates[firstSlot].player.id;
      final original = provider.playerStates[firstSlot].throws.first;
      final activeId = provider.currentPlayerState.player.id;

      await provider.correctNumericVisit(firstSlot, original.id!, 100, 3);

      final updated = provider.playerStates[firstSlot];
      expect(updated.player.id, playerId);
      expect(updated.throws.length, 2);
      expect(updated.throws.first.score, 100);
      expect(updated.throws.last.remainingBefore, 401);
      expect(updated.remaining, 361);
      expect(provider.currentPlayerState.player.id, activeId);
    });

    test('invalid correction does not alter stored history', () async {
      await provider.submitNumericVisit(60);
      final slot = provider.playerStates.indexWhere((s) => s.throws.isNotEmpty);
      final original = provider.playerStates[slot].throws.single;
      await expectLater(
        provider.correctNumericVisit(slot, original.id!, 181, 3),
        throwsArgumentError,
      );
      expect(provider.playerStates[slot].throws.single.score, 60);
      expect(provider.playerStates[slot].remaining, 441);
    });

    test('a corrected score cannot invalidate a later numeric visit', () async {
      await provider.submitNumericVisit(180);
      await provider.submitNumericVisit(0);
      await provider.submitNumericVisit(180);
      await provider.submitNumericVisit(0);
      await provider.submitNumericVisit(100); // first player left 41
      final slot = provider.playerStates.indexWhere((s) => s.throws.length == 3);
      final original = provider.playerStates[slot].throws.first;
      await expectLater(
        provider.correctNumericVisit(slot, original.id!, 180, 1),
        throwsArgumentError,
      );
      expect(provider.playerStates[slot].remaining, 41);
    });

    test('BUST records the selected dart count and preserves remaining', () async {
      await provider.submitNumericVisit(0, bust: true, bustDarts: 2);
      final slot = provider.playerStates.indexWhere((s) => s.throws.isNotEmpty);
      final visit = provider.playerStates[slot].throws.single;
      expect(visit.bust, isTrue);
      expect(visit.dartsUsed, 2);
      expect(provider.playerStates[slot].remaining, 501);
    });

    test('existing BUST dart count can be corrected without changing remaining or turn', () async {
      await provider.submitNumericVisit(0, bust: true, bustDarts: 2);
      final slot = provider.playerStates.indexWhere((s) => s.throws.isNotEmpty);
      final original = provider.playerStates[slot].throws.single;
      final activeId = provider.currentPlayerState.player.id;

      expect(provider.correctableVisits(slot).any((t) => t.id == original.id), isTrue);
      await provider.correctNumericVisit(slot, original.id!, 0, 3);

      final corrected = provider.playerStates[slot].throws.single;
      expect(corrected.id, original.id);
      expect(corrected.bust, isTrue);
      expect(corrected.score, 0);
      expect(corrected.dartsUsed, 3);
      expect(corrected.remainingBefore, 501);
      expect(provider.playerStates[slot].remaining, 501);
      expect(provider.currentPlayerState.player.id, activeId);
    });

    test('existing BUST cannot be changed into a scored visit', () async {
      await provider.submitNumericVisit(0, bust: true, bustDarts: 1);
      final slot = provider.playerStates.indexWhere((s) => s.throws.isNotEmpty);
      final original = provider.playerStates[slot].throws.single;

      await expectLater(
        provider.correctNumericVisit(slot, original.id!, 20, 1),
        throwsArgumentError,
      );
      final unchanged = provider.playerStates[slot].throws.single;
      expect(unchanged.bust, isTrue);
      expect(unchanged.score, 0);
      expect(unchanged.dartsUsed, 1);
      expect(provider.playerStates[slot].remaining, 501);
    });

    test('BUST becomes SCORE and replays following visit', () async {
      await provider.submitNumericVisit(0, bust: true, bustDarts: 1);
      await provider.submitNumericVisit(45);
      await provider.submitNumericVisit(60);
      final slot = provider.playerStates.indexWhere((s) => s.throws.length == 2);
      final first = provider.playerStates[slot].throws.first;
      final active = provider.currentPlayerState.player.id;
      await provider.correctVisit(slot, first.id!, 40, 2, bust: false);
      final visits = provider.playerStates[slot].throws;
      expect(visits.first.bust, isFalse);
      expect(visits.first.score, 40);
      expect(visits.first.dartsUsed, 2);
      expect(visits.last.remainingBefore, 461);
      expect(provider.playerStates[slot].remaining, 401);
      expect(provider.currentPlayerState.player.id, active);
    });

    test('SCORE becomes BUST with no points deducted', () async {
      await provider.submitNumericVisit(60);
      await provider.submitNumericVisit(45);
      await provider.submitNumericVisit(40);
      final slot = provider.playerStates.indexWhere((s) => s.throws.length == 2);
      final first = provider.playerStates[slot].throws.first;
      await provider.correctVisit(slot, first.id!, 0, 1, bust: true);
      final visits = provider.playerStates[slot].throws;
      expect(visits.first.bust, isTrue);
      expect(visits.first.score, 0);
      expect(visits.first.dartsUsed, 1);
      expect(visits.last.remainingBefore, 501);
      expect(provider.playerStates[slot].remaining, 461);
    });

    test('invalid BUST conversion is rejected without changes', () async {
      await provider.submitNumericVisit(60);
      final slot = provider.playerStates.indexWhere((s) => s.throws.isNotEmpty);
      final original = provider.playerStates[slot].throws.single;
      await expectLater(
        provider.correctVisit(slot, original.id!, 60, 3, bust: true),
        throwsArgumentError,
      );
      expect(provider.playerStates[slot].throws.single.bust, isFalse);
      expect(provider.playerStates[slot].remaining, 441);
    });

    test('resume after correction restores scores and next player', () async {
      await provider.submitNumericVisit(60);
      await provider.submitNumericVisit(45);
      await provider.submitNumericVisit(40);
      final slot = provider.playerStates.indexWhere((s) => s.throws.length == 2);
      final original = provider.playerStates[slot].throws.first;
      await provider.correctNumericVisit(slot, original.id!, 100, 3);
      final expectedRemaining = provider.playerStates.map((s) => s.remaining).toList();
      final expectedTurn = provider.currentPlayerState.player.id;
      final expectedHistory = provider.playerStates[slot].throws
          .map((t) => [t.id, t.score, t.remainingBefore, t.playerId]).toList();

      final restored = GameProvider();
      await restored.resumeGame(provider.game!, players);
      expect(restored.playerStates.map((s) => s.remaining).toList(), expectedRemaining);
      expect(restored.currentPlayerState.player.id, expectedTurn);
      expect(restored.playerStates[slot].throws
          .map((t) => [t.id, t.score, t.remainingBefore, t.playerId]).toList(), expectedHistory);
    });

    test('checkout cannot be committed without selecting finish dart', () async {
      // In a 501 double-out game, 501 is not a legal one-visit checkout;
      // first reduce to a reachable finish in alternating visits.
      await provider.submitNumericVisit(180);
      await provider.submitNumericVisit(0);
      await provider.submitNumericVisit(180);
      await provider.submitNumericVisit(0);
      await provider.submitNumericVisit(101); // leaves 40
      await provider.submitNumericVisit(0);
      final activeId = provider.currentPlayerState.player.id;
      await expectLater(provider.submitNumericVisit(40), throwsArgumentError);
      expect(provider.currentPlayerState.player.id, activeId);
      expect(provider.currentPlayerState.remaining, 40);
    });
  });

  group('Patch 10: team correction regression', () {
    useInMemoryDatabase();

    late GameProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = GameProvider();
      players = await insertPlayers(['A1', 'A2', 'B1', 'B2']);
      await provider.startGame(
        Game(
          startScore: 501,
          checkoutMode: CheckoutMode.doubleOut,
          legs: 3,
          sets: 1,
          createdAt: DateTime.now(),
          startingOrder: StartingOrder.fixed,
          teams: [
            TeamConfig(name: 'Team A', playerIds: [players[0].id!, players[1].id!]),
            TeamConfig(name: 'Team B', playerIds: [players[2].id!, players[3].id!]),
          ],
        ),
        players,
      );
    });

    test('earlier teammate correction replays shared remaining and preserves rotation', () async {
      await provider.submitNumericVisit(60); // A1, 501 -> 441
      await provider.submitNumericVisit(45); // B1, 501 -> 456
      await provider.submitNumericVisit(40); // A2, 441 -> 401
      await provider.submitNumericVisit(50); // B2, 456 -> 406

      final teamA = provider.playerStates[0];
      expect(teamA.throws.map((t) => t.playerId).toList(),
          [players[0].id, players[1].id]);
      final first = teamA.throws.first;
      final activeTeamBefore = provider.currentPlayerState.displayName;
      final nextMemberBefore = teamA.player.id;

      await provider.correctNumericVisit(0, first.id!, 100, 3);

      final corrected = provider.playerStates[0];
      expect(corrected.throws.map((t) => t.playerId).toList(),
          [players[0].id, players[1].id]);
      expect(corrected.throws.first.score, 100);
      expect(corrected.throws.last.remainingBefore, 401);
      expect(corrected.remaining, 361);
      expect(corrected.player.id, nextMemberBefore);
      expect(provider.currentPlayerState.displayName, activeTeamBefore);
      expect(provider.playerStates[1].remaining, 406);
    });

    test('invalid team correction leaves both teams and turn untouched', () async {
      await provider.submitNumericVisit(60);
      await provider.submitNumericVisit(45);
      await provider.submitNumericVisit(40);
      final first = provider.playerStates[0].throws.first;
      final activeBefore = provider.currentPlayerState.displayName;
      final beforeA = provider.playerStates[0].throws
          .map((t) => [t.id, t.score, t.remainingBefore, t.playerId]).toList();
      final beforeB = provider.playerStates[1].throws
          .map((t) => [t.id, t.score, t.remainingBefore, t.playerId]).toList();

      await expectLater(
        provider.correctNumericVisit(0, first.id!, 181, 3),
        throwsArgumentError,
      );
      expect(provider.playerStates[0].throws
          .map((t) => [t.id, t.score, t.remainingBefore, t.playerId]).toList(),
          beforeA);
      expect(provider.playerStates[1].throws
          .map((t) => [t.id, t.score, t.remainingBefore, t.playerId]).toList(),
          beforeB);
      expect(provider.currentPlayerState.displayName, activeBefore);
    });

    test('resume after team correction preserves shared scores and teammate rotation', () async {
      await provider.submitNumericVisit(60);
      await provider.submitNumericVisit(45);
      await provider.submitNumericVisit(40);
      await provider.submitNumericVisit(50);
      final first = provider.playerStates[0].throws.first;
      await provider.correctNumericVisit(0, first.id!, 100, 3);
      final expectedScores = provider.playerStates.map((s) => s.remaining).toList();
      final expectedMemberIds = provider.playerStates.map((s) => s.player.id).toList();
      final expectedActive = provider.currentPlayerState.displayName;
      final expectedHistory = provider.playerStates[0].throws
          .map((t) => [t.id, t.score, t.remainingBefore, t.playerId]).toList();

      final restored = GameProvider();
      await restored.resumeGame(provider.game!, players);
      expect(restored.playerStates.map((s) => s.remaining).toList(), expectedScores);
      expect(restored.playerStates.map((s) => s.player.id).toList(), expectedMemberIds);
      expect(restored.currentPlayerState.displayName, expectedActive);
      expect(restored.playerStates[0].throws
          .map((t) => [t.id, t.score, t.remainingBefore, t.playerId]).toList(), expectedHistory);
    });

    test('team BUST dart correction preserves shared score and next teammate', () async {
      await provider.submitNumericVisit(60); // A1
      await provider.submitNumericVisit(45); // B1
      await provider.submitNumericVisit(0, bust: true, bustDarts: 2); // A2
      final original = provider.playerStates[0].throws.last;
      final activeBefore = provider.currentPlayerState.displayName;
      final nextMemberBefore = provider.playerStates[0].player.id;

      expect(original.bust, isTrue);
      expect(provider.correctableVisits(0).any((t) => t.id == original.id), isTrue);
      await provider.correctNumericVisit(0, original.id!, 0, 3);

      final teamA = provider.playerStates[0];
      expect(teamA.throws.last.id, original.id);
      expect(teamA.throws.last.playerId, players[1].id);
      expect(teamA.throws.last.bust, isTrue);
      expect(teamA.throws.last.dartsUsed, 3);
      expect(teamA.throws.last.remainingBefore, 441);
      expect(teamA.remaining, 441);
      expect(teamA.player.id, nextMemberBefore);
      expect(provider.currentPlayerState.displayName, activeBefore);
      expect(provider.playerStates[1].remaining, 456);
    });
  });
}
