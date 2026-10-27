import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/screens/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

/// The screen of an iPhone SE (2nd/3rd generation), the shortest phone the app
/// targets and the one the input used to run off the bottom of.
const _seSurface = Size(375, 667);

/// The screen of a current, rounded phone, together with the insets its notch
/// and its home indicator claim.
const _roundedSurface = Size(402, 874);
const _roundedInsets = EdgeInsets.only(top: 59, bottom: 34);

void main() {
  group('the live X01 screen layout', () {
    useInMemoryDatabase();

    late GameProvider provider;

    setUp(() {
      provider = GameProvider();
    });

    /// Starts a game with [names] and renders it on a [surface] sized screen.
    ///
    /// [teams] is built from the inserted players, which is why it is a callback
    /// rather than a value: the ids only exist once the players are written.
    ///
    /// Starting the game runs inside `runAsync` because it writes rows, and a
    /// widget test otherwise runs in fake async where a real write never
    /// returns and the test simply hangs.
    Future<void> pumpGame(
      WidgetTester tester,
      List<String> names, {
      Size surface = _seSurface,
      EdgeInsets insets = EdgeInsets.zero,
      List<TeamConfig> Function(List<Player>)? teams,
    }) async {
      await tester.runAsync(() async {
        final players = await insertPlayers(names);
        await provider.startGame(
          Game(
            startScore: 501,
            legs: 3,
            sets: 1,
            createdAt: DateTime.now(),
            startingOrder: StartingOrder.fixed,
            teams: teams?.call(players),
          ),
          players,
        );
      });

      usePhoneSurface(tester, size: surface, safeArea: insets);
      await tester.pumpWidget(testApp(const GameScreen(), game: provider));
      await tester.pumpAndSettle();
    }

    /// Fails unless every button of the action row is fully on screen, clear of
    /// whatever the system claims at the bottom.
    ///
    /// Geometry, not a plain `findsOneWidget`: the row used to be laid out
    /// below the bottom edge inside a scroll view, where it is built and found
    /// like any other widget while the player cannot see or reach it.
    void expectActionRowVisible(
      WidgetTester tester,
      Size surface, {
      EdgeInsets insets = EdgeInsets.zero,
    }) {
      final limit = surface.height - insets.bottom;

      for (final label in ['MISS', 'ACCEPT']) {
        final finder = find.text(label);

        expect(
          finder,
          findsOneWidget,
          reason: '"$label" must exist on the scoring screen',
        );

        final rect = tester.getRect(finder);

        expect(
          rect.top,
          greaterThanOrEqualTo(insets.top),
          reason: '"$label" is above the visible area',
        );

        expect(
          rect.bottom,
          lessThanOrEqualTo(limit),
          reason: '"$label" reaches into the bottom system inset',
        );
      }
    }

    testWidgets('keeps the action row on screen with two players',
        (tester) async {
      await pumpGame(tester, ['Ada', 'Zoe']);

      expectActionRowVisible(tester, _seSurface);
    });

    testWidgets('keeps the action row on screen with four players',
        (tester) async {
      // Four players add the compact score strip below the two big cards.
      await pumpGame(tester, ['Ada', 'Zoe', 'Ben', 'Cleo']);

      expectActionRowVisible(tester, _seSurface);
    });

    testWidgets('keeps the action row on screen with teams', (tester) async {
      // A team slot carries a second line under the name, the tallest the
      // scoreboard ever gets.
      await pumpGame(
        tester,
        ['Ada', 'Zoe', 'Ben', 'Cleo'],
        teams: (p) => [
          TeamConfig(name: 'Team 1', playerIds: [p[0].id!, p[2].id!]),
          TeamConfig(name: 'Team 2', playerIds: [p[1].id!, p[3].id!]),
        ],
      );

      expect(find.text('Team 1'), findsOneWidget);
      expectActionRowVisible(tester, _seSurface);
    });

    testWidgets('MISS and BUST have equally sized touch targets', (tester) async {
      await pumpGame(tester, ['Ada', 'Zoe']);
      final miss = tester.getRect(find.text('MISS'));
      final bust = tester.getRect(find.text('BUST').last);
      expect(miss.width, moreOrLessEquals(bust.width, epsilon: 1));
      expect(miss.height, moreOrLessEquals(bust.height, epsilon: 1));
    });

    testWidgets('numeric input offers quick scores and confirmation', (tester) async {
      await pumpGame(tester, ['Ada', 'Zoe', 'Ben', 'Cleo']);
      for (final score in ['26', '30', '57', '41', '45', '60', '95', '100', '140', '180']) {
        expect(find.text(score), findsWidgets);
      }
      expect(find.text('ACCEPT'), findsOneWidget);
      expect(find.text('CLEAR'), findsOneWidget);
    });

    testWidgets('leaves the bottom inset of a rounded phone to the system',
        (tester) async {
      await pumpGame(
        tester,
        ['Ada', 'Zoe', 'Ben', 'Cleo'],
        surface: _roundedSurface,
        insets: _roundedInsets,
      );

      expectActionRowVisible(tester, _roundedSurface, insets: _roundedInsets);
    });

    testWidgets('action controls stay outside the scrolling keypad', (tester) async {
      await pumpGame(tester, ['Ada', 'Zoe']);
      final scroll = find.byType(SingleChildScrollView);
      final accept = find.text('ACCEPT');
      expect(accept, findsOneWidget);
      expect(find.ancestor(of: accept, matching: scroll), findsNothing);
    });

    testWidgets('fits on a phone that is both short and rounded',
        (tester) async {
      // The compact layout derives its row height from the box it is given, so
      // an inset the grid quietly claims for itself would overflow it. Pumping
      // is the assertion: an overflow fails the test on its own.
      await pumpGame(
        tester,
        ['Ada', 'Zoe', 'Ben', 'Cleo'],
        surface: const Size(375, 740),
        insets: _roundedInsets,
      );

      expectActionRowVisible(tester, const Size(375, 740),
          insets: _roundedInsets);
    });

    testWidgets('action buttons stay large enough to hit', (tester) async {
      await pumpGame(tester, ['Ada', 'Zoe', 'Ben', 'Cleo']);
      final button = tester.getSize(find.widgetWithText(OutlinedButton, 'MISS'));
      expect(button.height, greaterThanOrEqualTo(30));
      expect(button.width, greaterThanOrEqualTo(44));
    });
  });
}
