import 'package:dartscore_app/models/around_the_clock_game.dart';
import 'package:dartscore_app/models/shanghai_game.dart';
import 'package:dartscore_app/providers/around_the_clock_provider.dart';
import 'package:dartscore_app/providers/shanghai_provider.dart';
import 'package:dartscore_app/screens/around_the_clock_screen.dart';
import 'package:dartscore_app/screens/shanghai_screen.dart';
import 'package:dartscore_app/utils/layout.dart';
import 'package:dartscore_app/widgets/dartboard_target_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The two live screens built around a target board, on a tablet: beside each
/// other on its side, one column upright, and a board worth the screen either
/// way.
///
/// Every game is started in `setUp`, never in a test body: starting one writes
/// rows, and a widget test runs in fake async where a real database write never
/// completes.
void main() {
  group('a target board screen', () {
    useInMemoryDatabase();

    /// The screen of the mode under test, with its own provider around it.
    late Widget wrapped;

    Future<void> pumpLive(WidgetTester tester, Size size) async {
      usePhoneSurface(tester, size: size);
      await tester.pumpWidget(testApp(wrapped));
      await tester.pumpAndSettle();
    }

    /// The square the target board is painted in.
    Rect boardRect(WidgetTester tester) => tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is DartboardTargetPainter,
      ),
    );

    /// Where a player's row sits. Scoped to the card, because the input bar
    /// names whoever is throwing as well.
    Rect rowRect(WidgetTester tester, String name) => tester.getRect(
      find.descendant(of: find.byType(Card), matching: find.text(name)),
    );

    /// The same cases on both modes: the screens differ in what a row says, not
    /// in how the screen is divided.
    void sharedCases() {
      testWidgets('stands the list beside the board on its side', (
        tester,
      ) async {
        await pumpLive(tester, const Size(1180, 820));

        expect(find.byKey(kPaneDividerKey), findsOneWidget);
        final board = boardRect(tester);
        final list = rowRect(tester, 'Ada');
        expect(list.left, greaterThan(board.right));

        // And the board is worth the screen: it used to be capped at 500
        // whatever the tablet offered.
        expect(board.width, greaterThan(500));
        expect(board.width, closeTo(board.height, 1));
      });

      testWidgets('keeps one column upright, with a board that grew anyway', (
        tester,
      ) async {
        await pumpLive(tester, const Size(820, 1180));

        expect(find.byKey(kPaneDividerKey), findsNothing);
        final board = boardRect(tester);
        final list = rowRect(tester, 'Ada');
        expect(list.top, greaterThan(board.bottom));
        expect(board.width, greaterThan(500));
      });

      testWidgets('is the phone screen it has always been on a phone', (
        tester,
      ) async {
        await pumpLive(tester, const Size(400, 900));

        expect(find.byKey(kPaneDividerKey), findsNothing);
        final board = boardRect(tester);
        expect(rowRect(tester, 'Ada').top, greaterThan(board.bottom));
        // The width of the screen less its padding, as before.
        expect(board.width, closeTo(400 - 24, 1));
      });
    }

    group('Shanghai', () {
      setUp(() async {
        final players = await insertPlayers(['Ada', 'Zoe']);
        final p = ShanghaiProvider();
        await p.startGame(
          ShanghaiGame(
            variant: ShanghaiVariant.classic,
            legs: 1,
            sets: 1,
            createdAt: DateTime(2026, 4, 1),
            playerIds: players.map((pl) => pl.id!).toList(),
          ),
          players,
        );
        wrapped = ChangeNotifierProvider<ShanghaiProvider>.value(
          value: p,
          child: const ShanghaiScreen(),
        );
      });

      sharedCases();
    });

    group('Around the Clock', () {
      setUp(() async {
        final players = await insertPlayers(['Ada', 'Zoe']);
        final p = AroundTheClockProvider();
        await p.startGame(
          AroundTheClockGame(
            variant: AroundTheClockVariant.basic,
            legs: 1,
            sets: 1,
            createdAt: DateTime(2026, 4, 1),
            playerIds: players.map((pl) => pl.id!).toList(),
          ),
          players,
        );
        wrapped = ChangeNotifierProvider<AroundTheClockProvider>.value(
          value: p,
          child: const AroundTheClockScreen(),
        );
      });

      sharedCases();
    });
  });
}
