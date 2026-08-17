import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:fl_updater/fl_updater.dart';
import 'package:fl_updater/src/services/fl_updater_platform_interface.dart';
import 'package:fl_updater/src/services/fl_updater_method_channel.dart';
import 'package:fl_updater/src/services/snooze_store.dart';

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
