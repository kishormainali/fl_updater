import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/src/services/fl_updater_method_channel.dart';

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
