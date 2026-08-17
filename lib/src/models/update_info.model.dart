import 'update_status.dart';
import '../utils/version_comparator.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.status,
    this.iosAppId,
    this.androidPackageId,
  });

  factory UpdateInfo.fromRemoteConfigValues({
    required Map<String, String> values,
    required String currentVersion,
    String? iosAppId,
    String? androidPackageId,
  }) {
    final rawLatest = values['fl_updater_latest_version'];
    final latestVersion = (rawLatest != null && rawLatest.isNotEmpty) ? rawLatest : currentVersion;

    final rawMin = values['fl_updater_min_version'];
    final minVersion = (rawMin != null && rawMin.isNotEmpty) ? rawMin : '0.0.0';

    final status = VersionComparator.compare(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      minVersion: minVersion,
    );

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      status: status,
      iosAppId: (iosAppId == null || iosAppId.isEmpty) ? null : iosAppId,
      androidPackageId: (androidPackageId == null || androidPackageId.isEmpty) ? null : androidPackageId,
    );
  }

  final String currentVersion;
  final String latestVersion;
  final UpdateStatus status;
  final String? iosAppId;
  final String? androidPackageId;

  UpdateInfo copyWith({UpdateStatus? status}) {
    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      status: status ?? this.status,
      iosAppId: iosAppId,
      androidPackageId: androidPackageId,
    );
  }

  @override
  int get hashCode => Object.hash(currentVersion, latestVersion, status, iosAppId, androidPackageId);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateInfo &&
        other.currentVersion == currentVersion &&
        other.latestVersion == latestVersion &&
        other.status == status &&
        other.iosAppId == iosAppId &&
        other.androidPackageId == androidPackageId;
  }

  @override
  String toString() {
    return 'UpdateInfo(currentVersion: $currentVersion, latestVersion: $latestVersion, '
        'status: $status, iosAppId: $iosAppId, androidPackageId: $androidPackageId)';
  }
}
