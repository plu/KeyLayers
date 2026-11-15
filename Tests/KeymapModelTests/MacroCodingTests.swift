import Foundation
import IdentifiedCollections
@testable import KeymapModel
import Testing

struct MacroCodingTests {
  private func json(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func macroRoundTrip() throws {
    let macro = Macro(id: UUID(), name: "Hello", steps: [
      .key(KeyStep(key: .a, modifiers: Modifiers(.leftShift), kind: .tap)),
      .key(KeyStep(key: nil, modifiers: Modifiers(.leftCommand), kind: .press)),
      .text("Hi\n"),
      .delay(milliseconds: 50),
    ])
    var config = Configuration.starter
    config.macros = [macro]
    config.keymaps[id: Keymap.starterID]?.setAction(.macro(macro.id), for: .a, on: .base)
    let data = try Configuration.encoder.encode(config)
    let decoded = try Configuration.decoder.decode(Configuration.self, from: data)
    #expect(decoded == config)
    #expect(decoded.macros[id: macro.id] == macro)
  }

  @Test func macroActionJSON() throws {
    let id = UUID()
    let data = try JSONEncoder().encode(KeyAction.macro(id))
    let object = try json(data)
    #expect(object as NSDictionary == ["type": "macro", "macroID": id.uuidString] as NSDictionary)
    #expect(try JSONDecoder().decode(KeyAction.self, from: data) == .macro(id))
  }

  @Test func missingMacrosDecodesEmpty() throws {
    let c = try Configuration.decoder.decode(Configuration.self, from: Data(Fixtures.v1.utf8))
    #expect(c.macros.isEmpty)
  }

  @Test func unknownStepPreserved() throws {
    let step = try JSONDecoder().decode(MacroStep.self, from: Data(#"{"type":"mouseMove","x":3}"#.utf8))
    #expect(step == .unsupported(type: "mouseMove"))
    let object = try json(JSONEncoder().encode(step))
    #expect(object as NSDictionary == ["type": "mouseMove"] as NSDictionary)
  }

  @Test func duplicateMacroIDsRejected() throws {
    let id = UUID()
    var object = try json(Configuration.encoder.encode(Configuration.starter))
    let entry: [String: Any] = ["id": id.uuidString, "name": "M", "steps": [Any]()]
    object["macros"] = [entry, entry]
    let data = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DecodingError.self) {
      try Configuration.decoder.decode(Configuration.self, from: data)
    }
  }

  @Test func removeMacroClearsKeys() {
    let macro = Macro(id: UUID(), name: "M", steps: [.text("x")])
    var first = Keymap(id: UUID(), name: "A", abbreviation: "A")
    var second = Keymap(id: UUID(), name: "B", abbreviation: "B")
    first.setAction(.macro(macro.id), for: .a, on: .base)
    first.setAction(.block, for: .b, on: .base)
    second.setAction(.macro(macro.id), for: .c, on: .fn)
    var config = Configuration(macros: [macro], keymaps: [first, second], defaultKeymapID: first.id)

    let uses = config.keysUsing(macro.id)
    #expect(uses.count == 2)
    #expect(uses.contains { $0.keymapID == first.id && $0.layer == .base && $0.key == .a })
    #expect(uses.contains { $0.keymapID == second.id && $0.layer == .fn && $0.key == .c })

    config.removeMacro(macro.id)
    #expect(config.macros.isEmpty)
    #expect(config.keymaps[id: first.id]?.action(for: .a, on: .base) == nil)
    #expect(config.keymaps[id: first.id]?.action(for: .b, on: .base) == .block)
    #expect(config.keymaps[id: second.id]?.action(for: .c, on: .fn) == nil)
    #expect(config.keysUsing(macro.id).isEmpty)
  }
}
