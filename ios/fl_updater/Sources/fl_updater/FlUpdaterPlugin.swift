import Flutter
import UIKit

public class FlUpdaterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.kishormainali.fl_updater", binaryMessenger: registrar.messenger())
    let instance = FlUpdaterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "openStore":
      let args = call.arguments as? [String: Any]
      let iosAppId = args?["iosAppId"] as? String
      openStore(appId: iosAppId, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openStore(appId: String?, result: @escaping FlutterResult) {
    guard let appId = appId, !appId.isEmpty else {
      result(FlutterError(code: "MISSING_APP_ID", message: "iosAppId is required to open the App Store", details: nil))
      return
    }

    guard let storeUrl = URL(string: "itms-apps://itunes.apple.com/app/id\(appId)") else {
      result(FlutterError(code: "INVALID_URL", message: "Could not build store URL", details: nil))
      return
    }

    if UIApplication.shared.canOpenURL(storeUrl) {
      UIApplication.shared.open(storeUrl, options: [:]) { _ in result(nil) }
    } else if let webUrl = URL(string: "https://apps.apple.com/app/id\(appId)") {
      UIApplication.shared.open(webUrl, options: [:]) { _ in result(nil) }
    } else {
      result(FlutterError(code: "CANNOT_OPEN", message: "Could not open App Store", details: nil))
    }
  }
}
