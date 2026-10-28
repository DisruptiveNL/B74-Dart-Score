import 'package:dartscore_app/utils/platform_notices.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The notices for the Android libraries the plugins pull in through Gradle.
///
/// Flutter writes its own `NOTICES` from the Dart graph only, so nothing else
/// in the build mentions these. Read through the stream rather than through
/// `registerPlatformNotices`, which asks the platform and would answer nothing
/// on the machine a test runs on.
void main() {
  late List<LicenseEntry> entries;

  setUp(() async {
    entries = await androidNativeLicenses().toList();
  });

  /// The one entry that carries [package], for the assertions below.
  LicenseEntry entryFor(String package) =>
      entries.firstWhere((e) => e.packages.contains(package));

  /// The whole text of [entry], paragraphs joined back together.
  String textOf(LicenseEntry entry) =>
      entry.paragraphs.map((p) => p.text).join('\n');

  test('names the Gradle artifact behind every entry', () {
    expect(
      textOf(entryFor('Google Play services (ML Kit barcode scanning)')),
      contains('play-services-mlkit-barcode-scanning'),
    );
    expect(
      textOf(entryFor('Google Play Billing Library')),
      contains('com.android.billingclient:billing'),
    );
    expect(textOf(entryFor('AndroidX')), contains('androidx.camera'));
    expect(textOf(entryFor('Kotlin')), contains('kotlinx-coroutines-android'));
  });

  test('carries the Apache license where it applies', () {
    // Section 4 of that license asks that a copy travel with the libraries it
    // covers, so a link in its place would not do.
    for (final package in ['AndroidX', 'Kotlin']) {
      final text = textOf(entryFor(package));
      expect(text, contains('Apache License'));
      expect(text, contains('END OF TERMS AND CONDITIONS'));
    }
  });

  test('points at the terms of the two Google libraries', () {
    expect(
      textOf(entryFor('Google Play services (ML Kit barcode scanning)')),
      contains('https://developers.google.com/ml-kit/terms'),
    );
    expect(
      textOf(entryFor('Google Play Billing Library')),
      contains('https://developer.android.com/studio/terms'),
    );
  });
}
