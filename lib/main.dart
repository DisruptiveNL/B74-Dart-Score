import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'widgets/b74_link_indicator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'providers/players_provider.dart';
import 'providers/game_provider.dart';
import 'providers/cricket_provider.dart';
import 'providers/shanghai_provider.dart';
import 'providers/around_the_clock_provider.dart';
import 'providers/checkout_ladder_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/language_provider.dart';
import 'providers/tablet_layout_provider.dart';
import 'providers/text_scale_provider.dart';
import 'providers/pace_provider.dart';
import 'providers/donation_provider.dart';
import 'screens/backup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/sync_screen.dart';
import 'services/incoming_file.dart';
import 'utils/layout.dart';
import 'utils/platform_notices.dart';

/// App entry point: initializes the binding, registers the native licenses,
/// enables edge-to-edge on Android, and runs the app.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerPlatformNotices();
  // Android 15+ forces edge-to-edge. Enable it explicitly so Flutter
  // correctly reports the bottom inset (navigation bar height).
  // iOS handles safe-area insets natively: no change needed there.
  if (Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  runApp(const DartScoreApp());
}

/// Routes to OnboardingScreen until a primary player exists, then HomeScreen.
///
/// Also the one place a file another app handed to DartScore is taken: it needs
/// a navigator to push the screen that deals with it, and this is the first
/// widget under the one that provides it.
class _AppGate extends StatefulWidget {
  const _AppGate();

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  StreamSubscription<IncomingFile>? _incoming;
  StreamSubscription<String>? _incomingFailed;

  /// Set while an arrival is being dealt with, so a second file, or the same
  /// one announced twice, does not open a second screen over the first.
  bool _opening = false;

  /// A file that arrived before the database had finished loading.
  ///
  /// On a cold start the system hands the file over within milliseconds, and
  /// the players are still being read at that point. Dropping it there is what
  /// made a file tapped in Files open the app and nothing else: the native side
  /// had already handed it over and cleared it, so it never came again.
  IncomingFile? _waiting;

  @override
  void initState() {
    super.initState();
    _incoming = IncomingFiles.stream.listen(_open);
    _incomingFailed = IncomingFiles.failures.listen(_reportFailure);
    // A file the app was launched with is waiting rather than announced, since
    // there was no Dart to announce it to when it arrived.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final file = await IncomingFiles.initial();
      if (file != null) _open(file);
    });
  }

  @override
  void dispose() {
    _incoming?.cancel();
    _incomingFailed?.cancel();
    super.dispose();
  }

  /// Says that a file arrived and came to nothing.
  ///
  /// A line rather than a dialog: the user asked for a file to be opened, and
  /// what they get instead is the app they asked for plus the reason it could
  /// not. Saying nothing at all is what made this look broken.
  void _reportFailure(String name) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text('${context.l10n.fileOpenFailed}\n$name')),
    );
  }

  /// Opens the screen that knows what to do with [file].
  ///
  /// Neither screen acts on it: a database lands on the confirmation that says
  /// what it holds and what it replaces, a profile on the same questions a
  /// scanned one raises. Nothing is written until one of those is answered.
  Future<void> _open(IncomingFile file) async {
    if (_opening || !mounted) return;

    // Neither screen can do anything until the database has been read, and on
    // a cold start it has not been. Held rather than dropped: this is the one
    // hand-over, and the system will not repeat it.
    if (!context.read<PlayersProvider>().loaded) {
      _waiting = file;
      return;
    }

    _opening = true;
    try {
      final navigator = Navigator.of(context);
      switch (file.kind) {
        case IncomingFileKind.backup:
          await navigator.push(
            MaterialPageRoute(
              builder: (_) => BackupScreen(incomingPath: file.path),
            ),
          );
        case IncomingFileKind.profile:
          final payload = await File(file.path).readAsString();
          await File(file.path).delete();
          if (!mounted) return;
          await navigator.push(
            MaterialPageRoute(
              builder: (_) => SyncScreen(incomingPayload: payload),
            ),
          );
      }
    } catch (_) {
      // An unreadable file is not worth a dialog over the home screen. Both
      // screens have their own way of saying a file was no good, and this is
      // the case where there is no file left to say it about.
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayersProvider>();

    // Whatever was waiting on the database goes now. After the frame, because
    // a route cannot be pushed from inside a build.
    final waiting = _waiting;
    if (provider.loaded && waiting != null) {
      _waiting = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(waiting));
    }

    if (!provider.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (provider.primaryPlayer == null) {
      return const OnboardingScreen();
    }
    return const HomeScreen();
  }
}

/// Locks orientation to portrait on phones; allows all orientations on tablets.
class _OrientationLock extends StatefulWidget {
  final Widget child;
  const _OrientationLock({required this.child});

  @override
  State<_OrientationLock> createState() => _OrientationLockState();
}

class _OrientationLockState extends State<_OrientationLock> {
  /// What was last handed to the system, so the same thing is not sent again.
  ///
  /// [didChangeDependencies] runs on every change to the MediaQuery, which
  /// includes the keyboard opening and closing and every rotation, while the
  /// answer only ever changes when the app moves between a phone sized and a
  /// tablet sized window.
  bool? _lockedToPortrait;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final portraitOnly = MediaQuery.sizeOf(context).shortestSide < 600;
    if (portraitOnly == _lockedToPortrait) return;
    _lockedToPortrait = portraitOnly;

