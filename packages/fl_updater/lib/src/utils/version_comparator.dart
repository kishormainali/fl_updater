import '../models/update_status.dart';

class VersionComparator {
  const VersionComparator._();

  static UpdateStatus compare({
    required String currentVersion,
    required String latestVersion,
    required String minVersion,
  }) {
    if (_isLower(currentVersion, minVersion)) {
      return UpdateStatus.force;
    }
    if (_isLower(currentVersion, latestVersion)) {
      return UpdateStatus.soft;
    }
    return UpdateStatus.none;
  }

  static bool _isLower(String a, String b) {
    final partsA = _parse(a);
    final partsB = _parse(b);
    final length =
        partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < length; i++) {
      final valueA = i < partsA.length ? partsA[i] : 0;
      final valueB = i < partsB.length ? partsB[i] : 0;
      if (valueA != valueB) return valueA < valueB;
    }
    return false;
  }

  /// Parses a version in `MAJOR.MINOR.PATCH` form, optionally suffixed with
  /// a build number as `+BUILD` (e.g. `1.0.0+10`, matching the format
  /// `flutter`'s own `pubspec.yaml` `version:` field uses). The build number,
  /// when present, is appended as a final segment so two versions with
  /// otherwise-equal semantic parts are still ordered by build number.
  static List<int> _parse(String version) {
    final buildSeparator = version.indexOf('+');
    final semanticPart =
        buildSeparator == -1 ? version : version.substring(0, buildSeparator);
    final buildPart =
        buildSeparator == -1 ? null : version.substring(buildSeparator + 1);

    final parts = semanticPart
        .split('.')
        .map((segment) => int.tryParse(segment) ?? 0)
        .toList();

    if (buildPart != null) {
      parts.add(int.tryParse(buildPart) ?? 0);
    }

    return parts;
  }
}
