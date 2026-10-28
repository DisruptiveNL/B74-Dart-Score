import 'package:dartscore_app/screens/onboarding_screen.dart';
import 'package:dartscore_app/widgets/favorite_double_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';
import '../support/test_db.dart';

void main() {
  group('the onboarding screen', () {
    useInMemoryDatabase();

    /// Renders onboarding at [size], which defaults to the iPad the store
    /// review ran on.
    Future<void> pumpOnboarding(
      WidgetTester tester, {
      Size size = const Size(820, 1180),
    }) async {
      usePhoneSurface(tester, size: size);
      await tester.pumpWidget(testApp(const OnboardingScreen()));
      await tester.pumpAndSettle();
    }

    /// Taps the double ring at the top of the picker, which is D20.
    Future<void> pickDouble(WidgetTester tester) async {
      final board = tester.getRect(find.byType(FavoriteDoublePicker));
      await tester.tapAt(
        Offset(board.center.dx, board.center.dy - board.height * 0.3),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapLetsGo(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, "Let's go!"));
      await tester.pumpAndSettle();
    }

    testWidgets('names the missing name rather than doing nothing', (
      tester,
    ) async {
      await pumpOnboarding(tester);

      await tapLetsGo(tester);

      expect(find.text('Please enter a name'), findsOneWidget);
    });

    testWidgets('names the missing double once the name is there', (
      tester,
    ) async {
      await pumpOnboarding(tester);

      await tester.enterText(find.byType(TextField), 'Tester');
      await tapLetsGo(tester);

      expect(find.text('Please select a favorite double'), findsOneWidget);
      expect(find.text('Please enter a name'), findsNothing);
    });

    testWidgets('closes the keyboard so the message is not behind it', (
      tester,
    ) async {
      await pumpOnboarding(tester);

      // The field asks for focus on its own, which is what opens the keyboard
      // over the lower half of the screen.
      expect(tester.testTextInput.isVisible, isTrue);

      await tapLetsGo(tester);

      expect(tester.testTextInput.isVisible, isFalse);
    });

    /// The background the button actually paints, which is the default of the
    /// theme when the screen leaves it alone.
    Color buttonColor(WidgetTester tester) {
      final material = tester.widget<Material>(
        find.descendant(
          of: find.widgetWithText(FilledButton, "Let's go!"),
          matching: find.byType(Material),
        ),
      );
      return material.color!;
    }

    testWidgets('marks both fields as required', (tester) async {
      await pumpOnboarding(tester);

      expect(find.text('Required'), findsOneWidget);
      expect(find.text('Required: tap a double on the board'), findsOneWidget);
    });

    testWidgets('drops the board hint once a double is picked', (tester) async {
      await pumpOnboarding(tester);

      await pickDouble(tester);

      expect(find.text('Required: tap a double on the board'), findsNothing);
    });

    testWidgets('stays grey until both are given', (tester) async {
      await pumpOnboarding(tester);
      final empty = buttonColor(tester);

      await tester.enterText(find.byType(TextField), 'Tester');
      await tester.pumpAndSettle();
      expect(buttonColor(tester), empty, reason: 'the double is still missing');

      await pickDouble(tester);

      final ready = buttonColor(tester);
      expect(ready, isNot(empty));
      expect(
        ready,
        Theme.of(
          tester.element(find.byType(OnboardingScreen)),
        ).colorScheme.primary,
      );
    });

    testWidgets('answers the press while it is still grey', (tester) async {
      await pumpOnboarding(tester);

      await tapLetsGo(tester);

      expect(find.text('Please enter a name'), findsOneWidget);
    });

    testWidgets('takes the press once both are given', (tester) async {
      await pumpOnboarding(tester);

      await tester.enterText(find.byType(TextField), 'Tester');
      await pickDouble(tester);
      expect(find.text('D20'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, "Let's go!"));
      // A single frame rather than a settle: the press is through, and what
      // follows it is a write to SQLite that this clock never reaches.
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text('Please enter a name'), findsNothing);
      expect(find.text('Please select a favorite double'), findsNothing);
    });
  });
}
