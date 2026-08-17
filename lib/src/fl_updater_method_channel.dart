import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fl_updater_platform_interface.dart';

/// An implementation of [FlUpdaterPlatform] that uses method channels.
class MethodChannelFlUpdater extends FlUpdaterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('com.kishormainali.fl_updater');

  @override
  Future<void> openAppStore(String appId) {
    return methodChannel.invokeMethod('openAppStore', {'appId': appId});
  }

  @override
  Future<void> openGooglePlayStore() {
    return methodChannel.invokeMethod('openGooglePlayStore');
  }
}
