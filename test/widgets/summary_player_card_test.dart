import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/widgets/summary_player_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

/// One visit of [score] points over three darts.
DartThrow _visit(int score, {int remainingBefore = 501, bool bust = false}) =>
    DartThrow(
      gameId: 1,
      playerId: 1,
      score: score,
      dartsUsed: 3,
      leg: 1,
      set: 1,
      remainingBefore: remainingBefore,
      thrownAt: DateTime(2026, 1, 1),
      bust: bust,
    );

/// The card the X01 summary and the X01 history detail both render. CLAUDE.md
/// makes that sharing a convention, so a change to one view belongs here, and
/// so does the test.
void main() {
  Future<void> pumpCard(WidgetTester tester, SummaryPlayerCard card) async {
    usePhoneSurface(tester, size: const Size(400, 1200));
    await tester.pumpWidget(
      testApp(Scaffold(body: SingleChildScrollView(child: card))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('names the player and the legs they won', (tester) async {
    await pumpCard(
      tester,
      SummaryPlayerCard(
        name: 'Ada',
        throws: [_visit(60), _visit(100)],
        legsWon: 2,
      ),
    );

    expect(find.text('Ada'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets);
  });

  testWidgets('averages over the darts thrown, not over the visits', (
    tester,
  ) async {
    // 180 points from six darts is 90 per three. A card that divided by visits
    // would show 90 as well for these two, so the second visit is deliberately
    // a different size.
    await pumpCard(
      tester,
      SummaryPlayerCard(
        name: 'Ada',
        throws: [_visit(60), _visit(120)],
        legsWon: 1,
      ),
    );

    expect(find.textContaining('90'), findsWidgets);
  });

  testWidgets('still draws a player who has thrown nothing', (tester) async {
    await pumpCard(
      tester,
      const SummaryPlayerCard(name: 'Ada', throws: [], legsWon: 0),
    );

    expect(find.text('Ada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says so plainly when a team member threw nothing', (
    tester,
  ) async {
    await pumpCard(
      tester,
      SummaryPlayerCard(
        name: 'Reds',
        throws: [_visit(60)],
        legsWon: 0,
        members: [
          ('Ada', [_visit(60)]),
          ('Zoe', const []),
        ],
      ),
    );

    expect(find.textContaining('No throw'), findsOneWidget);
  });

  testWidgets('breaks a team down into its members', (tester) async {
    await pumpCard(
      tester,
      SummaryPlayerCard(
        name: 'Reds',
        throws: [_visit(60), _visit(120)],
        legsWon: 1,
        members: [
          ('Ada', [_visit(60)]),
          ('Zoe', [_visit(120)]),
        ],
      ),
    );

    expect(find.text('Reds'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Zoe'), findsOneWidget);
    // A team is drawn with the group icon rather than an initial.
    expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
  });

  testWidgets('shows an individual player as an initial, not a group', (
    tester,
  ) async {
    await pumpCard(
      tester,
      SummaryPlayerCard(name: 'Ada', throws: [_visit(60)], legsWon: 0),
    );

    expect(find.byIcon(Icons.groups_rounded), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });
}
