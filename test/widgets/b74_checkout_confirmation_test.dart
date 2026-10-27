import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/widgets/b74_numeric_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

void main() {
  group('Patch 10: checkout confirmation in numeric input', () {
    useInMemoryDatabase();

    late GameProvider game;

    setUp(() async {
      game = GameProvider();
      final players = await insertPlayers(['Ada', 'Zoe']);
      await game.startGame(
        Game(
          startScore: 501,
          checkoutMode: CheckoutMode.doubleOut,
          legs: 3,
          sets: 1,
          createdAt: DateTime.now(),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );
      // Ada reaches a valid D20 finish; Zoe's visits keep the turn order.
      await game.submitNumericVisit(180);
      await game.submitNumericVisit(0);
      await game.submitNumericVisit(180);
      await game.submitNumericVisit(0);
      await game.submitNumericVisit(101);
      await game.submitNumericVisit(0);
      expect(game.currentPlayerState.remaining, 40);
    });

    Future<void> openConfirmation(WidgetTester tester) async {
      usePhoneSurface(tester, size: const Size(480, 960));
      await tester.pumpWidget(testApp(
        const Scaffold(body: B74NumericInput()),
        game: game,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '4').last);
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, '0').last);
      await tester.pump();
      await tester.tap(find.text('ACCEPT'));
      await tester.pumpAndSettle();
      expect(find.text('CHECKOUT!'), findsOneWidget);
      await tester.tap(find.text('DART 2'));
      await tester.pumpAndSettle();
      expect(find.text('CHECKOUT BEVESTIGEN'), findsOneWidget);
    }

    testWidgets('ANNULEREN does not record a checkout or advance the leg',
        (tester) async {
      final beforeId = game.currentPlayerState.player.id;
      final beforeCount = game.currentPlayerState.throws.length;
      await openConfirmation(tester);
      await tester.tap(find.text('ANNULEREN'));
      await tester.pumpAndSettle();
      expect(game.currentPlayerState.player.id, beforeId);
      expect(game.currentPlayerState.remaining, 40);
      expect(game.currentPlayerState.throws.length, beforeCount);
      expect(find.text('40'), findsOneWidget);
    });

    testWidgets('BEVESTIG CHECKOUT commits the finish once', (tester) async {
      final finishingPlayer = game.currentPlayerState.player.id;
      final beforeCount = game.currentPlayerState.throws.length;
      await openConfirmation(tester);
      await tester.tap(find.text('BEVESTIG CHECKOUT'));
      await tester.pumpAndSettle();
      // Allow async database work to complete after the dialog route closes.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pumpAndSettle();
      final finishingState = game.playerStates.firstWhere(
        (state) => state.player.id == finishingPlayer,
      );
      expect(
        finishingState.throws.length,
        beforeCount + 1,
        reason: 'Checkout niet geregistreerd. '
            'Schermtekst: ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().join(' | ')}; '
            'leg: ${game.currentLeg}, speler: ${game.currentPlayerState.player.id}, '
            'remaining: ${finishingState.remaining}, gameOver: ${game.gameOver}, '
            'visibleErrors: ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().where((s) => s.contains('Error') || s.contains('Exception') || s.contains('Ongeldige') || s.contains('StateError')).join(' | ')}',
      );
      expect(finishingState.throws.last.score, 40);
      expect(finishingState.throws.last.dartsUsed, 2);
      expect(find.text('CHECKOUT BEVESTIGEN'), findsNothing);
    });
  });
}
