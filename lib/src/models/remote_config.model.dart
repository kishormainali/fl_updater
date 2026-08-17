class RemoteConfig({
  required final String currentAppVersion,
  required final String latestAppVersion,
  required final String appStoreUrl,
  required final String playStoreUrl,
  required final bool isUpdateAvailable,
  required final bool isForceUpdate,
}) {
  @override
  int get hashCode => Object.hashAll([
    currentAppVersion,
    latestAppVersion,
    appStoreUrl,
    playStoreUrl,
    isUpdateAvailable,
    isForceUpdate,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RemoteConfig &&
        other.currentAppVersion == currentAppVersion &&
        other.latestAppVersion == latestAppVersion &&
        other.appStoreUrl == appStoreUrl &&
        other.playStoreUrl == playStoreUrl &&
        other.isUpdateAvailable == isUpdateAvailable &&
        other.isForceUpdate == isForceUpdate;
  }

  @override
  String toString() {
    return '''RemoteConfig(currentAppVersion: $currentAppVersion, 
    latestAppVersion: $latestAppVersion, 
    appStoreUrl: $appStoreUrl,
     playStoreUrl: $playStoreUrl, 
     isUpdateAvailable: $isUpdateAvailable, 
     isForceUpdate: $isForceUpdate)''';
  }
}
