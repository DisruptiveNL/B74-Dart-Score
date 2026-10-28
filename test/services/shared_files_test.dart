import 'dart:io';

import 'package:dartscore_app/services/incoming_file.dart';
import 'package:flutter_test/flutter_test.dart';

/// What earlier shares leave behind.
///
/// A backup is the whole database, so a copy left in the cache after every
/// share is real space gone for nothing. Cleared on the way in rather than
/// after the sheet closes, because a target may still be reading the file off
/// its content URI at that point.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shared');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Puts an empty file called [name] in the directory.
  Future<File> touch(String name) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes([1]);
    return file;
  }

  /// What is left, by name.
  Future<List<String>> remaining() async =>
      (await dir.list().toList()).map((e) => e.uri.pathSegments.last).toList()
        ..sort();

  test('earlier shares of the same kind are cleared', () async {
    await touch('backup-1.$kBackupExtension');
    await touch('backup-2.$kBackupExtension');

    await clearSharedFiles(dir, kBackupExtension);

    expect(await remaining(), isEmpty);
  });

  test('the other kind is left alone', () async {
    // The two are shared from different screens and neither should be able to
    // pull the other's file out from under a share in progress.
    await touch('backup.$kBackupExtension');
    await touch('nik.$kSyncExtension');

    await clearSharedFiles(dir, kSyncExtension);

    expect(await remaining(), ['backup.$kBackupExtension']);
  });

  test('anything else in the directory is untouched', () async {
    await touch('somebody-elses.txt');
    await touch('picked-backup.db');

    await clearSharedFiles(dir, kBackupExtension);

    expect(await remaining(), ['picked-backup.db', 'somebody-elses.txt']);
  });

  test('a directory that is not there is not a failure', () async {
    final gone = Directory('${dir.path}/gone');

    await expectLater(clearSharedFiles(gone, kBackupExtension), completes);
  });
}
