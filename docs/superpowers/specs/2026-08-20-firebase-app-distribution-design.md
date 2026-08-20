# Firebase App Distribution support — design spec

## Motivation

`fl_updater` currently checks for updates via Firebase Remote Config and redirects
users to the App Store / Play Store. That flow only makes sense for a build that
is actually distributed through those stores. Teams also want in-app "a new build
is available" prompts for **pre-release builds distributed via Firebase App
Distribution** (internal testers, QA, staging builds) — a build source with its
own release metadata, its own tester-authentication model, and, critically, its
own installation mechanics per platform.

## Goals

- Let a `fl_updater` consumer check whether a newer Firebase App Distribution
  release exists for the current tester/build, and see its version and release
  notes.
- On Android, let the consumer trigger Firebase's own download-and-install flow
  for that release, with progress observation.
- On iOS, let the consumer trigger Firebase's hand-off to Safari for installing
  that release (the only mechanism iOS permits — no silent install is possible).
- Do this **without** putting any app that never uses this feature at risk of
  Google Play policy violations (see "Play policy constraint" below) — the
  default, unconfigured state of the plugin must be exactly as safe as it is
  today.

## Non-goals

- No integration with `RemoteConfigService`, `UpdateInfo`, or the
  `fl_updater_config` JSON schema. App Distribution is a separate update source
  with a separate data model and separate UI conventions (Firebase's own
  dialogs on Android; a hand-off to Safari on iOS) — mixing it into the
  version-comparison/snooze/dialog machinery built for Remote Config would
  conflate two different problems.
- No automatic channel selection (e.g. "flavor X always uses App Distribution").
  The calling app decides explicitly when to call these APIs — typically only
  from code paths that never ship to a store.
- No handling of the *build-time* upload workflow (`appDistributionUpload`
  Gradle task, `firebase appdistribution:distribute` CLI, CI wiring to push new
  builds to App Distribution). This spec is tester-side (checking for and
  installing a release) only.
- No custom Flutter-side "new release available" dialog is required by this
  feature — v1 exposes data and actions; a caller can build their own UI, or
  (on Android, when the full SDK is present) rely on Firebase's own built-in
  confirmation/progress UI from `updateApp()`.

## Play policy constraint (why this shapes the whole design)

Per Firebase's own documentation: bundling the **full** `firebase-appdistribution`
Android SDK into a build submitted to Google Play — even if the app never calls
its APIs at runtime — "may be considered a violation of Google Play policy...
Submitting your app to Google Play without removing the SDK may result in your
app being removed from Google Play."

This means `fl_updater`'s Android plugin must **never** unconditionally depend on
the full SDK, because that dependency would be compiled into every consuming
app's production/Play Store build regardless of whether that app ever touches
App Distribution. The lightweight, always-safe artifact
(`firebase-appdistribution-api`) does not carry this warning and provides
`checkForNewRelease()` — check-only, no download/install UI.

iOS has no equivalent split: there is only one pod (`FirebaseAppDistribution`),
and since it can never install silently (always hands off to Safari via a URL
the user must confirm), there's no analogous "bundled dormant self-update code"
risk documented for it. It's added directly, no opt-in gating.

## Architecture

```
FlUpdaterAppDistribution (new public Dart class, lib/fl_updater.dart export)
        │
        ▼
AppDistributionPlatform interface additions (fl_updater_platform_interface.dart)
        │
        ▼
MethodChannelFlUpdater additions (fl_updater_method_channel.dart)
        │
   ┌────┴─────┐
   ▼          ▼
Android    iOS
(Kotlin)   (Swift)
```

