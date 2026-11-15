import Dependencies
import DependenciesMacros
import Foundation
import IOKit.hid

/// Reads macOS's per-keyboard "Modifier Keys" remaps. They don't apply to a keyboard KeyLayers
/// seizes, so the configurator tells the user.
@DependencyClient
public struct ModifierKeysSettingsClient: Sendable {
  /// Names of the keyboards that have a Modifier Keys remap.
  public var remappedKeyboards: @Sendable () -> [String] = { [] }
}

extension ModifierKeysSettingsClient: DependencyKey {
  public static let liveValue = ModifierKeysSettingsClient(remappedKeyboards: { LiveModifierKeys.remappedKeyboards() })

  public static let testValue = ModifierKeysSettingsClient()

  public static let previewValue = ModifierKeysSettingsClient(remappedKeyboards: { [] })
}

public extension DependencyValues {
  var modifierKeysSettings: ModifierKeysSettingsClient {
    get { self[ModifierKeysSettingsClient.self] }
    set { self[ModifierKeysSettingsClient.self] = newValue }
  }
}

/// `defaults -currentHost read -g com.apple.keyboard.modifiermapping.<vendor>-<product>-<country>`.
enum LiveModifierKeys {
  static let prefix = "com.apple.keyboard.modifiermapping."

  static func remappedKeyboards() -> [String] {
    let keys = CFPreferencesCopyKeyList(
      kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
    ) as? [String] ?? []
    let names = keyboardNames()
    return keys.filter { $0.hasPrefix(prefix) }.compactMap { key -> String? in
      let value = CFPreferencesCopyValue(
        key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
      )
      guard let mappings = value as? [Any], !mappings.isEmpty else { return nil }
      let parts = key.dropFirst(prefix.count).split(separator: "-")
      guard parts.count >= 2, let vendor = Int(parts[0]), let product = Int(parts[1]) else { return nil }
      return names["\(vendor)-\(product)"] ?? "Keyboard \(vendor)-\(product)"
    }
    .sorted()
  }

  /// Product names of the connected keyboards, by "vendor-product".
  private static func keyboardNames() -> [String: String] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [
      kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
      kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
    ] as CFDictionary)
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [:] }
    var names: [String: String] = [:]
    for device in devices {
      guard
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
      else { continue }
      names["\(vendor)-\(product)"] = name
    }
    return names
  }
}
