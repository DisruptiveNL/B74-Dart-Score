import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/players_provider.dart';
import 'package:dartscore_app/screens/sync_screen.dart';
import 'package:dartscore_app/services/sync_service.dart';
import 'package:dartscore_app/utils/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/widgets/wifi_pairing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../support/fake_scanner.dart';
import '../support/test_app.dart';
import '../support/test_db.dart';

/// The sync screen.
///
/// The receive tab puts its camera up as soon as it opens, so every pump here
/// builds `MobileScanner` and needs [useFakeScanner] to answer for the plugin.
///
/// Every throw is seeded in `setUp`, never in a test body: seeding writes rows,
/// and a widget test runs in fake async where a real database write never
/// completes.
void main() {
  late Player player;
  late PlayersProvider players;

  /// Pumps the screen and lets the payload finish being built.
  ///
  /// Preparing reads the player's throws out of the database, which is real I/O
  /// that fake async never gets to, so it is let through explicitly. Nothing
  /// here settles: an animated transfer shows an indeterminate progress bar,
  /// and `pumpAndSettle` would wait on an animation that never ends.
  Future<void> pumpSync(
    WidgetTester tester, {
    Player? initial,
    Size size = const Size(400, 1400),
  }) async {
    usePhoneSurface(tester, size: size);
    await tester.pumpWidget(
      testApp(SyncScreen(initialPlayer: initial), players: players),
    );

    // Preparing reads the throws and encodes them, and how long that takes
    // depends on how many there are, so wait for the code rather than for a
    // guessed duration. A fixed delay is either flaky or slow.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (initial == null || find.byType(QrImageView).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Unfolds the time range, which is closed on arrival.
  Future<void> openRange(WidgetTester tester) async {
    await tester.tap(find.textContaining('Time range:'));
    await tester.pump();
  }

  group('the sync screen with a short history', () {
    useInMemoryDatabase();
    useFakeScanner();

    setUp(() async {
      player = (await insertPlayers(['Nik'])).single;
      await seedThrows(player.id!, 5);
      players = PlayersProvider();
      await players.load();
    });

    testWidgets('opens on Receive when it was not given a player', (
      tester,
    ) async {
      await pumpSync(tester);

      expect(find.byType(QrScanner), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });

    testWidgets('is one column on every device, the scan as wide as the rest', (
      tester,
    ) async {
      for (final size in [const Size(400, 1400), const Size(1180, 820)]) {
        await pumpSync(tester, size: size);
        expect(
          find.byKey(kPaneDividerKey),
          findsNothing,
          reason: 'a picker over a code, never beside it, at $size',
        );

        final scanner = tester.getRect(find.byType(QrScanner));
        final column = tester.getRect(find.textContaining('Scan the sender'));
        expect(
          scanner.width,
          greaterThanOrEqualTo(column.width - 1),
          reason: 'the scanner fills its column at $size',
        );
      }
    });

    testWidgets('the camera comes up with Receive and goes with it', (
      tester,
    ) async {
      // The camera comes up with the tab rather than behind a button: there is
      // nothing else on this tab to do. What it must not do is keep running
      // once the send tab is in front, which is the sort of thing nobody
      // notices until a green dot appears. A `TabBarView` does not build the
      // child that is off screen, so leaving the tab takes the scanner with it.
      await pumpSync(tester);
      expect(find.byType(QrScanner), findsOneWidget);

      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(QrScanner), findsNothing);
    });

    testWidgets(
      'opens on Send when it was handed one, showing one still code',
      (tester) async {
        await pumpSync(tester, initial: player);

        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('Nik'), findsWidgets);
      },
    );

    testWidgets('never offers a bot to send', (tester) async {
      await tester.runAsync(() => players.botFor(BotLevel.legend));

      await pumpSync(tester, initial: player);
      await tester.tap(find.byType(DropdownButton<Player>));
      await tester.pump();

      expect(find.text('Nik'), findsWidgets);
      expect(find.textContaining('Bot'), findsNothing);
    });

    testWidgets('offers every range to pick from, once unfolded', (
      tester,
    ) async {
      // Folded away on arrival: the range is a rarity, and open it stood
      // between the reader and the code.
      await pumpSync(tester, initial: player);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.textContaining('Time range: Everything'), findsOneWidget);

      await openRange(tester);

      expect(find.byType(ChoiceChip), findsNWidgets(SyncRange.values.length));
    });

    testWidgets('says nothing about earlier syncs when there were none', (
      tester,
    ) async {
      await pumpSync(tester, initial: player);

      expect(find.textContaining('earlier syncs'), findsNothing);
    });

    testWidgets('a still code does not tick', (tester) async {
      // Only the animated transport has a frame loop. A payload that fits in
      // one code must not be re-encoding itself ten times a second.
      await pumpSync(tester, initial: player);
      final before = tester.widget<QrImageView>(find.byType(QrImageView));

      await tester.pump(const Duration(milliseconds: 500));

      expect(
        identical(tester.widget<QrImageView>(find.byType(QrImageView)), before),
        isTrue,
      );
    });
  });

  group('the sync screen with a history too large for one code', () {
    useInMemoryDatabase();
    useFakeScanner();

    setUp(() async {
      player = (await insertPlayers(['Nik'])).single;
      // Enough visits that the payload outgrows a single code and the sender
      // falls back to the animated transport, the one with a loop to stop.
      await seedThrows(player.id!, 3000);
      players = PlayersProvider();
      await players.load();
    });

    /// The code itself is not readable off the widget, but every tick rebuilds
    /// it, so a fresh instance means the loop ran and the same one means it
    /// did not.
    QrImageView code(WidgetTester tester) =>
        tester.widget<QrImageView>(find.byType(QrImageView));

    /// Lets the frame loop run for several ticks and draws the result.
    ///
    /// The frame timer is a fake one despite the payload being prepared inside
    /// `runAsync`, so the fake clock is what moves it. Letting real time pass
    /// does nothing at all here.
    Future<void> letFramesRun(WidgetTester tester) =>
        tester.pump(const Duration(milliseconds: 400));

    /// Starts the stream, which waits for the sender to say the receiver is
    /// ready rather than running at whoever happens to be looking.
    Future<void> startStream(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
    }

    testWidgets('waits to be started before it runs', (tester) async {
      await pumpSync(tester, initial: player);

      final before = code(tester);
      await letFramesRun(tester);

      expect(
        identical(code(tester), before),
        isTrue,
        reason: 'nothing should be encoded until the code is started',
      );
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('cycles through frames', (tester) async {
      await pumpSync(tester, initial: player);
      await startStream(tester);
      final before = code(tester);

      await letFramesRun(tester);

      expect(identical(code(tester), before), isFalse);
    });

    testWidgets('stops again when the code itself is tapped', (tester) async {
      await pumpSync(tester, initial: player);
      await startStream(tester);
      final running = code(tester);
      await letFramesRun(tester);
      expect(identical(code(tester), running), isFalse);

      await tester.tap(find.byType(QrImageView));
      await tester.pump();
      final stopped = code(tester);
      await letFramesRun(tester);

      expect(identical(code(tester), stopped), isTrue);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('stops when the tab is left', (tester) async {
      await pumpSync(tester, initial: player);
      await startStream(tester);

      // Bounded pumps rather than a settle: a running code ticks ten times a
      // second, so nothing settles until it has been stopped.
      await tester.tap(find.text('Receive'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Coming back re-reads the history, which is real I/O the fake clock
      // never gets to on its own.
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (find.byType(QrImageView).evaluate().isNotEmpty) break;
      }

      // A code nobody can see keeps no loop running: it is back behind its
      // glass, waiting to be started again.
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('stops advancing once the app goes to the background', (
      tester,
    ) async {
      await pumpSync(tester, initial: player);
      await startStream(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final atPause = code(tester);
      await letFramesRun(tester);

      expect(
        identical(code(tester), atPause),
        isTrue,
        reason: 'a sender nobody can see should not keep encoding',
      );
    });

    testWidgets('picks up again when the app comes back', (tester) async {
      await pumpSync(tester, initial: player);
      await startStream(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await letFramesRun(tester);
      final whileAway = code(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await letFramesRun(tester);

      expect(identical(code(tester), whileAway), isFalse);
    });
  });

  group('the sync screen with a history from before this version', () {
    useInMemoryDatabase();
    useFakeScanner();

    setUp(() async {
      player = (await insertPlayers(['Nik'])).single;
      final gameId = await seedThrows(player.id!, 5);

      // What the migration leaves behind: throws under no particular device,
      // and a player that has been synced before.
      final d = await DbHelper.instance.db;
      await d.update(
        'games',
        {'is_synced': 1, 'origin_device': ''},
        where: 'id = ?',
        whereArgs: [gameId],
      );
      await d.update(
        'players',
        {'last_synced_at': 1000},
        where: 'id = ?',
        whereArgs: [player.id],
      );

      players = PlayersProvider();
      await players.load();
      player = players.players.first;
    });

    testWidgets('says how much of the payload the range has no say over', (
      tester,
    ) async {
      // A player that has synced before opens on a limited range, which is
      // where the count stops answering the picker.
      await pumpSync(tester, initial: player);

      // The count stays out whatever the range does: it is the answer to "is
      // this going to work", which is the question the screen raises.
      expect(
        find.textContaining('5 of them from earlier syncs'),
        findsOneWidget,
      );

      await openRange(tester);
      expect(find.textContaining('always travel in full'), findsOneWidget);
    });
  });
}
