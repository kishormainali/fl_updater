# Config Provider Split + Pub Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split Firebase Remote Config into its own package and make core provider-agnostic, with a callback-based API provider in core.

**Architecture:** Repo root becomes a pub workspace. Core (`packages/fl_updater`) defines `FlUpdaterConfigProvider` and a Firebase-free `UpdateService` holding all policy. `packages/fl_updater_firebase` implements the provider over `firebase_remote_config`.

**Tech Stack:** Flutter plugin, Dart pub workspaces, mocktail, firebase_remote_config.

**Spec:** `docs/superpowers/specs/2026-11-23-config-provider-workspace-design.md`

## Global Constraints
- Environment: `sdk: ^3.6.0`, `flutter: '>=3.27.0'` in every pubspec (workspace members add `resolution: workspace`).
- Core has no `firebase_*` dependency and no HTTP dependency.
- `fl_updater_config` JSON schema and `UpdateInfo.fromRemoteConfigJson` are unchanged.
- Version `0.2.0` for both packages; CHANGELOG entry notes the breaking `provider:` requirement.
- Names: `FlUpdaterConfigProvider`, `UpdateService`, `FirebaseConfigProvider`, `ApiConfigProvider`.

## Review Focus
- API `fetch` throws and nothing cached → status `none`, no crash (Task 2).
- API `fetch` throws after an earlier success → last cached JSON is used (Task 2).
- Provider returns `null`/empty/malformed JSON → status `none` (Task 2).
- Provider with `changes == null` + `listenForRealtimeUpdates: true` → wrapper doesn't crash, no subscription (Task 3).
- Firebase update event for an unrelated key is ignored; empty `updatedKeys` triggers (Task 4).

---

### Task 1: Workspace skeleton (move core, keep tests green)

**Files:**
- Create: root `pubspec.yaml` (`name: fl_updater_workspace`, `publish_to: none`, `workspace: [packages/fl_updater, packages/fl_updater_firebase, example]`)
- Move (git mv): `lib android ios test pubspec.yaml README.md CHANGELOG.md LICENSE analysis_options.yaml .metadata .pubignore` → `packages/fl_updater/`
- Modify: `example/pubspec.yaml` (`resolution: workspace`, path `../packages/fl_updater`, SDK floors), moved core `pubspec.yaml` (SDK floors, `resolution: workspace`, version 0.2.0), `.github/workflows/publish.yml` (see Task 5)
- Create: `packages/fl_updater_firebase/pubspec.yaml` (empty-lib placeholder: `resolution: workspace`, deps `fl_updater: ^0.2.0`, `firebase_remote_config`, `lib/fl_updater_firebase.dart` with a `library;` line only)

**Interfaces:** Produces the layout all later tasks assume; no code changes.

- [ ] **Step 1:** Do the moves/pubspecs above; the Android/iOS native dirs move with core and the example's native projects stay in `example/`.
- [ ] **Step 2:** From the root run `flutter pub get`. Expected: resolves the three members with no errors.
- [ ] **Step 3:** Run `cd packages/fl_updater && flutter test`. Expected: all existing tests PASS (still Firebase-based at this point).
- [ ] **Step 4:** Commit `refactor: convert repo to pub workspace`.

### Task 2: Provider interface, `UpdateService`, `ApiConfigProvider` (core)

**Files:**
- Create: `packages/fl_updater/lib/src/providers/config_provider.dart`, `.../providers/api_config_provider.dart`
- Move/rename: `lib/src/services/remote_config_service.dart` → `lib/src/services/update_service.dart` (class `UpdateService`)
- Modify: `lib/fl_updater.dart` (exports), `pubspec.yaml` (remove `firebase_remote_config`)
- Test: `test/update_service_test.dart` (renamed from `remote_config_service_test.dart`, rewritten around a `FakeProvider`), `test/api_config_provider_test.dart`

**Interfaces:**
- Produces:
  ```dart
  abstract class FlUpdaterConfigProvider {
    Future<String?> fetch({Duration minimumFetchInterval = const Duration(hours: 1)});
    Future<String?> current();
    Stream<void>? get changes;
  }
  class ApiConfigProvider implements FlUpdaterConfigProvider {
    ApiConfigProvider({required Future<String> Function() fetch});
  }
  class UpdateService {
    UpdateService({required FlUpdaterConfigProvider provider, FlUpdaterSnoozeStore? snoozeStore, bool? enableLogging});
    Future<UpdateInfo> checkForUpdate({...same params as today...});
    Future<UpdateInfo> evaluateActiveConfig({...same...});
    StreamSubscription<void>? listenForUpdates(Future<void> Function() onConfigUpdated, {bool? enableLogging});
  }
  ```
- Export `FlUpdaterConfigProvider`, `ApiConfigProvider` from `fl_updater.dart`.

