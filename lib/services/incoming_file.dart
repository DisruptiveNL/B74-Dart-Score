import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'sync_codec.dart' show kSyncPrefixV1, kSyncPrefixV2;

// ── Sharing out ───────────────────────────────────────────────────────────────

/// Deletes what earlier shares of [extension] left in [directory].
///
/// A file handed to the share sheet has to stay readable until the target has
/// taken it, and there is no telling when that is: some copy while the sheet is
/// open, some later, off the content URI. So it is cleared on the way in rather
/// than on the way out. Nothing accumulates, and nothing is pulled out from
/// under a share still in progress.
///
/// It matters because a backup is the whole database. Sharing one a few times
/// used to leave a full copy behind each time, which is the same waste the
/// picker's own copies are deliberately spared.
Future<void> clearSharedFiles(Directory directory, String extension) async {
  try {
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.$extension')) continue;
      try {
        await entry.delete();
      } catch (_) {
        // In use, or already gone. Neither is worth failing a share over.
      }
    }
  } catch (_) {
    // An unreadable directory means there is nothing to clear.
  }
}

// ── File kinds ────────────────────────────────────────────────────────────────

/// Extension a whole database carries, so the system can hand one to this app.
///
/// Its own extension rather than a plain `.db`, and its own declared type
/// beside it on each platform. That is what makes a backup arriving by AirDrop,
/// mail, Files, Drive or Nearby Share open DartScore rather than sit in a
/// download folder waiting to be hunted down through the picker.
const String kBackupExtension = 'dartscore';

/// Extension a single player's synced history carries.
///
/// The one way two iPhones can exchange a profile without a network at all:
/// Apple lets no app raise one, so a file through the share sheet, and AirDrop
/// with it, is what is left. One direction only, like a QR code.
const String kSyncExtension = 'dartsync';

/// The type a shared database is announced under.
///
/// Set explicitly on the way out, because neither platform can work it out from
/// an extension it has never seen: Android would fall back to
/// `application/octet-stream`, which says nothing, and a receiver matching on
/// the type would never see this one at all.
const String kBackupMimeType = 'application/vnd.ratka.dartscore';

/// The type a shared profile is announced under. See [kBackupMimeType].
const String kSyncMimeType = 'application/vnd.ratka.dartsync';

/// What a file the system handed this app turned out to be.
enum IncomingFileKind {
  /// A whole database. Replaces this device.
  backup,

  /// One player's history. Merged into this device.
  profile,
}

/// A file another app handed to DartScore.
class IncomingFile {
  /// A copy in this app's cache, to be used at once and thrown away.
  final String path;

  final IncomingFileKind kind;

  const IncomingFile(this.path, this.kind);

  /// Works out what [path] holds, or null when it is neither kind.
  ///
  /// The name is only the first guess. A file arriving from another app often
  /// reaches this one with the sender's name stripped or replaced, so the first
  /// bytes decide when the name does not: a database opens with SQLite's own
  /// header, a profile with the codec's prefix.
  ///
  /// This picks which flow the file enters, never what is done with it. The two
  /// do opposite things, one merges and one replaces, so what is inside is
  /// checked again by the flow that took it, exactly as a file out of the
  /// picker has always been.
  static Future<IncomingFile?> classify(String path) async {
    final name = path.toLowerCase();
    if (name.endsWith('.$kBackupExtension')) {
      return IncomingFile(path, IncomingFileKind.backup);
    }
    if (name.endsWith('.$kSyncExtension')) {
      return IncomingFile(path, IncomingFileKind.profile);
    }

    final kind = await _sniff(path);
    return kind == null ? null : IncomingFile(path, kind);
  }

  /// The first bytes a database and a profile can be told apart by.
  static const String _kSqliteHeader = 'SQLite format 3';

  /// Reads just enough of [path] to say which kind it is, or null.
  static Future<IncomingFileKind?> _sniff(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      if (length == 0) return null;

      final head = await file.openRead(0, _kSqliteHeader.length).first;
      final text = latin1.decode(head, allowInvalid: true);

      if (text.startsWith(_kSqliteHeader)) return IncomingFileKind.backup;
      if (text.startsWith(kSyncPrefixV2) || text.startsWith(kSyncPrefixV1)) {
        return IncomingFileKind.profile;
      }
    } catch (_) {
      // Unreadable is the same as unrecognised.
    }
    return null;
  }
}

// ── Arrivals ──────────────────────────────────────────────────────────────────

/// Files the system opens this app with.
///
/// Two ways in, because the platforms have two: an app launched by a file has
/// one waiting before Dart is even running, and an app already open is handed
/// one as it happens. [initial] covers the first, [stream] the second.
///
/// The native halves are `IncomingFileHandler.swift` and `MainActivity.kt`,
/// hand-written like the document picker beside them and for the same reason.
class IncomingFiles {
  static const MethodChannel _channel = MethodChannel(
    'dartscore/incoming_file',
  );

  static final StreamController<IncomingFile> _opened =
      StreamController<IncomingFile>.broadcast();

  /// Names of files the system handed over that could not be read.
  ///
  /// Reported rather than swallowed. Without this the app simply opens on its
  /// home screen and the user is left to guess whether anything happened.
  static final StreamController<String> _failed =
      StreamController<String>.broadcast();

  static bool _listening = false;

  /// Files handed over while the app is running.
  static Stream<IncomingFile> get stream {
    _listen();
    return _opened.stream;
  }

  /// Names of files the system offered that could not be read.
  static Stream<String> get failures {
    _listen();
    return _failed.stream;
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      final argument = call.arguments;
      if (argument is! String) return;
      switch (call.method) {
        case 'opened':
          final file = await IncomingFile.classify(argument);
          if (file != null) {
            _opened.add(file);
          } else {
            // Readable, but neither kind. Worth the same word as unreadable:
            // something was handed over and nothing came of it.
            _failed.add(argument.split('/').last);
          }
        case 'failed':
          _failed.add(argument);
      }
    });
  }

  /// The file this app was launched with, if it was.
  ///
  /// Asked for rather than pushed, because the native side has it before there
  /// is any Dart to push it to. Answering clears it, so a file is offered once
  /// and not again on the next rebuild.
  static Future<IncomingFile?> initial() async {
    try {
      final path = await _channel.invokeMethod<String>('initial');
      return path == null ? null : await IncomingFile.classify(path);
    } catch (_) {
      return null;
    }
  }
}
