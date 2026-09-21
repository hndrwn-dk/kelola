import Flutter
import LocalAuthentication
import UIKit

public class AppLockPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.tursinalabs.kelola/app_lock",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(AppLockPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "canAuthenticate":
      result(canAuthenticate())
    case "authenticate":
      authenticate(result: result)
    case "setSecure":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func canAuthenticate() -> Bool {
    let context = LAContext()
    var error: NSError?
    return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
  }

  private func authenticate(result: @escaping FlutterResult) {
    let context = LAContext()
    context.evaluatePolicy(
      .deviceOwnerAuthentication,
      localizedReason: "Unlock to open the inventory"
    ) { success, error in
      DispatchQueue.main.async {
        if success {
          result(true)
          return
        }
        let code = (error as? LAError)?.code
        if code == .userCancel || code == .appCancel || code == .systemCancel {
          result(false)
          return
        }
        result(
          FlutterError(
            code: "unavailable",
            message: error?.localizedDescription,
            details: nil
          )
        )
      }
    }
  }
}
