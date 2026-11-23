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

    test('treats a malformed current version as very old (soft, not force)',
        () {
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

    test('returns none when current and latest have the same version+build',
        () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0+10',
        latestVersion: '1.0.0+10',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.none);
    });

    test(
        'returns soft when only the build number is newer for an equal semantic version',
        () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0+9',
        latestVersion: '1.0.0+10',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.soft);
    });

    test('returns force when only the build number is below min', () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0+5',
        latestVersion: '1.0.0+10',
        minVersion: '1.0.0+10',
      );
      expect(status, UpdateStatus.force);
    });

    test('semantic version segments still take precedence over build number',
        () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0+999',
        latestVersion: '1.1.0+1',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.soft); // 1.1.0 > 1.0.0 regardless of build
    });

    test('treats a missing build number as build 0', () {
      final status = VersionComparator.compare(
        currentVersion: '1.0.0',
        latestVersion: '1.0.0+1',
        minVersion: '0.0.0',
      );
      expect(status, UpdateStatus.soft);
    });
  });
}
