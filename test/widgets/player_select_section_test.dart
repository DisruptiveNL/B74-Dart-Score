import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/widgets/player_select_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

/// The roster every setup screen picks from. All four modes render this one
/// widget, so what is pinned here holds for each of them.
void main() {
  /// [count] players named A, B, C ... in the order a setup screen gets them.
  List<Player> roster(int count) => List.generate(
    count,
    (i) => Player(id: i + 1, name: String.fromCharCode(65 + i)),
  );

  Future<void> pumpSection(
    WidgetTester tester,
    List<Player> players, {
    List<Player> selected = const [],
  }) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: SingleChildScrollView(
            child: PlayerSelectSection(
              allPlayers: players,
              selectedPlayers: selected,
              onToggle: (_, _) {},
              onAddPlayer: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the roster a game is picked from', () {
    testWidgets('shows everyone while there are six or fewer', (tester) async {
      await pumpSection(tester, roster(6));

      expect(find.byType(CheckboxListTile), findsNWidgets(6));
      expect(
        find.textContaining('more'),
        findsNothing,
        reason: 'nothing is hidden, so nothing offers to unhide it',
      );
    });

    testWidgets('stops at six and offers the rest', (tester) async {
      await pumpSection(tester, roster(11));

      expect(find.byType(CheckboxListTile), findsNWidgets(6));
      expect(find.text('F'), findsOneWidget, reason: 'the sixth is shown');
      expect(find.text('G'), findsNothing, reason: 'the seventh is not');
      expect(find.text('Show 5 more'), findsOneWidget);
    });

    testWidgets('expands to the full roster and back', (tester) async {
      await pumpSection(tester, roster(11));

      await tester.tap(find.text('Show 5 more'));
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsNWidgets(11));
      expect(find.text('K'), findsOneWidget);

      await tester.tap(find.text('Show fewer'));
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsNWidgets(6));
    });

    testWidgets('marks the main profile with a star', (tester) async {
      await pumpSection(tester, [
        Player(id: 1, name: 'Ann', isPrimary: true),
        Player(id: 2, name: 'Bob'),
      ]);

      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      // The star belongs to the row it marks, not to the card.
      expect(
        find.descendant(
          of: find.widgetWithText(CheckboxListTile, 'Ann'),
          matching: find.byIcon(Icons.star_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('numbers a player once they are picked', (tester) async {
      final players = roster(3);
      await pumpSection(tester, players, selected: [players[1]]);

      expect(find.text('Player 1'), findsOneWidget);
    });
  });
}
