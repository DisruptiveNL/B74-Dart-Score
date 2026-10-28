import 'package:dartscore_app/providers/players_provider.dart';
import 'package:dartscore_app/screens/game_setup_screen.dart';
import 'package:dartscore_app/utils/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The X01 setup screen: the form that decides what a game will be. Players are
/// written in `setUp`, because a widget test runs in fake async where a real
/// database write never completes.
void main() {
  group('the X01 setup screen', () {
    useInMemoryDatabase();

    late PlayersProvider players;

    setUp(() async {
      await insertPlayers(['Ada', 'Zoe']);
      players = PlayersProvider();
      await players.load();
    });

    Future<void> pumpSetup(WidgetTester tester) async {
      usePhoneSurface(tester, size: const Size(400, 2000));
      await tester.pumpWidget(
        testApp(const GameSetupScreen(), players: players),
      );
      await tester.pumpAndSettle();
    }

    /// The Start button, whichever wording it currently carries.
    ///
    /// Found through its label rather than by type: it is a
    /// `FilledButton.icon`, whose child is a private widget, so the text is
    /// not reachable from the button itself.
    Finder startButton() => find
        .ancestor(
          of: find.textContaining('Start'),
          matching: find.byType(FilledButton),
        )
        .first;

    testWidgets('will not start a game nobody is playing', (tester) async {
      await pumpSetup(tester);

      expect(find.text('Select at least 1 player'), findsOneWidget);
      final button = tester.widget<FilledButton>(startButton());
      expect(button.onPressed, isNull);
    });

    /// The switch in the header of the computer opponent card.
    Finder botSwitch() => find.descendant(
      of: find.widgetWithText(Card, 'Computer opponent'),
      matching: find.byType(Switch),
    );

    testWidgets(
      'adds a computer opponent by its plus and says where it throws',
      (tester) async {
        await pumpSetup(tester);
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();

        expect(
          find.byTooltip('Add Pro bot'),
          findsNothing,
          reason: 'the tiers stay folded away until the card is switched on',
        );
        await tester.tap(botSwitch());
        await tester.pumpAndSettle();

        expect(
          find.text('about 85 points per visit'),
          findsOneWidget,
          reason: 'every tier is listed with its average before any is picked',
        );
        expect(find.textContaining('throws as player'), findsNothing);

        await tester.tap(find.byTooltip('Add Pro bot'));
        // The bot row is written to the database on first use, which is real
        // I/O a widget test only reaches by letting it through.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();

        expect(find.text('The bot throws as player 2.'), findsOneWidget);
        expect(
          find.text('Pro bot'),
          findsNothing,
          reason: 'the rows name the tiers, the counter says how many',
        );
        expect(
          find.text('Ada'),
          findsOneWidget,
          reason: 'the roster still lists people only',
        );
        expect(
          find.textContaining('Bot Pro'),
          findsNothing,
          reason: 'the stored name never shows',
        );
        // Two players now, so the game has a format, not a solo leg count.
        expect(find.textContaining('Start'), findsOneWidget);
        expect(find.text('Start Solo Game'), findsNothing);
      },
    );

    testWidgets('adds a second bot of the same strength and takes one away', (
      tester,
    ) async {
      await pumpSetup(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(botSwitch());
      await tester.pumpAndSettle();

      /// The counter of the Pro row.
      String proCount() => (tester.widget<Text>(
        find.descendant(
          of: find.ancestor(
            of: find.byTooltip('Add Pro bot'),
            matching: find.byType(ListTile),
          ),
          matching: find.byWidgetPredicate(
            (w) => w is Text && RegExp(r'^\d$').hasMatch(w.data ?? ''),
          ),
        ),
      )).data!;

      /// The minus of the Pro row, which is off while the row counts zero.
      IconButton proMinus() => tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Remove Pro bot'),
          matching: find.byType(IconButton),
        ),
      );

      expect(proCount(), '0');
      expect(proMinus().onPressed, isNull, reason: 'nothing to take away yet');

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Add Pro bot'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }

      expect(proCount(), '2');
      expect(find.text('The bots throw as players 2 and 3.'), findsOneWidget);
      expect(proMinus().onPressed, isNotNull);

      await tester.tap(find.byTooltip('Remove Pro bot'));
      await tester.pumpAndSettle();

      expect(proCount(), '1');
      expect(
        find.text('The bot throws as player 2.'),
        findsOneWidget,
        reason: 'the last one added went, the first keeps its slot',
      );
    });

    testWidgets('holds no more than five bots of one strength', (tester) async {
      await pumpSetup(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(botSwitch());
      await tester.pumpAndSettle();

      IconButton proPlus() => tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Add Pro bot'),
          matching: find.byType(IconButton),
        ),
      );

      for (var i = 0; i < 5; i++) {
        expect(proPlus().onPressed, isNotNull);
        await tester.tap(find.byTooltip('Add Pro bot'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }

      expect(
        find.text('The bots throw as players 2, 3, 4, 5 and 6.'),
        findsOneWidget,
      );
      expect(proPlus().onPressed, isNull, reason: 'the tier is full');
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Add Legend bot'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNotNull,
        reason: 'the cap is per tier',
      );
    });

    testWidgets('drops the bots again when the card is switched off', (
      tester,
    ) async {
      await pumpSetup(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(botSwitch());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add Amateur bot'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('The bot throws as player 2.'), findsOneWidget);

      await tester.tap(botSwitch());
      await tester.pumpAndSettle();

      expect(find.textContaining('throws as player'), findsNothing);
      expect(find.byTooltip('Add Amateur bot'), findsNothing);
      expect(
        find.text('Start Solo Game'),
        findsOneWidget,
        reason: 'Ada is alone again',
      );
    });

    testWidgets('will not start a game with only a bot in it', (tester) async {
      await pumpSetup(tester);

      await tester.tap(botSwitch());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add Legend bot'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(find.text('The bot throws as player 1.'), findsOneWidget);
      expect(tester.widget<FilledButton>(startButton()).onPressed, isNull);
      expect(find.text('Select at least 1 player'), findsOneWidget);
    });

    testWidgets('starts once a player is picked, and says it is a solo game', (
      tester,
    ) async {
      await pumpSetup(tester);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(find.text('Select at least 1 player'), findsNothing);
      expect(tester.widget<FilledButton>(startButton()).onPressed, isNotNull);
      expect(find.textContaining('Solo'), findsWidgets);
    });

    testWidgets('offers every start score, on 501 by default', (tester) async {
      await pumpSetup(tester);

      for (final score in ['101', '170', '201', '301', '501', '701', '1001']) {
        expect(
          find.text(score),
          findsWidgets,
          reason: '$score should be offered as a start score',
        );
      }
    });

    testWidgets('moves the selection when another start score is picked', (
      tester,
    ) async {
      await pumpSetup(tester);

      ChoiceChip chipFor(String score) => tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, score).first,
      );
      expect(chipFor('501').selected, isTrue, reason: '501 is the default');

      await tester.tap(find.widgetWithText(ChoiceChip, '301'));
      await tester.pumpAndSettle();

      expect(chipFor('301').selected, isTrue);
      expect(chipFor('501').selected, isFalse);
    });

    testWidgets('offers check-in and check-out separately', (tester) async {
      await pumpSetup(tester);

      // Straight, Double and Master exist twice over: once for getting in and
      // once for getting out. A screen that lost one of the two rows would
      // still look plausible.
      expect(find.text('Straight'), findsNWidgets(2));
      expect(find.text('Double'), findsNWidgets(2));
      expect(find.text('Master'), findsNWidgets(2));
    });

    testWidgets('keeps the settings above the players on a phone', (
      tester,
    ) async {
      await pumpSetup(tester);

      // The order a phone has always shown: the game first, then who plays it.
      expect(find.byKey(kPaneDividerKey), findsNothing);
      expect(
        tester.getRect(find.text('Start Score')).bottom,
        lessThan(tester.getRect(find.text('Players')).top),
      );
    });
  });

  group('the X01 setup screen on a tablet', () {
    useInMemoryDatabase();

    late PlayersProvider players;

    setUp(() async {
      await insertPlayers(['Ada', 'Zoe']);
      players = PlayersProvider();
      await players.load();
    });

    /// Renders the setup at [size]. No layout provider is wrapped around it on
    /// purpose: this screen divides in the middle and keeps nothing.
    Future<void> pumpSetup(WidgetTester tester, Size size) async {
      usePhoneSurface(tester, size: size);
      await tester.pumpWidget(
        testApp(const GameSetupScreen(), players: players),
      );
      await tester.pumpAndSettle();
    }

    /// The Start button, found through its label as on the phone.
    Finder startButton() => find
        .ancestor(
          of: find.textContaining('Start '),
          matching: find.byType(FilledButton),
        )
        .first;

    testWidgets('stands the players beside the settings', (tester) async {
      await pumpSetup(tester, const Size(1180, 820));

      final settings = tester.getRect(find.text('Start Score'));
      final picker = tester.getRect(find.text('Players'));
      expect(picker.left, greaterThan(settings.right));
      expect(find.byKey(kPaneDividerKey), findsOneWidget);
    });

    testWidgets('puts the start button under both columns', (tester) async {
      await pumpSetup(tester, const Size(1180, 820));

      // Each column scrolls on its own, so the button may not belong to one of
      // them: it sits below both, and so does the reason it is disabled.
      final button = tester.getRect(startButton());
      for (final column in tester.widgetList(find.byType(ListView))) {
        expect(
          button.top,
          greaterThanOrEqualTo(tester.getRect(find.byWidget(column)).bottom),
        );
      }
      expect(tester.widget<FilledButton>(startButton()).onPressed, isNull);
      expect(find.text('Select at least 1 player'), findsOneWidget);
    });

    testWidgets('divides in the middle and stays there', (tester) async {
      await pumpSetup(tester, const Size(1180, 820));

      final divider = tester.getRect(find.byKey(kPaneDividerKey));
      expect(divider.center.dx, closeTo(1180 / 2, 8));

      // Both columns hold the same kind of thing, so there is nothing to
      // rebalance: the divider is a line, not a grip.
      await tester.drag(
        find.byKey(kPaneDividerKey),
        const Offset(120, 0),
        touchSlopX: 0,
      );
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byKey(kPaneDividerKey)), divider);
    });

    testWidgets('lays both columns out full, upright and on its side', (
      tester,
    ) async {
      // Two players is where the screen is at its fullest: the format, the
      // handicaps, the teams and the throwing order all appear at once.
      await pumpSetup(tester, const Size(820, 1180));
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byType(Checkbox).at(i));
        await tester.pumpAndSettle();
      }

      expect(find.text('Match Format'), findsOneWidget);
      expect(find.text('Starting order'), findsOneWidget);
      expect(tester.widget<FilledButton>(startButton()).onPressed, isNotNull);

      // Turned on its side. The screen keeps its state, so nothing is picked
      // twice, and both columns lay out again at the other shape.
      await pumpSetup(tester, const Size(1180, 820));

      expect(find.text('Match Format'), findsOneWidget);
      expect(find.text('Starting order'), findsOneWidget);
      expect(
        tester.getRect(find.text('Players')).left,
        greaterThan(tester.getRect(find.text('Match Format')).right),
      );
    });

    testWidgets('stays one column where two would be too narrow', (
      tester,
    ) async {
      // A small tablet upright: wide enough for two panes by the breakpoint,
      // not wide enough for two of these.
      await pumpSetup(tester, const Size(620, 1000));

      expect(find.byKey(kPaneDividerKey), findsNothing);
      expect(
        tester.getRect(find.text('Start Score')).bottom,
        lessThan(tester.getRect(find.text('Players')).top),
      );
    });
  });
}