    SystemChrome.setPreferredOrientations(
      portraitOnly
          ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
          : DeviceOrientation.values,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Root widget: wires up all providers, the light/dark themes and locale, and
/// hosts the [MaterialApp] gated by [_AppGate].
class DartScoreApp extends StatelessWidget {
  const DartScoreApp({super.key});

  // B74 Blue Edition v0.1 — application chrome only.
  // Dartboard segment and team identity colors remain unchanged.
  static final _lightScheme = const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF087CE8),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFD7EBFF),
    onPrimaryContainer: Color(0xFF092D56),
    secondary: Color(0xFF006A91),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFC7EEFF),
    onSecondaryContainer: Color(0xFF00344A),
    tertiary: Color(0xFF155D9C),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFD7E9FF),
    onTertiaryContainer: Color(0xFF0A315A),
    error: Color(0xFFB3261E),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF5F9FF),
    onSurface: Color(0xFF10243D),
    surfaceContainerHighest: Color(0xFFD8E6F5),
    surfaceContainerHigh: Color(0xFFE4EFFB),
    surfaceContainerLow: Color(0xFFF0F6FF),
    surfaceContainer: Color(0xFFEAF2FC),
    outline: Color(0xFF48617E),
    outlineVariant: Color(0xFFA5BDD6),
    onSurfaceVariant: Color(0xFF3D5570),
    inverseSurface: Color(0xFF10243D),
    onInverseSurface: Color(0xFFF5F9FF),
    inversePrimary: Color(0xFF7BC6FF),
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  static final _darkScheme = const ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF58B7FF),
    onPrimary: Color(0xFF061B34),
    primaryContainer: Color(0xFF087CE8),
    onPrimaryContainer: Colors.white,
    secondary: Color(0xFF00C8F8),
    onSecondary: Color(0xFF002C3B),
    secondaryContainer: Color(0xFF125273),
    onSecondaryContainer: Color(0xFFDBF7FF),
    tertiary: Color(0xFF8BC9FF),
    onTertiary: Color(0xFF062D50),
    tertiaryContainer: Color(0xFF174B7D),
    onTertiaryContainer: Color(0xFFE0F1FF),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF081A35),
    onSurface: Color(0xFFF6FAFF),
    surfaceContainerHighest: Color(0xFF244D7D),
    surfaceContainerHigh: Color(0xFF1A426E),
    surfaceContainerLow: Color(0xFF0C274B),
    surfaceContainer: Color(0xFF123B70),
    outline: Color(0xFF87A9CD),
    outlineVariant: Color(0xFF40658C),
    onSurfaceVariant: Color(0xFFBCD6F1),
    inverseSurface: Color(0xFFF5F9FF),
    onInverseSurface: Color(0xFF10243D),
    inversePrimary: Color(0xFF0759A8),
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  /// The two themes, built once instead of on every rebuild of the root.
  ///
  /// [ThemeData] assembles a good number of sub-themes on construction, and
  /// the schemes it is built from never change, so there is nothing to gain
  /// from doing that again whenever the theme mode or the locale changes.
  static final _lightTheme = _build(_lightScheme);
  static final _darkTheme = _build(_darkScheme);

  /// Builds the shared [ThemeData] for the given [cs] color scheme (cards,
  /// app bar, and chips tuned to the dartboard palette).
  static ThemeData _build(ColorScheme cs) => ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    scaffoldBackgroundColor: cs.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
    ),
    chipTheme: ChipThemeData(backgroundColor: cs.surfaceContainerHigh),
  );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => TabletLayoutProvider()),
        ChangeNotifierProvider(create: (_) => TextScaleProvider()),
        ChangeNotifierProvider(create: (_) => PaceProvider()),
        ChangeNotifierProvider(create: (_) => DonationProvider()),
        ChangeNotifierProvider(create: (_) => PlayersProvider()..load()),
        ChangeNotifierProvider(create: (_) => GameProvider()),
        ChangeNotifierProvider(create: (_) => CricketProvider()),
        ChangeNotifierProvider(create: (_) => ShanghaiProvider()),
        ChangeNotifierProvider(create: (_) => AroundTheClockProvider()),
        ChangeNotifierProvider(create: (_) => CheckoutLadderProvider()),
      ],
      child: Consumer2<ThemeProvider, LanguageProvider>(
        builder: (context, tp, lp, child) => MaterialApp(
          title: 'B74 Dart Score',
          debugShowCheckedModeBanner: false,
          themeMode: tp.mode,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          locale: lp.locale, // null = follow system
          // On Android: wrap every route in SafeArea(top:false) so the
          // 3-button navigation bar never overlaps interactive content.
          // On iOS: the system handles safe-area insets natively.
          builder: (context, child) {
            final wrapped = _OrientationLock(
              child: Platform.isAndroid
                  ? SafeArea(top: false, child: child!)
                  : child!,
            );
            // The text size the reader set, applied once for the whole app so
            // that no screen can be left out of it. A phone keeps exactly what
            // the system asks for: the setting is about the distance a tablet
            // is read from, and the phone screens have no room to spare.
            return TextScaleBy(
              factor: isTabletLayout(context)
                  ? context.watch<TextScaleProvider>().factor
                  : 1.0,
              child: wrapped, //child: B74LinkOverlay(child: wrapped),
            );
          },
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('de')],
          home: const _AppGate(),
        ),
      ),
    );
  }
}
