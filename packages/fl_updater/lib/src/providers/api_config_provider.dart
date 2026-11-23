import 'config_provider.dart';

/// Provider backed by a user-supplied async callback, e.g.
/// `ApiConfigProvider(fetch: () async => (await dio.get<String>(url)).data!)`.
/// If your client decodes JSON into a `Map`, return `jsonEncode(map)` — a
/// non-String result throws and the check silently yields no update.
///
/// The callback must return the `fl_updater_config` JSON string. No push
/// support: the config is re-fetched on each update check.
class ApiConfigProvider implements FlUpdaterConfigProvider {
  ApiConfigProvider({required Future<String> Function() fetch})
      : _fetch = fetch;

  final Future<String> Function() _fetch;
  String? _cached;

  @override
  Future<String?> fetch({
    Duration minimumFetchInterval = const Duration(hours: 1),
  }) async =>
      _cached = await _fetch();

  @override
  Future<String?> current() async => _cached;

  @override
  Stream<void>? get changes => null;
}
