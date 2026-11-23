import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:fl_updater_firebase/fl_updater_firebase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseRemoteConfig extends Mock implements FirebaseRemoteConfig {}

void main() {
  setUpAll(() {
    registerFallbackValue(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: const Duration(hours: 1),
    ));
  });

  late MockFirebaseRemoteConfig rc;
  late FirebaseConfigProvider provider;

  setUp(() {
    rc = MockFirebaseRemoteConfig();
    when(() => rc.setConfigSettings(any())).thenAnswer((_) async {});
    when(() => rc.setDefaults(any())).thenAnswer((_) async {});
    when(() => rc.fetchAndActivate()).thenAnswer((_) async => true);
    when(() => rc.activate()).thenAnswer((_) async => true);
    when(() => rc.getString('fl_updater_config')).thenReturn('{"a":1}');
    provider = FirebaseConfigProvider(remoteConfig: rc);
  });

  test('fetch configures, fetches+activates, and returns the JSON', () async {
    final raw =
        await provider.fetch(minimumFetchInterval: const Duration(minutes: 5));

    expect(raw, '{"a":1}');
    final settings = verify(() => rc.setConfigSettings(captureAny()))
        .captured
        .single as RemoteConfigSettings;
    expect(settings.fetchTimeout, const Duration(minutes: 1));
    expect(settings.minimumFetchInterval, const Duration(minutes: 5));
    verify(() => rc.setDefaults({'fl_updater_config': '{}'})).called(1);
    verify(() => rc.fetchAndActivate()).called(1);
  });

  test('fetch propagates fetchAndActivate errors', () async {
    when(() => rc.fetchAndActivate()).thenThrow(Exception('network'));
    await expectLater(provider.fetch(), throwsException);
  });

  test('current reads the active value without fetching', () async {
    expect(await provider.current(), '{"a":1}');
    verifyNever(() => rc.fetchAndActivate());
  });

  group('changes', () {
    late StreamController<RemoteConfigUpdate> controller;

    setUp(() {
      controller = StreamController<RemoteConfigUpdate>();
      when(() => rc.onConfigUpdated).thenAnswer((_) => controller.stream);
      addTearDown(controller.close);
    });

    test('activates then emits for the config key', () async {
      var events = 0;
      final sub = provider.changes.listen((_) => events++);
      controller.add(RemoteConfigUpdate({'fl_updater_config'}));
      await pumpEventQueue();
      expect(events, 1);
      verify(() => rc.activate()).called(1);
      await sub.cancel();
    });

    test('emits when updatedKeys is empty (whole-template update)', () async {
      var events = 0;
      final sub = provider.changes.listen((_) => events++);
      controller.add(RemoteConfigUpdate(<String>{}));
      await pumpEventQueue();
      expect(events, 1);
      await sub.cancel();
    });

    test('ignores unrelated keys', () async {
      var events = 0;
      final sub = provider.changes.listen((_) => events++);
      controller.add(RemoteConfigUpdate({'other'}));
      await pumpEventQueue();
      expect(events, 0);
      verifyNever(() => rc.activate());
      await sub.cancel();
    });

    test('still emits when activate throws', () async {
      when(() => rc.activate()).thenThrow(Exception('boom'));
      var events = 0;
      final sub = provider.changes.listen((_) => events++);
      controller.add(RemoteConfigUpdate({'fl_updater_config'}));
      await pumpEventQueue();
      expect(events, 1);
      await sub.cancel();
    });
  });
}