- [ ] **Step 1: Write failing tests** — `api_config_provider_test.dart`: `fetch` returns callback value and `current()` then returns it; `fetch` throwing with a prior success returns... (provider rethrows; `current()` still returns cached); `changes` is null. `update_service_test.dart`: port every existing case (enabled gate, soft/force/none, snooze, flavor/platform, logging, `evaluateActiveConfig`, `listenForUpdates`) with `FakeProvider`; add: provider `fetch` throws + `current()` returns cached JSON → uses cached; throws + `current()` null → `UpdateStatus.none`; `listenForUpdates` returns `null` when `changes == null`; `listenForUpdates` invokes callback per `changes` event.
- [ ] **Step 2:** Run `flutter test test/api_config_provider_test.dart test/update_service_test.dart`. Expected: FAIL (types undefined).
- [ ] **Step 3:** Implement. `UpdateService.checkForUpdate`: same flow as today's `RemoteConfigService`, but replace the Firebase try-block with `raw = await provider.fetch(minimumFetchInterval:)` caught into `raw = await provider.current()`. `evaluateActiveConfig` reads `provider.current()`. `listenForUpdates` returns `provider.changes?.listen(...)` (null when unsupported). `ApiConfigProvider` caches the last successful string; `fetch` assigns then returns, errors propagate.
- [ ] **Step 4:** Run the two test files. Expected: PASS.
- [ ] **Step 5:** Commit `feat: config provider interface, UpdateService, ApiConfigProvider`.

### Task 3: Wire provider into `FlUpdater` and `FlUpdaterWrapper`

**Files:**
- Modify: `lib/fl_updater.dart`, `lib/src/widgets/update_wrapper.dart`
- Test: `test/fl_updater_test.dart`, `test/update_wrapper_test.dart`, `test/logger_test.dart`

**Interfaces:**
- Consumes: `UpdateService`, `FlUpdaterConfigProvider` (Task 2).
- Produces: `FlUpdater({required FlUpdaterConfigProvider provider, FlUpdaterSnoozeStore? snoozeStore, bool? enableLogging, @visibleForTesting UpdateService? updateService})`; `FlUpdaterWrapper({..., required FlUpdaterConfigProvider provider, @visibleForTesting UpdateService? updateService})`; `listenForUpdates` returns `StreamSubscription<void>?`; wrapper `_realtimeSubscription` is `StreamSubscription<void>?`. Remove the `firebase_remote_config` import from the wrapper.

- [ ] **Step 1: Update tests** — mock `UpdateService` instead of `RemoteConfigService`; pass a `FakeProvider` where `provider:` is now required; add wrapper test: provider with `changes == null`, `listenForRealtimeUpdates: true` → pumps without error and `listenForUpdates` returns null.
- [ ] **Step 2:** Run `flutter test`. Expected: FAIL (constructor signatures).
- [ ] **Step 3:** Implement the signatures above; update doc comments that mention Firebase to be provider-neutral.
- [ ] **Step 4:** Run `flutter test` in core; `flutter analyze`. Expected: PASS, no issues; `grep -r firebase packages/fl_updater/lib packages/fl_updater/pubspec.yaml` returns nothing.
- [ ] **Step 5:** Commit `refactor: FlUpdater and wrapper take a config provider`.

### Task 4: `fl_updater_firebase` package

**Files:**
- Create: `packages/fl_updater_firebase/lib/fl_updater_firebase.dart` (exports), `.../lib/src/firebase_config_provider.dart`, `.../test/firebase_config_provider_test.dart`, `README.md`, `CHANGELOG.md`, `LICENSE`, `analysis_options.yaml`

**Interfaces:**
- Consumes: `FlUpdaterConfigProvider` (core).
- Produces: `FirebaseConfigProvider({FirebaseRemoteConfig? remoteConfig})` (instance resolved lazily, as today).

- [ ] **Step 1: Write failing tests** (port from the old `remote_config_service_test.dart` with `MockFirebaseRemoteConfig`): `fetch` calls `setConfigSettings` (fetchTimeout 1 min, given `minimumFetchInterval`), `setDefaults({'fl_updater_config': '{}'})`, `fetchAndActivate`, returns `getString('fl_updater_config')`; `current()` returns `getString` without fetching; `changes` emits after `activate()` when `updatedKeys` contains `fl_updater_config` **or is empty**, and does not emit for an unrelated key; `activate()` throwing still emits (logged, not fatal).
- [ ] **Step 2:** Run `cd packages/fl_updater_firebase && flutter test`. Expected: FAIL.
- [ ] **Step 3:** Implement by lifting the Firebase calls out of the old service; `changes` maps `onConfigUpdated` through an `asyncMap`/generator that filters, activates, then yields.
- [ ] **Step 4:** Run `flutter test`, `flutter analyze`. Expected: PASS.
- [ ] **Step 5:** Commit `feat: fl_updater_firebase provider package`.

### Task 5: Example, CI, docs

**Files:**
- Modify: `example/lib/main.dart` (Firebase provider; commented/README `ApiConfigProvider` sample), `example/pubspec.yaml` (add `fl_updater_firebase`), `.github/workflows/publish.yml`, `packages/fl_updater/README.md`, `packages/fl_updater/CHANGELOG.md`, `.gitignore` if needed

- [ ] **Step 1:** Pass `provider: FirebaseConfigProvider()` in the example's wrapper and `FlUpdater(...)`.
- [ ] **Step 2:** `publish.yml`: run `flutter pub get`, format check, `flutter analyze`, and `flutter test` per package (`for d in packages/*; do (cd $d && flutter test); done`); publish step runs `dart pub publish --force` in `packages/fl_updater` then `packages/fl_updater_firebase` (tag-triggered, core first).
- [ ] **Step 3:** README: new install matrix (core + firebase), API provider example (`ApiConfigProvider(fetch: () async => (await dio.get(url)).data)`), migration note; CHANGELOG 0.2.0 breaking entry.
- [ ] **Step 4:** Verify: `flutter pub get && flutter analyze` at root; `flutter test` in both packages; `cd example && flutter build apk --debug` (or `flutter analyze`). Expected: all green.
- [ ] **Step 5:** Commit `chore: example, CI and docs for workspace split`.
