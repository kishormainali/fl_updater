import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'fl_updater_method_channel.dart';

abstract class FlUpdaterPlatform extends PlatformInterface {
  /// Constructs a FlUpdaterPlatform.
  FlUpdaterPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlUpdaterPlatform _instance = MethodChannelFlUpdater();

  /// The default instance of [FlUpdaterPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlUpdater].
  static FlUpdaterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlUpdaterPlatform] when
  /// they register themselves.
  static set instance(FlUpdaterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Opens the app store page for the app with the given [appId].
  Future<void> openAppStore(String appId) {
    throw UnimplementedError('openAppStore() has not been implemented.');
  }

  /// Opens the Google Play Store page for the app
  Future<void> openGooglePlayStore() {
    throw UnimplementedError('openGooglePlayStore() has not been implemented.');
  }
}
