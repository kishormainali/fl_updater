# fl_updater: App Upgrade Dialog — Design

**Date:** 2026-08-17
**Status:** Approved

## Problem

`fl_updater` is a Flutter plugin scaffold (`flutter create --template=plugin`) with almost no real implementation: the Dart public API is an empty class, the platform interface has two unimplemented method stubs, the Android/iOS native sides still handle the default `getPlatformVersion` template method, and `lib/src/models/remote_config.model.dart` is not valid Dart (constructor parameters written directly as the class body).

The goal is to turn this into a working plugin that:
1. Reads app-update configuration from Firebase Remote Config.
2. Decides whether an update is available, and whether it must be forced (blocking) or is optional (dismissible).
3. Automatically checks and shows a highly customizable dialog via a top-level wrapper widget, with an imperative API available for manual control.
4. Lets the user snooze optional (soft) updates for a configurable period.
5. On tap, opens the correct app store page for the current platform using native APIs (not a generic browser URL).

## Non-goals

- No custom exception hierarchy or retry/backoff logic for Remote Config fetch — fail open and log.
- No Remote-Config-driven dialog copy — copy is a Dart-side API concern.
- No `url_launcher` dependency — store opening is implemented directly via native platform channel code.
- No analytics/telemetry hooks in v1.
- No lifecycle-based (app-resume) rechecking in v1 — the wrapper checks once per cold start only.
- No cost/usage telemetry or budget enforcement — the plugin only exposes `minimumFetchInterval` and `enableInDebugMode` as levers; tracking actual Remote Config spend is out of scope.

## Architecture

1. **Remote Config service** (`lib/src/remote_config_service.dart`)
   Wraps `firebase_remote_config`: sets defaults, applies a `minimumFetchInterval` via `setConfigSettings` before calling `fetchAndActivate()`, reads the flat keys described below, and produces an `UpdateInfo`.

   Firebase has announced usage-based pricing for Remote Config taking effect 2026-09-01, i.e. fetches will factor into cost, not just be free/unlimited as before. Since `FlUpdaterWrapper` already checks only once per cold start (no polling), the main remaining lever is the SDK's own fetch cache: `fetchAndActivate()` serves cached values instead of hitting the network when called again within `minimumFetchInterval`. The service sets this explicitly — default `Duration(hours: 12)`, matching the Firebase SDK's own default — instead of leaving it implicit, and exposes it as a parameter (`FlUpdater`/`FlUpdaterWrapper`) so a host app can widen it (e.g. `Duration(days: 1)`) to further cut fetch volume, or narrow it if they need faster propagation and accept the cost.

   The bigger source of avoidable fetches is development itself: every hot restart during debugging is a cold start, and a `FlUpdaterWrapper` sitting in `MaterialApp.builder` would otherwise fetch on every single one. So `checkForUpdate()` skips the fetch entirely — returning `UpdateStatus.none` immediately, no network call — whenever `kDebugMode` is true, unless the caller explicitly opts back in via `enableInDebugMode: true`. This also means the update dialog never pops up unannounced while developing, which would otherwise be surprising and annoying.

2. **Version comparison** (`lib/src/version_comparator.dart`)
   Uses `package_info_plus` to get the installed version, and compares it against `latest_version` / `min_version` from Remote Config using semantic-version rules. Produces an `UpdateStatus` enum: `none`, `soft` (update available, dismissible), `force` (installed version is below `min_version`, blocking).

3. **Snooze store** (`lib/src/snooze_store.dart`)
   Backed by `shared_preferences`. Lets a soft update be snoozed for a configurable duration, per-version.

   ```dart
   class FlUpdaterSnoozeStore {
     Future<void> snooze(String version, Duration duration);
     Future<bool> isSnoozed(String version);
     Future<void> clear();
   }
   ```

   Persists `fl_updater_snoozed_version` (string) and `fl_updater_snoozed_until` (epoch millis). `isSnoozed(version)` is `true` only if the stored version matches the version being checked **and** `DateTime.now()` is before the stored timestamp. A newer `latest_version` therefore automatically invalidates a prior snooze — the dialog reappears immediately for the new version even mid-snooze.

   `checkForUpdate()` takes an optional `snoozeDuration` (default `Duration(days: 3)`). If `status == soft` and `isSnoozed(latestVersion)` is true, `checkForUpdate()` downgrades the returned status to `none`. **Force updates always ignore snooze** — they are never downgraded.

