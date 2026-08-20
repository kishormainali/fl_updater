import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_updater/src/models/update_status.dart';
import 'package:fl_updater/src/services/remote_config_service.dart';
import 'package:fl_updater/src/services/snooze_store.dart';

class MockFirebaseRemoteConfig extends Mock implements FirebaseRemoteConfig {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Needed so mocktail knows how to match `any()`/non-stubbed positional
    // RemoteConfigSettings arguments passed to setConfigSettings().
    registerFallbackValue(
      RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );
  });

  late MockFirebaseRemoteConfig mockRemoteConfig;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    // PackageInfo.fromPlatform() is called before the injected
    // FirebaseRemoteConfig is ever touched, so it must be mocked too —
    // package_info_plus ships an official @visibleForTesting hook for
    // exactly this (see package_info_plus-10.2.1/lib/package_info_plus.dart)
    // rather than us reimplementing its method-channel wire format.
    PackageInfo.setMockInitialValues(
      appName: 'fl_updater_test',
      packageName: 'com.example.fl_updater_test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    mockRemoteConfig = MockFirebaseRemoteConfig();
    when(() => mockRemoteConfig.setConfigSettings(any()))
        .thenAnswer((_) async {});
    when(() => mockRemoteConfig.setDefaults(any())).thenAnswer((_) async {});
    when(() => mockRemoteConfig.activate()).thenAnswer((_) async => true);
    when(() => mockRemoteConfig.getString(any())).thenReturn('');
    when(() => mockRemoteConfig.onConfigUpdated)
        .thenAnswer((_) => const Stream.empty());
  });

  // flutter test runs in JIT/debug mode, so kDebugMode is true here —
  // enabled: true is required in every test below to reach the
  // real fetch -> status -> snooze-downgrade logic instead of the
  // enabled gate already covered elsewhere.

  test(
      'checkForUpdate returns soft when the fetched latest_version is newer than installed',
      () async {
    when(() => mockRemoteConfig.fetchAndActivate())
        .thenAnswer((_) async => true);
    when(() => mockRemoteConfig.getString('fl_updater_latest_version'))
        .thenReturn('2.0.0');
    when(() => mockRemoteConfig.getString('fl_updater_min_version'))
        .thenReturn('');

    final service = RemoteConfigService(remoteConfig: mockRemoteConfig);

    final info = await service.checkForUpdate(enabled: true);

    expect(info.status, UpdateStatus.soft);
    expect(info.currentVersion, '1.0.0');
    expect(info.latestVersion, '2.0.0');
  });

  test(
      'checkForUpdate downgrades soft to none when the latest version is already snoozed',
      () async {
    when(() => mockRemoteConfig.fetchAndActivate())
        .thenAnswer((_) async => true);
    when(() => mockRemoteConfig.getString('fl_updater_latest_version'))
        .thenReturn('2.0.0');
    when(() => mockRemoteConfig.getString('fl_updater_min_version'))
        .thenReturn('');

    final snoozeStore = FlUpdaterSnoozeStore();
    await snoozeStore.snooze('2.0.0', const Duration(days: 3));

    final service = RemoteConfigService(
        remoteConfig: mockRemoteConfig, snoozeStore: snoozeStore);

    final info = await service.checkForUpdate(enabled: true);

    expect(info.status, UpdateStatus.none);
  });

  test('checkForUpdate fails open to none when fetchAndActivate throws',
      () async {
    when(() => mockRemoteConfig.fetchAndActivate())
        .thenThrow(Exception('network error'));

    final service = RemoteConfigService(remoteConfig: mockRemoteConfig);

    final info = await service.checkForUpdate(enabled: true);

    expect(info.status, UpdateStatus.none);
  });

  test(
      'checkForUpdate skips the fetch and returns none in debug mode by default',
      () async {
    final service = RemoteConfigService();

    final info = await service.checkForUpdate();

    expect(info.status, UpdateStatus.none);
  });

  test(
      'checkForUpdate passes iosAppId/androidPackageId through even when gated',
      () async {
    final service = RemoteConfigService();

    final info = await service.checkForUpdate(
      iosAppId: '123',
      androidPackageId: 'com.example.app',
    );

    expect(info.iosAppId, '123');
    expect(info.androidPackageId, 'com.example.app');
  });

  test(
      'checkForUpdate fetches fl_updater_latest_version and fl_updater_min_version from remote config',
      () async {
    when(() => mockRemoteConfig.fetchAndActivate())
        .thenAnswer((_) async => true);
    when(() => mockRemoteConfig.getString('fl_updater_latest_version'))
        .thenReturn('2.0.0');
    when(() => mockRemoteConfig.getString('fl_updater_min_version'))
        .thenReturn('1.5.0');

    final service = RemoteConfigService(remoteConfig: mockRemoteConfig);

    final info = await service.checkForUpdate(
      enabled: true,
    );

    expect(info.status, UpdateStatus.force); // current is 1.0.0 < 1.5.0
    expect(info.latestVersion, '2.0.0');
  });

  test(
      'listenForUpdates activates config and invokes callback when relevant keys update',
      () async {
    final controller = StreamController<RemoteConfigUpdate>();
    when(() => mockRemoteConfig.onConfigUpdated)
        .thenAnswer((_) => controller.stream);

    var callbackCalled = false;
    final service = RemoteConfigService(remoteConfig: mockRemoteConfig);
    final sub = service.listenForUpdates(() async {
      callbackCalled = true;
    });

    controller.add(RemoteConfigUpdate({'fl_updater_latest_version'}));
    await pumpEventQueue();

    expect(callbackCalled, isTrue);
    verify(() => mockRemoteConfig.activate()).called(1);

    await sub?.cancel();
    await controller.close();
  });

  test('listenForUpdates ignores events for unrelated keys', () async {
    final controller = StreamController<RemoteConfigUpdate>();
    when(() => mockRemoteConfig.onConfigUpdated)
        .thenAnswer((_) => controller.stream);

    var callbackCalled = false;
    final service = RemoteConfigService(remoteConfig: mockRemoteConfig);
    final sub = service.listenForUpdates(() async {
      callbackCalled = true;
    });

    controller.add(RemoteConfigUpdate({'some_unrelated_key'}));
    await pumpEventQueue();

    expect(callbackCalled, isFalse);
    verifyNever(() => mockRemoteConfig.activate());

    await sub?.cancel();
    await controller.close();
  });

  test(
      'evaluateActiveConfig reads already active Remote Config values without fetch',
      () async {
    when(() => mockRemoteConfig.getString('fl_updater_latest_version'))
        .thenReturn('2.1.0');
    when(() => mockRemoteConfig.getString('fl_updater_min_version'))
        .thenReturn('1.8.0');

    final service = RemoteConfigService(remoteConfig: mockRemoteConfig);
    final info = await service.evaluateActiveConfig();

    expect(info.latestVersion, '2.1.0');
    expect(info.status, UpdateStatus.force); // installed is 1.0.0 < 1.8.0
    verifyNever(() => mockRemoteConfig.fetchAndActivate());
  });

  test('evaluateActiveConfig clears snooze store when clearSnooze is true',
      () async {
    when(() => mockRemoteConfig.getString('fl_updater_latest_version'))
        .thenReturn('2.1.0');
    when(() => mockRemoteConfig.getString('fl_updater_min_version'))
        .thenReturn('0.0.0');

    final snoozeStore = FlUpdaterSnoozeStore();
    await snoozeStore.snooze('2.1.0', const Duration(days: 3));
    expect(await snoozeStore.isSnoozed('2.1.0'), isTrue);

    final service = RemoteConfigService(
      remoteConfig: mockRemoteConfig,
      snoozeStore: snoozeStore,
    );
    final info = await service.evaluateActiveConfig(clearSnooze: true);

    expect(info.status,
        UpdateStatus.soft); // Not downgraded to none because snooze was cleared
    expect(await snoozeStore.isSnoozed('2.1.0'), isFalse);
  });
}
