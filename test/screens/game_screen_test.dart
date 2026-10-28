import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/widgets/b74_numeric_input.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/screens/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

void main() {
  group('the live X01 screen', () {
    useInMemoryDatabase();

    late GameProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = GameProvider();
      players = await insertPlayers(['Ada', 'Zoe']);
      await provider.startGame(
        Game(
          startScore: 501,
          legs: 3,
          sets: 1,
          createdAt: DateTime.now(),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );
    });

    /// Pumps the screen with the game already running.
    Future<void> pumpGame(WidgetTester tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(testApp(const GameScreen(), game: provider));
      await tester.pumpAndSettle();
    }

    /// Selects a quick visit score, then explicitly accepts it.
    Future<void> acceptScore(WidgetTester tester, String score) async {
      final input = find.byType(B74NumericInput);
      await tester.tap(
        find.descendant(of: input, matching: find.text(score)).first,
      );
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('ACCEPT'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('locks the input while a bot is on turn', (tester) async {
      // Real writes, let through: the fake clock of a widget test never
      // completes them.
      await tester.runAsync(() async {
        final botId = await DbHelper.instance.insertPlayer(
          Player(
            name: BotLevel.pro.storedName,
            uuid: BotLevel.pro.uuid,
            botLevel: BotLevel.pro,
          ),
        );
        final bot = (await DbHelper.instance.getPlayer(botId))!;
        await provider.startGame(
          Game(
            startScore: 501,
            legs: 1,
            createdAt: DateTime.now(),
            startingOrder: StartingOrder.fixed,
          ),
          [bot, players.first],
        );
      });
      // Held back, or its timer would outlive this test's fake clock.
      provider.stopBot();
      await pumpGame(tester);

      expect(find.text('Pro bot'), findsOneWidget);

      final accept = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'ACCEPT'),
      );
      expect(accept.onPressed, isNull);
      expect(provider.dartsInVisit, 0);
      expect(provider.playerStates[0].remaining, 501);
    });

    testWidgets('requires ACCEPT and advances after a numeric visit', (
      tester,
    ) async {
      await pumpGame(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byType(B74NumericInput),
              matching: find.text('60'),
            )
            .first,
      );
      await tester.pump();
      expect(provider.currentPlayerIndex, 0);
      expect(provider.playerStates[0].remaining, 501);
      expect(find.text('ACCEPT'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('ACCEPT'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(provider.playerStates[0].remaining, 441);
      expect(provider.currentPlayerIndex, 1);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('shows both players on their start score', (tester) async {
      await pumpGame(tester);

      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Zoe'), findsOneWidget);
      expect(find.text('501'), findsNWidgets(2));
    });

    testWidgets('counts a visit down and hands the turn on', (tester) async {
      await pumpGame(tester);
      final firstUp = provider.currentPlayerState.player.name;

      // Driven through the provider inside runAsync, because the third dart
      // closes the visit and that writes a row. A widget test otherwise runs
      // in fake async, where a real database write never completes.
      await tester.runAsync(() async {
        await provider.tapField(20, 1);
        await provider.tapField(20, 1);
        await provider.tapField(20, 1);
      });
      await tester.pumpAndSettle();

      expect(find.text('441'), findsOneWidget);
      expect(find.text('501'), findsOneWidget);
      expect(provider.currentPlayerState.player.name, isNot(firstUp));
    });

    testWidgets('undoes the last accepted numeric visit', (tester) async {
      await pumpGame(tester);
      await acceptScore(tester, '60');
      expect(provider.playerStates[0].remaining, 441);
      expect(provider.currentPlayerIndex, 1);
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.undo_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(provider.playerStates[0].remaining, 501);
      expect(provider.currentPlayerIndex, 0);
    });

    testWidgets('scores a numeric visit of 60 after ACCEPT', (tester) async {
      await pumpGame(tester);
      await acceptScore(tester, '60');
      expect(provider.playerStates[0].remaining, 441);
    });

    testWidgets('asks before leaving when the close button is used', (
      tester,
    ) async {
      await pumpGame(tester);

      // Scoped to the app bar: the Miss button on the dartboard carries a
      // close icon of its own, and tapping that would score instead of asking
      // anything.
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('answers the system back with the same question', (
      tester,
    ) async {
      // CLAUDE.md makes this a convention across all four live screens: a
      // running game must not be lost to a stray back gesture, so the route
      // refuses to pop and asks instead.
      await pumpGame(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(GameScreen), findsOneWidget);
    });

    testWidgets('stays in the game when the question is declined', (
      tester,
    ) async {
      await pumpGame(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(GameScreen), findsOneWidget);
    });
  });
}