- **Android** (`FlUpdaterPlugin.kt`):
  - `implementation("com.google.firebase:firebase-appdistribution-api:<version>")`
    added to the plugin's `android/build.gradle.kts` — unconditional, safe in
    every build. Powers `checkForNewRelease()` and tester sign-in status.
  - `compileOnly("com.google.firebase:firebase-appdistribution:<version>")`
    added alongside it, so the plugin can compile against the full SDK's types
    without embedding its bytecode. At runtime, the plugin looks up
    `com.google.firebase.appdistribution.FirebaseAppDistribution`'s full-SDK-only
    members (`updateApp`, `updateIfNewReleaseAvailable`, the progress listener
    surface) via reflection.
  - If the full SDK class/method isn't resolvable at runtime (because the
    consuming app didn't add the real `firebase-appdistribution` runtime
    dependency to their own `build.gradle` for that variant), the plugin
    resolves `downloadAndInstall()` with a typed "unavailable" outcome instead
    of throwing a raw reflection exception.
  - The consuming app is responsible for adding
    `<variant>Implementation("com.google.firebase:firebase-appdistribution:<version>")`
    themselves, scoped to whichever build variant they use for internal/QA
    builds — documented clearly in the README, mirroring Firebase's own
    guidance for regular (non-plugin) Android apps.

- **iOS** (`FlUpdaterPlugin.swift` / `fl_updater.podspec`):
  - `FirebaseAppDistribution` pod added directly (no split).
  - Wraps `AppDistribution.appDistribution().checkForUpdate { release, error in
    ... }`.
  - "Install" is implemented as `UIApplication.shared.open(release.downloadURL)`
    — opens Safari, which drives the actual OTA install; the plugin cannot and
    does not attempt anything beyond that hand-off.

## Public Dart API

New file `lib/src/services/app_distribution_service.dart` wraps the platform
calls; a new public class is exported from `lib/fl_updater.dart`:

```dart
class FlUpdaterAppDistribution {
  FlUpdaterAppDistribution({bool? enableLogging});

  /// Checks Firebase App Distribution for a newer release than the one
  /// currently installed. Safe to call in any build (uses the lightweight
  /// API-only SDK on Android; the only SDK on iOS).
  ///
  /// Returns `null` if there is no newer release, the tester isn't signed in
  /// (see [isTesterSignedIn]/[signInTester]), or the check fails.
  Future<AppDistributionRelease?> checkForNewRelease();

  /// Downloads and prompts to install [release] (or re-checks if omitted).
  ///
  /// - Android: requires the consuming app to have added the full
  ///   `firebase-appdistribution` SDK themselves (see README). If absent,
  ///   completes with [AppDistributionUpdateResult.unavailable] rather than
  ///   throwing. When present, delegates to Firebase's own download +
  ///   install-confirmation UI; [onProgress] surfaces download progress.
  /// - iOS: opens Safari to the release's install URL. Completion reflects
  ///   only whether the hand-off succeeded, not whether the tester completed
  ///   installation (iOS has no way to observe that).
  Future<AppDistributionUpdateResult> downloadAndInstall({
    AppDistributionRelease? release,
    void Function(AppDistributionUpdateProgress progress)? onProgress,
  });

  /// Whether the current user is signed in as an App Distribution tester.
  /// Meaningful on both platforms; required before [checkForNewRelease] can
  /// succeed.
  Future<bool> isTesterSignedIn();

  /// Prompts Google/Firebase sign-in for App Distribution tester access.
  /// Android: shows Firebase's own sign-in UI. iOS: same, via the SDK's
  /// built-in flow.
  Future<void> signInTester();
}
```

### Models (`lib/src/models/app_distribution_release.model.dart`)

```dart
class AppDistributionRelease {
  final String displayVersion;   // e.g. "1.2.0"
  final String buildVersion;     // e.g. "42" (Android versionCode / iOS buildVersion)
  final String? releaseNotes;
}

enum AppDistributionUpdateStatus { pending, downloading, downloaded, installing, failed }

class AppDistributionUpdateProgress {
  final int bytesDownloaded;
  final int totalBytes;
  final AppDistributionUpdateStatus status;
}

enum AppDistributionUpdateResult {
  /// Install flow was successfully started/handed off.
  started,

  /// Android only: the full SDK isn't present in this build — the consuming
  /// app hasn't added `firebase-appdistribution` for this variant.
  unavailable,

  /// The call failed (network, not signed in, no release, etc.) — paired
  /// with a thrown [AppDistributionException] carrying details, not just
  /// this enum value alone. (Exact error-signaling shape — enum vs.
  /// exception vs. both — to be finalized in the implementation plan.)
  failed,
}
```

