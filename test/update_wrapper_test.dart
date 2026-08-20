import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_updater/fl_updater.dart';
import 'package:fl_updater/src/services/fl_updater_platform_interface.dart';
import 'package:fl_updater/src/services/remote_config_service.dart';

class MockFlUpdaterPlatform
    with MockPlatformInterfaceMixin
    implements FlUpdaterPlatform {
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

class MockRemoteConfigService extends Mock implements RemoteConfigService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  late MockRemoteConfigService mockRemoteConfigService;
  late MockFlUpdaterPlatform mockPlatform;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRemoteConfigService = MockRemoteConfigService();
    when(() => mockRemoteConfigService.listenForUpdates(
          any(),
          enableLogging: any(named: 'enableLogging'),
        )).thenReturn(null);
    mockPlatform = MockFlUpdaterPlatform();
    FlUpdaterPlatform.instance = mockPlatform;
  });

  testWidgets(
      'renders child and shows no dialog when debug-gated (default enabled)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FlUpdaterWrapper(child: child!),
        home: const Scaffold(body: Text('child content')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('child content'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'presents update dialog in MaterialApp.builder without navigator missing error',
      (
    tester,
  ) async {
    when(() => mockRemoteConfigService.checkForUpdate(
          snoozeDuration: any(named: 'snoozeDuration'),
          minimumFetchInterval: any(named: 'minimumFetchInterval'),
          enabled: any(named: 'enabled'),
          iosAppId: any(named: 'iosAppId'),
          androidPackageId: any(named: 'androidPackageId'),
        )).thenAnswer((_) async => const UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '2.0.0',
          status: UpdateStatus.soft,
          iosAppId: '123456789',
          androidPackageId: 'com.example.app',
        ));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FlUpdaterWrapper(
          iosAppId: '123456789',
          androidPackageId: 'com.example.app',
          enabled: true,
          remoteConfigService: mockRemoteConfigService,
          child: child!,
        ),
        home: const Scaffold(body: Text('child content')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('child content'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Update available'), findsOneWidget);

    // Tap update button
    await tester.tap(find.byKey(const Key('fl_updater_update_button')));
    await tester.pumpAndSettle();

    expect(mockPlatform.openStoreCallCount, 1);
    expect(mockPlatform.lastIosAppId, '123456789');
    expect(mockPlatform.lastAndroidPackageId, 'com.example.app');
  });

  testWidgets(
      'snoozes and dismisses dialog when Later is tapped in MaterialApp.builder',
      (
    tester,
  ) async {
    final snoozeStore = FlUpdaterSnoozeStore();
    when(() => mockRemoteConfigService.checkForUpdate(
          snoozeDuration: any(named: 'snoozeDuration'),
          minimumFetchInterval: any(named: 'minimumFetchInterval'),
          enabled: any(named: 'enabled'),
          iosAppId: any(named: 'iosAppId'),
          androidPackageId: any(named: 'androidPackageId'),
        )).thenAnswer((_) async => const UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '2.0.0',
          status: UpdateStatus.soft,
        ));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FlUpdaterWrapper(
          enabled: true,
          remoteConfigService: mockRemoteConfigService,
          snoozeStore: snoozeStore,
          child: child!,
        ),
        home: const Scaffold(body: Text('child content')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('fl_updater_later_button')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(await snoozeStore.isSnoozed('2.0.0'), isTrue);
  });

  testWidgets('supports explicit navigatorKey', (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    when(() => mockRemoteConfigService.checkForUpdate(
          snoozeDuration: any(named: 'snoozeDuration'),
          minimumFetchInterval: any(named: 'minimumFetchInterval'),
          enabled: any(named: 'enabled'),
          iosAppId: any(named: 'iosAppId'),
          androidPackageId: any(named: 'androidPackageId'),
        )).thenAnswer((_) async => const UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '2.0.0',
          status: UpdateStatus.force,
        ));

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        builder: (context, child) => FlUpdaterWrapper(
          navigatorKey: navKey,
          enabled: true,
          remoteConfigService: mockRemoteConfigService,
          child: child!,
        ),
        home: const Scaffold(body: Text('child content')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    // Force update should not have later button
    expect(find.byKey(const Key('fl_updater_later_button')), findsNothing);
  });

  testWidgets(
      'clears snooze store on launch in debug mode when clearSnoozeInDebugMode is true',
      (
    tester,
  ) async {
    final snoozeStore = FlUpdaterSnoozeStore();
    await snoozeStore.snooze('2.0.0', const Duration(days: 3));
    expect(await snoozeStore.isSnoozed('2.0.0'), isTrue);

    when(() => mockRemoteConfigService.checkForUpdate(
          snoozeDuration: any(named: 'snoozeDuration'),
          minimumFetchInterval: any(named: 'minimumFetchInterval'),
          enabled: any(named: 'enabled'),
          clearSnoozeInDebugMode: any(named: 'clearSnoozeInDebugMode'),
          enableLogging: any(named: 'enableLogging'),
          iosAppId: any(named: 'iosAppId'),
          androidPackageId: any(named: 'androidPackageId'),
        )).thenAnswer((_) async => const UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '2.0.0',
          status: UpdateStatus.soft,
        ));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FlUpdaterWrapper(
          enabled: true,
          clearSnoozeInDebugMode: true,
          remoteConfigService: mockRemoteConfigService,
          snoozeStore: snoozeStore,
          child: child!,
        ),
        home: const Scaffold(body: Text('child content')),
      ),
    );
    await tester.pumpAndSettle();

    expect(await snoozeStore.isSnoozed('2.0.0'), isFalse);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets(
      'enabled: false disables all functionality (no check, no clearSnoozeInDebugMode, no realtime listener)',
      (
    tester,
  ) async {
    final snoozeStore = FlUpdaterSnoozeStore();
    await snoozeStore.snooze('2.0.0', const Duration(days: 3));
    expect(await snoozeStore.isSnoozed('2.0.0'), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FlUpdaterWrapper(
          enabled: false,
          clearSnoozeInDebugMode: true,
          remoteConfigService: mockRemoteConfigService,
          snoozeStore: snoozeStore,
          child: child!,
        ),
        home: const Scaffold(body: Text('child content')),
      ),
    );
    await tester.pumpAndSettle();

    // enabled takes first precedence: the wrapper never even calls into
    // RemoteConfigService.checkForUpdate, so clearSnoozeInDebugMode's
    // pre-clear (which runs before that call) never happens either, and
    // the real-time listener is never set up.
    expect(await snoozeStore.isSnoozed('2.0.0'), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    verifyNever(() => mockRemoteConfigService.checkForUpdate(
          snoozeDuration: any(named: 'snoozeDuration'),
          minimumFetchInterval: any(named: 'minimumFetchInterval'),
          enabled: any(named: 'enabled'),
          enableLogging: any(named: 'enableLogging'),
          iosAppId: any(named: 'iosAppId'),
          androidPackageId: any(named: 'androidPackageId'),
        ));
    verifyNever(() => mockRemoteConfigService.listenForUpdates(
          any(),
          enableLogging: any(named: 'enableLogging'),
        ));
  });

  testWidgets(
      'toggling enabled to false at runtime tears down the active realtime listener',
      (
    tester,
  ) async {
    final controller = StreamController<RemoteConfigUpdate>.broadcast();
    addTearDown(controller.close);

    when(() => mockRemoteConfigService.listenForUpdates(
          any(),
          enableLogging: any(named: 'enableLogging'),
        )).thenAnswer((invocation) => controller.stream.listen((_) {}));
    when(() => mockRemoteConfigService.checkForUpdate(
          snoozeDuration: any(named: 'snoozeDuration'),
          minimumFetchInterval: any(named: 'minimumFetchInterval'),
          enabled: any(named: 'enabled'),
          enableLogging: any(named: 'enableLogging'),
          iosAppId: any(named: 'iosAppId'),
          androidPackageId: any(named: 'androidPackageId'),
        )).thenAnswer((_) async => const UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '1.0.0',
          status: UpdateStatus.none,
        ));

    var enabled = true;
    late StateSetter setState;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setter) {
          setState = setter;
          return MaterialApp(
            builder: (context, child) => FlUpdaterWrapper(
              enabled: enabled,
              remoteConfigService: mockRemoteConfigService,
              child: child!,
            ),
            home: const Scaffold(body: Text('child content')),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.hasListener, isTrue);

    setState(() => enabled = false);
    await tester.pumpAndSettle();

    expect(controller.hasListener, isFalse);
  });

  testWidgets(
      'triggers update check immediately when real-time config update is received',
      (
    tester,
  ) async {
    Future<void> Function()? updateCallback;
    when(() => mockRemoteConfigService.listenForUpdates(
          any(),
          enableLogging: any(named: 'enableLogging'),
        )).thenAnswer((invocation) {
      updateCallback =
          invocation.positionalArguments[0] as Future<void> Function();
      return null;
    });

    when(() => mockRemoteConfigService.checkForUpdate(
          snoozeDuration: any(named: 'snoozeDuration'),
          minimumFetchInterval: any(named: 'minimumFetchInterval'),
          enabled: any(named: 'enabled'),
          clearSnoozeInDebugMode: any(named: 'clearSnoozeInDebugMode'),
          enableLogging: any(named: 'enableLogging'),
          iosAppId: any(named: 'iosAppId'),
          androidPackageId: any(named: 'androidPackageId'),
        )).thenAnswer((_) async => const UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '1.0.0',
          status: UpdateStatus.none,
        ));

    final snoozeStore = FlUpdaterSnoozeStore();
    await snoozeStore.snooze('2.0.0', const Duration(days: 3));
    expect(await snoozeStore.isSnoozed('2.0.0'), isTrue);

    when(() => mockRemoteConfigService.evaluateActiveConfig(
          iosAppId: any(named: 'iosAppId'),
          androidPackageId: any(named: 'androidPackageId'),
          clearSnooze: any(named: 'clearSnooze'),
          enableLogging: any(named: 'enableLogging'),
        )).thenAnswer((_) async => const UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '2.0.0',
          status: UpdateStatus.soft,
        ));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FlUpdaterWrapper(
          enabled: true,
          remoteConfigService: mockRemoteConfigService,
          snoozeStore: snoozeStore,
          child: child!,
        ),
        home: const Scaffold(body: Text('child content')),
      ),
    );
    await tester.pumpAndSettle();

    // Initial check: no update available
    expect(find.byType(AlertDialog), findsNothing);
    expect(updateCallback, isNotNull);

    // Real-time update arrives from Firebase Console
    unawaited(updateCallback!());
    await tester.pumpAndSettle();

    // Snooze should be cleared by real-time update
    expect(await snoozeStore.isSnoozed('2.0.0'), isFalse);

    // Re-check evaluated active config immediately and presented the dialog
    verify(() => mockRemoteConfigService.evaluateActiveConfig(
          iosAppId: any(named: 'iosAppId'),
          androidPackageId: any(named: 'androidPackageId'),
          clearSnooze: true,
          enableLogging: any(named: 'enableLogging'),
        )).called(1);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
