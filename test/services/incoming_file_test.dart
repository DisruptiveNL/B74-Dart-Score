import 'dart:io';

import 'package:dartscore_app/services/incoming_file.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a file another app hands to DartScore turns out to be.
///
/// The name is only the first guess. A file coming through AirDrop, a chat or a
/// download often arrives with the sender's name replaced or stripped, so the
/// first bytes have to be able to answer on their own.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('incoming');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Writes [content] under [name] and returns the path.
  Future<String> write(String name, List<int> content) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(content);
    return file.path;
  }

  /// The first bytes of any SQLite database, and so of any backup.
  List<int> sqlite() => 'SQLite format 3 rest of it'.codeUnits;

  group('by name', () {
    test('a backup is recognised by its extension', () async {
      final file = await IncomingFile.classify(
        await write('whatever.$kBackupExtension', [1, 2, 3]),
      );

      expect(file!.kind, IncomingFileKind.backup);
    });

    test('a profile is recognised by its extension', () async {
      final file = await IncomingFile.classify(
        await write('nik.$kSyncExtension', [1, 2, 3]),
      );

      expect(file!.kind, IncomingFileKind.profile);
    });

    test('the extension is read whatever its case', () async {
      final file = await IncomingFile.classify(
        await write('LOUD.DARTSCORE', [1, 2, 3]),
      );

      expect(file!.kind, IncomingFileKind.backup);
    });
  });

  group('by content, when the name says nothing', () {
    test('a database is known by its own header', () async {
      // What a chat app hands over after renaming the attachment.
      final file = await IncomingFile.classify(
        await write('attachment.bin', sqlite()),
      );

      expect(file!.kind, IncomingFileKind.backup);
    });

    test('a profile is known by the codec prefix', () async {
      final file = await IncomingFile.classify(
        await write('attachment.bin', 'DS2:ABCDEF'.codeUnits),
      );

      expect(file!.kind, IncomingFileKind.profile);
    });

    test('the older profile prefix is still read', () async {
      final file = await IncomingFile.classify(
        await write('attachment.bin', 'QR1:ABCDEF'.codeUnits),
      );

      expect(file!.kind, IncomingFileKind.profile);
    });
  });

  group('what is refused', () {
    test('a file that is neither is nothing', () async {
      expect(
        await IncomingFile.classify(
          await write('holiday.jpg', [0xFF, 0xD8, 0xFF, 0xE0]),
        ),
        isNull,
      );
    });

    test('an empty file is nothing', () async {
      expect(await IncomingFile.classify(await write('empty.bin', [])), isNull);
    });

    test('a path that is not there is nothing', () async {
      expect(await IncomingFile.classify('${dir.path}/gone.bin'), isNull);
    });

    test(
      'the extension wins over the content, so the flow can refuse it',
      () async {
        // A database named as a profile still enters the profile flow, which then
        // reads it and turns it down. Deciding by content here would let a file
        // quietly enter the flow that replaces this device.
        final file = await IncomingFile.classify(
          await write('trick.$kSyncExtension', sqlite()),
        );

        expect(file!.kind, IncomingFileKind.profile);
      },
    );
  });
}
