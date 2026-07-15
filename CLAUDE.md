# Notes for Claude

Operating notes for AI sessions on this repo. Read this first.

## Behavior: don't get stuck in no-op watch loops

When monitoring a PR (self-scheduled check-ins via `send_later`, or PR-activity
subscriptions): if several consecutive check-ins return **no change** (same head
SHA, same `updated_at`, no new comments/CI), do **not** keep re-arming an hourly
poll indefinitely. It burns tokens and reconnect churn while learning nothing.

Instead:
- Recognize the idle state early (≈2–3 identical cycles) and surface it.
- Back off to a long interval or pause polling; the passive webhook subscription
  already wakes the session on real events, so proactive hourly polling is
  redundant once the PR is idle and waiting on a human.
- Stop watching the moment the PR is merged/closed: cancel any pending
  `send_later` trigger (`delete_trigger`) so it can't fire again.
- A merged/closed PR is terminal — do not reopen it or open a new PR for the
  same change unless the user explicitly asks.

## Build / verification (no toolchain preinstalled)

This is a Flutter app (GetX + Hive). The web/remote environment has **no Flutter
toolchain** by default. To actually verify Dart changes:

- Clone the SDK (git works; a plain web GET to github.com may 403 via the proxy —
  that's fine, use git): `git clone --depth 1 --branch stable --filter=blob:none
  https://github.com/flutter/flutter.git /tmp/flutter`
- `export PATH="/tmp/flutter/bin:$PATH"`, then `flutter --version` (bootstraps
  Dart), `flutter pub get`, `flutter analyze`.
- `flutter analyze` is the high-value check — always run it before pushing Dart
  changes. A full APK build additionally needs the Android SDK/NDK and compiles
  the bundled `llama.cpp` (very heavy) — not practical here and usually
  unnecessary to validate a Dart-only change.
- `flutter pub get` updates `pubspec.lock`; commit it when adding a dependency.

## Repo facts

- No CI workflows / `.github/` at time of writing — GitHub shows no status checks
  on PRs, so there's no CI to wait on.
- Architecture: `lib/` is GetX — `controllers/`, `services/` (GetxService,
  registered in `main.dart`), `views/`, `models/`, `core/` (routes, constants,
  theme). Settings persist via `HiveService` (`lib/services/hive_service.dart`).
- Home tabs live in `lib/views/home_view.dart` as an `IndexedStack`; tab order is
  index-sensitive, so adding/removing a tab means auditing hardcoded
  `changeTab(i)` calls elsewhere.
