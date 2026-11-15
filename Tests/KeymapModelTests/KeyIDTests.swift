import Foundation
@testable import KeymapModel
import Testing

struct KeyIDTests {
  @Test func stringRoundTrip() {
    #expect(KeyID.a.description == "7:4")
    #expect(KeyID(string: "7:4") == .a)
    #expect(KeyID(string: "255:3") == .fn)
    #expect(KeyID(string: "x") == nil)
  }

  @Test func usageValues() {
    #expect(KeyID.capsLock == KeyID(page: 7, usage: 0x39))
    #expect(KeyID.escape.usage == 0x29)
    #expect(KeyID.f18.usage == 0x6D)
    #expect(KeyID.nonUSBackslash.usage == 0x64)
    #expect(KeyID.international3.usage == 0x89)
    #expect(KeyID.lang1.usage == 0x90)
    #expect(KeyID.leftGUI.usage == 0xE3)
    #expect(KeyID.rightGUI.usage == 0xE7)
    #expect(Set(KeyID.allKnown).count == KeyID.allKnown.count)
  }

  @Test func mediaKeyUsages() {
    let expected: [(KeyID, UInt16, UInt16)] = [
      (.brightnessDown, 0x0C, 0x70), (.brightnessUp, 0x0C, 0x6F), (.missionControl, 0x0C, 0x29F),
      (.spotlight, 0x0C, 0x221), (.dictation, 0x0C, 0xCF), (.doNotDisturb, 0x01, 0x9B),
      (.previousTrack, 0x0C, 0xB6), (.playPause, 0x0C, 0xCD), (.nextTrack, 0x0C, 0xB5),
      (.mute, 0x0C, 0xE2), (.volumeDown, 0x0C, 0xEA), (.volumeUp, 0x0C, 0xE9),
    ]
    for (key, page, usage) in expected {
      #expect(key == KeyID(page: page, usage: usage))
    }
    #expect(KeyID.mediaKeys == expected.map(\.0))
    #expect(Set(KeyID.allKnown).isSuperset(of: KeyID.mediaKeys))
  }

  @Test func dictionaryKeyEncoding() throws {
    let data = try JSONEncoder().encode([KeyID.a: 1])
    #expect(String(decoding: data, as: UTF8.self) == #"{"7:4":1}"#)
  }

  @Test func modifiersEncodeInCanonicalOrder() throws {
    let m: Modifiers = [Modifiers(.rightCommand), Modifiers(.leftShift), Modifiers(.leftControl)]
    #expect(
      try String(decoding: JSONEncoder().encode(m), as: UTF8.self)
        == #"["leftControl","leftShift","rightCommand"]"#
    )
    #expect(KeyID.leftAlt.modifier == .leftOption)
    #expect(KeyID.a.modifier == nil)
  }
}
