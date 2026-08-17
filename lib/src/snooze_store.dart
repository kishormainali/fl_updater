import 'package:shared_preferences/shared_preferences.dart';

class FlUpdaterSnoozeStore {
  static const _versionKey = 'fl_updater_snoozed_version';
  static const _untilKey = 'fl_updater_snoozed_until';

  Future<void> snooze(String version, Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    await prefs.setString(_versionKey, version);
    await prefs.setInt(_untilKey, until);
  }

  Future<bool> isSnoozed(String version) async {
    final prefs = await SharedPreferences.getInstance();
    final snoozedVersion = prefs.getString(_versionKey);
    final until = prefs.getInt(_untilKey);
    if (snoozedVersion == null || until == null) return false;
    if (snoozedVersion != version) return false;
    return DateTime.now().millisecondsSinceEpoch < until;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_versionKey);
    await prefs.remove(_untilKey);
  }
}
