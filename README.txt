B74 C1B9d — RETAIN → REMOVE database patch (Dart Score only)

Copy lib/ and test/ into D:\b74dev\projects\B74-Dart-Score.
Run:
  flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
  flutter test --no-pub test/database/c1b9d_retain_to_remove_test.dart
  flutter test --no-pub --reporter compact

This patch changes the SQLite admin-intents schema to allow a NEW REMOVE grant after a COMPLETED RETAIN. It retains old audit intents and atomically upgrades the tombstone after removal. It is not the finished Dashboard workflow. DO NOT delete real official data yet.

Flutter is not available in the patch-building environment; tests have NOT been run here.
