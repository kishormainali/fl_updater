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
