import 'package:dartscore_app/models/checkout_ladder_game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/checkout_ladder_provider.dart';
import 'package:dartscore_app/providers/tablet_layout_provider.dart';
import 'package:dartscore_app/screens/checkout_ladder_history_summary_screen.dart';
import 'package:dartscore_app/screens/checkout_ladder_screen.dart';
import 'package:dartscore_app/screens/checkout_ladder_setup_screen.dart';
import 'package:dartscore_app/screens/checkout_ladder_summary_screen.dart';
import 'package:dartscore_app/screens/game_mode_selection_screen.dart';
import 'package:dartscore_app/widgets/dartboard_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The Checkout Ladder screens. Every game is started and played in `setUp`,
/// never inside a test body: a dart writes a row, and a widget test runs in
/// fake async where a real database write never completes.
void main() {
  CheckoutLadderGame game(
    List<Player> players, {
    CheckoutLadderVariant variant = CheckoutLadderVariant.training,
    int? target,
  }) =>
      CheckoutLadderGame(
        variant:         variant,
        startNumber:     81,
        targetNumber:    target,
        dartsPerAttempt: 6,
        createdAt:       DateTime(2026, 10, 25),
        playerIds:       players.map((p) => p.id!).toList(),
        startingOrder:   StartingOrder.fixed,
      );

  /// Enters darts in the board's notation (`T15`, `D10`, `S16`, `M`) for
  /// whoever is on turn.
  Future<void> tap(CheckoutLadderProvider p, String darts) async {
    for (final s in darts.split(' ')) {
      if (s == 'M') {
        await p.tapField(0, 1);
        continue;
      }
      final m = switch (s[0]) { 'T' => 3, 'D' => 2, _ => 1 };
      await p.tapField(int.parse(s.substring(1)), m);
    }
  }

  /// [child] with [provider] above it under its concrete type, so the
  /// screen's Consumer finds it.
  Widget wrap(CheckoutLadderProvider provider, Widget child) =>
      testApp(ChangeNotifierProvider<CheckoutLadderProvider>.value(
        value: provider,
        child: child,
      ));

  group('the live screen in training', () {
    useInMemoryDatabase();

    late CheckoutLadderProvider provider;

    setUp(() async {
      final players = await insertPlayers(['Ada', 'Zoe']);
      provider = CheckoutLadderProvider();
      await provider.startGame(game(players), players);
      await tap(provider, 'T15 S16');
    });

    tearDown(() => provider.dispose());

    testWidgets('shows the ladders, the rest and the route to it',
        (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(wrap(provider, const CheckoutLadderScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Training from 81'), findsOneWidget);
      expect(find.text('81'), findsNWidgets(2));
      expect(find.text('20'), findsNWidgets(2),
          reason: 'the rest of 81, and the 20 of the input grid');
      expect(find.text('Floor 81'), findsNWidgets(2));
      expect(find.text('Attempt 1 of 2'), findsNothing,
          reason: 'on the floor an attempt costs nothing, so none is counted');
      expect(find.byType(DartboardInput<CheckoutLadderProvider>), findsOneWidget);
    });

    testWidgets('offers to continue later or to end the training',
        (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(wrap(provider, const CheckoutLadderScreen()));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Continue later'), findsOneWidget);
      expect(find.text('End training'), findsOneWidget);
    });

    testWidgets('fits a small phone without overflowing', (tester) async {
      usePhoneSurface(tester, size: const Size(375, 667));
      await tester.pumpWidget(wrap(provider, const CheckoutLadderScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Miss'), findsOneWidget);
    });

    testWidgets('lays the input beside the ladders on a tablet',
        (tester) async {
      usePhoneSurface(tester, size: const Size(1280, 800));
      await tester.pumpWidget(ChangeNotifierProvider<TabletLayoutProvider>(
        create: (_) => TabletLayoutProvider(),
        child: wrap(provider, const CheckoutLadderScreen()),
      ));
      await tester.pumpAndSettle();

      final input = tester.getRect(
          find.byType(DartboardInput<CheckoutLadderProvider>));
      expect(input.width, lessThan(1280 * 0.75));
      expect(tester.takeException(), isNull);
    });
  });

  group('a finished race', () {
    useInMemoryDatabase();

    late CheckoutLadderProvider provider;
    late List<Player> players;

    setUp(() async {
      players = await insertPlayers(['Ada', 'Zoe']);
      provider = CheckoutLadderProvider();
      await provider.startGame(
          game(players, variant: CheckoutLadderVariant.race, target: 82),
          players);
      await tap(provider, 'T15 S16 D10');    // Ada: 81
      await tap(provider, 'T15 S16 D10');    // Zoe: 81
      await tap(provider, 'T14 M D20');      // Ada: 82, six darts in all
      await tap(provider, 'T14 D20');        // Zoe: 82, five darts in all
    });

    tearDown(() => provider.dispose());

    testWidgets('names the winner in the summary', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
          wrap(provider, const CheckoutLadderSummaryScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Zoe wins!'), findsOneWidget);
      expect(find.text('Race'), findsOneWidget);
      expect(find.text('Highest checked'), findsNWidgets(2));
    });

    testWidgets('reads the same in the history detail', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(wrap(
        provider,
        CheckoutLadderHistorySummaryScreen(
            game: provider.game!, players: players),
      ));
      await pumpUntilLoaded(tester);

      expect(find.textContaining('Zoe wins!'), findsOneWidget);
      expect(find.text('Safehouses'), findsNWidgets(2));
    });
  });

  group('a training ended by hand', () {
    useInMemoryDatabase();

    late CheckoutLadderProvider provider;

    setUp(() async {
      final players = await insertPlayers(['Ada']);
      provider = CheckoutLadderProvider();
      await provider.startGame(game(players), players);
      await tap(provider, 'T15 S16 D10');    // 81 in three: a safehouse
      await provider.endTraining();
    });

    tearDown(() => provider.dispose());

    testWidgets('shows how high it got, without a winner', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
          wrap(provider, const CheckoutLadderSummaryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Highest checked: 81'), findsOneWidget);
      expect(find.textContaining('wins!'), findsNothing);
    });
  });

  group('the setup', () {
    useInMemoryDatabase();

    testWidgets('asks for a target only in a race', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(testApp(ChangeNotifierProvider(
        create: (_) => CheckoutLadderProvider(),
        child: const CheckoutLadderSetupScreen(),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Target'), findsNothing);
      await tester.tap(find.text('Race'));
      await tester.pumpAndSettle();

      expect(find.text('Target'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('keeps the target above the start', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(testApp(ChangeNotifierProvider(
        create: (_) => CheckoutLadderProvider(),
        child: const CheckoutLadderSetupScreen(),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Race'));
      await tester.pumpAndSettle();

      // Ten long presses on the start's plus carry it to its top, 169.
      final plus = find.byIcon(Icons.add_rounded).first;
      for (var i = 0; i < 10; i++) {
        await tester.longPress(plus);
        await tester.pumpAndSettle();
      }

      expect(find.text('169'), findsOneWidget);
      expect(find.text('170'), findsOneWidget);
    });
  });

  testWidgets('the mode selection lists the ladder', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(testApp(const GameModeSelectionScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Checkout Ladder'), findsOneWidget);
  });
}
