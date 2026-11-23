# Config provider split + pub workspace

## Intent
Let apps use fl_updater without Firebase. Firebase Remote Config becomes one
config provider in its own package; a callback-based API provider ships in core.

## Goals
- Pub workspace at repo root: `packages/fl_updater` (core), `packages/fl_updater_firebase`, `example/`.
- Core contains: models, snooze, widgets, native code, `FlUpdaterConfigProvider` interface, `ApiConfigProvider`. No `firebase_*` dependency.
- `fl_updater_firebase` contains `FirebaseConfigProvider` (current Firebase logic + its tests).
- The `fl_updater_config` JSON schema stays the shared contract; `UpdateInfo.fromRemoteConfigJson` is untouched.

## Non-goals
- No built-in HTTP client, no polling/push for the API provider (checks on launch only).
- No behaviour change to version comparison, snooze, dialogs.

## Constraints
- Workspaces need Dart >=3.6 / Flutter >=3.47 (bump from 3.4 / 3.24).
- Breaking: `FlUpdater` and `FlUpdaterWrapper` require `provider:`; `RemoteConfigService` is renamed/reshaped (0.2.0, CHANGELOG entry).

## Approaches
1. **API provider = callback in core** (chosen): `ApiConfigProvider(fetch: () async => json)`; user brings Dio/http. Smallest; core stays dependency-light.
2. Separate `fl_updater_api` package with `http`: a third package for ~30 lines.
3. HTTP provider in core: adds `http` dep, contradicts "core only".

## Design
```dart
abstract class FlUpdaterConfigProvider {
  /// Fetch (and activate) latest config; returns raw fl_updater_config JSON.
  Future<String?> fetch({Duration minimumFetchInterval});
  /// Last known config without hitting the network.
  Future<String?> current();
  /// Push notifications of changes; null when unsupported.
  Stream<void>? get changes;
}
```
- `RemoteConfigService` → `UpdateService` in core: takes a provider, keeps the `enabled` gate, snooze, logging, error fallback; `checkForUpdate` uses `fetch`, `evaluateActiveConfig` uses `current`, `listenForUpdates` wraps `changes` (returns null if unsupported).
- `FirebaseConfigProvider({FirebaseRemoteConfig? remoteConfig})`: `fetch` = setConfigSettings + setDefaults + fetchAndActivate + getString; `changes` = onConfigUpdated filtered to `fl_updater_config`, activating before emitting.
- `ApiConfigProvider({required fetch})`: `fetch` calls the callback and caches; `current` returns the cache; `changes` is null. Fetch errors propagate to the service, which falls back to the last cached value then to `none`.
- Wrapper's `_realtimeSubscription` type becomes `StreamSubscription<void>?`; `listenForRealtimeUpdates` is a no-op for providers without `changes`.
- Tests: move the Firebase-specific ones to `fl_updater_firebase`; core tests use a fake provider; add a small `ApiConfigProvider` test.
- CI: `publish.yml` publishes each package from its directory (core first).

## Left to the builder
File/class naming details, example app wiring (Firebase provider by default, API provider sample in README), README split.
