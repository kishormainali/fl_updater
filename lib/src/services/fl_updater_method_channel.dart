import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fl_updater_platform_interface.dart';

class MethodChannelFlUpdater extends FlUpdaterPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('com.kishormainali.fl_updater');

  @override
  Future<void> openStore({String? iosAppId, String? androidPackageId}) {
    return methodChannel.invokeMethod<void>('openStore', {
      'iosAppId': iosAppId,
      'androidPackageId': androidPackageId,
    });
  }
}
