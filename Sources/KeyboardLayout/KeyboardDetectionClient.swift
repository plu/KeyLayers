import Carbon
import Dependencies
import DependenciesMacros
import Foundation
import IOKit.hid

/// A connected Apple keyboard the configurator can draw.
public struct DetectedKeyboard: Equatable, Identifiable, Sendable {
  public var id: String
  public var name: String
  public var kind: KeyboardKind
  public var isBuiltIn: Bool

  public init(id: String, name: String, kind: KeyboardKind, isBuiltIn: Bool) {
    self.id = id
    self.name = name
    self.kind = kind
    self.isBuiltIn = isBuiltIn
  }
}

@DependencyClient
public struct KeyboardDetectionClient: Sendable {
  /// The connected Apple keyboards, built-in first; empty when there is none (e.g. in a VM).
  public var keyboards: @Sendable () -> [DetectedKeyboard] = { [] }
}

extension KeyboardDetectionClient: DependencyKey {
  public static let liveValue = KeyboardDetectionClient(keyboards: { LiveKeyboardDetection.keyboards() })

  public static let testValue = KeyboardDetectionClient()

  public static let previewValue = KeyboardDetectionClient(keyboards: {
    [DetectedKeyboard(id: "preview", name: "Apple Internal Keyboard / Trackpad", kind: .fallback, isBuiltIn: true)]
  })
}

public extension DependencyValues {
  var keyboardDetection: KeyboardDetectionClient {
    get { self[KeyboardDetectionClient.self] }
    set { self[KeyboardDetectionClient.self] = newValue }
  }
}

/// IOHID enumeration of Apple keyboards; the layout type comes from the system (`KBGetLayoutType`),
/// which macOS keeps for the keyboard type it last identified, so every keyboard gets the same one.
enum LiveKeyboardDetection {
  static let appleVendorID = 0x05AC

  static func keyboards() -> [DetectedKeyboard] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
      kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
      kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
      kIOHIDVendorIDKey: appleVendorID,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }

    let layout = systemLayout()
    var seen = Set<String>()
    return devices.compactMap { device -> DetectedKeyboard? in
      let name = property(device, kIOHIDProductKey) as? String ?? "Apple Keyboard"
      // A macOS VM's keyboard ("Virtual USB Keyboard") carries Apple's vendor ID but isn't one.
      guard !name.contains("Virtual") else { return nil }
      let transport = property(device, kIOHIDTransportKey) as? String ?? ""
      let isBuiltIn = (property(device, "Built-In") as? Bool) == true || transport == "SPI" || transport == "FIFO"
      let productID = property(device, kIOHIDProductIDKey) as? Int ?? 0
      let serial = property(device, kIOHIDSerialNumberKey) as? String
      let id = isBuiltIn ? "built-in" : "\(productID):\(serial ?? name)"
      guard seen.insert(id).inserted else { return nil }
      let model: KeyboardModel = name.contains("Numeric Keypad") ? .extended : .compact
      let kind = KeyboardKind(model: model, layout: layout)
      return DetectedKeyboard(id: id, name: name, kind: kind, isBuiltIn: isBuiltIn)
    }
    .sorted { ($0.isBuiltIn ? 0 : 1, $0.name) < ($1.isBuiltIn ? 0 : 1, $1.name) }
  }

  static func systemLayout() -> PhysicalLayout {
    switch Int(KBGetLayoutType(Int16(LMGetKbdType()))) {
    case kKeyboardJIS: .jis
    case kKeyboardISO: .iso
    default: .ansi
    }
  }

  private static func property(_ device: IOHIDDevice, _ key: String) -> Any? {
    IOHIDDeviceGetProperty(device, key as CFString)
  }
}
