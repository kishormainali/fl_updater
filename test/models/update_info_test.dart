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
