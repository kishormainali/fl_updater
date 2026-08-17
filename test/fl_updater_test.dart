import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/fl_updater.dart';
import 'package:fl_updater/src/fl_updater_platform_interface.dart';
import 'package:fl_updater/src/fl_updater_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlUpdaterPlatform
    with MockPlatformInterfaceMixin
    implements FlUpdaterPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlUpdaterPlatform initialPlatform = FlUpdaterPlatform.instance;

  test('$MethodChannelFlUpdater is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlUpdater>());
  });

  test('getPlatformVersion', () async {
    FlUpdater flUpdaterPlugin = FlUpdater();
    MockFlUpdaterPlatform fakePlatform = MockFlUpdaterPlatform();
    FlUpdaterPlatform.instance = fakePlatform;

    expect(await flUpdaterPlugin.getPlatformVersion(), '42');
  });
}
