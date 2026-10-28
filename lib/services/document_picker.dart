import 'package:flutter/services.dart';

/// The platform's own file picker, as a path.
///
/// Both halves are written by hand, in `DocumentPickerHandler.swift` and
/// `MainActivity.kt`, because the file picking packages all still require
/// CocoaPods on iOS and this project builds without it. That keeps the contract
/// to the one thing the backup restore needs.
class DocumentPicker {
  static const MethodChannel _channel = MethodChannel(
    'dartscore/document_picker',
  );

  /// Opens the document picker and returns a path this app can read, or null
  /// when the user backed out without choosing anything.
  ///
  /// The file is always a copy the app owns, on both platforms: on Android
  /// because the picker hands back a `content://` URI that no plain file read
  /// can open, on iOS because the picker imports rather than lending out a
  /// location that would have to stay claimed while it is read. The copy sits
  /// in a cache directory the system is free to clear, so it is meant to be
  /// used at once, not kept.
  static Future<String?> pickFile() =>
      _channel.invokeMethod<String>('pickFile');
}
