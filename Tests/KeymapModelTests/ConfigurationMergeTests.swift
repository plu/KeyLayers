import Foundation
import IdentifiedCollections
@testable import KeymapModel
import Testing

private let codingID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
private let gamingID = UUID(uuidString: "00000000-0000-0000-0000-00000000BEEF")!

/// Hands out 00…A1, 00…A2, … in order.
private func sequentialIDs() -> () -> Keymap.ID {
  var next = 0xA1
  return {
    defer { next += 1 }
    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", next))!
  }
}

private func id(_ n: Int) -> UUID {
  UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", n))!
}

/// The starter plus "Coding" (COD).
private func current() -> Configuration {
  var configuration = Configuration.starter
  configuration.settings = Settings(doubleTapTimeoutMilliseconds: 300, showLayerHUD: false)
  configuration.keymaps.append(Keymap(id: codingID, name: "Coding", abbreviation: "COD"))
  return configuration
}

struct ConfigurationMergeTests {
  @Test func importedKeymapsGetNewIDsAndAreAppended() {
    let other = Configuration(
      keymaps: [Keymap(id: gamingID, name: "Gaming", abbreviation: "GAM")],
      defaultKeymapID: gamingID
    )
    let merged = current().addingKeymaps(from: other, newID: sequentialIDs())
    #expect(merged.keymaps.map(\.id) == [Keymap.starterID, codingID, id(0xA1)])
    #expect(merged.keymaps[2].name == "Gaming")
    #expect(merged.keymaps[2].abbreviation == "GAM")
  }

  @Test func importingTheSameConfigurationNeverCollides() throws {
    let base = current()
    let merged = base.addingKeymaps(from: base, newID: sequentialIDs())
    #expect(merged.keymaps.count == 4)
    #expect(Set(merged.keymaps.map(\.id)).count == 4)
    #expect(merged.keymaps.map(\.abbreviation) == ["DEF", "COD", "DE2", "CO2"])
    #expect(merged.keymaps.map(\.name) == ["Default", "Coding", "Default (imported)", "Coding (imported)"])
    // Layers come along unchanged.
    #expect(merged.keymaps[2].layers == Configuration.starter.keymaps[0].layers)
    // Still valid on disk.
    let data = try Configuration.encoder.encode(merged)
    #expect(try Configuration.decoder.decode(Configuration.self, from: data) == merged)
  }

  @Test func abbreviationsAreNormalizedAndUniqueAmongImportedOnes() {
    let other = Configuration(
      keymaps: [
        Keymap(id: id(1), name: "One", abbreviation: " def "),
        Keymap(id: id(2), name: "Two", abbreviation: "DEF"),
        Keymap(id: id(3), name: "Three", abbreviation: "writing"),
      ],
      defaultKeymapID: id(1)
    )
    let merged = current().addingKeymaps(from: other, newID: sequentialIDs())
    #expect(merged.keymaps.map(\.abbreviation) == ["DEF", "COD", "DE2", "DE3", "WRI"])
  }

  @Test func clashingNamesStayDistinct() {
    var base = current()
    base.keymaps.append(Keymap(id: id(9), name: "Coding (imported)", abbreviation: "CI"))
    let other = Configuration(
      keymaps: [
        Keymap(id: id(1), name: "Coding", abbreviation: "X"),
        Keymap(id: id(2), name: "Writing", abbreviation: "W"),
      ],
      defaultKeymapID: id(1)
    )
    let merged = base.addingKeymaps(from: other, newID: sequentialIDs())
    #expect(merged.keymaps.suffix(2).map(\.name) == ["Coding (imported 2)", "Writing"])
  }

  @Test func switchKeymapActionsFollowTheImportedKeymaps() {
    var first = Keymap(id: id(0x11), name: "First", abbreviation: "FIR")
    var second = Keymap(id: id(0x12), name: "Second", abbreviation: "SEC")
    let dangling = id(0x77)
    first.setAction(.switchKeymap(id(0x12)), for: .a, on: .base)
    first.setAction(.switchKeymap(dangling), for: .b, on: .base)
    first.setAction(.block, for: .c, on: .fn)
    second.setAction(.switchKeymap(id(0x11)), for: .a, on: .mod)
    // Points at a keymap outside the file (here one of the current configuration): kept as is.
    second.setAction(.switchKeymap(codingID), for: .b, on: .mod)
    let other = Configuration(keymaps: [first, second], defaultKeymapID: id(0x11))

    let merged = current().addingKeymaps(from: other, newID: sequentialIDs())
    let newFirst = merged.keymaps[id: id(0xA1)]
    let newSecond = merged.keymaps[id: id(0xA2)]
    #expect(newFirst?.action(for: .a, on: .base) == .switchKeymap(id(0xA2)))
    #expect(newFirst?.action(for: .b, on: .base) == .switchKeymap(dangling))
    #expect(newFirst?.action(for: .c, on: .fn) == .block)
    #expect(newSecond?.action(for: .a, on: .mod) == .switchKeymap(id(0xA1)))
    #expect(newSecond?.action(for: .b, on: .mod) == .switchKeymap(codingID))
  }

