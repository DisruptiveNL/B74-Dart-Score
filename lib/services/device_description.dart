import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What this device calls itself, for the other end of a transfer to read.
///
/// A sync packet and a backup both carry a label naming where they came from,
/// and "iPhone" or "Android" stopped being enough the moment two devices of the
/// same kind were involved. This reports whatever each platform will say about
/// itself, with the operating system after it in brackets.
///
/// What that amounts to differs by platform, and deliberately nothing here
/// papers over the difference. Android answers with the name from the device
/// settings when one is set, so it reads as a name. iOS answers with the model
/// identifier, "iPhone16,1", because the name the owner gave the device has
/// needed an entitlement Apple grants case by case since iOS 16. The identifier
/// is not pretty, but it is exact, unique per model and never goes out of date,
/// which a table of marketing names would every autumn.
///
/// Both halves are written by hand, in `DeviceDescriptionHandler.swift` and
/// `MainActivity.kt`, for the reason the document picker is: a package for this
/// would pull CocoaPods onto the iOS side, and the plus_plugins family that
/// covers it is already held back in `pubspec.yaml` over the Kotlin plugin.
class DeviceDescription {
  static const MethodChannel _channel = MethodChannel(
    'dartscore/device_description',
  );

  /// Resolved once and kept: nothing it reads changes while the app runs.
  static String? _cached;

  /// The label to put on anything leaving this device, for example
  /// "iPhone16,1 (iOS 18.5)" or "Niklas' S23 (Android 14)".
  ///
  /// Falls back to the platform's name alone if the channel cannot answer,
  /// which is what the label was before it carried anything else. Never throws:
  /// a transfer must not fail over what it is called.
  static Future<String> get label async {
    if (_cached != null) return _cached!;
    try {
      final info = await _channel.invokeMapMethod<String, String>('describe');
      final name = info?['name'];
      final os = info?['os'];
      if (name != null && name.isNotEmpty) {
        return _cached = os == null || os.isEmpty ? name : '$name ($os)';
      }
    } catch (_) {
      // Falls through to the plain name below.
    }
    return _cached ??= defaultTargetPlatform == TargetPlatform.iOS
        ? 'iPhone'
        : 'Android';
  }

  /// Fixes the label for a test, or clears it again with null.
  @visibleForTesting
  static void debugSetLabel(String? label) => _cached = label;
}
