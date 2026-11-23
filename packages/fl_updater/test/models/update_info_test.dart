import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/src/models/update_info.model.dart';
import 'package:fl_updater/src/models/update_status.dart';

void main() {
  group('UpdateInfo.fromRemoteConfigJson', () {
    test('returns status none when current equals latest', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: '{"latest_version": "1.0.0", "min_version": "0.0.0"}',
        currentVersion: '1.0.0',
      );

      expect(info.status, UpdateStatus.none);
      expect(info.latestVersion, '1.0.0');
    });

    test('returns status soft when a newer version is available', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: '{"latest_version": "1.2.0", "min_version": "0.0.0"}',
        currentVersion: '1.0.0',
      );

      expect(info.status, UpdateStatus.soft);
    });

    test('returns status force when current is below min version', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: '{"latest_version": "2.0.0", "min_version": "1.5.0"}',
        currentVersion: '1.0.0',
      );

      expect(info.status, UpdateStatus.force);
    });

    test('falls back to currentVersion and 0.0.0 when json is null', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: null,
        currentVersion: '1.0.0',
      );

      expect(info.latestVersion, '1.0.0');
      expect(info.status, UpdateStatus.none);
    });

    test('falls back to currentVersion and 0.0.0 when json is empty', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: '{}',
        currentVersion: '1.0.0',
      );

      expect(info.latestVersion, '1.0.0');
      expect(info.status, UpdateStatus.none);
    });

    test('falls back to currentVersion and 0.0.0 when json is malformed', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: 'not valid json',
        currentVersion: '1.0.0',
      );

      expect(info.latestVersion, '1.0.0');
      expect(info.status, UpdateStatus.none);
    });

    test('passes through caller-supplied iosAppId and androidPackageId as-is',
        () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: '{"latest_version": "1.0.0"}',
        currentVersion: '1.0.0',
        iosAppId: '123456789',
        androidPackageId: 'com.example.app',
      );

      expect(info.iosAppId, '123456789');
      expect(info.androidPackageId, 'com.example.app');
    });

    test('iosAppId and androidPackageId default to null when omitted', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: '{"latest_version": "1.0.0"}',
        currentVersion: '1.0.0',
      );

      expect(info.iosAppId, isNull);
      expect(info.androidPackageId, isNull);
    });

    test('treats caller-supplied empty string ids as null', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: '{"latest_version": "1.0.0"}',
        currentVersion: '1.0.0',
        iosAppId: '',
        androidPackageId: '',
      );

      expect(info.iosAppId, isNull);
      expect(info.androidPackageId, isNull);
    });

    test('parses top-level latest_version and min_version fields', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: '{"latest_version": "2.5.0", "min_version": "2.0.0"}',
        currentVersion: '1.8.0',
        androidPackageId: 'com.example.android',
      );

      expect(info.latestVersion, '2.5.0');
      expect(info.status, UpdateStatus.force); // 1.8.0 < 2.0.0
      expect(info.androidPackageId, 'com.example.android');
    });

    test('uses the flavor entry when it fully overrides both fields', () {
      const json = '''
      {
        "latest_version": "1.0.0",
        "min_version": "1.0.0",
        "flavors": {
          "staging": {"latest_version": "3.0.0", "min_version": "2.8.0"}
        }
      }
      ''';

      final info = UpdateInfo.fromRemoteConfigJson(
        json: json,
        currentVersion: '2.9.0',
        flavor: 'staging',
      );

      expect(info.latestVersion, '3.0.0');
      expect(info.status, UpdateStatus.soft); // 2.9.0 >= 2.8.0 but < 3.0.0
    });

    test(
        'falls back per-field to the top-level value when the flavor entry only overrides one field',
        () {
      const json = '''
      {
        "latest_version": "1.0.0",
        "min_version": "5.0.0",
        "flavors": {
          "staging": {"latest_version": "9.9.9"}
        }
      }
      ''';

      final info = UpdateInfo.fromRemoteConfigJson(
        json: json,
        currentVersion: '1.0.0',
        flavor: 'staging',
      );

      // latest_version comes from the flavor entry...
      expect(info.latestVersion, '9.9.9');
      // ...but min_version isn't in the flavor entry, so it falls back to
      // the top-level 5.0.0, forcing an update.
      expect(info.status, UpdateStatus.force);
    });

    test('falls back to top-level values when flavor has no matching entry',
        () {
      const json = '''
      {
        "latest_version": "1.2.0",
        "min_version": "0.0.0",
        "flavors": {
          "staging": {"latest_version": "9.9.9"}
        }
      }
      ''';

      final info = UpdateInfo.fromRemoteConfigJson(
        json: json,
        currentVersion: '1.0.0',
        flavor: 'production',
      );

      expect(info.latestVersion, '1.2.0');
      expect(info.status, UpdateStatus.soft);
    });

    test(
        'falls back to top-level values when the "flavors" key is entirely absent '
        'from the JSON, even though a flavor is passed', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: '{"latest_version": "1.2.0", "min_version": "1.0.0"}',
        currentVersion: '1.0.0',
        flavor: 'production',
      );

      expect(info.latestVersion, '1.2.0');
      expect(info.status, UpdateStatus.soft); // 1.0.0 >= min, but < latest
    });

    test('falls back to top-level values when flavor is null', () {
      const json = '''
      {
        "latest_version": "1.2.0",
        "min_version": "0.0.0",
        "flavors": {
          "staging": {"latest_version": "9.9.9"}
        }
      }
      ''';

      final info = UpdateInfo.fromRemoteConfigJson(
        json: json,
        currentVersion: '1.0.0',
      );

      expect(info.latestVersion, '1.2.0');
    });

    test('uses the platform entry when one matches', () {
      const json = '''
      {
        "latest_version": "1.0.0",
        "min_version": "1.0.0",
        "platforms": {
          "android": {"latest_version": "2.0.0", "min_version": "1.5.0"}
        }
      }
      ''';

      final info = UpdateInfo.fromRemoteConfigJson(
        json: json,
        currentVersion: '1.0.0',
        platform: 'android',
      );

      expect(info.latestVersion, '2.0.0');
      expect(info.status, UpdateStatus.force); // 1.0.0 < min 1.5.0
    });

    test('falls back to top-level values when platform has no matching entry',
        () {
      const json = '''
      {
        "latest_version": "1.2.0",
        "min_version": "0.0.0",
        "platforms": {
          "android": {"latest_version": "9.9.9"}
        }
      }
      ''';

      final info = UpdateInfo.fromRemoteConfigJson(
        json: json,
        currentVersion: '1.0.0',
        platform: 'ios',
      );

      expect(info.latestVersion, '1.2.0');
    });

    test(
        'falls back to top-level values when the "platforms" key is entirely absent '
        'from the JSON, even though a platform is passed', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: '{"latest_version": "1.2.0", "min_version": "1.0.0"}',
        currentVersion: '1.0.0',
        platform: 'android',
      );

      expect(info.latestVersion, '1.2.0');
      expect(info.status, UpdateStatus.soft); // 1.0.0 >= min, but < latest
    });

    test(
        'falls back to top-level values when both "flavors" and "platforms" keys '
        'are absent, even though both a flavor and platform are passed', () {
      final info = UpdateInfo.fromRemoteConfigJson(
        json: '{"latest_version": "1.2.0", "min_version": "1.0.0"}',
        currentVersion: '1.0.0',
        flavor: 'production',
        platform: 'android',
      );

      expect(info.latestVersion, '1.2.0');
      expect(info.status, UpdateStatus.soft); // 1.0.0 >= min, but < latest
    });

    test(
        'the platform+flavor combo takes precedence over platform-only, flavor-only, and top-level',
        () {
      const json = '''
      {
        "latest_version": "0.0.0",
        "min_version": "0.0.0",
        "flavors": {
          "staging": {"latest_version": "1.0.0"}
        },
        "platforms": {
          "android": {
            "latest_version": "2.0.0",
            "flavors": {
              "staging": {"latest_version": "3.0.0"}
            }
          }
        }
      }
      ''';

      final info = UpdateInfo.fromRemoteConfigJson(
        json: json,
        currentVersion: '1.0.0',
        flavor: 'staging',
        platform: 'android',
      );

      expect(info.latestVersion, '3.0.0');
    });

    test(
        'falls back to the platform-only value when the platform has no matching flavor entry',
        () {
      const json = '''
      {
        "latest_version": "0.0.0",
        "flavors": {
          "staging": {"latest_version": "1.0.0"}
        },
        "platforms": {
          "android": {"latest_version": "2.0.0"}
        }
      }
      ''';

      final info = UpdateInfo.fromRemoteConfigJson(
        json: json,
        currentVersion: '1.0.0',
        flavor: 'staging',
        platform: 'android',
      );

      // platforms.android has no "flavors.staging" entry, and platforms.android
      // itself sets latest_version, so that wins over the top-level flavors.staging.
      expect(info.latestVersion, '2.0.0');
    });

    test(
        'falls back to the top-level flavor value when the platform entry does not set the field',
        () {
      const json = '''
      {
        "latest_version": "0.0.0",
        "flavors": {
          "staging": {"latest_version": "1.0.0"}
        },
        "platforms": {
          "android": {"min_version": "0.5.0"}
        }
      }
      ''';

      final info = UpdateInfo.fromRemoteConfigJson(
        json: json,
        currentVersion: '1.0.0',
        flavor: 'staging',
        platform: 'android',
      );

      // platforms.android doesn't set latest_version at all, so it falls
      // through to flavors.staging.latest_version.
      expect(info.latestVersion, '1.0.0');
    });
  });

  group('UpdateInfo.fromTemplateJson', () {
    test('reads the fl_updater_config parameter default value', () {
      final template = {
        'parameters': {
          'fl_updater_config': {
            'defaultValue': {
              'value': '{"latest_version": "2.5.0", "min_version": "2.0.0"}'
            },
            'valueType': 'STRING'
          }
        }
      };

      final info = UpdateInfo.fromTemplateJson(
        template: template,
        currentVersion: '1.8.0',
      );

      expect(info.latestVersion, '2.5.0');
      expect(info.status, UpdateStatus.force); // 1.8.0 < 2.0.0
    });

    test('applies the flavors fallback the same way as fromRemoteConfigJson',
        () {
      final template = {
        'parameters': {
          'fl_updater_config': {
            'defaultValue': {
              'value': '{"latest_version": "1.0.0", "min_version": "1.0.0", '
                  '"flavors": {"staging": {"latest_version": "3.0.0", "min_version": "2.8.0"}}}'
            },
            'valueType': 'STRING'
          }
        }
      };

      final info = UpdateInfo.fromTemplateJson(
        template: template,
        currentVersion: '2.9.0',
        flavor: 'staging',
      );

      expect(info.latestVersion, '3.0.0');
      expect(info.status, UpdateStatus.soft);
    });

    test('applies the platforms fallback the same way as fromRemoteConfigJson',
        () {
      final template = {
        'parameters': {
          'fl_updater_config': {
            'defaultValue': {
              'value': '{"latest_version": "1.0.0", '
                  '"platforms": {"android": {"latest_version": "2.5.0"}}}'
            },
            'valueType': 'STRING'
          }
        }
      };

      final info = UpdateInfo.fromTemplateJson(
        template: template,
        currentVersion: '1.0.0',
        platform: 'android',
      );

      expect(info.latestVersion, '2.5.0');
    });

    test(
        'falls back to currentVersion and 0.0.0 when the parameter has useInAppDefault: true',
        () {
      final template = {
        'parameters': {
          'fl_updater_config': {
            'defaultValue': {'useInAppDefault': true},
            'valueType': 'STRING'
          }
        }
      };

      final info = UpdateInfo.fromTemplateJson(
        template: template,
        currentVersion: '1.0.0',
      );

      expect(info.status, UpdateStatus.none);
    });

    test(
        'falls back to currentVersion and 0.0.0 when the fl_updater_config parameter is absent',
        () {
      final info = UpdateInfo.fromTemplateJson(
        template: const {'parameters': <String, dynamic>{}},
        currentVersion: '1.0.0',
      );

      expect(info.latestVersion, '1.0.0');
      expect(info.status, UpdateStatus.none);
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
