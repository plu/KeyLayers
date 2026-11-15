import Foundation
import KeymapModel
import RemapEngine

/// Tracks what the virtual keyboard currently holds down and turns engine output events into
/// input reports. Report 1 (keyboard, 10 bytes): ID, modifiers, reserved, 6 key slots, fn (Apple
/// top-case vendor byte). Report 2 (consumer, 3 bytes): ID, one 16-bit usage, little-endian.
/// Report 3 (system control, 2 bytes): ID, one 8-bit usage.
public struct VirtualKeyboardState: Equatable, Sendable {
  public static let keySlots = 6
  static let reportSize = 1 + 2 + keySlots + 1
  static let consumerReportID: UInt8 = 2
  static let systemReportID: UInt8 = 3

  /// The reply to a get-report request: report `id` with nothing held, its ID byte first and
  /// sized as the descriptor declares it (1: 10 bytes, 2: 3, 3: 2), capped at `maxSize`. With no
  /// ID (or an unknown one), the keyboard report.
  static func getReportReply(id: UInt8?, maxSize: Int) -> Data {
    let (reportID, size): (UInt8, Int) = switch id {
    case consumerReportID?: (consumerReportID, 3)
    case systemReportID?: (systemReportID, 2)
    default: (1, reportSize)
    }
    let report = Data([reportID] + [UInt8](repeating: 0, count: size - 1))
    return report.prefix(max(0, maxSize))
  }

  /// Three top-level collections, each with a report ID. Report 1: a keyboard (modifier byte,
  /// reserved byte, 6 key slots) plus a trailing vendor byte, Usage Page 0xFF, Usage 0x03 (Apple
  /// top case, fn). Report 2: Consumer Control, one 16-bit usage (media keys). Report 3: Generic
  /// Desktop System Control, one 8-bit usage (e.g. Do Not Disturb, 0x9B).
  public static let descriptor = Data([
    0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x85, 0x01,
    // Modifier byte.
    0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02,
    // Reserved byte.
    0x95, 0x01, 0x75, 0x08, 0x81, 0x01,
    // Six key slots.
    0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x05, 0x07, 0x19, 0x00, 0x2A, 0xFF, 0x00, 0x81, 0x00,
    // fn byte.
    0x05, 0xFF, 0x09, 0x03, 0x15, 0x00, 0x25, 0x01, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02,
    0xC0,
    // Consumer Control: one 16-bit usage (report 2).
    0x05, 0x0C, 0x09, 0x01, 0xA1, 0x01, 0x85, 0x02, 0x15, 0x00, 0x26, 0xFF, 0x03,
    0x19, 0x00, 0x2A, 0xFF, 0x03, 0x75, 0x10, 0x95, 0x01, 0x81, 0x00, 0xC0,
    // System Control: one 8-bit usage (report 3).
    0x05, 0x01, 0x09, 0x80, 0xA1, 0x01, 0x85, 0x03, 0x15, 0x00, 0x26, 0xFF, 0x00,
    0x19, 0x00, 0x29, 0xFF, 0x75, 0x08, 0x95, 0x01, 0x81, 0x00, 0xC0,
  ])

  /// Modifier-key outputs currently down.
  private var explicit: Modifiers = []
  /// Held non-modifier keys in press order, each with the extra modifiers it was pressed with.
  private var held: [(usage: UInt8, modifiers: Modifiers)] = []
  /// Keys whose down was ignored because all slots were full; their up is ignored too.
  private var dropped: Set<UInt8> = []
  private var fnDown = false
  private var lastReport = Data([1] + [UInt8](repeating: 0, count: reportSize - 1))
  /// The consumer (page 0x0C) and system control (page 0x01) usage currently held, 0 = none.
  private var consumer: UInt16 = 0
  private var system: UInt8 = 0
  private var lastConsumer: UInt16 = 0
  private var lastSystem: UInt8 = 0

  public init() {}

  /// Modifier-key outputs currently down on this keyboard.
  public var explicitModifiers: Modifiers {
    explicit
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.explicit == rhs.explicit && lhs.fnDown == rhs.fnDown && lhs.dropped == rhs.dropped
      && lhs.consumer == rhs.consumer && lhs.system == rhs.system
      && lhs.held.map(\.usage) == rhs.held.map(\.usage)
      && lhs.held.map(\.modifiers) == rhs.held.map(\.modifiers)
  }

  /// Applies one output event; returns the report to send, or nil if nothing changed.
  /// `heldElsewhere` = modifiers held down on the other virtual keyboards.
  public mutating func apply(_ event: OutputEvent, heldElsewhere: Modifiers = []) -> Data? {
    guard !event.isRepeat else { return nil }
    if let modifier = event.key.modifier {
      let flag = Modifiers(modifier)
      if event.isDown {
        explicit.insert(flag)
      } else {
        explicit.remove(flag)
      }
    } else if event.key == .fn {
      fnDown = event.isDown
    } else if event.key.page == 0x07, (0x04 ... 0xDF).contains(event.key.usage) {
      let usage = UInt8(event.key.usage)
      // Physical/synthetic modifiers arrive as their own modifier-key events (here or on another
      // virtual keyboard); only true remap extras are tied to this key.
      let extras = event.modifiers.subtracting(explicit).subtracting(heldElsewhere)
      if event.isDown {
        if let index = held.firstIndex(where: { $0.usage == usage }) {
          held[index].modifiers = extras
        } else if held.count < Self.keySlots {
          held.append((usage, extras))
        } else {
          dropped.insert(usage)
        }
      } else if dropped.remove(usage) == nil {
        held.removeAll { $0.usage == usage }
      }
    } else if event.key.page == 0x0C, (1 ... 0x3FF).contains(event.key.usage) {
      // Only the latest press is held; an up of a replaced key changes nothing.
      let usage = event.key.usage
      if event.isDown {
        consumer = usage
      } else if consumer == usage {
        consumer = 0
      }
      return consumerReportIfChanged()
    } else if event.key.page == 0x01, (1 ... 0xFF).contains(event.key.usage) {
      let usage = UInt8(event.key.usage)
      if event.isDown {
        system = usage
      } else if system == usage {
        system = 0
      }
      return systemReportIfChanged()
    } else {
      return nil
    }
    return emitIfChanged()
  }

  /// Releases everything; returns the reports (keyboard, consumer, system) that changed.
  public mutating func releaseAll() -> [Data] {
    explicit = []
    held = []
    dropped = []
    fnDown = false
    consumer = 0
    system = 0
    return [emitIfChanged(), consumerReportIfChanged(), systemReportIfChanged()].compactMap(\.self)
  }

  private mutating func consumerReportIfChanged() -> Data? {
    guard consumer != lastConsumer else { return nil }
    lastConsumer = consumer
    return Data([Self.consumerReportID, UInt8(consumer & 0xFF), UInt8(consumer >> 8)])
  }

  private mutating func systemReportIfChanged() -> Data? {
    guard system != lastSystem else { return nil }
    lastSystem = system
    return Data([Self.systemReportID, system])
  }

  private mutating func emitIfChanged() -> Data? {
    let extra = held.reduce(into: Modifiers()) { $0.formUnion($1.modifiers) }
    var report = Data(repeating: 0, count: Self.reportSize)
    report[0] = 1
    report[1] = explicit.union(extra).rawValue
    for (slot, key) in held.enumerated() {
      report[3 + slot] = key.usage
    }
    report[Self.reportSize - 1] = fnDown ? 1 : 0
    guard report != lastReport else { return nil }
    lastReport = report
    return report
  }
}
