import 'package:dartscore_app/screens/about_screen.dart';
import 'package:dartscore_app/screens/licenses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

/// The about screen and the two license screens it opens.
///
/// The version comes from a platform channel, which a widget test has to answer
/// itself: left unanswered it throws into the future the screen started in
/// `initState`, and the failure lands in whatever test is running by then.
void main() {
  const channel = MethodChannel('dev.fluttercommunity.plus/package_info');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => <String, dynamic>{
            'appName': 'DartScore',
            'packageName': 'com.ratka.dartscore',
            'version': '1.0.0',
            'buildNumber': '1',
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpAbout(WidgetTester tester, Size size) async {
    usePhoneSurface(tester, size: size);
    await tester.pumpWidget(testApp(const AboutScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('reads the licence notice in a column, not across the tablet', (
    tester,
  ) async {
    await pumpAbout(tester, const Size(1180, 820));

    await tester.tap(find.text('License').last);
    await tester.pumpAndSettle();

    // The notice is a page of prose, so it keeps the width the rest of the app
    // reads at rather than running the whole way across.
    final notice = tester.getRect(
      find.textContaining('GNU General Public').last,
    );
    expect(notice.width, lessThan(700));
    expect(notice.center.dx, closeTo(1180 / 2, 20));
  });

  testWidgets('names the repository the binary is built from', (tester) async {
    await pumpAbout(tester, const Size(400, 900));

    // The GPL asks a binary to say where its source is, and the store build is
    // the only copy most readers ever see.
    expect(find.text('Source code'), findsOneWidget);

    await tester.tap(find.text('License').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('https://github.com/Rdiger-36/DartScore'),
      findsOneWidget,
    );
  });

  testWidgets('opens the packaged licenses in the app\'s own screen', (
    tester,
  ) async {
    await pumpAbout(tester, const Size(1180, 820));

    await tester.tap(find.text('Open Source Licenses').last);
    await tester.pumpAndSettle();

    // Flutter's own page divides itself from 840 dp in a way that fights the
    // scroll, so the app brings its own list and its own pane.
    expect(find.byType(LicensePage), findsNothing);
    expect(find.byType(LicensesScreen), findsOneWidget);
  });
}
