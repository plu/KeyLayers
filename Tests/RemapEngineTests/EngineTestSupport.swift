import IdentifiedCollections
import KeymapModel
@testable import RemapEngine

func ms(_ value: UInt64) -> UInt64 {
  value * 1_000_000
}

func down(_ key: KeyID, at time: UInt64 = 0) -> KeyEvent {
  KeyEvent(key: key, phase: .down, timestamp: time)
}

func up(_ key: KeyID, at time: UInt64 = 0) -> KeyEvent {
  KeyEvent(key: key, phase: .up, timestamp: time)
}

func rep(_ key: KeyID, at time: UInt64 = 0) -> KeyEvent {
  KeyEvent(key: key, phase: .repeat, timestamp: time)
}

func out(_ key: KeyID, _ isDown: Bool, _ modifiers: Modifiers = [], repeat isRepeat: Bool = false) -> OutputEvent {
  OutputEvent(key: key, isDown: isDown, isRepeat: isRepeat, modifiers: modifiers)
}

extension Configuration {
  /// A one-keymap configuration with ID `Keymap.starterID`.
  static func testing(_ layers: [LayerName: [KeyID: KeyAction]], macros: [Macro] = []) -> Configuration {
    let keymap = Keymap(
      id: Keymap.starterID,
      name: "Test",
      abbreviation: "TST",
      layers: layers.mapValues { Layer(actions: $0) }
    )
    return Configuration(
      macros: IdentifiedArray(uniqueElements: macros),
      keymaps: IdentifiedArray(uniqueElements: [keymap]),
      defaultKeymapID: Keymap.starterID
    )
  }
}

extension Keypress {
  static func plain(_ key: KeyID?, _ modifiers: Modifiers = []) -> Keypress {
    Keypress(key: key, modifiers: modifiers)
  }
}
