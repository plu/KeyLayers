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
    struct MediaKey {
      let key: KeyID
      let page: UInt16
      let usage: UInt16
      init(_ key: KeyID, _ page: UInt16, _ usage: UInt16) {
        self.key = key
        self.page = page
        self.usage = usage
      }
    }
    let expected: [MediaKey] = [
      .init(.brightnessDown, 0x0C, 0x70), .init(.brightnessUp, 0x0C, 0x6F), .init(.missionControl, 0x0C, 0x29F),
      .init(.spotlight, 0x0C, 0x221), .init(.dictation, 0x0C, 0xCF), .init(.doNotDisturb, 0x01, 0x9B),
      .init(.previousTrack, 0x0C, 0xB6), .init(.playPause, 0x0C, 0xCD), .init(.nextTrack, 0x0C, 0xB5),
      .init(.mute, 0x0C, 0xE2), .init(.volumeDown, 0x0C, 0xEA), .init(.volumeUp, 0x0C, 0xE9),
    ]
    for media in expected {
      #expect(media.key == KeyID(page: media.page, usage: media.usage))
    }
    #expect(KeyID.mediaKeys == expected.map(\.key))
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
