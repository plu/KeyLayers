import CoreHID
import Foundation
import InputDaemonIPC
import OSLog

/// One virtual HID keyboard standing in for one seized physical keyboard.
public protocol VirtualKeyboard: Sendable {
  /// Sends one input report. Reports reach the system in the order they were sent; never blocks.
  func send(_ report: Data)
}

public protocol VirtualKeyboardFactory: Sendable {
  /// Checks that virtual keyboards can be created at all (entitlement, Accessibility).
  /// Throws `KeyIOError.virtualKeyboardUnavailable` otherwise.
  func preflight() throws
  /// The virtual keyboard for `device`. Throws `KeyIOError.virtualKeyboardUnavailable`.
  func make(for device: InputDevice) throws -> any VirtualKeyboard
}

/// How a virtual keyboard presents itself to the system. The daemon recognises (and never seizes)
/// KeyLayers' virtual keyboards by `vendorID` and the `uniqueID` prefix.
public struct VirtualKeyboardIdentity: Equatable, Sendable {
  /// "KL", reserved for KeyLayers' virtual keyboards.
  public static let vendorID: UInt32 = 0x4B4C
  public static let productID: UInt32 = 0x4C01
  public static let uniqueIDPrefix = "com.plunien.keylayers.virtual."

  public var vendorID: UInt32 { Self.vendorID }
  public var productID: UInt32 { Self.productID }
  public var uniqueID: String
  public var product: String
  /// The physical keyboard's HID country code, mirrored so macOS picks the same layout type
  /// (ANSI/ISO/JIS). Best effort: which layout macOS assigns is only checked on hardware.
  public var countryCode: Int

  public init(for device: InputDevice) {
    uniqueID = Self.uniqueIDPrefix + String(device.id)
    product = "KeyLayers \(device.name)"
    countryCode = device.countryCode
  }
}

/// Virtual keyboards on CoreHID's `HIDVirtualDevice` (needs the
/// `com.apple.developer.hid.virtual.device` entitlement and Accessibility). Not unit-tested beyond
/// the property mapping: it needs the real entitlement.
public struct LiveVirtualKeyboardFactory: VirtualKeyboardFactory {
  public init() {}

  public func preflight() throws {
    let probe = keyboard(identity: nil)
    guard HIDVirtualDevice(properties: probe) != nil else {
      Self.logger.error("virtual keyboard unavailable (entitlement or Accessibility missing?)")
      throw KeyIOError.virtualKeyboardUnavailable
    }
  }

  public func make(for device: InputDevice) throws -> any VirtualKeyboard {
    guard let virtual = HIDVirtualDevice(properties: keyboard(identity: VirtualKeyboardIdentity(for: device)))
    else {
      Self.logger.error("virtual keyboard for \(device.name, privacy: .public) unavailable")
      throw KeyIOError.virtualKeyboardUnavailable
    }
    return LiveVirtualKeyboard(device: virtual)
  }

  private func keyboard(identity: VirtualKeyboardIdentity?) -> HIDVirtualDevice.Properties {
    HIDVirtualDevice.Properties(
      descriptor: VirtualKeyboardState.descriptor,
      vendorID: VirtualKeyboardIdentity.vendorID,
      productID: VirtualKeyboardIdentity.productID,
      transport: .virtual,
      product: identity?.product ?? "KeyLayers",
      manufacturer: "KeyLayers",
      uniqueID: identity?.uniqueID ?? VirtualKeyboardIdentity.uniqueIDPrefix + "probe",
      localizationCode: identity.flatMap { Self.localizationCode(forCountryCode: $0.countryCode) }
    )
  }

  /// HID country codes (HID 1.11, §6.2.1) 0...35, in `HIDDeviceLocalizationCode`'s case order.
  private static let localizationCodes: [HIDDeviceLocalizationCode] = [
    .unsupported, .arabic, .belgium, .canada, .canadaFrench, .czechia, .denmark, .finland, .france,
    .germany, .greece, .hebrew, .hungary, .unitedStatesISO, .italy, .japan, .korea, .latinAmerica,
    .netherlands, .norway, .persian, .poland, .portugal, .russia, .slovakia, .spain, .sweden,
    .switzerlandFrench, .switzerlandGerman, .switzerland, .chineseZhuyin, .turkeyQWERTY,
    .unitedKingdom, .unitedStates, .yugoslavia, .turkeyStandard,
  ]

  static func localizationCode(forCountryCode code: Int) -> HIDDeviceLocalizationCode? {
    localizationCodes.indices.contains(code) ? localizationCodes[code] : nil
  }

  static let logger = Logger(subsystem: "com.plunien.keylayers", category: "KeyIO")
}

/// Activates the device, then dispatches reports in order on one task (reports sent before
/// activation finishes wait in the stream). Dropping the keyboard finishes the stream; the task
/// sends what is queued and then releases the device, which removes it from the system.
final class LiveVirtualKeyboard: VirtualKeyboard {
  private let continuation: AsyncStream<Data>.Continuation

  init(device: HIDVirtualDevice) {
    let (stream, continuation) = AsyncStream<Data>.makeStream()
    self.continuation = continuation
    Task {
      await device.activate(delegate: IgnoringDelegate())
      for await report in stream {
        do {
          try await device.dispatchInputReport(data: report, timestamp: SuspendingClock.now)
        } catch {
          LiveVirtualKeyboardFactory.logger.error("virtual keyboard report failed: \(error, privacy: .public)")
        }
      }
    }
  }

  deinit {
    continuation.finish()
  }

  func send(_ report: Data) {
    continuation.yield(report)
  }
}

/// LED output reports (Caps Lock) are not forwarded to the physical keyboards; get-report requests are answered with an empty report of the requested ID.
private struct IgnoringDelegate: HIDVirtualDeviceDelegate {
  func hidVirtualDevice(
    _: HIDVirtualDevice, receivedSetReportRequestOfType _: HIDReportType, id _: HIDReportID?, data _: Data
  ) async throws {}

  func hidVirtualDevice(
    _: HIDVirtualDevice, receivedGetReportRequestOfType _: HIDReportType, id: HIDReportID?, maxSize: Int
  ) async throws -> Data {
    VirtualKeyboardState.getReportReply(id: id?.rawValue, maxSize: maxSize)
  }
}