4. **Dialog widget** (`lib/src/update_dialog.dart`)
   Built-in adaptive `AlertDialog`, `FlUpdaterDialog`.
   - Force mode: `PopScope(canPop: false)`, `barrierDismissible: false`, no "Later" button — only path forward is tapping "Update".
   - Soft mode: adds a "Later" button. Tapping it calls `FlUpdaterSnoozeStore.snooze(latestVersion, snoozeDuration)` and then dismisses.
   - Fully customizable at two levels:
     - **Style params** for the built-in dialog: `FlUpdaterDialogStyle` (`backgroundColor`, `titleStyle`, `messageStyle`, `shape`, `icon`, `updateButtonStyle`, `laterButtonStyle`, `barrierColor`), plus `title`/`message`/`updateButtonText`/`laterButtonText` strings — all optional with sensible English defaults.
     - **Full builder override**: `typedef FlUpdaterDialogBuilder = Widget Function(BuildContext context, UpdateInfo info, VoidCallback onUpdate, VoidCallback onLater)`. When supplied, this replaces `FlUpdaterDialog` entirely; `onUpdate`/`onLater` already carry the correct store-launch / snooze-and-dismiss behavior, so a fully custom widget still behaves correctly.

5. **Wrapper widget** (`lib/src/update_wrapper.dart`)
   `FlUpdaterWrapper`, a `StatefulWidget` meant to be used inside `MaterialApp.builder`:

   ```dart
   MaterialApp(
     builder: (context, child) => FlUpdaterWrapper(child: child!),
     home: ...,
   )
   ```

   ```dart
   class FlUpdaterWrapper extends StatefulWidget {
     final Widget child;
     final String? iosAppId;
     final String? androidPackageId;
     final FlUpdaterDialogBuilder? dialogBuilder;
     final String? title;
     final String? message;
     final String? updateButtonText;
     final String? laterButtonText;
     final FlUpdaterDialogStyle? style;
     final Duration snoozeDuration;
     final Duration minimumFetchInterval;
     final bool enableInDebugMode;
   }
   ```

   `iosAppId`/`androidPackageId` are plain Dart-side configuration passed by the host app — not Remote Config values (see schema below) — so they're available synchronously without waiting on a fetch.

   - Placed via `MaterialApp.builder` so it always has a `BuildContext` under a `Navigator` to call `showDialog()` with.
   - `initState()` triggers `checkForUpdate()` exactly once (no `WidgetsBindingObserver`, no resume-recheck). When the result is `soft` or `force`, the dialog is shown via a post-frame callback (`WidgetsBinding.instance.addPostFrameCallback`) so it never tries to show mid-build.
   - Built on top of the imperative API below — it is a convenience layer, not a separate code path.

6. **Store launcher** (platform channel — replaces the current `openAppStore` / `openGooglePlayStore` stubs)
   - Android (Kotlin): opens `market://details?id=<package>` via an explicit `Intent` targeting the Play Store app; if that fails (`ActivityNotFoundException`, Play Store app not installed), falls back to `https://play.google.com/store/apps/details?id=<package>` via `ACTION_VIEW`.
   - iOS (Swift): opens `itms-apps://itunes.apple.com/app/id<appId>` via `UIApplication.shared.open(...)`; if `canOpenURL` returns false, falls back to `https://apps.apple.com/app/id<appId>`.
   - `androidPackageId` defaults to the host app's own package name (read on-device) when not passed by the host app; `iosAppId` has no on-device fallback and must be passed by the host app or the store won't open.

## Public Dart API

Replaces the empty `FlUpdater` class in `lib/fl_updater.dart`. Both the wrapper and this imperative API are supported; the wrapper is built on top of it.

```dart
class FlUpdater {
  Future<UpdateInfo> checkForUpdate({
    Duration snoozeDuration = const Duration(days: 3),
    Duration minimumFetchInterval = const Duration(hours: 12),
    bool enableInDebugMode = false,
    String? iosAppId,
    String? androidPackageId,
  });

  Future<void> showUpdateDialog(
    BuildContext context, {
    UpdateInfo? info, // if omitted, calls checkForUpdate() internally
    String? iosAppId,
    String? androidPackageId,
    FlUpdaterDialogBuilder? dialogBuilder,
    String? title,
    String? message,
    String? updateButtonText,
    String? laterButtonText,
    FlUpdaterDialogStyle? style,
    Duration snoozeDuration = const Duration(days: 3),
    Duration minimumFetchInterval = const Duration(hours: 12),
    bool enableInDebugMode = false,
  });
}
```

`UpdateInfo` (replacing/fixing `lib/src/models/remote_config.model.dart`, renamed `lib/src/models/update_info.model.dart`):

