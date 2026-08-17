import Flutter
import UIKit
import StoreKit

public class FlUpdaterPlugin: NSObject, FlutterPlugin, SKStoreProductViewControllerDelegate {
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

    guard let itunesId = Int(appId) else {
      openStoreWebFallback(appId: appId, result: result)
      return
    }

    guard let rootViewController = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
      .first(where: { $0.isKeyWindow })?.rootViewController else {
      openStoreWebFallback(appId: appId, result: result)
      return
    }

    let storeViewController = SKStoreProductViewController()
    storeViewController.delegate = self
    let parameters = [SKStoreProductParameterITunesItemIdentifier: NSNumber(value: itunesId)]
    storeViewController.loadProduct(withParameters: parameters) { [weak self] success, _ in
      DispatchQueue.main.async {
        if success {
          rootViewController.present(storeViewController, animated: true)
          result(nil)
        } else {
          self?.openStoreWebFallback(appId: appId, result: result)
        }
      }
    }
  }

  private func openStoreWebFallback(appId: String, result: @escaping FlutterResult) {
    guard let webUrl = URL(string: "https://apps.apple.com/app/id\(appId)") else {
      result(FlutterError(code: "CANNOT_OPEN", message: "Could not open App Store", details: nil))
      return
    }
    UIApplication.shared.open(webUrl, options: [:]) { opened in
      if opened {
        result(nil)
      } else {
        result(FlutterError(code: "CANNOT_OPEN", message: "Could not open App Store", details: nil))
      }
    }
  }

  public func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
    viewController.dismiss(animated: true, completion: nil)
  }
}
