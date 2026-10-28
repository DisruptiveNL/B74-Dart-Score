import 'package:dartscore_app/models/around_the_clock_game.dart';
import 'package:dartscore_app/models/cricket_game.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/models/shanghai_game.dart';
import 'package:dartscore_app/providers/around_the_clock_provider.dart';
import 'package:dartscore_app/providers/cricket_provider.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/providers/shanghai_provider.dart';
import 'package:dartscore_app/screens/around_the_clock_summary_screen.dart';
import 'package:dartscore_app/screens/cricket_summary_screen.dart';
import 'package:dartscore_app/screens/game_summary_screen.dart';
import 'package:dartscore_app/screens/shanghai_summary_screen.dart';
import 'package:dartscore_app/utils/layout.dart';
import 'package:dartscore_app/widgets/game_info_card.dart';
import 'package:dartscore_app/widgets/summary_player_card.dart';
import 'package:dartscore_app/widgets/throw_log_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The four post-game summaries, each rendered from a game that was really
/// played to its end through its provider.
///
/// The games are played in `setUp`, because every visit writes a row and a
/// widget test runs in fake async where a real database write never returns.
/// The headings of the two cards the Cricket summary builds itself. The first
/// is also the title of the screen, so it is looked up inside a card.
const l10nResults = 'Game Summary';
const l10nMarks = 'Marks';

