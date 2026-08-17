# fl_updater App Upgrade Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the `fl_updater` scaffold into a working Flutter plugin that reads app-update config from Firebase Remote Config, decides soft/force update status by semantic version comparison, shows a highly customizable dialog (via an automatic top-level wrapper or an imperative API), lets soft updates be snoozed, and opens the correct native app-store page.

**Architecture:** Six Dart layers under `lib/src/`: pure version comparison, a model, a `shared_preferences`-backed snooze store, a Remote Config service, a customizable dialog widget, and a shared dialog-presentation helper used by both the imperative `FlUpdater` API and the automatic `FlUpdaterWrapper` widget. Native Android (Kotlin) and iOS (Swift) implementations open the platform's store app directly via URI scheme, falling back to a web URL.

**Tech Stack:** Flutter 3.47 / Dart 3.13, `firebase_remote_config`, `package_info_plus`, `shared_preferences`, `plugin_platform_interface`, `flutter_test`.

**Spec:** [docs/superpowers/specs/2026-08-17-app-upgrade-dialog-design.md](../specs/2026-08-17-app-upgrade-dialog-design.md)

## Global Constraints

- No `url_launcher` dependency — store opening goes through the platform channel only.
- Remote Config keys are exactly: `fl_updater_latest_version`, `fl_updater_min_version`. Nothing else lives in Remote Config.
- `fl_updater_min_version` defaults to `"0.0.0"` when unset (force update never triggers unless explicitly configured).
- `iosAppId`/`androidPackageId` are **not** Remote Config values — they're explicit Dart parameters on `FlUpdaterWrapper`, `FlUpdater.checkForUpdate`, and `FlUpdater.showUpdateDialog`, threaded through to `RemoteConfigService.checkForUpdate` and from there into `UpdateInfo`.
- Default `snoozeDuration` is `Duration(days: 3)`, configurable per call.
- Force updates (`UpdateStatus.force`) always ignore snooze and are never dismissible (no barrier dismiss, no back button via `PopScope(canPop: false)`).
- `checkForUpdate()` fails open: any Remote Config fetch error returns `UpdateStatus.none`, logged via `debugPrint`, never thrown to the caller.
- No analytics/telemetry hooks.
- No lifecycle-based (app-resume) rechecking — `FlUpdaterWrapper` checks exactly once per cold start.
- Default `minimumFetchInterval` is `Duration(hours: 12)` (matches the Firebase SDK's own default), set explicitly via `setConfigSettings` before every `fetchAndActivate()` — Remote Config's usage-based pricing (effective 2026-09-01) makes fetch volume a real cost, not just a nice-to-have to minimize.
- `checkForUpdate()` skips the fetch entirely under `kDebugMode` (returns `UpdateStatus.none`, no platform channel touched) unless `enableInDebugMode: true` is passed — avoids a fetch (and a surprise dialog) on every debug hot restart.
- Android store URI: `market://details?id=<package>`, fallback `https://play.google.com/store/apps/details?id=<package>`.
- iOS store URI: `itms-apps://itunes.apple.com/app/id<appId>`, fallback `https://apps.apple.com/app/id<appId>`.
- Method channel name (must match across Dart/Android/iOS): `com.kishormainali.fl_updater`.

**Design note beyond the spec's literal file list:** to avoid a circular import between `lib/fl_updater.dart` (which must `export 'src/update_wrapper.dart'`) and `lib/src/update_wrapper.dart` (which needs the dialog-showing logic), the dialog-presentation logic is factored into a new shared file `lib/src/dialog_presenter.dart`, used by both `FlUpdater.showUpdateDialog` and `FlUpdaterWrapper`. This keeps the two entry points behaviorally identical without one importing the other.

---

### Task 1: Version comparison

**Files:**
- Create: `lib/src/models/update_status.dart`
- Create: `lib/src/version_comparator.dart`
- Test: `test/version_comparator_test.dart`

**Interfaces:**
- Produces: `enum UpdateStatus { none, soft, force }`; `class VersionComparator { static UpdateStatus compare({required String currentVersion, required String latestVersion, required String minVersion}) }`

- [ ] **Step 1: Write the failing test**

```dart
// test/version_comparator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/src/models/update_status.dart';
import 'package:fl_updater/src/version_comparator.dart';

void main() {
  group('VersionComparator.compare', () {
    test('returns none when current equals latest', () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0',
        latestVersion: '1.0.0',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.none);
    });

    test('returns soft when a newer version is available', () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.soft);
    });

    test('returns soft (not force) when current equals min', () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        minVersion: '1.0.0',
      );
      expect(status, UpdateStatus.soft);
    });

    test('returns force when current is below min', () {
      final status = VersionComparator.compare(
        currentVersion: '0.9.0',
        latestVersion: '1.1.0',
        minVersion: '1.0.0',
      );
      expect(status, UpdateStatus.force);
    });

    test('treats missing version segments as zero', () {
      final status = VersionComparator.compare(
        currentVersion: '1.2',
        latestVersion: '1.2.0',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.none);
    });

    test('treats a malformed current version as very old (soft, not force)', () {
      final status = VersionComparator.compare(
        currentVersion: 'not-a-version',
        latestVersion: '1.0.0',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.soft);
    });

    test('treats a malformed latest version as not newer', () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0',
        latestVersion: 'not-a-version',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.none);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/version_comparator_test.dart`
Expected: FAIL — `lib/src/version_comparator.dart` and `lib/src/models/update_status.dart` don't exist yet.

- [ ] **Step 3: Create the enum**

```dart
// lib/src/models/update_status.dart
enum UpdateStatus { none, soft, force }
```

- [ ] **Step 4: Create the comparator**

```dart
// lib/src/version_comparator.dart
import 'models/update_status.dart';

class VersionComparator {
  const VersionComparator._();

  static UpdateStatus compare({
    required String currentVersion,
    required String latestVersion,
    required String minVersion,
  }) {
    if (_isLower(currentVersion, minVersion)) {
      return UpdateStatus.force;
    }
    if (_isLower(currentVersion, latestVersion)) {
      return UpdateStatus.soft;
    }
    return UpdateStatus.none;
  }

  static bool _isLower(String a, String b) {
    final partsA = _parse(a);
    final partsB = _parse(b);
    final length = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < length; i++) {
      final valueA = i < partsA.length ? partsA[i] : 0;
      final valueB = i < partsB.length ? partsB[i] : 0;
      if (valueA != valueB) return valueA < valueB;
    }
    return false;
  }

  static List<int> _parse(String version) {
    return version.split('.').map((segment) => int.tryParse(segment) ?? 0).toList();
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/version_comparator_test.dart`
Expected: PASS (7/7)

- [ ] **Step 6: Commit**

```bash
git add lib/src/models/update_status.dart lib/src/version_comparator.dart test/version_comparator_test.dart
git commit -m "feat: add version comparator and update status enum"
```

---

### Task 2: UpdateInfo model

**Files:**
- Create: `lib/src/models/update_info.model.dart`
- Delete: `lib/src/models/remote_config.model.dart` (invalid Dart syntax, superseded by `UpdateInfo`)
- Test: `test/models/update_info_test.dart`

**Interfaces:**
- Consumes: `UpdateStatus` and `VersionComparator.compare(...)` from Task 1.
- Produces: `class UpdateInfo { currentVersion, latestVersion, status, iosAppId, androidPackageId; UpdateInfo.fromRemoteConfigValues({required Map<String,String> values, required String currentVersion, String? iosAppId, String? androidPackageId}); UpdateInfo copyWith({UpdateStatus? status}); }`. Note: `values` only ever contains `fl_updater_latest_version`/`fl_updater_min_version` — `iosAppId`/`androidPackageId` are passed straight through by the caller, not parsed out of `values`.

- [ ] **Step 1: Write the failing test**

```dart
// test/models/update_info_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/src/models/update_info.model.dart';
import 'package:fl_updater/src/models/update_status.dart';

void main() {
  group('UpdateInfo.fromRemoteConfigValues', () {
    test('returns status none when current equals latest', () {
      final info = UpdateInfo.fromRemoteConfigValues(
        values: const {
          'fl_updater_latest_version': '1.0.0',
          'fl_updater_min_version': '0.0.0',
        },
        currentVersion: '1.0.0',
      );

      expect(info.status, UpdateStatus.none);
      expect(info.latestVersion, '1.0.0');
    });

    test('returns status soft when a newer version is available', () {
      final info = UpdateInfo.fromRemoteConfigValues(
        values: const {
          'fl_updater_latest_version': '1.2.0',
          'fl_updater_min_version': '0.0.0',
        },
        currentVersion: '1.0.0',
      );

      expect(info.status, UpdateStatus.soft);
    });

    test('returns status force when current is below min version', () {
      final info = UpdateInfo.fromRemoteConfigValues(
        values: const {
          'fl_updater_latest_version': '2.0.0',
          'fl_updater_min_version': '1.5.0',
        },
        currentVersion: '1.0.0',
      );

      expect(info.status, UpdateStatus.force);
    });

    test('falls back to currentVersion and 0.0.0 when keys are missing', () {
      final info = UpdateInfo.fromRemoteConfigValues(
        values: const {},
        currentVersion: '1.0.0',
      );

      expect(info.latestVersion, '1.0.0');
      expect(info.status, UpdateStatus.none);
    });

    test('passes through caller-supplied iosAppId and androidPackageId as-is', () {
      final info = UpdateInfo.fromRemoteConfigValues(
        values: const {'fl_updater_latest_version': '1.0.0'},
        currentVersion: '1.0.0',
        iosAppId: '123456789',
        androidPackageId: 'com.example.app',
      );

      expect(info.iosAppId, '123456789');
      expect(info.androidPackageId, 'com.example.app');
    });

    test('iosAppId and androidPackageId default to null when omitted', () {
      final info = UpdateInfo.fromRemoteConfigValues(
        values: const {'fl_updater_latest_version': '1.0.0'},
        currentVersion: '1.0.0',
      );

      expect(info.iosAppId, isNull);
      expect(info.androidPackageId, isNull);
    });

    test('treats caller-supplied empty string ids as null', () {
      final info = UpdateInfo.fromRemoteConfigValues(
        values: const {'fl_updater_latest_version': '1.0.0'},
        currentVersion: '1.0.0',
        iosAppId: '',
        androidPackageId: '',
      );

      expect(info.iosAppId, isNull);
      expect(info.androidPackageId, isNull);
    });
  });

  group('UpdateInfo equality', () {
    test('two instances with the same fields are equal', () {
      const a = UpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        status: UpdateStatus.soft,
      );
      const b = UpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        status: UpdateStatus.soft,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith overrides only the given field', () {
      const a = UpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        status: UpdateStatus.soft,
      );

      final copy = a.copyWith(status: UpdateStatus.none);

      expect(copy.status, UpdateStatus.none);
      expect(copy.currentVersion, a.currentVersion);
      expect(copy.latestVersion, a.latestVersion);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/update_info_test.dart`
Expected: FAIL — `lib/src/models/update_info.model.dart` doesn't exist yet.

- [ ] **Step 3: Delete the broken model file**

```bash
rm lib/src/models/remote_config.model.dart
```

- [ ] **Step 4: Create the model**

```dart
// lib/src/models/update_info.model.dart
import 'update_status.dart';
import '../version_comparator.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.status,
    this.iosAppId,
    this.androidPackageId,
  });

  factory UpdateInfo.fromRemoteConfigValues({
    required Map<String, String> values,
    required String currentVersion,
    String? iosAppId,
    String? androidPackageId,
  }) {
    final rawLatest = values['fl_updater_latest_version'];
    final latestVersion = (rawLatest != null && rawLatest.isNotEmpty) ? rawLatest : currentVersion;

    final rawMin = values['fl_updater_min_version'];
    final minVersion = (rawMin != null && rawMin.isNotEmpty) ? rawMin : '0.0.0';

    final status = VersionComparator.compare(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      minVersion: minVersion,
    );

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      status: status,
      iosAppId: (iosAppId == null || iosAppId.isEmpty) ? null : iosAppId,
      androidPackageId: (androidPackageId == null || androidPackageId.isEmpty) ? null : androidPackageId,
    );
  }

  final String currentVersion;
  final String latestVersion;
  final UpdateStatus status;
  final String? iosAppId;
  final String? androidPackageId;

  UpdateInfo copyWith({UpdateStatus? status}) {
    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      status: status ?? this.status,
      iosAppId: iosAppId,
      androidPackageId: androidPackageId,
    );
  }

  @override
  int get hashCode => Object.hash(currentVersion, latestVersion, status, iosAppId, androidPackageId);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateInfo &&
        other.currentVersion == currentVersion &&
        other.latestVersion == latestVersion &&
        other.status == status &&
        other.iosAppId == iosAppId &&
        other.androidPackageId == androidPackageId;
  }

  @override
  String toString() {
    return 'UpdateInfo(currentVersion: $currentVersion, latestVersion: $latestVersion, '
        'status: $status, iosAppId: $iosAppId, androidPackageId: $androidPackageId)';
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/models/update_info_test.dart`
Expected: PASS (9/9)

- [ ] **Step 6: Commit**

```bash
git add lib/src/models/update_info.model.dart test/models/update_info_test.dart
git rm lib/src/models/remote_config.model.dart
git commit -m "feat: replace broken remote_config model with UpdateInfo"
```

---

### Task 3: Snooze store

**Files:**
- Modify: `pubspec.yaml` (adds `shared_preferences`)
- Create: `lib/src/snooze_store.dart`
- Test: `test/snooze_store_test.dart`

**Interfaces:**
- Produces: `class FlUpdaterSnoozeStore { Future<void> snooze(String version, Duration duration); Future<bool> isSnoozed(String version); Future<void> clear(); }`

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add shared_preferences`
Expected: `pubspec.yaml` gains a `shared_preferences: ^x.y.z` line and `pubspec.lock` updates.

- [ ] **Step 2: Write the failing test**

```dart
// test/snooze_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_updater/src/snooze_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('isSnoozed is false when nothing has been snoozed', () async {
    final store = FlUpdaterSnoozeStore();
    expect(await store.isSnoozed('1.0.0'), isFalse);
  });

  test('isSnoozed is true for the snoozed version within the duration', () async {
    final store = FlUpdaterSnoozeStore();
    await store.snooze('1.2.0', const Duration(days: 3));

    expect(await store.isSnoozed('1.2.0'), isTrue);
  });

  test('isSnoozed is false for a different version', () async {
    final store = FlUpdaterSnoozeStore();
    await store.snooze('1.2.0', const Duration(days: 3));

    expect(await store.isSnoozed('1.3.0'), isFalse);
  });

  test('isSnoozed is false once the duration has elapsed', () async {
    final store = FlUpdaterSnoozeStore();
    await store.snooze('1.2.0', const Duration(seconds: -1));

    expect(await store.isSnoozed('1.2.0'), isFalse);
  });

  test('clear removes the snoozed state', () async {
    final store = FlUpdaterSnoozeStore();
    await store.snooze('1.2.0', const Duration(days: 3));
    await store.clear();

    expect(await store.isSnoozed('1.2.0'), isFalse);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/snooze_store_test.dart`
Expected: FAIL — `lib/src/snooze_store.dart` doesn't exist yet.

- [ ] **Step 4: Create the snooze store**

```dart
// lib/src/snooze_store.dart
import 'package:shared_preferences/shared_preferences.dart';

class FlUpdaterSnoozeStore {
  static const _versionKey = 'fl_updater_snoozed_version';
  static const _untilKey = 'fl_updater_snoozed_until';

  Future<void> snooze(String version, Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    await prefs.setString(_versionKey, version);
    await prefs.setInt(_untilKey, until);
  }

  Future<bool> isSnoozed(String version) async {
    final prefs = await SharedPreferences.getInstance();
    final snoozedVersion = prefs.getString(_versionKey);
    final until = prefs.getInt(_untilKey);
    if (snoozedVersion == null || until == null) return false;
    if (snoozedVersion != version) return false;
    return DateTime.now().millisecondsSinceEpoch < until;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_versionKey);
    await prefs.remove(_untilKey);
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/snooze_store_test.dart`
Expected: PASS (5/5)

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/src/snooze_store.dart test/snooze_store_test.dart
git commit -m "feat: add shared_preferences-backed snooze store"
```

---

### Task 4: Platform interface and method channel — `openStore`

**Files:**
- Modify: `lib/src/fl_updater_platform_interface.dart` (rewrite; replaces `openAppStore`/`openGooglePlayStore` stubs)
- Modify: `lib/src/fl_updater_method_channel.dart` (rewrite)
- Test: `test/fl_updater_method_channel_test.dart` (rewrite; old file tests a nonexistent `getPlatformVersion` method)

**Interfaces:**
- Produces: `abstract class FlUpdaterPlatform { static FlUpdaterPlatform instance; Future<void> openStore({String? iosAppId, String? androidPackageId}); }`; `class MethodChannelFlUpdater extends FlUpdaterPlatform` sending method `'openStore'` on channel `'com.kishormainali.fl_updater'` with arguments `{'iosAppId': ..., 'androidPackageId': ...}`.

- [ ] **Step 1: Write the failing test**

```dart
// test/fl_updater_method_channel_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/src/fl_updater_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelFlUpdater();
  const channel = MethodChannel('com.kishormainali.fl_updater');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      calls.add(methodCall);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('openStore forwards iosAppId and androidPackageId', () async {
    await platform.openStore(iosAppId: '123456789', androidPackageId: 'com.example.app');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'openStore');
    expect(calls.single.arguments, {
      'iosAppId': '123456789',
      'androidPackageId': 'com.example.app',
    });
  });

  test('openStore forwards null arguments when omitted', () async {
    await platform.openStore();

    expect(calls.single.arguments, {'iosAppId': null, 'androidPackageId': null});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/fl_updater_method_channel_test.dart`
Expected: FAIL — `openStore` doesn't exist on `MethodChannelFlUpdater` yet (and the channel name doesn't match).

- [ ] **Step 3: Rewrite the platform interface**

```dart
// lib/src/fl_updater_platform_interface.dart
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'fl_updater_method_channel.dart';

abstract class FlUpdaterPlatform extends PlatformInterface {
  FlUpdaterPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlUpdaterPlatform _instance = MethodChannelFlUpdater();

  static FlUpdaterPlatform get instance => _instance;

  static set instance(FlUpdaterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Opens the platform's app store page. On Android, [androidPackageId]
  /// defaults to the host app's own package name when omitted. On iOS,
  /// [iosAppId] must be provided — there is no on-device way to discover it.
  Future<void> openStore({String? iosAppId, String? androidPackageId}) {
    throw UnimplementedError('openStore() has not been implemented.');
  }
}
```

- [ ] **Step 4: Rewrite the method channel implementation**

```dart
// lib/src/fl_updater_method_channel.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fl_updater_platform_interface.dart';

class MethodChannelFlUpdater extends FlUpdaterPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('com.kishormainali.fl_updater');

  @override
  Future<void> openStore({String? iosAppId, String? androidPackageId}) {
    return methodChannel.invokeMethod<void>('openStore', {
      'iosAppId': iosAppId,
      'androidPackageId': androidPackageId,
    });
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/fl_updater_method_channel_test.dart`
Expected: PASS (2/2)

- [ ] **Step 6: Commit**

```bash
git add lib/src/fl_updater_platform_interface.dart lib/src/fl_updater_method_channel.dart test/fl_updater_method_channel_test.dart
git commit -m "feat: replace store stubs with unified openStore method channel"
```

---

### Task 5: Android native store launcher

**Files:**
- Modify: `android/src/main/kotlin/com/kishormainali/fl_updater/FlUpdaterPlugin.kt` (rewrite)
- Delete: `android/src/test/kotlin/com/kishormainali/fl_updater/FlUpdaterPluginTest.kt` (tests the removed `getPlatformVersion` behavior)

**Interfaces:**
- Consumes: method channel `com.kishormainali.fl_updater`, method `openStore` with args `androidPackageId` (nullable String) from Task 4.

**Decision:** No automated Android unit test is added — testing `openStore` correctly requires mocking `Context`/`PackageManager` for an `Intent`-launch, which the spec's testing section does not call for. Correctness is verified manually by running the example app on an Android emulator (Task 12).

- [ ] **Step 1: Rewrite the plugin**

```kotlin
// android/src/main/kotlin/com/kishormainali/fl_updater/FlUpdaterPlugin.kt
package com.kishormainali.fl_updater

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FlUpdaterPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.kishormainali.fl_updater")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        if (call.method == "openStore") {
            val packageId = call.argument<String>("androidPackageId")?.takeIf { it.isNotEmpty() }
                ?: context.packageName
            openStore(packageId)
            result.success(null)
        } else {
            result.notImplemented()
        }
    }

    private fun openStore(packageId: String) {
        try {
            val marketIntent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageId"))
            marketIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(marketIntent)
        } catch (e: ActivityNotFoundException) {
            val webIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$packageId"),
            )
            webIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(webIntent)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
```

- [ ] **Step 2: Delete the stale native test**

```bash
rm android/src/test/kotlin/com/kishormainali/fl_updater/FlUpdaterPluginTest.kt
```

- [ ] **Step 3: Commit**

```bash
git add android/src/main/kotlin/com/kishormainali/fl_updater/FlUpdaterPlugin.kt
git rm android/src/test/kotlin/com/kishormainali/fl_updater/FlUpdaterPluginTest.kt
git commit -m "feat: implement Android store-opening via market intent"
```

---

### Task 6: iOS native store launcher

**Files:**
- Modify: `ios/fl_updater/Sources/fl_updater/FlUpdaterPlugin.swift` (rewrite)

**Interfaces:**
- Consumes: method channel `com.kishormainali.fl_updater`, method `openStore` with args `iosAppId` (nullable String) from Task 4.

**Bug fix:** the existing file registers its channel as `"fl_updater"`, which does not match the Dart side's `"com.kishormainali.fl_updater"` — this rewrite fixes that mismatch.

**Decision:** No automated iOS unit test is added (same rationale as Task 5). Verified manually on an iOS simulator (Task 12).

- [ ] **Step 1: Rewrite the plugin**

```swift
// ios/fl_updater/Sources/fl_updater/FlUpdaterPlugin.swift
import Flutter
import UIKit

public class FlUpdaterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.kishormainali.fl_updater", binaryMessenger: registrar.messenger())
    let instance = FlUpdaterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "openStore":
      let args = call.arguments as? [String: Any]
      let iosAppId = args?["iosAppId"] as? String
      openStore(appId: iosAppId, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openStore(appId: String?, result: @escaping FlutterResult) {
    guard let appId = appId, !appId.isEmpty else {
      result(FlutterError(code: "MISSING_APP_ID", message: "iosAppId is required to open the App Store", details: nil))
      return
    }

    guard let storeUrl = URL(string: "itms-apps://itunes.apple.com/app/id\(appId)") else {
      result(FlutterError(code: "INVALID_URL", message: "Could not build store URL", details: nil))
      return
    }

    if UIApplication.shared.canOpenURL(storeUrl) {
      UIApplication.shared.open(storeUrl, options: [:]) { _ in result(nil) }
    } else if let webUrl = URL(string: "https://apps.apple.com/app/id\(appId)") {
      UIApplication.shared.open(webUrl, options: [:]) { _ in result(nil) }
    } else {
      result(FlutterError(code: "CANNOT_OPEN", message: "Could not open App Store", details: nil))
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add ios/fl_updater/Sources/fl_updater/FlUpdaterPlugin.swift
git commit -m "feat: implement iOS store-opening and fix channel name mismatch"
```

---

### Task 7: Remote Config service

**Files:**
- Modify: `pubspec.yaml` (adds `package_info_plus`)
- Create: `lib/src/remote_config_service.dart`
- Test: `test/remote_config_service_test.dart`

**Interfaces:**
- Consumes: `UpdateInfo.fromRemoteConfigValues` (Task 2), `UpdateInfo.copyWith` (Task 2), `FlUpdaterSnoozeStore` (Task 3).
- Produces: `class RemoteConfigService { RemoteConfigService({FirebaseRemoteConfig? remoteConfig, FlUpdaterSnoozeStore? snoozeStore}); Future<UpdateInfo> checkForUpdate({Duration snoozeDuration = const Duration(days: 3), Duration minimumFetchInterval = const Duration(hours: 12), bool enableInDebugMode = false, String? iosAppId, String? androidPackageId}); }`

**Decision:** The debug-mode gate (Step 1–4 below) is genuinely unit-testable and gets a real TDD test. The rest of `checkForUpdate` — the actual `FirebaseRemoteConfig.instance` fetch path — is not: it requires heavy platform-channel mocking to fake, matching the spec's testing section, which lists unit tests only for `VersionComparator`, `UpdateInfo`, the snooze store, and the method channel. That path is verified via `flutter analyze` and manually in the example app (Task 12).

**Pricing note:** Remote Config is moving to usage-based pricing on 2026-09-01, so fetches now have a cost dimension. `setConfigSettings` is called with an explicit `minimumFetchInterval` before every `fetchAndActivate()` — the Firebase SDK serves cached values instead of a network fetch when called again inside that window, so this is a real lever for controlling fetch volume, not just documentation. Default matches the Firebase SDK's own default (12 hours); callers can widen it via `FlUpdater`/`FlUpdaterWrapper` to cut volume further.

**Debug-mode note:** every hot restart during development is a cold start, so an unguarded `FlUpdaterWrapper` would fetch (and could pop a dialog) on each one. `checkForUpdate` checks `kDebugMode` **before touching any platform channel** (`PackageInfo.fromPlatform()` or `FirebaseRemoteConfig`) and short-circuits to `UpdateStatus.none` unless `enableInDebugMode: true` is passed. `FirebaseRemoteConfig.instance` is also resolved lazily (a getter, not in the constructor initializer list) so constructing a `RemoteConfigService()` never touches Firebase until a check actually needs it — this is also what makes the debug-gate test below able to run without any Firebase test setup: `flutter test` runs in JIT/debug mode, so `kDebugMode` is `true` there, and the gate returns before any platform channel is touched.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add package_info_plus`
Expected: `pubspec.yaml` gains a `package_info_plus: ^x.y.z` line.

- [ ] **Step 2: Write the failing test for the debug-mode gate**

```dart
// test/remote_config_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/src/models/update_status.dart';
import 'package:fl_updater/src/remote_config_service.dart';

void main() {
  // flutter test runs in JIT/debug mode, so kDebugMode is true here —
  // these tests exercise the default (fetch-disabled) debug behavior
  // without needing any Firebase or package_info_plus test setup.
  test('checkForUpdate skips the fetch and returns none in debug mode by default', () async {
    final service = RemoteConfigService();

    final info = await service.checkForUpdate();

    expect(info.status, UpdateStatus.none);
  });

  test('checkForUpdate passes iosAppId/androidPackageId through even when gated', () async {
    final service = RemoteConfigService();

    final info = await service.checkForUpdate(
      iosAppId: '123',
      androidPackageId: 'com.example.app',
    );

    expect(info.iosAppId, '123');
    expect(info.androidPackageId, 'com.example.app');
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/remote_config_service_test.dart`
Expected: FAIL — `lib/src/remote_config_service.dart` doesn't exist yet.

- [ ] **Step 4: Create the service**

```dart
// lib/src/remote_config_service.dart
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'models/update_info.model.dart';
import 'models/update_status.dart';
import 'snooze_store.dart';

class RemoteConfigService {
  RemoteConfigService({FirebaseRemoteConfig? remoteConfig, FlUpdaterSnoozeStore? snoozeStore})
      : _providedRemoteConfig = remoteConfig,
        _snoozeStore = snoozeStore ?? FlUpdaterSnoozeStore();

  // Resolved lazily via the getter below so constructing a RemoteConfigService
  // never touches FirebaseRemoteConfig.instance until a check actually needs
  // it — that's what keeps the debug-mode-gated tests above free of any
  // Firebase test setup.
  final FirebaseRemoteConfig? _providedRemoteConfig;
  final FlUpdaterSnoozeStore _snoozeStore;

  FirebaseRemoteConfig get _remoteConfig => _providedRemoteConfig ?? FirebaseRemoteConfig.instance;

  static const _keys = [
    'fl_updater_latest_version',
    'fl_updater_min_version',
  ];

  Future<UpdateInfo> checkForUpdate({
    Duration snoozeDuration = const Duration(days: 3),
    Duration minimumFetchInterval = const Duration(hours: 12),
    bool enableInDebugMode = false,
    String? iosAppId,
    String? androidPackageId,
  }) async {
    if (kDebugMode && !enableInDebugMode) {
      return UpdateInfo(
        currentVersion: '',
        latestVersion: '',
        status: UpdateStatus.none,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    try {
      await _remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(minutes: 1),
          minimumFetchInterval: minimumFetchInterval,
        ),
      );
      await _remoteConfig.setDefaults({for (final key in _keys) key: ''});
      await _remoteConfig.fetchAndActivate();

      final values = {for (final key in _keys) key: _remoteConfig.getString(key)};

      var info = UpdateInfo.fromRemoteConfigValues(
        values: values,
        currentVersion: currentVersion,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );

      if (info.status == UpdateStatus.soft && await _snoozeStore.isSnoozed(info.latestVersion)) {
        info = info.copyWith(status: UpdateStatus.none);
      }

      return info;
    } catch (error, stackTrace) {
      debugPrint('fl_updater: failed to fetch remote config: $error\n$stackTrace');
      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        status: UpdateStatus.none,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );
    }
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/remote_config_service_test.dart`
Expected: PASS (2/2)

- [ ] **Step 6: Verify the whole file compiles cleanly**

Run: `flutter analyze lib/src/remote_config_service.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/src/remote_config_service.dart test/remote_config_service_test.dart
git commit -m "feat: add Remote Config service with debug-mode gating and fail-open error handling"
```

---

### Task 8: Customizable dialog widget

**Files:**
- Create: `lib/src/update_dialog.dart`
- Test: `test/update_dialog_test.dart`

**Interfaces:**
- Consumes: `UpdateInfo`, `UpdateStatus` (Task 2).
- Produces: `typedef FlUpdaterDialogBuilder = Widget Function(BuildContext, UpdateInfo, VoidCallback onUpdate, VoidCallback onLater)`; `class FlUpdaterDialogStyle { backgroundColor, titleStyle, messageStyle, shape, icon, updateButtonStyle, laterButtonStyle, barrierColor }`; `class FlUpdaterDialog extends StatelessWidget { info, onUpdate, onLater, title, message, updateButtonText, laterButtonText, style }`. Button widget keys: `Key('fl_updater_update_button')`, `Key('fl_updater_later_button')`.

- [ ] **Step 1: Write the failing test**

```dart
// test/update_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/src/models/update_info.model.dart';
import 'package:fl_updater/src/models/update_status.dart';
import 'package:fl_updater/src/update_dialog.dart';

void main() {
  const softInfo = UpdateInfo(
    currentVersion: '1.0.0',
    latestVersion: '1.1.0',
    status: UpdateStatus.soft,
  );

  const forceInfo = UpdateInfo(
    currentVersion: '1.0.0',
    latestVersion: '2.0.0',
    status: UpdateStatus.force,
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    required UpdateInfo info,
    required VoidCallback onUpdate,
    required VoidCallback onLater,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FlUpdaterDialog(
              info: info,
              onUpdate: onUpdate,
              onLater: onLater,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('soft update shows Later button and calls callbacks', (tester) async {
    var updateTapped = false;
    var laterTapped = false;

    await pumpDialog(
      tester,
      info: softInfo,
      onUpdate: () => updateTapped = true,
      onLater: () => laterTapped = true,
    );

    expect(find.byKey(const Key('fl_updater_later_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('fl_updater_later_button')));
    await tester.pump();
    expect(laterTapped, isTrue);

    await tester.tap(find.byKey(const Key('fl_updater_update_button')));
    await tester.pump();
    expect(updateTapped, isTrue);
  });

  testWidgets('force update hides Later button', (tester) async {
    await pumpDialog(
      tester,
      info: forceInfo,
      onUpdate: () {},
      onLater: () {},
    );

    expect(find.byKey(const Key('fl_updater_later_button')), findsNothing);
    expect(find.byKey(const Key('fl_updater_update_button')), findsOneWidget);
  });

  testWidgets('custom title, message and button text are used', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FlUpdaterDialog(
              info: softInfo,
              onUpdate: () {},
              onLater: () {},
              title: 'Custom title',
              message: 'Custom message',
              updateButtonText: 'Go',
              laterButtonText: 'Nope',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Custom title'), findsOneWidget);
    expect(find.text('Custom message'), findsOneWidget);
    expect(find.text('Go'), findsOneWidget);
    expect(find.text('Nope'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/update_dialog_test.dart`
Expected: FAIL — `lib/src/update_dialog.dart` doesn't exist yet.

- [ ] **Step 3: Create the dialog**

```dart
// lib/src/update_dialog.dart
import 'package:flutter/material.dart';

import 'models/update_info.model.dart';
import 'models/update_status.dart';

typedef FlUpdaterDialogBuilder = Widget Function(
  BuildContext context,
  UpdateInfo info,
  VoidCallback onUpdate,
  VoidCallback onLater,
);

class FlUpdaterDialogStyle {
  const FlUpdaterDialogStyle({
    this.backgroundColor,
    this.titleStyle,
    this.messageStyle,
    this.shape,
    this.icon,
    this.updateButtonStyle,
    this.laterButtonStyle,
    this.barrierColor,
  });

  final Color? backgroundColor;
  final TextStyle? titleStyle;
  final TextStyle? messageStyle;
  final ShapeBorder? shape;
  final Widget? icon;
  final ButtonStyle? updateButtonStyle;
  final ButtonStyle? laterButtonStyle;
  final Color? barrierColor;
}

class FlUpdaterDialog extends StatelessWidget {
  const FlUpdaterDialog({
    super.key,
    required this.info,
    required this.onUpdate,
    required this.onLater,
    this.title,
    this.message,
    this.updateButtonText,
    this.laterButtonText,
    this.style,
  });

  final UpdateInfo info;
  final VoidCallback onUpdate;
  final VoidCallback onLater;
  final String? title;
  final String? message;
  final String? updateButtonText;
  final String? laterButtonText;
  final FlUpdaterDialogStyle? style;

  bool get _isForce => info.status == UpdateStatus.force;

  @override
  Widget build(BuildContext context) {
    final dialog = AlertDialog(
      backgroundColor: style?.backgroundColor,
      shape: style?.shape,
      icon: style?.icon,
      title: Text(title ?? 'Update available', style: style?.titleStyle),
      content: Text(
        message ??
            (_isForce
                ? 'A required update is available. Please update to continue using the app.'
                : 'A new version (${info.latestVersion}) is available.'),
        style: style?.messageStyle,
      ),
      actions: [
        if (!_isForce)
          TextButton(
            key: const Key('fl_updater_later_button'),
            style: style?.laterButtonStyle,
            onPressed: onLater,
            child: Text(laterButtonText ?? 'Later'),
          ),
        FilledButton(
          key: const Key('fl_updater_update_button'),
          style: style?.updateButtonStyle,
          onPressed: onUpdate,
          child: Text(updateButtonText ?? 'Update'),
        ),
      ],
    );

    if (_isForce) {
      return PopScope(canPop: false, child: dialog);
    }
    return dialog;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/update_dialog_test.dart`
Expected: PASS (3/3)

- [ ] **Step 5: Commit**

```bash
git add lib/src/update_dialog.dart test/update_dialog_test.dart
git commit -m "feat: add customizable FlUpdaterDialog widget"
```

---

### Task 9: Shared dialog-presentation helper

**Files:**
- Create: `lib/src/dialog_presenter.dart`

**Interfaces:**
- Consumes: `FlUpdaterPlatform.instance.openStore(...)` (Task 4), `FlUpdaterSnoozeStore` (Task 3), `UpdateInfo`/`UpdateStatus` (Task 2), `FlUpdaterDialog`/`FlUpdaterDialogBuilder`/`FlUpdaterDialogStyle` (Task 8).
- Produces: `Future<void> presentUpdateDialog(BuildContext context, {required UpdateInfo info, required FlUpdaterSnoozeStore snoozeStore, required Duration snoozeDuration, FlUpdaterDialogBuilder? dialogBuilder, String? title, String? message, String? updateButtonText, String? laterButtonText, FlUpdaterDialogStyle? style})`. Used by both `FlUpdater.showUpdateDialog` (Task 10) and `FlUpdaterWrapper` (Task 11) so their dialog behavior is identical without one importing the other (see Global Constraints).

**Decision:** No dedicated test file — this function's behavior (dialog shown/not shown, Update/Later callback wiring) is exercised end-to-end by Task 10's widget tests through `FlUpdater.showUpdateDialog`.

- [ ] **Step 1: Create the helper**

```dart
// lib/src/dialog_presenter.dart
import 'package:flutter/material.dart';

import 'fl_updater_platform_interface.dart';
import 'models/update_info.model.dart';
import 'models/update_status.dart';
import 'snooze_store.dart';
import 'update_dialog.dart';

Future<void> presentUpdateDialog(
  BuildContext context, {
  required UpdateInfo info,
  required FlUpdaterSnoozeStore snoozeStore,
  required Duration snoozeDuration,
  FlUpdaterDialogBuilder? dialogBuilder,
  String? title,
  String? message,
  String? updateButtonText,
  String? laterButtonText,
  FlUpdaterDialogStyle? style,
}) async {
  if (info.status == UpdateStatus.none) return;
  if (!context.mounted) return;

  Future<void> onUpdate() async {
    try {
      await FlUpdaterPlatform.instance.openStore(
        iosAppId: info.iosAppId,
        androidPackageId: info.androidPackageId,
      );
    } catch (error) {
      debugPrint('fl_updater: failed to open store: $error');
    }
  }

  Future<void> onLater() async {
    await snoozeStore.snooze(info.latestVersion, snoozeDuration);
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: info.status != UpdateStatus.force,
    barrierColor: style?.barrierColor,
    builder: (dialogContext) {
      if (dialogBuilder != null) {
        return dialogBuilder(dialogContext, info, onUpdate, onLater);
      }
      return FlUpdaterDialog(
        info: info,
        onUpdate: onUpdate,
        onLater: onLater,
        title: title,
        message: message,
        updateButtonText: updateButtonText,
        laterButtonText: laterButtonText,
        style: style,
      );
    },
  );
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/src/dialog_presenter.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/src/dialog_presenter.dart
git commit -m "feat: add shared dialog-presentation helper"
```

---

### Task 10: Public `FlUpdater` API

**Files:**
- Modify: `lib/fl_updater.dart` (rewrite; replaces the empty `class FlUpdater {}`)
- Create: `lib/src/update_wrapper.dart` (temporary placeholder — see Step 3; replaced with the real widget in Task 11)
- Test: `test/fl_updater_test.dart` (rewrite; old file tests a nonexistent `getPlatformVersion` method)

**Interfaces:**
- Consumes: `RemoteConfigService` (Task 7), `FlUpdaterSnoozeStore` (Task 3), `presentUpdateDialog` (Task 9), `FlUpdaterPlatform` (Task 4).
- Produces: `class FlUpdater { FlUpdater({RemoteConfigService? remoteConfigService, FlUpdaterSnoozeStore? snoozeStore}); Future<UpdateInfo> checkForUpdate({Duration snoozeDuration, Duration minimumFetchInterval, bool enableInDebugMode, String? iosAppId, String? androidPackageId}); Future<void> showUpdateDialog(BuildContext context, {UpdateInfo? info, String? iosAppId, String? androidPackageId, FlUpdaterDialogBuilder? dialogBuilder, String? title, String? message, String? updateButtonText, String? laterButtonText, FlUpdaterDialogStyle? style, Duration snoozeDuration, Duration minimumFetchInterval, bool enableInDebugMode}); }`. Also exports `UpdateInfo`, `UpdateStatus`, `FlUpdaterDialog`, `FlUpdaterDialogBuilder`, `FlUpdaterDialogStyle`, and `FlUpdaterWrapper` (Task 11) as the package's public surface.

- [ ] **Step 1: Write the failing test**

```dart
// test/fl_updater_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:fl_updater/fl_updater.dart';
import 'package:fl_updater/src/fl_updater_platform_interface.dart';
import 'package:fl_updater/src/fl_updater_method_channel.dart';
import 'package:fl_updater/src/snooze_store.dart';

class MockFlUpdaterPlatform with MockPlatformInterfaceMixin implements FlUpdaterPlatform {
  String? lastIosAppId;
  String? lastAndroidPackageId;
  var openStoreCallCount = 0;

  @override
  Future<void> openStore({String? iosAppId, String? androidPackageId}) async {
    openStoreCallCount++;
    lastIosAppId = iosAppId;
    lastAndroidPackageId = androidPackageId;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('$MethodChannelFlUpdater is the default instance', () {
    expect(FlUpdaterPlatform.instance, isInstanceOf<MethodChannelFlUpdater>());
  });

  test('checkForUpdate returns none by default in debug mode with no injected dependencies', () async {
    // No mocked platform, no mocked RemoteConfigService, no Firebase setup —
    // this only works because RemoteConfigService gates on kDebugMode before
    // touching any platform channel (see Task 7).
    final updater = FlUpdater();

    final info = await updater.checkForUpdate();

    expect(info.status, UpdateStatus.none);
  });

  testWidgets('showUpdateDialog does nothing when status is none', (tester) async {
    FlUpdaterPlatform.instance = MockFlUpdaterPlatform();
    final updater = FlUpdater();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => updater.showUpdateDialog(
              context,
              info: const UpdateInfo(
                currentVersion: '1.0.0',
                latestVersion: '1.0.0',
                status: UpdateStatus.none,
              ),
            ),
            child: const Text('check'),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('showUpdateDialog shows dialog and opens store on Update tap', (tester) async {
    final platform = MockFlUpdaterPlatform();
    FlUpdaterPlatform.instance = platform;
    final updater = FlUpdater();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => updater.showUpdateDialog(
              context,
              info: const UpdateInfo(
                currentVersion: '1.0.0',
                latestVersion: '1.1.0',
                status: UpdateStatus.soft,
                iosAppId: '123',
                androidPackageId: 'com.example.app',
              ),
            ),
            child: const Text('check'),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('fl_updater_update_button')));
    await tester.pumpAndSettle();

    expect(platform.openStoreCallCount, 1);
    expect(platform.lastIosAppId, '123');
    expect(platform.lastAndroidPackageId, 'com.example.app');
  });

  testWidgets('showUpdateDialog snoozes and dismisses on Later tap', (tester) async {
    FlUpdaterPlatform.instance = MockFlUpdaterPlatform();
    final updater = FlUpdater();
    final snoozeStore = FlUpdaterSnoozeStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => updater.showUpdateDialog(
              context,
              info: const UpdateInfo(
                currentVersion: '1.0.0',
                latestVersion: '1.1.0',
                status: UpdateStatus.soft,
              ),
            ),
            child: const Text('check'),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fl_updater_later_button')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(await snoozeStore.isSnoozed('1.1.0'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/fl_updater_test.dart`
Expected: FAIL — `FlUpdater.showUpdateDialog` doesn't exist yet (current `FlUpdater` is an empty class).

- [ ] **Step 3: Rewrite the public API**

```dart
// lib/fl_updater.dart
import 'package:flutter/material.dart';

import 'src/dialog_presenter.dart';
import 'src/models/update_info.model.dart';
import 'src/remote_config_service.dart';
import 'src/snooze_store.dart';
import 'src/update_dialog.dart';

export 'src/models/update_info.model.dart';
export 'src/models/update_status.dart';
export 'src/update_dialog.dart' show FlUpdaterDialog, FlUpdaterDialogBuilder, FlUpdaterDialogStyle;
export 'src/update_wrapper.dart';

class FlUpdater {
  FlUpdater({RemoteConfigService? remoteConfigService, FlUpdaterSnoozeStore? snoozeStore})
      : _remoteConfigService = remoteConfigService ?? RemoteConfigService(),
        _snoozeStore = snoozeStore ?? FlUpdaterSnoozeStore();

  final RemoteConfigService _remoteConfigService;
  final FlUpdaterSnoozeStore _snoozeStore;

  Future<UpdateInfo> checkForUpdate({
    Duration snoozeDuration = const Duration(days: 3),
    Duration minimumFetchInterval = const Duration(hours: 12),
    bool enableInDebugMode = false,
    String? iosAppId,
    String? androidPackageId,
  }) {
    return _remoteConfigService.checkForUpdate(
      snoozeDuration: snoozeDuration,
      minimumFetchInterval: minimumFetchInterval,
      enableInDebugMode: enableInDebugMode,
      iosAppId: iosAppId,
      androidPackageId: androidPackageId,
    );
  }

  Future<void> showUpdateDialog(
    BuildContext context, {
    UpdateInfo? info,
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
  }) async {
    final resolvedInfo = info ??
        await checkForUpdate(
          snoozeDuration: snoozeDuration,
          minimumFetchInterval: minimumFetchInterval,
          enableInDebugMode: enableInDebugMode,
          iosAppId: iosAppId,
          androidPackageId: androidPackageId,
        );
    await presentUpdateDialog(
      context,
      info: resolvedInfo,
      snoozeStore: _snoozeStore,
      snoozeDuration: snoozeDuration,
      dialogBuilder: dialogBuilder,
      title: title,
      message: message,
      updateButtonText: updateButtonText,
      laterButtonText: laterButtonText,
      style: style,
    );
  }
}
```

Note: when `info` is supplied directly, `iosAppId`/`androidPackageId` on `showUpdateDialog` are ignored — they only take effect when `checkForUpdate` runs internally. The debug-gated forwarding (`checkForUpdate` → `RemoteConfigService.checkForUpdate` → `UpdateInfo`) is covered by Task 7's tests and the new `checkForUpdate returns none by default in debug mode` test above. Forwarding through the actual Firebase fetch path (`enableInDebugMode: true` or a release build) is not automated — it requires a live `FirebaseRemoteConfig.instance`, which cannot be constructed in a plain `flutter test` run without Firebase test scaffolding. Verified manually in the example app (Task 12).

Note: this imports `src/update_wrapper.dart` transitively via the `export` directive; Task 11 must exist for this file to compile. If executing tasks in order, Step 4 below will fail to analyze cleanly until Task 11 is done — that's expected; the test in Step 2/5 only needs `FlUpdater`, and `flutter test` will still fail to compile without `update_wrapper.dart` existing. **Create an empty placeholder first** so this task is self-contained:

```dart
// lib/src/update_wrapper.dart (temporary placeholder, replaced by Task 11)
export 'update_dialog.dart' show FlUpdaterDialogBuilder, FlUpdaterDialogStyle;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/fl_updater_test.dart`
Expected: PASS (5/5)

- [ ] **Step 5: Commit**

```bash
git add lib/fl_updater.dart lib/src/update_wrapper.dart test/fl_updater_test.dart
git commit -m "feat: implement public FlUpdater API (checkForUpdate, showUpdateDialog)"
```

---

### Task 11: `FlUpdaterWrapper` automatic wrapper widget

**Files:**
- Modify: `lib/src/update_wrapper.dart` (replaces the Task 10 placeholder with the real widget)

**Interfaces:**
- Consumes: `RemoteConfigService` (Task 7), `FlUpdaterSnoozeStore` (Task 3), `presentUpdateDialog` (Task 9), `FlUpdaterDialogBuilder`/`FlUpdaterDialogStyle` (Task 8).
- Produces: `class FlUpdaterWrapper extends StatefulWidget { const FlUpdaterWrapper({required Widget child, String? iosAppId, String? androidPackageId, FlUpdaterDialogBuilder? dialogBuilder, String? title, String? message, String? updateButtonText, String? laterButtonText, FlUpdaterDialogStyle? style, Duration snoozeDuration = const Duration(days: 3), Duration minimumFetchInterval = const Duration(hours: 12), bool enableInDebugMode = false}); }`. Meant to be used as `MaterialApp(builder: (context, child) => FlUpdaterWrapper(child: child!))`. By default this means the wrapper is a no-op in debug builds — see Task 7's debug-mode note.

**Decision:** No automated test — checking for updates requires a live/faked Firebase Remote Config instance, which the spec's testing section does not call for automated coverage of. Verified manually in the example app (Task 12).

- [ ] **Step 1: Replace the placeholder with the real widget**

```dart
// lib/src/update_wrapper.dart
import 'package:flutter/material.dart';

import 'dialog_presenter.dart';
import 'remote_config_service.dart';
import 'snooze_store.dart';
import 'update_dialog.dart';

class FlUpdaterWrapper extends StatefulWidget {
  const FlUpdaterWrapper({
    super.key,
    required this.child,
    this.iosAppId,
    this.androidPackageId,
    this.dialogBuilder,
    this.title,
    this.message,
    this.updateButtonText,
    this.laterButtonText,
    this.style,
    this.snoozeDuration = const Duration(days: 3),
    this.minimumFetchInterval = const Duration(hours: 12),
    this.enableInDebugMode = false,
  });

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

  @override
  State<FlUpdaterWrapper> createState() => _FlUpdaterWrapperState();
}

class _FlUpdaterWrapperState extends State<FlUpdaterWrapper> {
  final _remoteConfigService = RemoteConfigService();
  final _snoozeStore = FlUpdaterSnoozeStore();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    final info = await _remoteConfigService.checkForUpdate(
      snoozeDuration: widget.snoozeDuration,
      minimumFetchInterval: widget.minimumFetchInterval,
      enableInDebugMode: widget.enableInDebugMode,
      iosAppId: widget.iosAppId,
      androidPackageId: widget.androidPackageId,
    );
    if (!mounted) return;
    await presentUpdateDialog(
      context,
      info: info,
      snoozeStore: _snoozeStore,
      snoozeDuration: widget.snoozeDuration,
      dialogBuilder: widget.dialogBuilder,
      title: widget.title,
      message: widget.message,
      updateButtonText: widget.updateButtonText,
      laterButtonText: widget.laterButtonText,
      style: widget.style,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

- [ ] **Step 2: Run the full test suite to confirm nothing broke**

Run: `flutter test`
Expected: All tests PASS (`version_comparator_test.dart`, `models/update_info_test.dart`, `snooze_store_test.dart`, `fl_updater_method_channel_test.dart`, `remote_config_service_test.dart`, `update_dialog_test.dart`, `fl_updater_test.dart`).

- [ ] **Step 3: Commit**

```bash
git add lib/src/update_wrapper.dart
git commit -m "feat: add FlUpdaterWrapper for automatic check-and-show"
```

---

### Task 12: Example app wiring and manual verification

**Files:**
- Modify: `example/pubspec.yaml` (adds `firebase_core`)
- Modify: `example/lib/main.dart` (rewrite)

**Interfaces:**
- Consumes: `FlUpdater`, `FlUpdaterWrapper`, `FlUpdaterDialogStyle` (public API from Tasks 10–11).

- [ ] **Step 1: Add firebase_core to the example app**

Run: `cd example && flutter pub add firebase_core && cd ..`
Expected: `example/pubspec.yaml` gains a `firebase_core: ^x.y.z` line.

- [ ] **Step 2: Rewrite the example app**

```dart
// example/lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_updater/fl_updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (error) {
    // No Firebase project is configured for this example yet. Run
    // `flutterfire configure` from the example/ directory to enable
    // real Remote Config values — fl_updater fails open without it,
    // so the app still runs, it just never finds an update.
    debugPrint('Firebase.initializeApp failed: $error');
  }
  runApp(const MyApp());
}

// Set these to your app's real identifiers before shipping — the Play
// Store package id and the numeric App Store id. Neither comes from
// Remote Config; the wrapper takes them directly. Leaving androidPackageId
// null falls back to the host app's own package name on Android; iOS has
// no such fallback and needs a real numeric id to open the App Store.
const _androidPackageId = 'com.kishormainali.fl_updater_example';
const _iosAppId = '000000000';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) => FlUpdaterWrapper(
        iosAppId: _iosAppId,
        androidPackageId: _androidPackageId,
        // This example app is specifically for exercising fl_updater during
        // development, so it opts back into fetching while debugging. A real
        // app normally leaves this false (the default) to avoid Remote
        // Config fetches and surprise dialogs on every debug hot restart.
        enableInDebugMode: true,
        child: child!,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _checkManually(BuildContext context) async {
    final updater = FlUpdater();
    await updater.showUpdateDialog(
      context,
      iosAppId: _iosAppId,
      androidPackageId: _androidPackageId,
      enableInDebugMode: true,
      style: const FlUpdaterDialogStyle(
        titleStyle: TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('fl_updater example')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _checkManually(context),
          child: const Text('Check for update'),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Static-analyze both packages**

Run: `flutter analyze && cd example && flutter analyze && cd ..`
Expected: `No issues found!` in both.

- [ ] **Step 4: Manual verification — Android**

1. Set up a Firebase project for the example app: `cd example && flutterfire configure` (requires a Google/Firebase account; skip if `FlUpdaterWrapper`'s fail-open behavior is all you need to confirm).
2. In the Firebase console, set the Remote Config parameter `fl_updater_latest_version` to a version higher than `example/pubspec.yaml`'s version. Set `_androidPackageId` in `example/lib/main.dart` to the example app's actual applicationId (see `example/android/app/build.gradle.kts`) if it differs from the placeholder.
3. Temporarily remove `enableInDebugMode: true` from both call sites in `example/lib/main.dart`, run `cd example && flutter run -d <android-emulator-id>`, and confirm no dialog appears and no Remote Config fetch happens (debug-mode default). Restore `enableInDebugMode: true` afterward — the remaining steps below need it.
4. Run `cd example && flutter run -d <android-emulator-id>`.
5. Confirm the soft-update dialog appears automatically on launch, "Later" dismisses it and it does not reappear on a hot-restart within the snooze window, and "Update" opens (or attempts to open) the Play Store.
6. Set `fl_updater_min_version` above the example app's version, relaunch, and confirm the dialog is now non-dismissible (no Later button, back button does nothing).

- [ ] **Step 5: Manual verification — iOS**

1. Repeat Step 4 on an iOS simulator, first setting `_iosAppId` in `example/lib/main.dart` to any real numeric App Store id (e.g. an existing app's id) to confirm the App Store deep link fires.

- [ ] **Step 6: Commit**

```bash
git add example/pubspec.yaml example/pubspec.lock example/lib/main.dart
git commit -m "feat: wire example app to FlUpdaterWrapper and imperative API"
```

---

### Task 13: Package metadata and README

**Files:**
- Modify: `pubspec.yaml` (description)
- Modify: `README.md` (rewrite)

- [ ] **Step 1: Update the package description**

In `pubspec.yaml`, change:

```yaml
description: "A new Flutter plugin project."
```

to:

```yaml
description: "Firebase Remote Config-driven app update dialog with automatic wrapper, snoozable soft updates, and native App/Play Store opening."
```

- [ ] **Step 2: Rewrite the README**

```markdown
# fl_updater

A Flutter plugin that shows an app-update dialog driven by Firebase Remote
Config, and opens the platform's App Store / Play Store page natively.

## Remote Config keys

| Key | Type | Meaning |
| --- | --- | --- |
| `fl_updater_latest_version` | string | Latest published version, e.g. `"2.3.0"` |
| `fl_updater_min_version` | string | Versions below this trigger a blocking update. Defaults to `"0.0.0"` (never forces). |

That's the whole schema — nothing else lives in Remote Config. The App Store
id and Android package id are static per-app values, not something you'd
toggle from a dashboard, so they're passed directly instead:

```dart
FlUpdaterWrapper(
  iosAppId: '123456789',           // required on iOS — no on-device fallback
  androidPackageId: 'com.you.app', // optional — defaults to the host app's own package name
  child: child!,
)
```

## Automatic usage

```dart
MaterialApp(
  builder: (context, child) => FlUpdaterWrapper(
    iosAppId: '123456789',
    androidPackageId: 'com.you.app',
    child: child!,
  ),
  home: const HomePage(),
)
```

Checks once per app launch and shows the dialog automatically when an update
is available.

## Imperative usage

```dart
final updater = FlUpdater();
await updater.showUpdateDialog(
  context,
  iosAppId: '123456789',
  androidPackageId: 'com.you.app',
);
```

## Fetch behavior and cost

Remote Config moved to usage-based pricing on 2026-09-01, so `fl_updater`
is deliberately conservative about fetching:

- **Debug builds fetch nothing by default.** `kDebugMode` disables the
  Remote Config check entirely (no dialog, no network call) so hot restarts
  while developing don't burn fetches or pop up dialogs unannounced. Pass
  `enableInDebugMode: true` to opt back in — e.g. in your own debug/staging
  build of the example app.
- **`minimumFetchInterval`** (default 12 hours, matching the Firebase SDK's
  own default) caps how often a real fetch happens even in release builds;
  repeated checks inside that window are served from the SDK's cache.

```dart
FlUpdaterWrapper(
  minimumFetchInterval: const Duration(days: 1),
  child: child!,
)
```

## Customization

Style the built-in dialog:

```dart
FlUpdaterWrapper(
  style: FlUpdaterDialogStyle(
    titleStyle: TextStyle(fontWeight: FontWeight.bold),
  ),
  title: 'New version available',
  child: child!,
)
```

Or replace it entirely:

```dart
FlUpdaterWrapper(
  dialogBuilder: (context, info, onUpdate, onLater) {
    return MyCustomUpdateSheet(info: info, onUpdate: onUpdate, onLater: onLater);
  },
  child: child!,
)
```

## Snoozing

Tapping "Later" on a soft (non-forced) update snoozes it for `snoozeDuration`
(default 3 days), per version — publishing a newer `fl_updater_latest_version`
immediately invalidates an active snooze.

```dart
FlUpdaterWrapper(
  snoozeDuration: const Duration(days: 7),
  child: child!,
)
```

Force updates (installed version below `fl_updater_min_version`) always
ignore snooze and cannot be dismissed.
```

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml README.md
git commit -m "docs: document Remote Config keys and usage"
```
