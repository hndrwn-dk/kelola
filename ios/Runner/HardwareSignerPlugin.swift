import Flutter
import Security
import UIKit

public class HardwareSignerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "labs.tursina.kelola/hardware_signer",
      binaryMessenger: registrar.messenger()
    )
    let instance = HardwareSignerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "generateKey":
      guard let alias = args?["alias"] as? String else {
        result(FlutterError(code: "bad_args", message: "alias required", details: nil))
        return
      }
      do {
        result(try generateKey(alias: alias))
      } catch {
        result(FlutterError(code: "generate_failed", message: error.localizedDescription, details: nil))
      }
    case "sign":
      guard let alias = args?["alias"] as? String,
            let data = args?["data"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "alias and data required", details: nil))
        return
      }
      do {
        result(try sign(alias: alias, data: data.data))
      } catch {
        result(FlutterError(code: "sign_failed", message: error.localizedDescription, details: nil))
      }
    case "keyExists":
      guard let alias = args?["alias"] as? String else {
        result(FlutterError(code: "bad_args", message: "alias required", details: nil))
        return
      }
      result(loadKey(alias: alias) != nil)
    case "deleteKey":
      guard let alias = args?["alias"] as? String else {
        result(FlutterError(code: "bad_args", message: "alias required", details: nil))
        return
      }
      deleteKey(alias: alias)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func generateKey(alias: String) throws -> [String: Any] {
    if let existing = loadKey(alias: alias) {
      return try publicPayload(privateKey: existing, backend: currentBackendLabel(), auth: true)
    }

    var error: Unmanaged<CFError>?
    let access = SecAccessControlCreateWithFlags(
      kCFAllocatorDefault,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      [.privateKeyUsage, .biometryCurrentSet],
      &error
    )
    if let error {
      throw error.takeRetainedValue() as Error
    }

    var attrs: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: alias.data(using: .utf8)!,
        kSecAttrAccessControl as String: access!,
      ],
    ]

    var backend = "software"
    #if !targetEnvironment(simulator)
      attrs[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
      backend = "secureEnclave"
    #endif

    guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
      throw error!.takeRetainedValue() as Error
    }
    return try publicPayload(privateKey: privateKey, backend: backend, auth: true)
  }

  private func publicPayload(privateKey: SecKey, backend: String, auth: Bool) throws -> [String: Any] {
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      throw NSError(domain: "kelola", code: 1, userInfo: [NSLocalizedDescriptionKey: "no public key"])
    }
    var error: Unmanaged<CFError>?
    guard let representation = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
      throw error!.takeRetainedValue() as Error
    }
    return [
      "publicKeySpki": FlutterStandardTypedData(bytes: representation),
      "backend": backend,
      "authRequired": auth,
    ]
  }

  private func sign(alias: String, data: Data) throws -> FlutterStandardTypedData {
    guard let key = loadKey(alias: alias) else {
      throw NSError(domain: "kelola", code: 2, userInfo: [NSLocalizedDescriptionKey: "missing key"])
    }
    var error: Unmanaged<CFError>?
    guard let sig = SecKeyCreateSignature(
      key,
      .ecdsaSignatureMessageX962SHA256,
      data as CFData,
      &error
    ) as Data? else {
      throw error!.takeRetainedValue() as Error
    }
    return FlutterStandardTypedData(bytes: sig)
  }

  private func loadKey(alias: String) -> SecKey? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: alias.data(using: .utf8)!,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else {
      return nil
    }
    return (item as! SecKey)
  }

  private func deleteKey(alias: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: alias.data(using: .utf8)!,
    ]
    SecItemDelete(query as CFDictionary)
  }

  private func currentBackendLabel() -> String {
    #if targetEnvironment(simulator)
      return "software"
    #else
      return "secureEnclave"
    #endif
  }
}