void main() {
  // ── X01 ─────────────────────────────────────────────────────────────────────

  group('the X01 summary', () {
    useInMemoryDatabase();

    late GameProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = GameProvider();
      players = await insertPlayers(['Ada', 'Zoe']);
      await provider.startGame(
        Game(
          startScore: 101,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 4, 1),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );
      // 101 in one visit: T20, 9, D16. The double checks Ada out and, with a
      // single leg, ends the game.
      await provider.tapField(20, 3);
      await provider.tapField(9, 1);
      await provider.tapField(16, 2);
    });

    Future<void> pumpSummary(WidgetTester tester) async {
      usePhoneSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(
        testApp(const GameSummaryScreen(), game: provider),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('crowns whoever checked out', (tester) async {
      expect(
        provider.gameOver,
        isTrue,
        reason: 'the setup has to leave a finished game behind',
      );

      await pumpSummary(tester);

      expect(find.text('Game Summary'), findsOneWidget);
      expect(find.text('🎯 Ada wins!'), findsOneWidget);
    });

    testWidgets('gives both players a card and keeps the export actions', (
      tester,
    ) async {
      await pumpSummary(tester);

      expect(find.text('Ada'), findsWidgets);
      expect(find.text('Zoe'), findsWidgets);
      // Saving and sharing the result card are the two things this screen can
      // do that no other summary offers.
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    });

    testWidgets('offers the way home and the way into the next game at the '
        'bottom of the screen', (tester) async {
      await pumpSummary(tester);

      // Both stand on the bar under the summary rather than in the middle of
      // it, so neither is a scroll away.
      final home = tester.getRect(find.text('Main Menu'));
      final again = tester.getRect(find.text('Replay'));
      expect(again.left, greaterThan(home.right));
      expect(
        home.top,
        greaterThan(tester.getRect(find.text('All Throws')).top),
      );
    });

    testWidgets('keeps the settings under the winner in a single column', (
      tester,
    ) async {
      await pumpSummary(tester);

      // On a phone the settings describe the result rather than the log, so
      // they follow the winner instead of waiting under the player cards.
      final winner = tester.getRect(find.text('🎯 Ada wins!'));
      final info = tester.getRect(find.byType(GameInfoCard));
      final card = tester.getRect(find.byType(SummaryPlayerCard).first);
      expect(info.top, greaterThan(winner.bottom));
      expect(info.bottom, lessThanOrEqualTo(card.top));
    });

    testWidgets('stacks every card at one width', (tester) async {
      await pumpSummary(tester);

      /// The surface of a card, which is its box less the margin around it.
      double surface(Finder of) => tester
          .getRect(
            find.descendant(of: of, matching: find.byType(Material)).first,
          )
          .width;

      final info = surface(find.byType(GameInfoCard));
      expect(surface(find.byType(SummaryPlayerCard).first), closeTo(info, 0.5));
      expect(surface(find.byType(ThrowLogCard)), closeTo(info, 0.5));
    });

    testWidgets('spaces every card the same way down the column', (
      tester,
    ) async {
      await pumpSummary(tester);

      /// The visible box of a card, which is what the eye measures a gap by.
      Rect surface(Finder of) => tester.getRect(
        find.descendant(of: of, matching: find.byType(Material)).first,
      );

      final info = surface(find.byType(GameInfoCard));
      final first = surface(find.byType(SummaryPlayerCard).first);
      final last = surface(find.byType(SummaryPlayerCard).last);
      final log = surface(find.byType(ThrowLogCard));

      // The player cards used to stand closer to each other than the log stood
      // to them, because the blocks carried a gap on top of the card margins.
      expect(log.top - last.bottom, closeTo(first.top - info.bottom, 0.5));
    });

    testWidgets('stands the winner over both columns and the settings with '
        'the numbers on a tablet', (tester) async {
      usePhoneSurface(tester, size: const Size(1180, 820));
      await tester.pumpWidget(
        testApp(const GameSummaryScreen(), game: provider),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(kPaneDividerKey), findsOneWidget);

      // The winner belongs to the whole screen, so it stands over the divider
      // rather than in the half beside it.
      final winner = tester.getRect(find.text('🎯 Ada wins!'));
      final divider = tester.getRect(find.byKey(kPaneDividerKey));
      expect(winner.center.dx, closeTo(1180 / 2, 12));
      expect(winner.bottom, lessThanOrEqualTo(divider.top));

      // What was played sits over how it went, in the right hand column.
      final info = tester.getRect(find.byType(GameInfoCard));
      final log = tester.getRect(find.text('All Throws'));
      final card = tester.getRect(find.byType(SummaryPlayerCard).first);
      expect(info.left, greaterThan(card.right));
      expect(info.bottom, lessThan(log.top));
    });

    testWidgets('draws the exported card at one size, whatever the screen is '
        'read at', (tester) async {
      usePhoneSurface(tester, size: const Size(1180, 820));
      await tester.pumpWidget(
        testApp(
          const TextScaleBy(factor: 1.3, child: GameSummaryScreen()),
          game: provider,
        ),
      );
      await tester.pumpAndSettle();

      // The screen is drawn at the size the reader set, the way the app draws
      // every screen.
      final onScreen = MediaQuery.textScalerOf(
        tester.element(find.text('All Throws')),
      );
      expect(onScreen.scale(14), greaterThan(14));

      await tester.tap(find.byIcon(Icons.download_rounded));
      await tester.pump();

      // The image does not: it is the same picture wherever it was made, and
      // a card of a fixed width would be overflowed by a larger one.
      final inCard = MediaQuery.textScalerOf(
        tester.element(
          find.descendant(
            of: find.byKey(kExportCardKey),
            matching: find.byType(GameInfoCard),
          ),
        ),
      );
      expect(inCard.scale(14), 14);
    });

    testWidgets('builds the exported image from the same parts, wherever the '
        'screen puts them', (tester) async {
      await pumpSummary(tester);

      // Nothing is rendered for an image nobody asked for yet.
      expect(find.byKey(kExportCardKey), findsNothing);

      await tester.tap(find.byIcon(Icons.download_rounded));
      await tester.pump();

      final card = find.byKey(kExportCardKey);
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('🎯 Ada wins!')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byType(GameInfoCard)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byType(SummaryPlayerCard)),
        findsNWidgets(2),
      );
      // The log is too long for an image and stays out of it, and so does the
      // way out of the screen.
      expect(
        find.descendant(of: card, matching: find.text('All Throws')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Replay')),
        findsNothing,
      );
    });
  });

  // ── X01, checked out in the fewest darts there are ────────────────────────

  group('the X01 summary of a perfect leg', () {
    useInMemoryDatabase();

    late GameProvider provider;

    setUp(() async {
      provider = GameProvider();
      final players = await insertPlayers(['Ada', 'Zoe']);
      await provider.startGame(
        Game(
          startScore: 101,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 4, 1),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );
      // 101 in two darts, which is the fewest 101 can be checked out in:
      // T17 leaves 50, and the bull is a double.
      await provider.tapField(17, 3);
      await provider.tapField(25, 2);
    });

    testWidgets('pins the honour to the card of whoever threw it', (
      tester,
    ) async {
      usePhoneSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(
        testApp(const GameSummaryScreen(), game: provider),
      );
      await tester.pumpAndSettle();

      expect(find.text('2-Darter'), findsOneWidget);
      // In the header of Ada's card, beside her name, not in a band of its own
      // under the winner.
      final card = find.ancestor(
        of: find.text('2-Darter'),
        matching: find.byType(SummaryPlayerCard),
      );
      expect(card, findsOneWidget);
      expect(tester.widget<SummaryPlayerCard>(card).name, 'Ada');
    });
  });

  // ── Cricket ─────────────────────────────────────────────────────────────────

  group('the Cricket summary', () {
    useInMemoryDatabase();

    late CricketProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = CricketProvider();
      players = await insertPlayers(['Ada', 'Zoe']);
      await provider.startGame(
        CricketGame(
          variant: CricketVariant.normal,
          scoringMode: CricketScoringMode.standard,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 4, 1),
          playerIds: players.map((p) => p.id!).toList(),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );

      // Ada closes every field with a triple while Zoe throws her visits away.
      for (final field in cricketFields) {
        await provider.recordDart(field, 3);
        if (provider.gameOver) break;
        if (provider.dartsInVisit == 0) {
          for (var i = 0; i < 3; i++) {
            await provider.recordDart(0, 0);
          }
        }
      }
    });

    Future<void> pumpSummary(WidgetTester tester) async {
      usePhoneSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(
        testApp(
          ChangeNotifierProvider<CricketProvider>.value(
            value: provider,
            child: const CricketSummaryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('crowns the player who closed the board', (tester) async {
      expect(provider.gameOver, isTrue);

      await pumpSummary(tester);

      expect(find.text('🎯 Ada wins!'), findsOneWidget);
    });

    testWidgets('counts the closed fields per player', (tester) async {
      await pumpSummary(tester);

      expect(find.text('7/7 Fields closed'), findsOneWidget);
      expect(find.text('0/7 Fields closed'), findsOneWidget);
    });

    testWidgets('stacks its cards at the width the other modes use', (
      tester,
    ) async {
      await pumpSummary(tester);

      /// The surface of a card, which is its box less the margin around it.
      double surface(Finder of) => tester
          .getRect(
            find.descendant(of: of, matching: find.byType(Material)).first,
          )
          .width;

      // The two cards this mode builds itself used to keep the margin a Card
      // brings by default, which left them narrower than the shared ones.
      final info = surface(find.byType(GameInfoCard));
      for (final title in [l10nMarks, l10nResults]) {
        expect(
          surface(
            find.ancestor(of: find.text(title), matching: find.byType(Card)),
          ),
          closeTo(info, 0.5),
          reason: '\$title should be as wide as the info card',
        );
      }
    });

    testWidgets('lists every Cricket field in the marks grid', (tester) async {
      await pumpSummary(tester);

      expect(find.text('Marks'), findsOneWidget);
      for (final field in [20, 19, 18, 17, 16, 15]) {
        expect(find.text('$field'), findsWidgets, reason: '$field is a row');
      }
      expect(
        find.text('Bull'),
        findsOneWidget,
        reason: '25 is shown as Bull, not as a number',
      );
    });

    testWidgets('stands the winner over both columns on a tablet', (
      tester,
    ) async {
      usePhoneSurface(tester, size: const Size(1180, 820));
      await tester.pumpWidget(
        testApp(
          ChangeNotifierProvider<CricketProvider>.value(
            value: provider,
            child: const CricketSummaryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final winner = tester.getRect(find.text('🎯 Ada wins!'));
      final divider = tester.getRect(find.byKey(kPaneDividerKey));
      expect(winner.center.dx, closeTo(1180 / 2, 12));
      expect(winner.bottom, lessThanOrEqualTo(divider.top));
    });

    testWidgets('repeats the settings the game was played under', (
      tester,
    ) async {
      await pumpSummary(tester);

      expect(find.text('Cricket'), findsWidgets);
      expect(find.text('Normal'), findsWidgets);
      expect(
        find.text('Fixed'),
        findsWidgets,
        reason: 'the starting order belongs in the info card',
      );
    });
  });

  // ── Shanghai ────────────────────────────────────────────────────────────────

  group('the Shanghai summary', () {
    useInMemoryDatabase();

    late ShanghaiProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = ShanghaiProvider();
      players = await insertPlayers(['Ada', 'Zoe']);
      await provider.startGame(
        ShanghaiGame(
          variant: ShanghaiVariant.classic,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 4, 1),
          playerIds: players.map((p) => p.id!).toList(),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );

      // Ada scores a triple with every dart, Zoe misses every one, over all
      // nine rounds. Ada throws no single-double-triple round, so the game is
      // decided on points rather than by an instant Shanghai.
      while (!provider.gameOver) {
        await provider.recordDart(provider.currentPlayerIndex == 0 ? 3 : 0);
      }
    });

    Future<void> pumpSummary(WidgetTester tester) async {
      usePhoneSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(
        testApp(
          ChangeNotifierProvider<ShanghaiProvider>.value(
            value: provider,
            child: const ShanghaiSummaryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('crowns the player with the higher score', (tester) async {
      await pumpSummary(tester);

      expect(find.text('🎯 Ada wins!'), findsOneWidget);
    });

    testWidgets('shows both final scores', (tester) async {
      await pumpSummary(tester);

      // Nine rounds, three triples each, on the targets 1 to 9.
      final expected = List.generate(
        9,
        (i) => (i + 1) * 9,
      ).reduce((a, b) => a + b);
      expect(provider.playerStates[0].score, expected);
      expect(find.text('$expected'), findsOneWidget);
      expect(find.text('0'), findsOneWidget, reason: 'Zoe never scored');
      expect(find.text('Total Score'), findsNWidgets(2));
    });

    testWidgets('names the variant it was played in', (tester) async {
      await pumpSummary(tester);

      expect(find.text('Shanghai'), findsWidgets);
      expect(find.text('Classic (1-9)'), findsWidgets);
    });
  });

  // ── Around the Clock ────────────────────────────────────────────────────────

  group('the Around the Clock summary', () {
    useInMemoryDatabase();

    late AroundTheClockProvider provider;
    late List<Player> players;

    setUp(() async {
      provider = AroundTheClockProvider();
      players = await insertPlayers(['Ada', 'Zoe']);
      await provider.startGame(
        AroundTheClockGame(
          variant: AroundTheClockVariant.basic,
          legs: 1,
          sets: 1,
          createdAt: DateTime(2026, 4, 1),
          playerIds: players.map((p) => p.id!).toList(),
          startingOrder: StartingOrder.fixed,
        ),
        players,
      );

      // Ada hits her target with every dart, Zoe never hits hers.
      while (!provider.gameOver) {
        if (provider.currentPlayerIndex == 0) {
          await provider.recordDart(provider.activeTarget, 1);
        } else {
          await provider.recordDart(0, 0);
        }
      }
    });

    Future<void> pumpSummary(WidgetTester tester) async {
      usePhoneSurface(tester, size: const Size(400, 2400));
      await tester.pumpWidget(
        testApp(
          ChangeNotifierProvider<AroundTheClockProvider>.value(
            value: provider,
            child: const AroundTheClockSummaryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('crowns whoever reached the Bull first', (tester) async {
      await pumpSummary(tester);

      expect(find.text('🎯 Ada wins!'), findsOneWidget);
    });

    testWidgets('reports how far each player got', (tester) async {
      await pumpSummary(tester);

      final total = aroundTheClockOrder.length;
      expect(find.text('$total/$total hit'), findsOneWidget);
      expect(find.text('0/$total hit'), findsOneWidget);
      expect(
        find.text('$total darts'),
        findsOneWidget,
        reason: 'one dart per target is what the winner needed',
      );
    });
  });
}
