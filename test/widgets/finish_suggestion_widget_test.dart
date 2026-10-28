import 'package:dartscore_app/widgets/finish_suggestion_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  group('a checkout route', () {
    testWidgets('spells the bull\'s eye out as the double it is', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const Scaffold(
            body: FinishSuggestionWidget(remaining: 82, favoriteDouble: 'D16'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('D-Bull'), findsOneWidget);
      expect(find.text('D16'), findsOneWidget);
      expect(find.text('Bull'), findsNothing);
    });

    testWidgets('spells the outer bull out as the single it is', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const Scaffold(
            body: FinishSuggestionWidget(remaining: 125, favoriteDouble: 'D20'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('S-Bull'), findsOneWidget);
      expect(find.text('25'), findsNothing);
    });
  });
}
