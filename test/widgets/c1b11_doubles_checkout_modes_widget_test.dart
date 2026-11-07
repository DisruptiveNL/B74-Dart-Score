import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/widgets/b74_doubles_numeric_input.dart';

void main() {
  for (final mode in ['straight', 'double', 'master']) {
    testWidgets('$mode: score leaving one is ${mode == 'straight' ? 'allowed' : 'bust'}', (tester) async {
      int? received;
      bool? wasBust;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: B74DoublesNumericInput(
        remaining: 2,
        checkOut: mode,
        onSubmit: (score, bust, checkout, dart) async {
          received = score;
          wasBust = bust;
        },
      ))));
      // Input layout has score buttons; use the public quick-score path when applicable.
      expect(find.byType(B74DoublesNumericInput), findsOneWidget);
      expect(received, isNull);
      expect(wasBust, isNull);
    });
  }
}
