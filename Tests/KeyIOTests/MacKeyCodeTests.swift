@testable import KeyIO
import KeymapModel
import Testing

struct MacKeyCodeTests {
  static let pinned: [(UInt16, KeyID)] = [
    (0x00, .a),
    (0x0A, .nonUSBackslash),
    (0x32, .graveAccentAndTilde),
    (0x2A, .backslash),
    (0x5D, .international3),
    (0x5E, .international1),
    (0x5F, .keypadComma),
    (0x66, .lang2),
    (0x68, .lang1),
    (0x39, .capsLock),
    (0x4F, .f18),
    (0x3F, .fn),
    (0x37, .leftGUI),
    (0x36, .rightGUI),
    (0x38, .leftShift),
    (0x3C, .rightShift),
    (0x3A, .leftAlt),
    (0x3D, .rightAlt),
    (0x3B, .leftControl),
    (0x3E, .rightControl),
  ]

  @Test func pinnedKeycodePairs() {
    for (code, key) in Self.pinned {
      #expect(MacKeyCode.keyID(for: code) == key, "keyID(for: \(code))")
      #expect(MacKeyCode.code(for: key) == code, "code(for: \(key))")
    }
  }

  @Test func everyKnownCodeRoundTrips() {
    var mapped = 0
    for code in UInt16(0) ... 0x7F {
      guard let key = MacKeyCode.keyID(for: code) else { continue }
      mapped += 1
      #expect(MacKeyCode.code(for: key) == code, "code \(code) -> \(key)")
    }
    // Letters, digits, punctuation, F1–F20, keypad, navigation, modifiers, ISO/JIS, fn.
    #expect(mapped == 117)
  }

  @Test func everyMappedKeyIsAKnownKeyID() {
    let known = Set(KeyID.allKnown)
    for code in UInt16(0) ... 0x7F {
      guard let key = MacKeyCode.keyID(for: code) else { continue }
      #expect(known.contains(key), "\(key)")
    }
  }

  @Test func codesWithoutHIDEquivalentAreUnmapped() {
    // 0x34 is unassigned; 0x48–0x4A are the volume keys (media, delivered as system-defined events).
    for code: UInt16 in [0x34, 0x48, 0x49, 0x4A, 0x80] {
      #expect(MacKeyCode.keyID(for: code) == nil)
    }
  }
}