*(Exact field names/types for `AppDistributionRelease` are drawn from the iOS
SDK's confirmed `displayVersion`/`buildVersion`/`downloadURL`, mirrored onto
Android's equivalent `AppDistributionRelease` object. Android's precise field
names should be confirmed against the SDK's actual class during
implementation — Firebase's rendered API reference didn't fully load via
automated fetch during this design session.)*

## Platform-interface additions

`FlUpdaterPlatform` (and `MethodChannelFlUpdater`) gain:

```dart
Future<Map<String, dynamic>?> checkForNewAppDistributionRelease();
Future<String> downloadAndInstallAppDistributionUpdate({
  Map<String, dynamic>? release,
});
Future<bool> isAppDistributionTesterSignedIn();
Future<void> signInAppDistributionTester();
```

Progress during `downloadAndInstall` streams back via an `EventChannel`
(`com.kishormainali.fl_updater/app_distribution_progress`) rather than
threading progress through the method-call result, matching how long-running
progress-reporting operations are conventionally bridged in Flutter plugins.
`FlUpdaterAppDistribution.downloadAndInstall`'s public `onProgress` callback
is implemented by subscribing to this event stream for the duration of the
call and forwarding each event — callers never see the `EventChannel` itself.

## Error handling

| Condition | Behavior |
|---|---|
| Full Android SDK absent at runtime | `downloadAndInstall()` resolves `AppDistributionUpdateResult.unavailable` — no exception, no crash. |
| Tester not signed in | `checkForNewRelease()` returns `null`; a dedicated flag/exception distinguishes "not signed in" from "no new release" so the app can prompt `signInTester()` specifically rather than silently doing nothing. Exact shape (sentinel value vs. exception type) finalized during planning. |
| iOS `checkForUpdate` / Safari hand-off fails | Surfaced via `FlutterError` → a thrown Dart exception, consistent with how `openStore` already surfaces native failures today. |
| Network / generic failure | Same — thrown exception, not a silent `null`, so callers can distinguish "no update" from "couldn't check." |

## Testing

- **Dart-side** (`test/app_distribution_service_test.dart`): mock
  `FlUpdaterPlatform` the same way `test/fl_updater_test.dart` and
  `test/update_wrapper_test.dart` already mock `RemoteConfigService` — cover
  release-found / no-release / not-signed-in / unavailable / error paths for
  `FlUpdaterAppDistribution`, with no real platform channel involved.
- **Native code** (Gradle reflection bridge, podspec wiring): not unit-testable
  within this repo's existing Dart test suite. Verified manually via the
  example app, the same way `openStore`'s Play Core / StoreKit integration is
  today — this spec does not introduce native-side automated tests where none
  existed before.

## Documentation updates

- New README section: "Firebase App Distribution (pre-release builds)" —
  covering the Android Gradle opt-in step (with the exact policy warning
  reproduced, so consumers understand *why* it's opt-in), the iOS pod
  addition, and example usage of `FlUpdaterAppDistribution`.
- Example app: a debug-only screen or button demonstrating
  `checkForNewRelease()` / `downloadAndInstall()`, gated so it's obviously not
  wired into the app's production update path.
- CHANGELOG entry once implemented.

## Open items to verify during implementation

These don't block the design but must be pinned down against the actual SDKs
before/while implementing, since Firebase's rendered API reference pages
didn't fully load via automated fetch during this design session:

1. Exact `AppDistributionRelease` field names on **Android** (assumed to
   parallel iOS's `displayVersion`/`buildVersion`, but not directly confirmed).
2. Whether the Android full SDK requires any `AndroidManifest.xml` permission
   (e.g. `REQUEST_INSTALL_PACKAGES`) declared by the *consuming app*, or
   whether the SDK's own manifest merge handles it.
3. Current stable version numbers for both
   `firebase-appdistribution-api`/`firebase-appdistribution` (Android) and
   `FirebaseAppDistribution` (iOS pod) to pin in the plugin's dependency
   declarations.
4. Exact reflection call shape for `updateApp()`'s progress listener on
   Android (listener interface name, callback method signature) needed to
   bridge it cleanly to Dart via the `EventChannel`.
