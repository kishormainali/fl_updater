import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_updater/src/models/update_status.dart';
import 'package:fl_updater/src/remote_config_service.dart';
import 'package:fl_updater/src/snooze_store.dart';

class MockFirebaseRemoteConfig extends Mock implements FirebaseRemoteConfig {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Needed so mocktail knows how to match `any()`/non-stubbed positional
    // RemoteConfigSettings arguments passed to setConfigSettings().
    registerFallbackValue(
      RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 12),
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
    when(() => mockRemoteConfig.setConfigSettings(any())).thenAnswer((_) async {});
    when(() => mockRemoteConfig.setDefaults(any())).thenAnswer((_) async {});
  });

  // flutter test runs in JIT/debug mode, so kDebugMode is true here —
  // enableInDebugMode: true is required in every test below to reach the
  // real fetch -> status -> snooze-downgrade logic instead of the
  // kDebugMode gate already covered elsewhere.

  test('checkForUpdate returns soft when the fetched latest_version is newer than installed', () async {
    when(() => mockRemoteConfig.fetchAndActivate()).thenAnswer((_) async => true);
    when(() => mockRemoteConfig.getString('fl_updater_latest_version')).thenReturn('2.0.0');
    when(() => mockRemoteConfig.getString('fl_updater_min_version')).thenReturn('');

    final service = RemoteConfigService(remoteConfig: mockRemoteConfig);

    final info = await service.checkForUpdate(enableInDebugMode: true);

    expect(info.status, UpdateStatus.soft);
    expect(info.currentVersion, '1.0.0');
    expect(info.latestVersion, '2.0.0');
  });

  test('checkForUpdate downgrades soft to none when the latest version is already snoozed', () async {
    when(() => mockRemoteConfig.fetchAndActivate()).thenAnswer((_) async => true);
    when(() => mockRemoteConfig.getString('fl_updater_latest_version')).thenReturn('2.0.0');
    when(() => mockRemoteConfig.getString('fl_updater_min_version')).thenReturn('');

    final snoozeStore = FlUpdaterSnoozeStore();
    await snoozeStore.snooze('2.0.0', const Duration(days: 3));

    final service = RemoteConfigService(remoteConfig: mockRemoteConfig, snoozeStore: snoozeStore);

    final info = await service.checkForUpdate(enableInDebugMode: true);

    expect(info.status, UpdateStatus.none);
  });

  test('checkForUpdate fails open to none when fetchAndActivate throws', () async {
    when(() => mockRemoteConfig.fetchAndActivate()).thenThrow(Exception('network error'));

    final service = RemoteConfigService(remoteConfig: mockRemoteConfig);

    final info = await service.checkForUpdate(enableInDebugMode: true);

    expect(info.status, UpdateStatus.none);
  });

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
