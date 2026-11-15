import Carbon
import Foundation
import KeyIO
import KeymapModel

/// One key press with the modifiers held around it.
public struct TextStroke: Equatable, Hashable, Sendable {
  public var key: KeyID
  public var modifiers: Modifiers

  public init(key: KeyID, modifiers: Modifiers) {
    self.key = key
    self.modifiers = modifiers
  }
}

/// Reverse keyboard-layout table: which key presses type a character, with Caps Lock off.
///
/// Built by running `UCKeyTranslate` over every key of `KeyID.allKnown` with no modifiers, ⇧, ⌥ and
/// ⇧⌥, and again from every dead-key state those reach, so a character is typed by one stroke or by a
/// dead key followed by a second stroke. Fewer strokes win, then fewer modifiers, then `allKnown` order.
public struct TextKeystrokes: Sendable {
  private let table: [Character: [TextStroke]]

  public init(layoutData: Data, keyboardType: UInt32) {
    table = layoutData.withUnsafeBytes { raw in
      guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return [:] }
      return Self.build(layout, keyboardType)
    }
  }

  /// The strokes that type `character`, or nil when the layout cannot type it.
  public func strokes(for character: Character) -> [TextStroke]? {
    switch character {
    case "\n", "\r", "\r\n": [TextStroke(key: .returnOrEnter, modifiers: [])]
    case "\t": [TextStroke(key: .tab, modifiers: [])]
    default: table[character]
    }
  }

  /// `UCKeyTranslate` modifier states: Carbon modifier flags shifted right by 8.
  private static let modifierStates: [(modifiers: Modifiers, state: UInt32)] = [
    ([], 0),
    ([Modifiers(.leftShift)], UInt32(shiftKey >> 8)),
    ([Modifiers(.leftOption)], UInt32(optionKey >> 8)),
    ([Modifiers(.leftShift), Modifiers(.leftOption)], UInt32((shiftKey | optionKey) >> 8)),
  ]

  private static func build(
    _ layout: UnsafePointer<UCKeyboardLayout>,
    _ keyboardType: UInt32
  ) -> [Character: [TextStroke]] {
    let keys = KeyID.allKnown.compactMap { key in MacKeyCode.code(for: key).map { (key: key, code: $0) } }
    var table: [Character: [TextStroke]] = [:]
    func consider(_ character: Character, _ strokes: [TextStroke]) {
      guard let existing = table[character] else {
        table[character] = strokes
        return
      }
      if (strokes.count, modifierCount(strokes)) < (existing.count, modifierCount(existing)) {
        table[character] = strokes
      }
    }

    var deadKeys: [(stroke: TextStroke, state: UInt32)] = []
    for key in keys {
      for modifierState in modifierStates {
        let stroke = TextStroke(key: key.key, modifiers: modifierState.modifiers)
        let result = translate(layout, key.code, modifierState.state, keyboardType, deadKeyState: 0)
        if let character = result.character {
          consider(character, [stroke])
        } else if result.isDeadKey {
          deadKeys.append((stroke, result.deadKeyState))
        }
      }
    }

    for deadKey in deadKeys {
      for key in keys {
        for modifierState in modifierStates {
          let result = translate(layout, key.code, modifierState.state, keyboardType, deadKeyState: deadKey.state)
          guard let character = result.character else { continue }
          consider(character, [deadKey.stroke, TextStroke(key: key.key, modifiers: modifierState.modifiers)])
        }
      }
    }
    return table
  }

  private static func modifierCount(_ strokes: [TextStroke]) -> Int {
    strokes.reduce(0) { $0 + $1.modifiers.members.count }
  }

  private struct Translation {
    /// The single printable character produced, if any.
    var character: Character?
    var deadKeyState: UInt32
    /// No output, but a dead-key state to continue from.
    var isDeadKey: Bool
  }

  private static func translate(
    _ layout: UnsafePointer<UCKeyboardLayout>,
    _ code: UInt16,
    _ modifierState: UInt32,
    _ keyboardType: UInt32,
    deadKeyState: UInt32
  ) -> Translation {
    var state = deadKeyState
    var length = 0
    var characters = [UniChar](repeating: 0, count: 8)
    let status = UCKeyTranslate(
      layout, code, UInt16(kUCKeyActionDown), modifierState, keyboardType,
      0, &state, characters.count, &length, &characters
    )
    guard status == noErr else { return Translation(character: nil, deadKeyState: 0, isDeadKey: false) }
    guard length > 0 else { return Translation(character: nil, deadKeyState: state, isDeadKey: state != 0) }
    let text = String(utf16CodeUnits: characters, count: length)
    guard text.count == 1, let character = text.first,
          !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { return Translation(character: nil, deadKeyState: state, isDeadKey: false) }
    return Translation(character: character, deadKeyState: state, isDeadKey: false)
  }
}

/// Keyboard layout data (`uchr`) of input sources, shared by key labels and text keystrokes.
enum KeyboardLayoutData {
  /// The selected keyboard input source, or the current ASCII-capable one when the selected one has
  /// no layout data (e.g. an input method).
  static func current() -> (inputSourceID: String, data: Data)? {
    for copy in [TISCopyCurrentKeyboardLayoutInputSource, TISCopyCurrentASCIICapableKeyboardLayoutInputSource] {
      guard let source = copy()?.takeRetainedValue(), let data = layoutData(source) else { continue }
      return (inputSourceID(source) ?? "", data)
    }
    return nil
  }

  /// The layout data of an installed input source, e.g. `com.apple.keylayout.US`.
  static func layoutData(inputSourceID: String) -> Data? {
    let filter = [kTISPropertyInputSourceID as String: inputSourceID] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
      return nil
    }
    return list.lazy.compactMap(layoutData).first
  }

  private static func layoutData(_ source: TISInputSource) -> Data? {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
  }

  private static func inputSourceID(_ source: TISInputSource) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
  }
}
