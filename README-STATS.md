# B74 Stats — installable LOCAL staging patch (not final remote Stats release)

This replaces `lib/main.dart`, `lib/database/db_helper.dart` and adds two services.
It activates **local** periodic enqueueing of completed Singles 501 (including archived RETAIN records), but **does not send HTTP**.

Safety: REMOVE clears the local outbox transactionally; pending selection excludes REMOVE intents/tombstones; no code changes to Dashboard or Live TV.

Important: a central DELETE/RETAIN protocol and an in-flight HTTP race must be resolved before activating the HTTP sender. A successful local Flutter test does NOT prove production readiness.

Installation: back up or `git diff` first, extract ZIP at repo root, then run `dart format lib/main.dart lib/database/db_helper.dart lib/services/statistics_single_publish_coordinator.dart lib/services/statistics_single_publish_service.dart`, `flutter analyze`, `flutter test`, `git diff --check`.
Do not commit or push as a finished Stats release until server deletion is verified.
