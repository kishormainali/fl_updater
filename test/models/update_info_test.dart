import 'package:flutter/foundation.dart';
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

    test('passes through caller-supplied iosAppId and androidPackageId as-is',
        () {
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

    test('parses fl_updater_latest_version and fl_updater_min_version values',
        () {
      final info = UpdateInfo.fromRemoteConfigValues(
        values: const {
          'fl_updater_latest_version': '2.5.0',
          'fl_updater_min_version': '2.0.0',
        },
        currentVersion: '1.8.0',
        androidPackageId: 'com.example.android',
      );

      expect(info.latestVersion, '2.5.0');
      expect(info.status, UpdateStatus.force); // 1.8.0 < 2.0.0
      expect(info.androidPackageId, 'com.example.android');
    });

    test('parses fl_updater_latest_version with soft update status', () {
      final info = UpdateInfo.fromRemoteConfigValues(
        values: const {
          'fl_updater_latest_version': '3.0.0',
          'fl_updater_min_version': '2.8.0',
        },
        currentVersion: '2.9.0',
        iosAppId: '123456789',
      );

      expect(info.latestVersion, '3.0.0');
      expect(info.status, UpdateStatus.soft); // 2.9.0 >= 2.8.0 but < 3.0.0
      expect(info.iosAppId, '123456789');
    });

    test(
        'parses Firebase Console exported template JSON with conditions and conditionalValues',
        () {
      final template = {
        'conditions': [
          {
            'name': 'fl_updater_android',
            'expression': "device.os == 'android'",
            'tagColor': 'DEEP_ORANGE'
          },
          {
            'name': 'fl_updater_ios',
            'expression': "device.os == 'ios'",
            'tagColor': 'PINK'
          }
        ],
        'parameters': {
          'fl_updater_latest_version': {
            'defaultValue': {'value': '1.0.0'},
            'conditionalValues': {
              'fl_updater_android': {'value': '2.5.0'},
              'fl_updater_ios': {'value': '2.1.0'}
            },
            'description': 'Latest Version of the App',
            'valueType': 'STRING'
          },
          'fl_updater_min_version': {
            'defaultValue': {'useInAppDefault': true},
            'conditionalValues': {
              'fl_updater_android': {'value': '2.0.0'},
              'fl_updater_ios': {'value': '1.8.0'}
            },
            'valueType': 'STRING'
          }
        }
      };

      // Test Android evaluation
      final androidInfo = UpdateInfo.fromTemplateJson(
        template: template,
        currentVersion: '1.9.0',
        platform: TargetPlatform.android,
      );
      expect(androidInfo.latestVersion, '2.5.0');
      expect(androidInfo.status, UpdateStatus.force); // 1.9.0 < 2.0.0

      // Test iOS evaluation
      final iosInfo = UpdateInfo.fromTemplateJson(
        template: template,
        currentVersion: '1.9.0',
        platform: TargetPlatform.iOS,
      );
      expect(iosInfo.latestVersion, '2.1.0');
      expect(iosInfo.status, UpdateStatus.soft); // 1.9.0 >= 1.8.0 but < 2.1.0
    });

    test(
        'evaluates template JSON with useInAppDefault: true falling back to default or current',
        () {
      final userTemplate = {
        'conditions': [
          {
            'name': 'fl_updater_android',
            'expression': "device.os == 'android'",
            'tagColor': 'DEEP_ORANGE'
          },
          {
            'name': 'fl_updater_ios',
            'expression': "device.os == 'ios'",
            'tagColor': 'PINK'
          }
        ],
        'parameters': {
          'fl_updater_latest_version': {
            'defaultValue': {'value': '0.0.0'},
            'conditionalValues': {
              'fl_updater_android': {'useInAppDefault': true},
              'fl_updater_ios': {'useInAppDefault': true}
            },
            'description': 'Latest Version of the App',
            'valueType': 'STRING'
          },
          'fl_updater_min_version': {
            'defaultValue': {'useInAppDefault': true},
            'conditionalValues': {
              'fl_updater_android': {'useInAppDefault': true},
              'fl_updater_ios': {'useInAppDefault': true}
            },
            'valueType': 'STRING'
          }
        }
      };

      final infoAndroid = UpdateInfo.fromTemplateJson(
        template: userTemplate,
        currentVersion: '1.0.0',
        platform: TargetPlatform.android,
      );
      expect(infoAndroid.status, UpdateStatus.none);

      final infoIos = UpdateInfo.fromTemplateJson(
        template: userTemplate,
        currentVersion: '1.0.0',
        platform: TargetPlatform.iOS,
      );
      expect(infoIos.status, UpdateStatus.none);
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
