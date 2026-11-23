import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_updater/src/models/update_status.dart';
import 'package:fl_updater/src/services/update_service.dart';
import 'package:fl_updater/src/services/snooze_store.dart';

import 'fake_provider.dart';

/// Captures stdout writes made via `print()` — what `package:fp_logger`
/// emits through internally — by running [body] inside a zone with a
/// custom print handler.
Future<List<String>> _captureLogs(FutureOr<void> Function() body) async {
  final logs = <String>[];
  await runZoned(
    () async => await body(),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => logs.add(line),
    ),
  );
  return logs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });

  // flutter test runs in JIT/debug mode, so kDebugMode is true here —
  // enabled: true is required in every test below to reach the
  // real fetch -> status -> snooze-downgrade logic instead of the
  // enabled gate already covered elsewhere.

  test(
      'checkForUpdate returns soft when the fetched latest_version is newer than installed',
      () async {
    final provider = FakeProvider(
        fetched: '{"latest_version": "2.0.0"}',
        active: '{"latest_version": "2.0.0"}');

    final service = UpdateService(provider: provider);

    final info = await service.checkForUpdate(enabled: true);

    expect(info.status, UpdateStatus.soft);
    expect(info.currentVersion, '1.0.0+1');
    expect(info.latestVersion, '2.0.0');
  });

  test(
      'checkForUpdate downgrades soft to none when the latest version is already snoozed',
      () async {
    final provider = FakeProvider(
        fetched: '{"latest_version": "2.0.0"}',
        active: '{"latest_version": "2.0.0"}');

    final snoozeStore = FlUpdaterSnoozeStore();
    await snoozeStore.snooze('2.0.0', const Duration(days: 3));

    final service = UpdateService(provider: provider, snoozeStore: snoozeStore);

    final info = await service.checkForUpdate(enabled: true);

    expect(info.status, UpdateStatus.none);
  });

  test('checkForUpdate fails open to none when fetch throws', () async {
    final service = UpdateService(
        provider: FakeProvider(fetchError: Exception('network error')));

    final info = await service.checkForUpdate(enabled: true);

    expect(info.status, UpdateStatus.none);
  });

  test(
      'checkForUpdate skips the fetch and returns none in debug mode by default',
      () async {
    final service = UpdateService(provider: FakeProvider());

    final info = await service.checkForUpdate();

    expect(info.status, UpdateStatus.none);
  });

  test(
      'checkForUpdate passes iosAppId/androidPackageId through even when gated',
      () async {
    final service = UpdateService(provider: FakeProvider());

    final info = await service.checkForUpdate(
      iosAppId: '123',
      androidPackageId: 'com.example.app',
    );

    expect(info.iosAppId, '123');
    expect(info.androidPackageId, 'com.example.app');
  });

  test(
      'checkForUpdate fetches latest_version and min_version from the fl_updater_config JSON',
      () async {
    final provider = FakeProvider(
        fetched: '{"latest_version": "2.0.0", "min_version": "1.5.0"}',
        active: '{"latest_version": "2.0.0", "min_version": "1.5.0"}');

    final service = UpdateService(provider: provider);

    final info = await service.checkForUpdate(
      enabled: true,
    );

    expect(info.status, UpdateStatus.force); // current is 1.0.0 < 1.5.0
    expect(info.latestVersion, '2.0.0');
  });

  test(
      'checkForUpdate includes the installed build number in currentVersion so a '
      'min_version build-number requirement does not always force-update',
      () async {
    PackageInfo.setMockInitialValues(
      appName: 'fl_updater_test',
      packageName: 'com.example.fl_updater_test',
      version: '1.0.0',
      buildNumber: '15',
      buildSignature: '',
    );

    final provider = FakeProvider(
        fetched: '{"latest_version": "1.0.0+15", "min_version": "1.0.0+10"}',
        active: '{"latest_version": "1.0.0+15", "min_version": "1.0.0+10"}');

    final service = UpdateService(provider: provider);

    final info = await service.checkForUpdate(enabled: true);

    expect(info.currentVersion, '1.0.0+15');
    expect(info.status, UpdateStatus.none);
  });

  test(
      'checkForUpdate logs the fetched config JSON pretty-printed (indented, multi-line) '
      'rather than as one raw minified line', () async {
    final provider = FakeProvider(
        fetched: '{"latest_version": "2.0.0", "min_version": "1.5.0"}',
        active: '{"latest_version": "2.0.0", "min_version": "1.5.0"}');

    final service = UpdateService(provider: provider);

    final logs = await _captureLogs(() async {
      await service.checkForUpdate(enabled: true, enableLogging: true);
    });

    final output = logs.join('\n');
    // Pretty-printed via JsonEncoder.withIndent('  ', ...): each key gets
    // its own indented line, unlike the raw `{"latest_version": ...}` blob.
    expect(output, contains('"latest_version": "2.0.0"'));
    expect(output, contains('"min_version": "1.5.0"'));
    expect(output, contains('  "latest_version"'));
    expect(output, isNot(contains('config={')));
  });

  test('checkForUpdate uses the flavor entry when one matches', () async {
    final provider = FakeProvider(
        fetched: '{"latest_version": "1.1.0", "min_version": "5.0.0", '
            '"flavors": {"dev": {"latest_version": "9.9.9"}}}',
        active: '{"latest_version": "1.1.0", "min_version": "5.0.0", '
            '"flavors": {"dev": {"latest_version": "9.9.9"}}}');

    final service = UpdateService(provider: provider);

    final info = await service.checkForUpdate(enabled: true, flavor: 'dev');

    // Flavor entry wins for latest_version...
    expect(info.latestVersion, '9.9.9');
    // ...but min_version isn't in the flavor entry, so it falls back to the
    // top-level 5.0.0, forcing an update (installed is 1.0.0).
    expect(info.status, UpdateStatus.force);
  });

  test(
      'checkForUpdate falls back to top-level values when the flavor has no matching entry',
      () async {
    final provider = FakeProvider(
        fetched:
            '{"latest_version": "2.0.0", "flavors": {"staging": {"latest_version": "9.9.9"}}}',
        active:
            '{"latest_version": "2.0.0", "flavors": {"staging": {"latest_version": "9.9.9"}}}');

    final service = UpdateService(provider: provider);

    final info = await service.checkForUpdate(enabled: true, flavor: 'dev');

    expect(info.latestVersion, '2.0.0');
  });

  test('checkForUpdate uses an explicit platform override', () async {
    final provider = FakeProvider(
        fetched:
            '{"latest_version": "1.0.0", "platforms": {"ios": {"latest_version": "5.0.0"}}}',
        active:
            '{"latest_version": "1.0.0", "platforms": {"ios": {"latest_version": "5.0.0"}}}');

    final service = UpdateService(provider: provider);

    final info = await service.checkForUpdate(enabled: true, platform: 'ios');

    expect(info.latestVersion, '5.0.0');
  });

  test(
      'evaluateActiveConfig reads already active Remote Config values without fetch',
      () async {
    final provider = FakeProvider(
        fetched: '{"latest_version": "2.1.0", "min_version": "1.8.0"}',
        active: '{"latest_version": "2.1.0", "min_version": "1.8.0"}');

    final service = UpdateService(provider: provider);
    final info = await service.evaluateActiveConfig();

    expect(info.latestVersion, '2.1.0');
    expect(info.status, UpdateStatus.force); // installed is 1.0.0 < 1.8.0
    expect(provider.fetchCount, 0);
  });

  test('evaluateActiveConfig clears snooze store when clearSnooze is true',
      () async {
    final provider = FakeProvider(
        fetched: '{"latest_version": "2.1.0", "min_version": "0.0.0"}',
        active: '{"latest_version": "2.1.0", "min_version": "0.0.0"}');

    final snoozeStore = FlUpdaterSnoozeStore();
    await snoozeStore.snooze('2.1.0', const Duration(days: 3));
    expect(await snoozeStore.isSnoozed('2.1.0'), isTrue);

    final service = UpdateService(provider: provider, snoozeStore: snoozeStore);
    final info = await service.evaluateActiveConfig(clearSnooze: true);

    expect(info.status,
        UpdateStatus.soft); // Not downgraded to none because snooze was cleared
    expect(await snoozeStore.isSnoozed('2.1.0'), isFalse);
  });

  test('evaluateActiveConfig applies the flavor entry fallback', () async {
    final provider = FakeProvider(
        fetched: '{"latest_version": "1.0.0", "min_version": "1.0.0", '
            '"flavors": {"staging": {"latest_version": "3.0.0", "min_version": "2.8.0"}}}',
        active: '{"latest_version": "1.0.0", "min_version": "1.0.0", '
            '"flavors": {"staging": {"latest_version": "3.0.0", "min_version": "2.8.0"}}}');

    final service = UpdateService(provider: provider);
    final info = await service.evaluateActiveConfig(
        clearSnooze: false, flavor: 'staging');

    expect(info.latestVersion, '3.0.0');
    expect(info.status, UpdateStatus.force); // installed 1.0.0 < min 2.8.0
  });

  test('checkForUpdate falls back to the cached config when fetch throws',
      () async {
    final provider = FakeProvider(
      fetchError: Exception('offline'),
      active: '{"latest_version": "2.0.0"}',
    );
    final info =
        await UpdateService(provider: provider).checkForUpdate(enabled: true);
    expect(info.status, UpdateStatus.soft);
    expect(info.latestVersion, '2.0.0');
  });

  test('checkForUpdate yields none for null, empty and malformed config',
      () async {
    for (final raw in <String?>[null, '', '{not json']) {
      final info = await UpdateService(
        provider: FakeProvider(fetched: raw, active: raw),
      ).checkForUpdate(enabled: true);
      expect(info.status, UpdateStatus.none, reason: 'raw=$raw');
    }
  });

  test('listenForUpdates returns null when the provider has no changes stream',
      () {
    final sub =
        UpdateService(provider: FakeProvider()).listenForUpdates(() async {});
    expect(sub, isNull);
  });

  test('listenForUpdates invokes the callback for each provider change',
      () async {
    final provider = FakeProvider(push: true);
    var calls = 0;
    final sub = UpdateService(provider: provider).listenForUpdates(() async {
      calls++;
    });
    provider.emitChange();
    provider.emitChange();
    await pumpEventQueue();
    expect(calls, 2);
    await sub?.cancel();
  });

  test(
      'listenForUpdates returns null (does not throw) when reading changes throws',
      () {
    final sub = UpdateService(provider: _ThrowingChangesProvider())
        .listenForUpdates(() async {});
    expect(sub, isNull);
  });
}

class _ThrowingChangesProvider extends FakeProvider {
  @override
  Stream<void>? get changes => throw StateError('Firebase not initialised');
}
