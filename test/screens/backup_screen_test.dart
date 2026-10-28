import 'dart:io';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/players_provider.dart';
import 'package:dartscore_app/screens/backup_screen.dart';
import 'package:dartscore_app/services/device_identity.dart';
import 'package:dartscore_app/utils/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_app.dart';

/// The channel the hand-written document picker answers on.
const _pickerChannel = MethodChannel('dartscore/document_picker');

void main() {
  group('restoring a backup from the screen', () {
    late Directory dir;
    late String dbPath;
    late PlayersProvider players;

    /// What the mocked picker hands back on the next call.
    String? pickedPath;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      DeviceIdentity.debugSetId(null);
      pickedPath = null;

      // A file rather than an in-memory database: restoring swaps the file, so
      // there has to be one.
      dir = await Directory.systemTemp.createTemp('dartscore_backup_screen');
      dbPath = '${dir.path}/dartscore.db';
      DbHelper.debugDatabasePath = dbPath;
      await DbHelper.debugReset();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pickerChannel, (call) async {
            return call.method == 'pickFile' ? pickedPath : null;
          });

      players = PlayersProvider();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pickerChannel, null);
      await DbHelper.debugReset();
      DbHelper.debugDatabasePath = null;
      DeviceIdentity.debugSetId(null);
      await dir.delete(recursive: true);
    });

    /// Writes a backup holding exactly [names] and leaves the live database
    /// holding [thenAdd] on top, so a restore has something to undo.
    ///
    /// Through [WidgetTester.runAsync], like every real read and write in this
    /// file: a widget test runs on a fake clock that no file access ever
    /// returns on, and awaiting one there hangs the test rather than failing
    /// it.
    Future<String> backupOf(
      WidgetTester tester,
      List<String> names, {
      String? thenAdd,
      String device = 'iPhone',
    }) async {
      return (await tester.runAsync(() async {
        for (final name in names) {
          await DbHelper.instance.insertPlayer(Player(name: name));
        }
        final source = await DbHelper.instance.prepareBackup(
          'DEVICEAAAA000001',
          device,
        );
        final path = '${dir.path}/backup.db';
        await File(source).copy(path);
        if (thenAdd != null) {
          await DbHelper.instance.insertPlayer(Player(name: thenAdd));
        }
        return path;
      }))!;
    }

    /// Pumps real time in slices until [finder] matches, so the file reads
    /// behind the screen get a chance to finish. A widget test's own clock
    /// never lets real I/O complete.
    Future<void> pumpUntil(
      WidgetTester tester,
      Finder finder, {
      bool gone = false,
    }) async {
      for (var i = 0; i < 80; i++) {
        if (finder.evaluate().isEmpty == gone) return;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      fail('gave up waiting for $finder');
    }

    /// Waits for the screen to be idle again. Never `pumpAndSettle`: the busy
    /// indicator is a running animation, so settling only ever times out while
    /// the work behind it is still going.
    Future<void> pumpUntilIdle(WidgetTester tester) =>
        pumpUntil(tester, find.byType(CircularProgressIndicator), gone: true);

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.runAsync(players.load);
      await tester.pumpWidget(testApp(const BackupScreen(), players: players));
      await tester.pumpAndSettle();
    }

    /// Walks the gates a restore goes through before a file is even picked:
    /// the entry, the warning with its offer to save first, then the source.
    Future<void> tapRestoreFromFile(WidgetTester tester) async {
      await tester.tap(find.text('Restore backup').first);
      await tester.pumpAndSettle();

      expect(
        find.text('Save the current data first?'),
        findsOneWidget,
        reason:
            'the only way back out of a wrong restore is a copy of what '
            'is there now, and this is the last moment to make one',
      );

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From a file'));
      await tester.pump();
    }

    testWidgets('asks first, and says what the backup holds', (tester) async {
      pickedPath = await backupOf(tester, ['Ann', 'Bob'], thenAdd: 'Later');
      await pumpScreen(tester);

      await tapRestoreFromFile(tester);
      await pumpUntil(tester, find.text('Restore backup?'));

      // What it holds, so two backups can be told apart before one of them
      // replaces everything.
      expect(find.text('This backup'), findsOneWidget);
      expect(find.text('2'), findsOneWidget, reason: 'two players');
      expect(
        find.text('iPhone'),
        findsOneWidget,
        reason: 'the device it came from',
      );
      expect(find.textContaining('cannot be undone'), findsWidgets);
      expect(
        find.textContaining('stay filed under the device'),
        findsOneWidget,
      );
    });

    testWidgets('has room for a device that names itself in full', (
      tester,
    ) async {
      // The label names the device and its operating system now, not just
      // "iPhone", so this row has to hold a good deal more than it used to.
      // On a narrow phone, which is where it runs out of room.
      const device = "Niklas' Galaxy S23 Ultra (Android 14)";
      usePhoneSurface(tester, size: const Size(360, 800));
      pickedPath = await backupOf(
        tester,
        ['Ann'],
        thenAdd: 'Later',
        device: device,
      );
      await pumpScreen(tester);

      await tapRestoreFromFile(tester);
      await pumpUntil(tester, find.text('Restore backup?'));

      expect(find.text(device), findsOneWidget);

      // Measured rather than left to an overflow error, because there is none
      // to catch: the row sits in a box that lets it grow, so a value too long
      // for the dialog is quietly cut off at the edge instead of reported. Laid
      // out behind a Spacer this text takes 513 logical pixels on a 360 pixel
      // screen, and everything past the edge is simply not there for the user.
      final dialog = tester.getSize(
        find.ancestor(
          of: find.text('Restore backup?'),
          matching: find.byType(AlertDialog),
        ),
      );
      expect(
        tester.getSize(find.text(device)).width,
        lessThanOrEqualTo(dialog.width),
        reason: 'the device name has to fit the dialog that shows it',
      );
    });

    testWidgets(
      'writes the confirming button in the colour that goes with it',
      (tester) async {
        // A FilledButton given only a background writes in onPrimary, which is
        // white in both themes. Against the dark theme's error, a light red,
        // that is barely readable. The pair has to be set together.
        pickedPath = await backupOf(tester, ['Ann'], thenAdd: 'Later');
        await pumpScreen(tester);

        await tapRestoreFromFile(tester);
        await pumpUntil(tester, find.text('Restore backup?'));

        final button = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Restore backup'),
            matching: find.byType(FilledButton),
          ),
        );
        final cs = Theme.of(
          tester.element(find.byType(AlertDialog).last),
        ).colorScheme;

        expect(button.style?.backgroundColor?.resolve({}), cs.error);
        expect(
          button.style?.foregroundColor?.resolve({}),
          cs.onError,
          reason: 'the colour named for what is behind it, not onPrimary',
        );
      },
    );

    /// Opens the restore confirmation on a screen of [size] and reports how
    /// wide the dialog ended up.
    Future<double> confirmationWidthAt(WidgetTester tester, Size size) async {
      usePhoneSurface(tester, size: size);
      pickedPath = await backupOf(tester, ['Ann'], thenAdd: 'Later');
      await pumpScreen(tester);

      await tapRestoreFromFile(tester);
      await pumpUntil(tester, find.text('Restore backup?'));

      return tester
          .getSize(
            find.ancestor(
              of: find.text('Restore backup?'),
              matching: find.byType(AlertDialog),
            ),
          )
          .width;
    }

    // An AlertDialog takes the width it is offered, and on an iPad that is most
    // of the screen for a few lines of text. Every dialog in the sync screen is
    // bounded; the two here were the ones that were not.
    testWidgets('keeps the confirmation readable on a tablet in landscape', (
      tester,
    ) async {
      expect(
        await confirmationWidthAt(tester, const Size(1194, 834)),
        lessThanOrEqualTo(kMaxContentWidth),
      );
    });

    testWidgets('keeps the confirmation readable on a tablet in portrait', (
      tester,
    ) async {
      expect(
        await confirmationWidthAt(tester, const Size(834, 1194)),
        lessThanOrEqualTo(kMaxContentWidth),
      );
    });

    testWidgets('changes nothing when the question is declined', (
      tester,
    ) async {
      pickedPath = await backupOf(tester, ['Ann'], thenAdd: 'Later');
      await pumpScreen(tester);

      await tapRestoreFromFile(tester);
      await pumpUntil(tester, find.text('Restore backup?'));
      // Scoped to the confirmation: the route dialog behind it is still on its
      // way out and carries a Cancel of its own.
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Restore backup?'),
            matching: find.byType(AlertDialog),
          ),
          matching: find.text('Cancel'),
        ),
      );
      await pumpUntilIdle(tester);

      final names = (await tester.runAsync(
        DbHelper.instance.getPlayers,
      ))!.map((p) => p.name);
      expect(names, containsAll(['Ann', 'Later']));
      // The copy the picker left behind is not kept around either.
      expect(await tester.runAsync(() => File(pickedPath!).exists()), isFalse);
    });

    testWidgets('replaces the data once it is confirmed', (tester) async {
      pickedPath = await backupOf(tester, ['Ann'], thenAdd: 'Later');
      await pumpScreen(tester);

      await tapRestoreFromFile(tester);
      await pumpUntil(tester, find.text('Restore backup?'));
      await tester.tap(find.widgetWithText(FilledButton, 'Restore backup'));
      await pumpUntil(tester, find.text('Backup restored.'));

      final names = (await tester.runAsync(
        DbHelper.instance.getPlayers,
      ))!.map((p) => p.name);
      expect(names, ['Ann']);
      expect(
        await DeviceIdentity.id,
        isNot('DEVICEAAAA000001'),
        reason:
            'this device keeps its own id, or it could never sync with '
            'the one the backup came from again',
      );
    });

    testWidgets('says so when the file is not a backup', (tester) async {
      pickedPath = '${dir.path}/notes.txt';
      await tester.runAsync(
        () => File(pickedPath!).writeAsString('not a database'),
      );
      await pumpScreen(tester);

      await tapRestoreFromFile(tester);
      await pumpUntil(
        tester,
        find.text('This file is not a DartScore backup.'),
      );

      expect(find.text('Restore backup?'), findsNothing);
    });

    testWidgets('does nothing when the picker is dismissed', (tester) async {
      await tester.runAsync(
        () => DbHelper.instance.insertPlayer(Player(name: 'Ann')),
      );
      pickedPath = null;
      await pumpScreen(tester);

      await tapRestoreFromFile(tester);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      expect(find.text('Restore backup?'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
