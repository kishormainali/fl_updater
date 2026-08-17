// test/version_comparator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/src/models/update_status.dart';
import 'package:fl_updater/src/utils/version_comparator.dart';

void main() {
  group('VersionComparator.compare', () {
    test('returns none when current equals latest', () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0',
        latestVersion: '1.0.0',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.none);
    });

    test('returns soft when a newer version is available', () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.soft);
    });

    test('returns soft (not force) when current equals min', () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        minVersion: '1.0.0',
      );
      expect(status, UpdateStatus.soft);
    });

    test('returns force when current is below min', () {
      final status = VersionComparator.compare(
        currentVersion: '0.9.0',
        latestVersion: '1.1.0',
        minVersion: '1.0.0',
      );
      expect(status, UpdateStatus.force);
    });

    test('treats missing version segments as zero', () {
      final status = VersionComparator.compare(
        currentVersion: '1.2',
        latestVersion: '1.2.0',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.none);
    });

    test('treats a malformed current version as very old (soft, not force)', () {
      final status = VersionComparator.compare(
        currentVersion: 'not-a-version',
        latestVersion: '1.0.0',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.soft);
    });

    test('treats a malformed latest version as not newer', () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0',
        latestVersion: 'not-a-version',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.none);
    });
  });
}
