import 'package:dartscore_app/utils/layout.dart';
import 'package:dartscore_app/widgets/summary_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

/// The body every post-game summary is laid out by: one column, or two with the
/// way out under both.
void main() {
  group('a summary body', () {
    /// Renders a stand-in summary at [size]: one card of result, one of detail
    /// and a button out. [safeArea] describes the insets of a device with a
    /// home indicator under the bar.
    Future<void> pumpBody(
      WidgetTester tester,
      Size size, {
      EdgeInsets safeArea = EdgeInsets.zero,
    }) async {
      usePhoneSurface(tester, size: size, safeArea: safeArea);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: SummaryBody(
              result: const [
                Card(child: SizedBox(height: 200, child: Text('won'))),
              ],
              details: const [
                Card(child: SizedBox(height: 200, child: Text('numbers'))),
              ],
              actions: [
                FilledButton(onPressed: () {}, child: const Text('home')),
                FilledButton(onPressed: () {}, child: const Text('again')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is one column on a phone, in the order it was given', (
      tester,
    ) async {
      await pumpBody(tester, const Size(400, 900));

      expect(find.byKey(kPaneDividerKey), findsNothing);
      expect(
        tester.getRect(find.text('won')).bottom,
        lessThan(tester.getRect(find.text('numbers')).top),
      );
      // The way out sits under everything, on a bar of its own that the
      // content scrolls behind rather than into.
      expect(
        tester.getRect(find.text('numbers')).bottom,
        lessThan(tester.getRect(find.text('home')).top),
      );
      expect(
        tester.getRect(find.text('again')).left,
        greaterThan(tester.getRect(find.text('home')).right),
      );
    });

    testWidgets('gives the buttons the same room above as below them', (
      tester,
    ) async {
      await pumpBody(
        tester,
        const Size(400, 900),
        safeArea: const EdgeInsets.only(bottom: 20),
      );

      final bar = tester.getRect(find.byType(SummaryActionBar));
      final button = tester.getRect(find.byType(FilledButton).first);

      // Below the buttons is the padding plus the home indicator; the same
      // amount goes above them, or the bar reads as bottom heavy. The hairline
      // the bar starts with is the one pixel of slack.
      expect(button.top - bar.top, closeTo(bar.bottom - button.bottom, 1.5));
    });

    testWidgets('keeps its room on a device that reports no inset', (
      tester,
    ) async {
      // Android reports nothing under the bar, driven by gestures or by three
      // buttons alike. The room around the buttons used to be almost entirely
      // the iPhone's home indicator, which left three pixels here.
      await pumpBody(tester, const Size(400, 900));

      final bar = tester.getRect(find.byType(SummaryActionBar));
      final button = tester.getRect(find.byType(FilledButton).first);

      expect(button.top - bar.top, greaterThan(12), reason: 'above');
      expect(bar.bottom - button.bottom, greaterThan(12), reason: 'below');
    });

    testWidgets('gives a tablet with no inset its room as well', (
      tester,
    ) async {
      await pumpBody(tester, const Size(1180, 820));

      final bar = tester.getRect(find.byType(SummaryActionBar));
      final button = tester.getRect(find.byType(FilledButton).first);

      expect(button.top - bar.top, greaterThan(20), reason: 'above');
      expect(bar.bottom - button.bottom, greaterThan(20), reason: 'below');
    });

    testWidgets('clears a home indicator underneath the buttons', (
      tester,
    ) async {
      await pumpBody(
        tester,
        const Size(400, 900),
        safeArea: const EdgeInsets.only(bottom: 34),
      );

      final bar = tester.getRect(find.byType(SummaryActionBar));
      final button = tester.getRect(find.byType(FilledButton).first);

      // The indicator is drawn inside the room below rather than under it, so
      // the room is the larger of the two and not their sum.
      expect(bar.bottom - button.bottom, closeTo(34, 1.5), reason: 'below');
      expect(button.top - bar.top, closeTo(20, 1.5), reason: 'above');
    });

    testWidgets('stays one column on a tablet held upright', (tester) async {
      // An iPad upright is 768 wide, which is two summary columns short of the
      // width they need.
      await pumpBody(tester, const Size(768, 1024));

      expect(find.byKey(kPaneDividerKey), findsNothing);
      expect(
        tester.getRect(find.text('won')).bottom,
        lessThan(tester.getRect(find.text('numbers')).top),
      );
    });

    testWidgets('divides once there is room, with the way out under both', (
      tester,
    ) async {
      await pumpBody(tester, const Size(1180, 820));

      expect(find.byKey(kPaneDividerKey), findsOneWidget);
      expect(
        tester.getRect(find.text('numbers')).left,
        greaterThan(tester.getRect(find.text('won')).right),
      );

      // Under both: below whichever column reaches furthest down.
      final home = tester.getRect(find.text('home'));
      final again = tester.getRect(find.text('again'));
      for (final column in tester.widgetList(find.byType(ListView))) {
        expect(
          home.top,
          greaterThan(tester.getRect(find.byWidget(column)).bottom),
        );
      }
      // Side by side, and the pair centred rather than stretched across the
      // whole window.
      expect(again.left, greaterThan(home.right));
      expect((home.left + again.right) / 2, closeTo(1180 / 2, 12));
    });
  });
}
