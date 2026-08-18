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

  static List<int> _parse(String version) {
    return version
        .split('.')
        .map((segment) => int.tryParse(segment) ?? 0)
        .toList();
  }
}
