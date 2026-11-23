import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:fl_updater/fl_updater.dart';
import 'package:fp_logger/fp_logger.dart';

/// Reads the `fl_updater_config` JSON parameter from Firebase Remote Config
/// and forwards real-time updates.
class FirebaseConfigProvider implements FlUpdaterConfigProvider {
  FirebaseConfigProvider({FirebaseRemoteConfig? remoteConfig})
      : _provided = remoteConfig;

  // Resolved lazily so constructing the provider never touches
  // FirebaseRemoteConfig.instance until it is actually used.
  final FirebaseRemoteConfig? _provided;
  FirebaseRemoteConfig get _rc => _provided ?? FirebaseRemoteConfig.instance;

  static const _configKey = 'fl_updater_config';
  static const _logTag = 'fl_updater_firebase';

  @override
  Future<String?> fetch({
    Duration minimumFetchInterval = const Duration(hours: 1),
  }) async {
    await _rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: minimumFetchInterval,
    ));
    await _rc.setDefaults(const {_configKey: '{}'});
    await _rc.fetchAndActivate();
    return _rc.getString(_configKey);
  }

  @override
  Future<String?> current() async => _rc.getString(_configKey);

  /// Emits after the updated config has been activated. Events for other
  /// keys are ignored; an empty `updatedKeys` (whole-template update) counts.
  ///
  /// Built from `where`/`asyncMap` rather than an `async*` generator: cancelling
  /// a generator blocked on its source stream hangs until the next event.
  @override
  Stream<void> get changes => _rc.onConfigUpdated
          .where((event) =>
              event.updatedKeys.isEmpty ||
              event.updatedKeys.contains(_configKey))
          .asyncMap((_) async {
        try {
          await _rc.activate();
        } catch (error, stackTrace) {
          if (FlUpdater.enableLogging) {
            Logger.e(
              'Failed to activate real-time Remote Config update: $error',
              error: error,
              stackTrace: stackTrace,
              tag: _logTag,
            );
          }
        }
      });
}
