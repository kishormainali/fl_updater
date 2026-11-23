/// Source of the raw `fl_updater_config` JSON (see `UpdateInfo.fromRemoteConfigJson`
/// for the schema). Implement this to plug in any backend.
abstract class FlUpdaterConfigProvider {
  /// Fetches (and activates, if the backend has such a concept) the latest
  /// config and returns its raw JSON. May throw; callers fall back to [current].
  Future<String?> fetch({
    Duration minimumFetchInterval = const Duration(hours: 1),
  });

  /// The last known config without hitting the network, or `null` if none.
  Future<String?> current();

  /// Push notifications that the config changed, or `null` when the backend
  /// does not support push. After an event, [current] returns the new config.
  Stream<void>? get changes;
}
