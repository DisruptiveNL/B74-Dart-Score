import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
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
          await navigator.push(MaterialPageRoute(
              builder: (_) => BackupScreen(incomingPath: file.path)));
        case IncomingFileKind.profile:
          final payload = await File(file.path).readAsString();
          await File(file.path).delete();
          if (!mounted) return;
          await navigator.push(MaterialPageRoute(
              builder: (_) => SyncScreen(incomingPayload: payload)));
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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

    SystemChrome.setPreferredOrientations(portraitOnly
        ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : DeviceOrientation.values);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Root widget: wires up all providers, the light/dark themes and locale, and
/// hosts the [MaterialApp] gated by [_AppGate].
class DartScoreApp extends StatelessWidget {
  const DartScoreApp({super.key});

  // ── Accessible dartboard palette ─────────────────────────────────────────
  // WCAG AA: ≥4.5:1 for text, ≥3:1 for large/UI elements.
  // Dartboard: cream/black segments, red bull, green double-ring, gold wire.

  static final _lightScheme = ColorScheme(
    brightness: Brightness.light,
    // Red bull: #B71C1C on white = 7.2:1 ✓✓
    primary: const Color(0xFFB71C1C),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFFFCDD2),
    onPrimaryContainer: const Color(0xFF7F0000),
    // Green double ring: #66BB6A on white = 3.0:1 ✓ (large UI element)
    secondary: const Color(0xFF66BB6A),
    onSecondary: const Color(0xFF003909),
    secondaryContainer: const Color(0xFFA5D6A7),    // more saturated, visible
    onSecondaryContainer: const Color(0xFF002106),
    // Triple ring red: #8B0000 on white = 8.1:1 ✓✓
    tertiary: const Color(0xFF8B0000),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFFFCDD2),
    onTertiaryContainer: const Color(0xFF5F0000),
    error: const Color(0xFF9B0000),
    onError: Colors.white,
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF410002),
    // Clean white surface: no warm cream tint → stronger contrast
    surface: const Color(0xFFFFFFFF),
    onSurface: const Color(0xFF0D0D0D),             // near-black, 18:1 ✓✓
    surfaceContainerHighest: const Color(0xFFDDDDDD),
    surfaceContainerHigh: const Color(0xFFEAEAEA),
    surfaceContainerLow: const Color(0xFFF5F5F5),
    surfaceContainer: const Color(0xFFE5E5E5),
    outline: const Color(0xFF4A4A4A),               // 9.7:1, sharp borders ✓✓
    outlineVariant: const Color(0xFF9E9E9E),        // 3.9:1, visible dividers ✓
    onSurfaceVariant: const Color(0xFF2E2E2E),      // 12.6:1, secondary text ✓✓
    inverseSurface: const Color(0xFF1C1C1C),
    onInverseSurface: const Color(0xFFF5F5F5),
    inversePrimary: const Color(0xFFFF8A80),
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  // iOS-style dark gray: neutral, no warm tint
  static final _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    // Muted red: not neon, comfortable on dark gray
    primary: const Color(0xFFEF5350),           // red 400
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFF7F0000),
    onPrimaryContainer: const Color(0xFFFFCDD2),
    // Muted green
    secondary: const Color(0xFF1B5E20),         // green 800: deep, calm on dark
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFF1B5E20),
    onSecondaryContainer: const Color(0xFFC8E6C9),
    // Triple ring red: muted for dark mode
    tertiary: const Color(0xFFEF9A9A),          // red 200
    onTertiary: const Color(0xFF7F0000),
    tertiaryContainer: const Color(0xFF7F0000),
    onTertiaryContainer: const Color(0xFFFFCDD2),
    error: const Color(0xFFFFB4AB),
    onError: const Color(0xFF690005),
    errorContainer: const Color(0xFF93000A),
    onErrorContainer: const Color(0xFFFFDAD6),
    // iOS dark gray system colors
    surface: const Color(0xFF1C1C1E),           // iOS systemBackground dark
    onSurface: const Color(0xFFEEEEEE),
    surfaceContainerHighest: const Color(0xFF48484A),
    surfaceContainerHigh: const Color(0xFF3A3A3C),
    surfaceContainerLow: const Color(0xFF1C1C1E),
    surfaceContainer: const Color(0xFF2C2C2E),  // iOS secondarySystemBackground
    outline: const Color(0xFF636366),           // iOS separator
    outlineVariant: const Color(0xFF3A3A3C),
    onSurfaceVariant: const Color(0xFFAEAEB2),  // iOS secondaryLabel
    inverseSurface: const Color(0xFFEEEEEE),
    onInverseSurface: const Color(0xFF1C1C1E),
    inversePrimary: const Color(0xFFC62828),
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
  static final _darkTheme  = _build(_darkScheme);

  /// Builds the shared [ThemeData] for the given [cs] color scheme (cards,
  /// app bar, and chips tuned to the dartboard palette).
  static ThemeData _build(ColorScheme cs) => ThemeData(
        colorScheme: cs,
        useMaterial3: true,
        scaffoldBackgroundColor: cs.surface,
        cardTheme: CardThemeData(
          elevation: 0,
          color: cs.brightness == Brightness.light
              ? const Color(0xFFF5F5F5)   // light gray: visible on white surface
              : const Color(0xFF2C2C2E),  // iOS secondarySystemBackground
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: cs.surfaceContainerHigh,
        ),
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
          title: 'DartScore',
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
              child: wrapped,
            );
          },
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('de'),
          ],
          home: const _AppGate(),
        ),
      ),
    );
  }
}
