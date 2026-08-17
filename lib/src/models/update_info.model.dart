import 'update_status.dart';
import '../utils/version_comparator.dart';

/// Represents the update evaluation result for an application.
class UpdateInfo {
  /// Creates an [UpdateInfo] instance.
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.status,
    this.iosAppId,
    this.androidPackageId,
  });

  /// Constructs an [UpdateInfo] by comparing [currentVersion] against the
  /// Firebase Remote Config values in [values].
  ///
  /// Expected keys in [values]:
  /// - `'fl_updater_latest_version'`: The latest published version (e.g. `'2.1.0'`).
  /// - `'fl_updater_min_version'`: The minimum required version below which an update is forced (e.g. `'1.5.0'`).
  factory UpdateInfo.fromRemoteConfigValues({
    required Map<String, String> values,
    required String currentVersion,
    String? iosAppId,
    String? androidPackageId,
  }) {
    final rawLatest = values['fl_updater_latest_version'];
    final latestVersion = (rawLatest != null && rawLatest.isNotEmpty)
        ? rawLatest
        : currentVersion;

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
      androidPackageId: (androidPackageId == null || androidPackageId.isEmpty)
          ? null
          : androidPackageId,
    );
  }

  /// The currently installed version of the application.
  final String currentVersion;

  /// The latest available version retrieved from Remote Config.
  final String latestVersion;

  /// The determined update requirement status ([UpdateStatus.none],
  /// [UpdateStatus.soft], or [UpdateStatus.force]).
  final UpdateStatus status;

  /// The iOS App Store numeric identifier.
  final String? iosAppId;

  /// The Android Google Play Store application package identifier.
  final String? androidPackageId;

  /// Creates a copy of this [UpdateInfo] with updated fields.
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
  int get hashCode => Object.hash(
      currentVersion, latestVersion, status, iosAppId, androidPackageId);

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
