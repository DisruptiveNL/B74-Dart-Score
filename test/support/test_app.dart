import 'package:dartscore_app/l10n/app_localizations.dart';
import 'package:dartscore_app/providers/game_provider.dart';
import 'package:dartscore_app/providers/players_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Wraps [child] in the localizations and [MaterialApp] a screen needs to
/// build, so a widget test can pump one screen instead of the app.
///
/// Only [PlayersProvider] is supplied by default, and only because several
/// screens read it without depending on its contents. A mode's provider is
/// deliberately *not* handed out: a screen whose provider is missing should
/// fail with a clear ProviderNotFound, not quietly bind to an empty one and
/// spin on its loading indicator forever. Tests wrap their own, with the
/// concrete type, so `Consumer<CricketProvider>` actually finds it.
///
/// The theme providers are left out too: they read shared_preferences, and no
/// screen under test depends on which theme is active.
Widget testApp(
  Widget child, {
  PlayersProvider? players,
  GameProvider? game,
  Locale locale = const Locale('en'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PlayersProvider>.value(
        value: players ?? PlayersProvider(),
      ),
      if (game != null) ChangeNotifierProvider<GameProvider>.value(value: game),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: child,
    ),
  );
}

/// Lets a screen's database read through and settles once it is done.
///
/// A widget test runs in fake async, where real I/O never completes, so a
/// screen whose body is a `FutureBuilder` over a query would sit on its
/// spinner forever. Waiting for the spinner to go rather than for a guessed
/// duration keeps this neither flaky nor slow: settling straight away would
/// wait on an animation that only stops once the future is done.
Future<void> pumpUntilLoaded(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
}

/// Gives the widget a surface tall enough that the screens under test lay out
/// without overflowing, and undoes it afterwards.
///
/// The default test surface is 800x600, which is shorter than any phone these
/// screens were built for, so a scoreboard plus a numpad does not fit and every
/// assertion drowns in overflow errors.
///
/// [safeArea] describes the insets of a phone with a notch and a home
/// indicator. It defaults to none, which is the flat rectangle most tests want;
/// a layout test that cares where the system bars sit passes its own.
void usePhoneSurface(
  WidgetTester tester, {
  Size size = const Size(400, 900),
  EdgeInsets safeArea = EdgeInsets.zero,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  final padding = FakeViewPadding(
    top: safeArea.top,
    bottom: safeArea.bottom,
    left: safeArea.left,
    right: safeArea.right,
  );
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}
