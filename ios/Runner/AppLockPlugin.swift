import Flutter
import LocalAuthentication
import UIKit

public class AppLockPlugin: NSObject, FlutterPlugin {
  private var secure = false
  private var privacyView: UIView?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.tursinalabs.kelola/app_lock",
      binaryMessenger: registrar.messenger()
    )
    let instance = AppLockPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.startObserving()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "canAuthenticate":
      result(canAuthenticate())
    case "authenticate":
      authenticate(result: result)
    case "setSecure":
      setSecure(call.arguments)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startObserving() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(willResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  private func setSecure(_ arguments: Any?) {
    let enabled: Bool
    if let args = arguments as? [String: Any], let value = args["secure"] as? Bool {
      enabled = value
    } else {
      enabled = false
    }
    secure = enabled
    if !enabled {
      hidePrivacy()
    }
  }

  @objc private func willResignActive() {
    if secure {
      showPrivacy()
    }
  }

  @objc private func didBecomeActive() {
    hidePrivacy()
  }

  private func showPrivacy() {
    guard privacyView == nil else { return }
    guard let window = keyWindow() else { return }
    let overlay = UIView(frame: window.bounds)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.backgroundColor = .black
    overlay.isUserInteractionEnabled = true
    overlay.accessibilityIdentifier = "kelola-privacy-overlay"
    window.addSubview(overlay)
    privacyView = overlay
  }

  private func hidePrivacy() {
    privacyView?.removeFromSuperview()
    privacyView = nil
  }

  private func keyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      if let key = scene.windows.first(where: { $0.isKeyWindow }) {
        return key
      }
    }
    return scenes.first?.windows.first
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
