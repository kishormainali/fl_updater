import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'fl_updater_method_channel.dart';

abstract class FlUpdaterPlatform extends PlatformInterface {
  FlUpdaterPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlUpdaterPlatform _instance = MethodChannelFlUpdater();

  static FlUpdaterPlatform get instance => _instance;

  static set instance(FlUpdaterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Opens the platform's app store page. On Android, [androidPackageId]
  /// defaults to the host app's own package name when omitted. On iOS,
  /// [iosAppId] must be provided — there is no on-device way to discover it.
  Future<void> openStore({String? iosAppId, String? androidPackageId}) {
    throw UnimplementedError('openStore() has not been implemented.');
  }
}
