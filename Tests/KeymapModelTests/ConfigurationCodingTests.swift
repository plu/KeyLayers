import Foundation
@testable import KeymapModel
import Testing

struct ConfigurationCodingTests {
  @Test func starterKeymap() throws {
    let k = Configuration.starter.defaultKeymap
    #expect(k.id == Keymap.starterID && k.name == "Default" && k.abbreviation == "DEF")
    #expect(k.action(for: .fn, on: .base) == .switchLayer(.mod, mode: .hold))
    #expect(k.action(for: .capsLock, on: .base) == nil)
    let mod: [KeyID: KeyID] = [
      .h: .leftArrow, .j: .downArrow, .k: .upArrow, .l: .rightArrow,
      .y: .home, .u: .pageDown, .i: .pageUp, .o: .end,
      // fn's own macOS combos, so fn as Mod doesn't take them away.
      .deleteOrBackspace: .deleteForward,
      .leftArrow: .home, .rightArrow: .end, .upArrow: .pageUp, .downArrow: .pageDown,
    ]
    for (from, to) in mod {
      #expect(k.action(for: from, on: .mod) == .keypress(.init(key: to, modifiers: [])))
    }
    let fRow: [KeyID] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
    for (from, to) in zip(fRow, KeyID.mediaKeys) {
      #expect(k.action(for: from, on: .mod) == .keypress(.init(key: to, modifiers: [])))
    }
    #expect(try k.layers[.base]?.actions.count == 1 && #require(k.layers[.mod]?.actions.count) == 25)
    #expect(Configuration.starter.settings == Settings(doubleTapTimeoutMilliseconds: 250, showLayerHUD: true))
  }

  @Test func goldenFixtureDecodes() throws {
    let c = try Configuration.decoder.decode(Configuration.self, from: Data(Fixtures.v1.utf8))
    let k = try #require(c.keymaps[id: Keymap.starterID])
    #expect(
      k.action(for: .a, on: .fn)
        == .keypress(.init(key: .b, modifiers: [.init(.leftCommand)], secondaryRole: .modifier(.leftShift)))
    )
    #expect(k.action(for: .capsLock, on: .base) == .switchLayer(.fn, mode: .holdAndDoubleTapToggle))
    #expect(k.action(for: .b, on: .fn) == .block)
    #expect(k.action(for: .c, on: .fn) == .unsupported(type: "playMacro"))
  }

  @Test func roundTripIsStable() throws {
    let c = try Configuration.decoder.decode(Configuration.self, from: Data(Fixtures.v1.utf8))
    let once = try Configuration.encoder.encode(c)
    let twice = try Configuration.encoder.encode(Configuration.decoder.decode(Configuration.self, from: once))
    #expect(once == twice)
    #expect(String(decoding: once, as: UTF8.self).contains(#""type" : "playMacro""#))
  }

  @Test func unknownFieldsAreIgnored() throws {
    let json = Fixtures.v1
      .replacingOccurrences(of: "{\n  \"defaultKeymapID\"", with: "{\n  \"macros\" : [],\n  \"defaultKeymapID\"")
      .replacingOccurrences(of: "\"type\" : \"keypress\"", with: "\"color\" : \"red\", \"type\" : \"keypress\"")
    #expect(json.contains("\"macros\"") && json.contains("\"color\""))
    let c = try Configuration.decoder.decode(Configuration.self, from: Data(json.utf8))
    #expect(c.defaultKeymap.action(for: .a, on: .fn) != nil)
  }

  @Test func newerFormatVersionFailsToDecode() {
    #expect(throws: ConfigurationError.newerFormat(2)) {
      try Configuration.decoder.decode(Configuration.self, from: Data(Fixtures.v2.utf8))
    }
  }

  @Test func setActionNilRemovesAndPrunesLayer() {
    var k = Configuration.starter.defaultKeymap
    k.setAction(nil, for: .fn, on: .base)
    #expect(k.layers[.base] == nil)
  }

  @Test func abbreviationNormalization() {
    #expect(Keymap.normalizedAbbreviation("  qwerty ") == "QWE")
  }

  @Test func duplicateKeymapIDsFailToDecode() throws {
    let c = try Configuration.decoder.decode(Configuration.self, from: Data(Fixtures.v1.utf8))
    let keymap = try #require(c.keymaps.first)
    let data = try JSONEncoder().encode(
      ["formatVersion": AnyEncodable(1), "keymaps": AnyEncodable([keymap, keymap]),
       "defaultKeymapID": AnyEncodable(keymap.id)]
    )
    #expect(throws: DecodingError.self) { try Configuration.decoder.decode(Configuration.self, from: data) }
  }

  @Test func emptyKeymapsFailToDecode() {
    let json = """
    {"formatVersion": 1, "keymaps": [], "defaultKeymapID": "00000000-0000-0000-0000-000000000001"}
    """
    #expect(throws: DecodingError.self) { try Configuration.decoder.decode(Configuration.self, from: Data(json.utf8)) }
  }
}

private struct AnyEncodable: Encodable {
  let value: any Encodable
  init(_ value: any Encodable) {
    self.value = value
  }

  func encode(to encoder: any Encoder) throws {
    try value.encode(to: encoder)
  }
}
