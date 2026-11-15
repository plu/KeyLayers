import Foundation
import KeymapModel

public struct KeyEvent: Equatable, Sendable {
  public enum Phase: Sendable { case down, up, `repeat` }

  public var key: KeyID
  public var phase: Phase
  /// Nanoseconds, monotonic.
  public var timestamp: UInt64

  public init(key: KeyID, phase: Phase, timestamp: UInt64) {
    self.key = key
    self.phase = phase
    self.timestamp = timestamp
  }
}

public struct OutputEvent: Equatable, Sendable {
  public var key: KeyID
  public var isDown: Bool
  public var isRepeat: Bool
  public var modifiers: Modifiers

  public init(key: KeyID, isDown: Bool, isRepeat: Bool = false, modifiers: Modifiers) {
    self.key = key
    self.isDown = isDown
    self.isRepeat = isRepeat
    self.modifiers = modifiers
  }
}

public enum Disposition: Equatable, Sendable {
  case passThrough, suppress
}

public enum EngineNotification: Equatable, Sendable {
  case layerLatched(LayerName)
  case layerUnlatched(LayerName)
  case keymapSwitched(Keymap.ID)
  case emergencyStop
}

public struct EngineResult: Equatable, Sendable {
  public var disposition: Disposition
  public var output: [OutputEvent]
  public var notifications: [EngineNotification]
  /// Macros to play after `output` is posted, as configured at press time.
  public var macros: [Macro]

  public init(
    disposition: Disposition,
    output: [OutputEvent] = [],
    notifications: [EngineNotification] = [],
    macros: [Macro] = []
  ) {
    self.disposition = disposition
    self.output = output
    self.notifications = notifications
    self.macros = macros
  }
}

public struct EngineStatus: Equatable, Sendable {
  public var activeKeymapID: Keymap.ID
  public var activeLayer: LayerName

  public init(activeKeymapID: Keymap.ID, activeLayer: LayerName) {
    self.activeKeymapID = activeKeymapID
    self.activeLayer = activeLayer
  }
}