  @Test func settingsDefaultKeymapAndExistingKeymapsAreKept() {
    let base = current()
    let other = Configuration(
      settings: Settings(doubleTapTimeoutMilliseconds: 999, showLayerHUD: true),
      keymaps: [Keymap(id: codingID, name: "Coding", abbreviation: "COD")],
      defaultKeymapID: codingID
    )
    let merged = base.addingKeymaps(from: other, newID: sequentialIDs())
    #expect(merged.settings == base.settings)
    #expect(merged.defaultKeymapID == Keymap.starterID)
    #expect(merged.formatVersion == base.formatVersion)
    #expect(Array(merged.keymaps.prefix(2)) == Array(base.keymaps))
  }

  @Test func defaultIDGeneratorMakesFreshIDs() {
    let base = current()
    let merged = base.addingKeymaps(from: base)
    #expect(Set(merged.keymaps.map(\.id)).count == 4)
  }

  @Test func uniqueAbbreviation() {
    #expect(Keymap.uniqueAbbreviation("NEW", existing: []) == "NEW")
    #expect(Keymap.uniqueAbbreviation("NEW", existing: ["NEW"]) == "NE2")
    #expect(Keymap.uniqueAbbreviation("NEW", existing: ["NEW", "NE2", "NE4"]) == "NE3")
    #expect(Keymap.uniqueAbbreviation("DEF", existing: ["DEF"]) == "DE2")
    #expect(Keymap.uniqueAbbreviation("A", existing: ["A"]) == "A2")
  }

  @Test func abbreviationStaysUniqueWhenAllVariantsAreTaken() {
    var taken: Set<String> = Set(["NEW"] + (2 ... 9).map { "NE\($0)" })
    #expect(Keymap.uniqueAbbreviation("NEW", existing: taken) == "N10")
    taken.formUnion((10 ... 99).map { "N\($0)" })
    let fallback = Keymap.uniqueAbbreviation("NEW", existing: taken)
    #expect(!taken.contains(fallback))
    #expect(fallback.count == 3)
    // Short abbreviations too.
    #expect(Keymap.uniqueAbbreviation("A", existing: Set(["A"] + (2 ... 9).map { "A\($0)" })) == "A10")

    // Importing the own configuration ten times: DE2…DE9, then D10 and D11.
    var configuration = Configuration.starter
    for _ in 1 ... 10 {
      configuration = configuration.addingKeymaps(from: .starter)
    }
    #expect(configuration.keymaps.map(\.abbreviation) == ["DEF"] + (2 ... 9).map { "DE\($0)" } + ["D10", "D11"])
  }

  @Test func collidingNewIDsAreRedrawn() {
    let other = Configuration(
      keymaps: [
        Keymap(id: id(0x11), name: "One", abbreviation: "ONE"),
        Keymap(id: id(0x12), name: "Two", abbreviation: "TWO"),
      ],
      defaultKeymapID: id(0x11)
    )
    // An existing ID, then a fresh one, then the one just assigned again, then another fresh one.
    var ids = [Keymap.starterID, id(0xA1), id(0xA1), codingID, id(0xA2)][...]
    let result = current().importingKeymaps(from: other, newID: { ids.popFirst()! })
    #expect(result.configuration.keymaps.map(\.id) == [Keymap.starterID, codingID, id(0xA1), id(0xA2)])
    #expect(result.newIDs == [id(0x11): id(0xA1), id(0x12): id(0xA2)])
  }

  @Test func switchKeymapDanglingInTheFileLinksToACurrentKeymapWithThatID() {
    var keymap = Keymap(id: id(0x11), name: "One", abbreviation: "ONE")
    keymap.setAction(.switchKeymap(codingID), for: .a, on: .base)
    let other = Configuration(keymaps: [keymap], defaultKeymapID: id(0x11))
    let merged = current().addingKeymaps(from: other, newID: sequentialIDs())
    #expect(merged.keymaps.last?.action(for: .a, on: .base) == .switchKeymap(codingID))
  }
}