```dart
enum UpdateStatus { none, soft, force }

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final UpdateStatus status;
  final String? iosAppId;
  final String? androidPackageId;

  const UpdateInfo({...});

  // iosAppId/androidPackageId come from the caller (FlUpdater /
  // FlUpdaterWrapper), not from `values` — see Remote Config schema below.
  factory UpdateInfo.fromRemoteConfigValues({
    required Map<String, String> values,
    required String currentVersion,
    String? iosAppId,
    String? androidPackageId,
  });

  @override
  int get hashCode => ...;
  @override
  bool operator ==(Object other) => ...;
  @override
  String toString() => ...;
}
```

## Remote Config schema (flat keys)

- `fl_updater_latest_version` (string, e.g. `"2.3.0"`)
- `fl_updater_min_version` (string) — installed version below this ⇒ `UpdateStatus.force`

Both keys have safe defaults (`fl_updater_min_version` defaults to `"0.0.0"`, i.e. force update never triggers unless explicitly configured) so an app that hasn't configured Remote Config yet never breaks.

**`iosAppId` / `androidPackageId` are not Remote Config values.** They're static per-app identifiers (an App Store id, an optional package-name override) that don't need a dashboard toggle, so they're passed as plain Dart parameters on `FlUpdaterWrapper` / `FlUpdater.checkForUpdate` / `FlUpdater.showUpdateDialog` instead — one less network round-trip in the way of them being available, and one less thing to misconfigure in the Firebase console.

## Error handling

`checkForUpdate()` wraps the Remote Config fetch in try/catch:
- On failure (network error, Remote Config misconfigured), logs via `debugPrint` and returns an `UpdateInfo` with `status: UpdateStatus.none`. The plugin fails open — a Remote Config outage must never block a user from using the app.
- No custom exception type in v1; this may change if consumers need to distinguish "no update" from "check failed."

## Testing

- **Unit tests** (`test/`):
  - `VersionComparator`: equal versions, patch/minor/major differences, malformed version strings, boundary at exactly `min_version`.
  - `UpdateInfo`: parsing from raw Remote Config value maps (`fl_updater_latest_version`/`fl_updater_min_version` only), passthrough of caller-supplied `iosAppId`/`androidPackageId`, `==`/`hashCode` contract.
  - `FlUpdaterSnoozeStore`: snooze then immediately re-check (still snoozed), snooze then simulate elapsed time (no longer snoozed), snooze one version then check a newer version (not snoozed), using mocked `shared_preferences`.
  - `MethodChannelFlUpdater`: mocked `MethodChannel` verifying correct method names/arguments are sent for store-opening calls (existing pattern in the scaffold's `test/` dir).
- **Manual verification** in `example/`:
  - Android emulator: trigger soft and force update states, confirm dialog behavior (dismissible vs. blocked, back button behavior), confirm "Later" snoozes and the dialog doesn't reappear on next launch until the snooze expires, and that tapping "Update" opens the Play Store app (or browser fallback).
  - iOS simulator: same, confirming App Store app opens (or Safari fallback).
  - Confirm a debug build (`flutter run` without `--release`/`--profile`) shows no dialog and makes no Remote Config fetch by default, and that passing `enableInDebugMode: true` restores the normal debug-mode fetch behavior.

## Files touched

- `lib/fl_updater.dart` — implement public API
- `lib/src/fl_updater_platform_interface.dart` — already has `openAppStore`/`openGooglePlayStore`; may adjust signatures to pass package/app id
- `lib/src/fl_updater_method_channel.dart` — already wired; verify method names match native side
- `lib/src/remote_config_service.dart` — new
- `lib/src/version_comparator.dart` — new
- `lib/src/snooze_store.dart` — new
- `lib/src/update_dialog.dart` — new (`FlUpdaterDialog`, `FlUpdaterDialogStyle`, `FlUpdaterDialogBuilder` typedef)
- `lib/src/update_wrapper.dart` — new (`FlUpdaterWrapper`)
- `lib/src/models/update_info.model.dart` — replaces broken `remote_config.model.dart`
- `android/src/main/kotlin/com/kishormainali/fl_updater/FlUpdaterPlugin.kt` — implement store-opening intents
- `ios/fl_updater/Sources/fl_updater/FlUpdaterPlugin.swift` — implement store-opening URL handling
- `pubspec.yaml` — add `package_info_plus` and `shared_preferences` dependencies (already has `firebase_remote_config`)
- `example/lib/main.dart` — demo usage of both the wrapper and the imperative API
- `test/` — unit tests as described above
