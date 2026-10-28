import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/db_helper.dart';
import 'device_description.dart';
import 'device_identity.dart';
import 'document_picker.dart';
import 'incoming_file.dart'
    show clearSharedFiles, kBackupExtension, kBackupMimeType;

/// Why a file the user picked cannot be restored.
enum BackupRejection {
  /// Not a readable SQLite database, or not one of this app's.
  notABackup,

  /// Written by a newer app version, whose schema this build cannot read.
  tooNew,
}

/// Thrown by [BackupService.restore] when the picked file is refused. The
/// screen turns [reason] into a sentence; there is nothing to retry.
class BackupRejectedException implements Exception {
  final BackupRejection reason;
  const BackupRejectedException(this.reason);
}

/// Writing the local database out as a single file and reading one back in.
///
/// The backup is the SQLite file itself rather than a dump of it, which keeps
/// restoring exact and costs no second serialiser to maintain beside the
/// schema. Where the file then goes is the platform's business: the share sheet
/// offers iCloud Drive, Files, Drive, mail or anything else the user has, and
/// the document picker takes it back, so neither platform needs its own path
/// through this class and nothing has to be hosted anywhere.
///
/// This is deliberately not the sync in [sync_service.dart]. A sync merges two
/// devices and folds what it cannot carry into snapshots; a restore replaces
/// this device wholesale, including its identity.
class BackupService {
  /// Writes the current database to a temporary file and opens the share sheet
  /// on it. [sharePositionOrigin] anchors the popover on an iPad, where a sheet
  /// without an anchor fails instead of opening.
  ///
  /// Returns false when the user dismissed the sheet without choosing a target.
  static Future<bool> exportAndShare({Rect? sharePositionOrigin}) async {
    final source = await _prepare();
    final tmp = await getTemporaryDirectory();

    // Whatever an earlier share left. Cleared here rather than after the sheet
    // closes: a target may still be reading the file off its content URI then,
    // and a backup is the whole database, so leaving them to pile up costs
    // real space.
    await clearSharedFiles(tmp, kBackupExtension);

    final target = File('${tmp.path}/${backupFileName(DateTime.now())}');
    await File(source).copy(target.path);

    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(target.path, mimeType: kBackupMimeType)],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return result.status == ShareResultStatus.success;
  }

  /// Stamps the database with who is handing it over and when, and returns the
  /// path to read it from.
  static Future<String> _prepare() async => DbHelper.instance.prepareBackup(
    await DeviceIdentity.id,
    await DeviceDescription.label,
  );

  /// The database as bytes, ready to be handed to another device over the
  /// local network, together with what is in it.
  ///
  /// Same file the share sheet gets, checkpoint and markers included, only it
  /// never touches a temporary file on the way out. The summary comes back with
  /// it because the sending screen shows what it is about to give away, and
  /// reading it afterwards would describe a file that has already gone.
  static Future<(List<int>, BackupInfo)> exportBytes() async {
    final source = await _prepare();
    final info = await DbHelper.instance.describeLocal();
    return (await File(source).readAsBytes(), info);
  }

  /// Takes a database that arrived over the network and reports what it holds,
  /// exactly like [pick] does for a file the user chose.
  ///
  /// The bytes are written out before anything looks at them: reading a
  /// database means opening it, and opening it means having it somewhere.
  static Future<PickedBackup> acceptTransfer(List<int> bytes) async {
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}/incoming-backup.db');
    await file.writeAsBytes(bytes, flush: true);

    final info = await DbHelper.instance.inspectBackup(file.path);
    if (info == null) {
      await _discard(file.path);
      throw const BackupRejectedException(BackupRejection.notABackup);
    }
    if (info.schemaVersion > DbHelper.schemaVersion) {
      await _discard(file.path);
      throw const BackupRejectedException(BackupRejection.tooNew);
    }
    return PickedBackup(file.path, info);
  }

  /// Name a backup is offered under, dated so several of them stay apart in a
  /// cloud folder.
  ///
  /// The extension used to be a plain `.db`, because an invented one is a type
  /// the system knows nothing about and some share targets then refuse to take
  /// it. That reasoning held only while nothing declared the type. Both
  /// platforms now do, in `Info.plist` and in the manifest, conforming to
  /// `public.data`, so the system knows exactly what this is and hands it back
  /// to DartScore instead of leaving it in a download folder. What the file
  /// actually is still gets read out of it on the way in, never taken from its
  /// name.
  static String backupFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'dartscore-backup-${now.year}-${two(now.month)}-${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.$kBackupExtension';
  }

  /// Reads a backup the system handed this app and reports what it holds.
  ///
  /// The same two checks [pick] makes, on a file that arrived through AirDrop,
  /// mail or a share rather than through the picker. Nothing is replaced here:
  /// that waits for the confirmation, exactly as it does for a picked file.
  static Future<PickedBackup> open(String path) async {
    final info = await DbHelper.instance.inspectBackup(path);
    if (info == null) {
      await _discard(path);
      throw const BackupRejectedException(BackupRejection.notABackup);
    }
    if (info.schemaVersion > DbHelper.schemaVersion) {
      await _discard(path);
      throw const BackupRejectedException(BackupRejection.tooNew);
    }
    return PickedBackup(path, info);
  }

  /// Lets the user pick a backup and reports what it holds, without changing
  /// anything yet. Returns null when the picker was dismissed.
  ///
  /// Restoring is destructive, so it is split in two: this reads the file so
  /// the screen can show what is about to replace the current data, and
  /// [restore] carries it out once that has been confirmed.
  static Future<PickedBackup?> pick() async {
    final path = await DocumentPicker.pickFile();
    if (path == null) return null;

    // The picker offers every file rather than filtering by name, so what came
    // back is checked by what is in it. A name filter would be the weaker test
    // and, on iOS, one the system cannot always resolve to a type at all.
    return open(path);
  }

  /// Removes the copy the picker left behind. A backup is the whole database,
  /// so leaving one in the cache for the system to clear whenever it feels like
  /// it doubles what the app occupies for no reason.
  static Future<void> _discard(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Replaces the local database with [picked].
  ///
  /// This device keeps its own identity. When the backup came from a different
  /// device, the history in it is re-stamped as that device's on the way in,
  /// see [DbHelper.attributeRestoredHistory], which is what lets the two go on
  /// syncing afterwards.
  ///
  /// The caller has to reload every provider afterwards: the data behind them
  /// is not the data they were built from any more.
  static Future<void> restore(PickedBackup picked) async {
    final localId = await DeviceIdentity.id;
    await DbHelper.instance.replaceDatabase(picked.path);

    final source = picked.info.deviceId;
    if (source != null && source.isNotEmpty && source != localId) {
      await DbHelper.instance.attributeRestoredHistory(source);
    }
    await _discard(picked.path);
  }
}

/// A backup the user chose, read and accepted but not yet restored.
class PickedBackup {
  /// Where the picker put its copy. Valid until the restore is through or
  /// [discard] is called.
  final String path;
  final BackupInfo info;

  const PickedBackup(this.path, this.info);

  /// Throws the picked copy away again, for when the restore is called off.
  Future<void> discard() => BackupService._discard(path);
}
