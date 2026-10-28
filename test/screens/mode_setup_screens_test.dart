import 'package:dartscore_app/providers/players_provider.dart';
import 'package:dartscore_app/screens/around_the_clock_setup_screen.dart';
import 'package:dartscore_app/screens/cricket_setup_screen.dart';
import 'package:dartscore_app/screens/shanghai_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The setup screens of the three non-X01 modes, which decide what a game will
/// be before any provider is involved. Players are written in `setUp`, because
/// a widget test runs in fake async where a real database write never returns.
///
/// None of these tests presses Start: the mode providers are deliberately not
/// wired up, so a screen that started a game here would fail loudly rather than
/// navigate away mid assertion.
void main() {
  group('the mode setup screens', () {
    useInMemoryDatabase();

    late PlayersProvider players;

    setUp(() async {
      await insertPlayers(['Ada', 'Zoe']);
      players = PlayersProvider();
      await players.load();
    });

    /// Pumps [screen] on a surface tall enough for the whole form.
    Future<void> pumpSetup(WidgetTester tester, Widget screen) async {
      usePhoneSurface(tester, size: const Size(400, 2000));
      await tester.pumpWidget(testApp(screen, players: players));
      await tester.pumpAndSettle();
    }

    /// The Start button, found through its label rather than by type: it is a
    /// `FilledButton.icon`, whose child is private, so the text is not
    /// reachable from the button itself.
    Finder startButton() => find
        .ancestor(
          of: find.text('Start Game'),
          matching: find.byType(FilledButton),
        )
        .first;

    /// Whether the Start button would start a game in its current state.
    bool canStart(WidgetTester tester) =>
        tester.widget<FilledButton>(startButton()).onPressed != null;

    /// Toggles the checkbox of the player at [index] in the list.
    Future<void> tapPlayer(WidgetTester tester, int index) async {
      await tester.tap(find.byType(Checkbox).at(index));
      await tester.pumpAndSettle();
    }

    /// The switch in the header of the computer opponent card.
    Finder botSwitch() => find.descendant(
      of: find.widgetWithText(Card, 'Computer opponent'),
      matching: find.byType(Switch),
    );

    /// Opens the bot card and adds the Pro bot, letting the row's database
    /// write through.
    Future<void> addProBot(WidgetTester tester) async {
      await tester.tap(botSwitch());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add Pro bot'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    group('a computer opponent', () {
      for (final (name, screen) in [
        ('Cricket', const CricketSetupScreen() as Widget),
        ('Shanghai', const ShanghaiSetupScreen()),
        ('Around the Clock', const AroundTheClockSetupScreen()),
      ]) {
        testWidgets('makes a game of one person in $name', (tester) async {
          await pumpSetup(tester, screen);
          await tapPlayer(tester, 0);

          await addProBot(tester);

          expect(find.text('The bot throws as player 2.'), findsOneWidget);
          expect(canStart(tester), isTrue);
        });

        testWidgets('is no game on its own in $name', (tester) async {
          await pumpSetup(tester, screen);

          await addProBot(tester);

          expect(find.text('The bot throws as player 1.'), findsOneWidget);
          expect(canStart(tester), isFalse);
        });
      }
    });

    // ── Cricket ───────────────────────────────────────────────────────────────

    group('Cricket', () {
      testWidgets('will not start below two players', (tester) async {
        await pumpSetup(tester, const CricketSetupScreen());

        expect(
          find.text('Cricket requires at least 2 players.'),
          findsOneWidget,
        );
        expect(canStart(tester), isFalse);

        await tapPlayer(tester, 0);
        expect(
          canStart(tester),
          isFalse,
          reason: 'one player is not a game of Cricket',
        );

        await tapPlayer(tester, 1);
        expect(find.text('Cricket requires at least 2 players.'), findsNothing);
        expect(canStart(tester), isTrue);
      });

      testWidgets(
        'starts on Normal and explains Cut Throat once it is picked',
        (tester) async {
          await pumpSetup(tester, const CricketSetupScreen());

          ChoiceChip chipFor(String label) => tester.widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, label).first,
          );
          expect(chipFor('Normal').selected, isTrue);
          expect(chipFor('Cut Throat').selected, isFalse);
          expect(find.textContaining('Fewest points wins'), findsNothing);

          await tester.tap(find.widgetWithText(ChoiceChip, 'Cut Throat'));
          await tester.pumpAndSettle();

          expect(chipFor('Cut Throat').selected, isTrue);
          expect(chipFor('Normal').selected, isFalse);
          expect(find.textContaining('Fewest points wins'), findsOneWidget);
        },
      );

      testWidgets('starts on the standard scoring mode and explains the simple '
          'one once it is picked', (tester) async {
        await pumpSetup(tester, const CricketSetupScreen());

        ChoiceChip chipFor(String label) => tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, label).first,
        );
        expect(chipFor('Standard (S/D/T)').selected, isTrue);
        expect(find.textContaining('counts as 1 mark'), findsNothing);

        await tester.tap(
          find.widgetWithText(ChoiceChip, 'Simple (singles only)'),
        );
        await tester.pumpAndSettle();

        expect(chipFor('Simple (singles only)').selected, isTrue);
        expect(chipFor('Standard (S/D/T)').selected, isFalse);
        expect(find.textContaining('counts as 1 mark'), findsOneWidget);
      });
    });

    // ── Shanghai ──────────────────────────────────────────────────────────────

    group('Shanghai', () {
      testWidgets('will not start below two players', (tester) async {
        await pumpSetup(tester, const ShanghaiSetupScreen());

        expect(
          find.text('Shanghai requires at least 2 players.'),
          findsOneWidget,
        );
        expect(canStart(tester), isFalse);

        await tapPlayer(tester, 0);
        await tapPlayer(tester, 1);

        expect(
          find.text('Shanghai requires at least 2 players.'),
          findsNothing,
        );
        expect(canStart(tester), isTrue);
      });

      testWidgets('offers all three variants and describes the picked one', (
        tester,
      ) async {
        await pumpSetup(tester, const ShanghaiSetupScreen());

        ChoiceChip chipFor(String label) => tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, label).first,
        );
        expect(
          chipFor('Classic (1-9)').selected,
          isTrue,
          reason: 'Classic is the default',
        );
        expect(find.textContaining('9 rounds'), findsOneWidget);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Clockwise'));
        await tester.pumpAndSettle();
        expect(find.textContaining('7 darts'), findsOneWidget);
        expect(find.textContaining('9 rounds'), findsNothing);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Sequential'));
        await tester.pumpAndSettle();
        expect(chipFor('Sequential').selected, isTrue);
        expect(find.textContaining('up to 20'), findsOneWidget);
        expect(find.textContaining('7 darts'), findsNothing);
      });
    });

    // ── Around the Clock ──────────────────────────────────────────────────────

    group('Around the Clock', () {
      testWidgets('starts with a single player, unlike the other two modes', (
        tester,
      ) async {
        await pumpSetup(tester, const AroundTheClockSetupScreen());

        expect(find.text('Select at least 1 player.'), findsOneWidget);
        expect(canStart(tester), isFalse);

        await tapPlayer(tester, 0);

        expect(find.text('Select at least 1 player.'), findsNothing);
        expect(canStart(tester), isTrue);
      });

      testWidgets('offers all three variants and describes the picked one', (
        tester,
      ) async {
        await pumpSetup(tester, const AroundTheClockSetupScreen());

        ChoiceChip chipFor(String label) => tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, label).first,
        );
        expect(
          chipFor('Basic').selected,
          isTrue,
          reason: 'Basic is the default',
        );
        expect(find.textContaining('then the Bull'), findsOneWidget);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Full Segments'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Single, Double and Triple'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(ChoiceChip, 'Skip Rules'));
        await tester.pumpAndSettle();
        expect(chipFor('Skip Rules').selected, isTrue);
        expect(find.textContaining('joker'), findsOneWidget);
      });
    });

    // ── The two shared sections ───────────────────────────────────────────────

    group('teams and the starting order', () {
      /// Every mode hides both sections until a second player is on board, and
      /// every mode has to keep hiding them once the selection drops back.
      for (final mode in [
        ('Cricket', const CricketSetupScreen()),
        ('Shanghai', const ShanghaiSetupScreen()),
        ('Around the Clock', const AroundTheClockSetupScreen()),
      ]) {
        testWidgets('appear in ${mode.$1} only while two players are picked', (
          tester,
        ) async {
          await pumpSetup(tester, mode.$2);

          expect(find.text('Team Game'), findsNothing);
          expect(find.text('Starting order'), findsNothing);

          await tapPlayer(tester, 0);
          expect(
            find.text('Team Game'),
            findsNothing,
            reason: 'one player has nobody to team up with',
          );

          await tapPlayer(tester, 1);
          expect(find.text('Team Game'), findsOneWidget);
          expect(find.text('Starting order'), findsOneWidget);

          // Unticking the second player takes both sections away again.
          await tapPlayer(tester, 1);
          expect(find.text('Team Game'), findsNothing);
          expect(find.text('Starting order'), findsNothing);
        });

        testWidgets('offer a draggable order in ${mode.$1} once it is fixed', (
          tester,
        ) async {
          await pumpSetup(tester, mode.$2);
          await tapPlayer(tester, 0);
          await tapPlayer(tester, 1);

          // Random is the default, and it has nothing to sort by hand.
          expect(find.byIcon(Icons.drag_handle), findsNothing);

          await tester.tap(find.text('Fixed'));
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
          expect(find.text('Ada'), findsWidgets);
          expect(find.text('Zoe'), findsWidgets);
        });
      }
    });
  });
}
