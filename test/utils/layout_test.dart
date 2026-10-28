import 'package:dartscore_app/utils/layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// The arithmetic behind the two pane layouts, which no widget test reaches:
/// a pane width is decided before anything is laid out.
void main() {
  group('the width of the first pane', () {
    test('follows the share it is given', () {
      expect(
        paneWidthFor(total: 1000, fraction: 0.4, minPaneWidth: 300),
        closeTo(400, 0.01),
      );
    });

    test('stops where either pane would become unusable', () {
      // 20 percent of 1000 is below the floor, and 80 percent leaves the other
      // side below it.
      expect(
        paneWidthFor(total: 1000, fraction: 0.2, minPaneWidth: 300),
        closeTo(300, 0.01),
      );
      expect(
        paneWidthFor(total: 1000, fraction: 0.8, minPaneWidth: 300),
        closeTo(684, 0.01),
      );
    });

    test('divides a window too narrow for two floors anyway', () {
      // A 7 inch tablet upright is wide enough to divide by the breakpoint and
      // too narrow for two panes of 320. Both sides get what there is instead
      // of a floor that crosses itself, which used to throw.
      final width = paneWidthFor(total: 600, fraction: 0.5, minPaneWidth: 320);
      expect(width, closeTo((600 - kDividerHitWidth) / 2, 0.01));
      expect(width * 2 + kDividerHitWidth, lessThanOrEqualTo(600));
    });
  });

  group('two columns', () {
    test('are shown only where both stay readable', () {
      expect(
        fitsTwoPanes(
          2 * kMinSetupPaneWidth + kDividerHitWidth,
          kMinSetupPaneWidth,
        ),
        isTrue,
      );
      expect(fitsTwoPanes(2 * kMinSetupPaneWidth, kMinSetupPaneWidth), isFalse);
      // The setup divides on an iPad upright, but not on a small tablet.
      expect(fitsTwoPanes(768, kMinSetupPaneWidth), isTrue);
      expect(fitsTwoPanes(600, kMinSetupPaneWidth), isFalse);
      // A summary asks for more, so it waits for the iPad to be turned.
      expect(fitsTwoPanes(768, kMinSummaryPaneWidth), isFalse);
      expect(fitsTwoPanes(1024, kMinSummaryPaneWidth), isTrue);
    });
  });
}
