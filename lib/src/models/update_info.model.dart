import 'package:flutter/foundation.dart';

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
  /// Firebase Remote Config values in [values] for `fl_updater_latest_version` and `fl_updater_min_version`.
  factory UpdateInfo.fromRemoteConfigValues({
    required Map<String, String> values,
    required String currentVersion,
    String? iosAppId,
    String? androidPackageId,
  }) {
    final rawLatest = values['fl_updater_latest_version']?.trim();
    final latestVersion = (rawLatest != null && rawLatest.isNotEmpty)
        ? rawLatest
        : currentVersion;

    final rawMin = values['fl_updater_min_version']?.trim();
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

  /// Constructs an [UpdateInfo] from a Firebase Remote Config template JSON
  /// (e.g. exported from the Firebase Console containing "conditions" and "parameters").
  factory UpdateInfo.fromTemplateJson({
    required Map<String, dynamic> template,
    required String currentVersion,
    TargetPlatform? platform,
    String? iosAppId,
    String? androidPackageId,
  }) {
    final targetPlatform = platform ?? defaultTargetPlatform;
    final conditionName = targetPlatform == TargetPlatform.iOS
        ? 'fl_updater_ios'
        : (targetPlatform == TargetPlatform.android
            ? 'fl_updater_android'
            : null);

    final parameters = template['parameters'];
    final paramsMap = (parameters is Map) ? parameters : <dynamic, dynamic>{};

    String? extractParamValue(String paramKey) {
      final param = paramsMap[paramKey];
      if (param is! Map) return null;

      if (conditionName != null) {
        final conditionalValues = param['conditionalValues'];
        if (conditionalValues is Map) {
          final condVal = conditionalValues[conditionName];
          if (condVal is Map) {
            if (condVal['useInAppDefault'] != true) {
              final val = condVal['value']?.toString().trim();
              if (val != null && val.isNotEmpty) return val;
            }
          }
        }
      }

      final defaultValue = param['defaultValue'];
      if (defaultValue is Map) {
        if (defaultValue['useInAppDefault'] != true) {
          final val = defaultValue['value']?.toString().trim();
          if (val != null && val.isNotEmpty) return val;
        }
      }
      return null;
    }

    final latestVersion =
        extractParamValue('fl_updater_latest_version') ?? currentVersion;
    final minVersion = extractParamValue('fl_updater_min_version') ?? '0.0.0';

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
