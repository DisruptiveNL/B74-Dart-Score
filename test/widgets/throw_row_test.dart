import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/widgets/throw_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

/// The one row both throw lists are built from: what it says about a visit,
/// and that it says it on a narrow phone without running over.
void main() {
  group('a throw row', () {
    testWidgets('reads a lifetime entry as a step, its darts and its date', (
      tester,
    ) async {
      usePhoneSurface(tester, size: const Size(320, 640));
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: ThrowRow(
              t: DartThrow(
                gameId: 1,
                playerId: 1,
                score: 140,
                dartsUsed: 3,
                leg: 1,
                set: 2,
                remainingBefore: 301,
                thrownAt: DateTime(2026, 8, 17, 20, 15),
                hitsJson: '[{"f":20,"m":3},{"f":20,"m":3},{"f":19,"m":1}]',
              ),
              // Entries of the lifetime list come from different games, so their
              // leg says nothing and the date is what places them.
              showPosition: false,
              thrownAt: DateTime(2026, 8, 17, 20, 15),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('140'), findsOneWidget);
      expect(find.text('301 → 161'), findsOneWidget);
      expect(find.text('T20 · T20 · S19'), findsOneWidget);
      expect(find.text('3 darts'), findsOneWidget);
      expect(find.textContaining('Leg'), findsNothing);
    });

    testWidgets('keeps a long name and the tail of a game log apart', (
      tester,
    ) async {
      usePhoneSurface(tester, size: const Size(320, 640));
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: ThrowRow(
              t: DartThrow(
                gameId: 1,
                playerId: 1,
                score: 45,
                dartsUsed: 3,
                leg: 1,
                set: 2,
                remainingBefore: 301,
                thrownAt: DateTime(2026, 8, 17),
              ),
              playerName: 'Maximiliane Fernanda von Hohenzollern',
              showSet: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('301 → 256'), findsOneWidget);
      expect(find.text('Set 2 · Leg 1'), findsOneWidget);
      expect(find.text('3 darts'), findsOneWidget);
    });

    testWidgets('a bust leaves the remaining score where it was', (
      tester,
    ) async {
      usePhoneSurface(tester, size: const Size(320, 640));
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: ThrowRow(
              t: DartThrow(
                gameId: 1,
                playerId: 1,
                score: 0,
                dartsUsed: 2,
                leg: 1,
                set: 1,
                remainingBefore: 24,
                thrownAt: DateTime(2026, 8, 17),
                bust: true,
              ),
              playerName: 'Anna',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BUST'), findsOneWidget);
      expect(find.text('24 → 24'), findsOneWidget);
      expect(find.text('2 darts'), findsOneWidget);
    });
  });
}
