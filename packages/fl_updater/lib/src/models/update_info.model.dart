import 'dart:convert';

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

  /// Constructs an [UpdateInfo] from the raw `fl_updater_config` Remote Config
  /// parameter value in [json] — a JSON object shaped like:
  /// ```json
  /// {
  ///   "min_version": "1.0.0",
  ///   "latest_version": "1.0.0",
  ///   "flavors": {
  ///     "staging": { "min_version": "1.1.0", "latest_version": "1.1.0" }
  ///   },
  ///   "platforms": {
  ///     "android": {
  ///       "min_version": "1.0.1",
  ///       "latest_version": "1.0.1",
  ///       "flavors": {
  ///         "staging": { "min_version": "1.1.1", "latest_version": "1.1.1" }
  ///       }
  ///     }
  ///   }
  /// }
  /// ```
  /// `min_version`/`latest_version` are each resolved independently, most
  /// specific first: `platforms[platform].flavors[flavor]`, then
  /// `platforms[platform]`, then `flavors[flavor]`, then the top-level field.
  factory UpdateInfo.fromRemoteConfigJson({
    required String? json,
    required String currentVersion,
    String? flavor,
    String? platform,
    String? iosAppId,
    String? androidPackageId,
  }) {
    final versions = _extractVersions(
      root: _decodeConfig(json),
      currentVersion: currentVersion,
      flavor: flavor,
      platform: platform,
    );

    final status = VersionComparator.compare(
      currentVersion: currentVersion,
      latestVersion: versions.latestVersion,
      minVersion: versions.minVersion,
    );

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: versions.latestVersion,
      status: status,
      iosAppId: (iosAppId == null || iosAppId.isEmpty) ? null : iosAppId,
      androidPackageId: (androidPackageId == null || androidPackageId.isEmpty)
          ? null
          : androidPackageId,
    );
  }

  /// Constructs an [UpdateInfo] from a Firebase Remote Config template JSON
  /// (e.g. exported from the Firebase Console containing "conditions" and
  /// "parameters"), reading the `fl_updater_config` parameter's default value
  /// as the same JSON object documented on [fromRemoteConfigJson].
  factory UpdateInfo.fromTemplateJson({
    required Map<String, dynamic> template,
    required String currentVersion,
    String? flavor,
    String? platform,
    String? iosAppId,
    String? androidPackageId,
  }) {
    final parameters = template['parameters'];
    final paramsMap = (parameters is Map) ? parameters : <dynamic, dynamic>{};

    String? rawJson;
    final param = paramsMap['fl_updater_config'];
    if (param is Map) {
      final defaultValue = param['defaultValue'];
      if (defaultValue is Map && defaultValue['useInAppDefault'] != true) {
        final val = defaultValue['value'];
        if (val is String && val.trim().isNotEmpty) rawJson = val;
      }
    }

    final versions = _extractVersions(
      root: _decodeConfig(rawJson),
      currentVersion: currentVersion,
      flavor: flavor,
      platform: platform,
    );

    final status = VersionComparator.compare(
      currentVersion: currentVersion,
      latestVersion: versions.latestVersion,
      minVersion: versions.minVersion,
    );

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: versions.latestVersion,
      status: status,
      iosAppId: (iosAppId == null || iosAppId.isEmpty) ? null : iosAppId,
      androidPackageId: (androidPackageId == null || androidPackageId.isEmpty)
          ? null
          : androidPackageId,
    );
  }

  static Map<String, dynamic> _decodeConfig(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(rawJson);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  static String? _stringField(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Looks up `parent[sectionKey][entryKey]` and returns it as a
  /// `Map<String, dynamic>`, or `null` if any step of that path is missing
  /// or not a map.
  static Map<String, dynamic>? _mapEntry(
    Map<String, dynamic> parent,
    String sectionKey,
    String? entryKey,
  ) {
    if (entryKey == null || entryKey.isEmpty) return null;
    final section = parent[sectionKey];
    if (section is! Map) return null;
    final entry = section[entryKey];
    if (entry is! Map) return null;
    return Map<String, dynamic>.from(entry);
  }

  static ({String latestVersion, String minVersion}) _extractVersions({
    required Map<String, dynamic> root,
    required String currentVersion,
    String? flavor,
    String? platform,
  }) {
    final platformMap = _mapEntry(root, 'platforms', platform);
    final platformFlavorMap =
        platformMap != null ? _mapEntry(platformMap, 'flavors', flavor) : null;
    final flavorMap = _mapEntry(root, 'flavors', flavor);

    // Most specific first: platform+flavor, platform-only, flavor-only, then
    // the top-level fields as the ultimate fallback.
    final scopes = [platformFlavorMap, platformMap, flavorMap, root];

    String resolveField(String key, String fallback) {
      for (final scope in scopes) {
        final value = scope == null ? null : _stringField(scope, key);
        if (value != null) return value;
      }
      return fallback;
    }

    return (
      latestVersion: resolveField('latest_version', currentVersion),
      minVersion: resolveField('min_version', '0.0.0'),
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
