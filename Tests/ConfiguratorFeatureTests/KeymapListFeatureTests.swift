import ComposableArchitecture
@testable import ConfiguratorFeature
import Foundation
import KeymapModel
import SharedConfig
import Testing

@MainActor
private func makeStore(_ fakes: Fakes) -> TestStoreOf<KeymapListFeature> {
  TestStore(initialState: fakes.makeState { KeymapListFeature.State() }) {
    KeymapListFeature()
  } withDependencies: {
    fakes.apply(to: &$0)
  }
}

@MainActor
struct KeymapListFeatureTests {
  @Test func selectsDefaultKeymapInitially() throws {
    let fakes = try Fakes(file: twoKeymaps())
    let state = fakes.makeState { KeymapListFeature.State() }
    #expect(state.selection == Keymap.starterID)
  }

  @Test func addSelectsNewKeymap() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.addTapped) {
      $0.$configuration.withLock {
        _ = $0.keymaps.append(Keymap(id: newID, name: "New Keymap", abbreviation: "NEW", layers: [:]))
      }
      $0.selection = newID
    }
    #expect(store.state.configuration.keymaps.count == 2)
    let added = try #require(store.state.configuration.keymaps[id: newID])
    #expect(added.name == "New Keymap")
    #expect(added.abbreviation == "NEW")
    #expect(added.layers.isEmpty)
    #expect(try fakes.savedConfiguration()?.keymaps.count == 2)
  }

  @Test func duplicateCopiesLayers() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = makeStore(fakes)
    let starter = Configuration.starter.keymaps[0]

    await store.send(.duplicateTapped(Keymap.starterID)) {
      $0.$configuration.withLock {
        // Inserted right after the original.
        _ = $0.keymaps.insert(
          Keymap(id: newID, name: "Default Copy", abbreviation: "DE2", layers: starter.layers),
          at: 1
        )
      }
      $0.selection = newID
    }
    #expect(store.state.configuration.keymaps[id: newID]?.layers == starter.layers)
    #expect(store.state.configuration.defaultKeymapID == Keymap.starterID)
    #expect(try fakes.savedConfiguration()?.keymaps.map(\.id) == [Keymap.starterID, newID, codingID])
  }

  @Test func addedAbbreviationsAreUnique() async throws {
    let fakes = try Fakes()
    let store = TestStore(initialState: fakes.makeState { KeymapListFeature.State() }) {
      KeymapListFeature()
    } withDependencies: {
      fakes.apply(to: &$0)
      $0.uuid = UUIDGenerator { UUID() }
    }
    store.exhaustivity = .off

    for _ in 1 ... 3 {
      await store.send(.addTapped)
    }
    #expect(store.state.configuration.keymaps.map(\.abbreviation) == ["DEF", "NEW", "NE2", "NE3"])
  }

  @Test func duplicatedAbbreviationsAreUnique() async throws {
    let fakes = try Fakes()
    let store = TestStore(initialState: fakes.makeState { KeymapListFeature.State() }) {
      KeymapListFeature()
    } withDependencies: {
      fakes.apply(to: &$0)
      $0.uuid = UUIDGenerator { UUID() }
    }
    store.exhaustivity = .off

    await store.send(.duplicateTapped(Keymap.starterID))
    await store.send(.duplicateTapped(Keymap.starterID))
    // Inserted right after the original, so the newest copy comes first.
    #expect(store.state.configuration.keymaps.map(\.abbreviation) == ["DEF", "DE3", "DE2"])
  }

  @Test func uniqueAbbreviation() {
    #expect(KeymapListFeature.uniqueAbbreviation("NEW", existing: []) == "NEW")
    #expect(KeymapListFeature.uniqueAbbreviation("NEW", existing: ["NEW"]) == "NE2")
    #expect(KeymapListFeature.uniqueAbbreviation("NEW", existing: ["NEW", "NE2", "NE4"]) == "NE3")
    #expect(KeymapListFeature.uniqueAbbreviation("DEF", existing: ["DEF"]) == "DE2")
    #expect(KeymapListFeature.uniqueAbbreviation("A", existing: ["A"]) == "A2")
    let allTaken: Set<String> = Set(["NEW"] + (2 ... 9).map { "NE\($0)" })
    #expect(KeymapListFeature.uniqueAbbreviation("NEW", existing: allTaken) == "NEW")
  }

  @Test func deleteAsksForConfirmation() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = makeStore(fakes)
    let coding = try #require(twoKeymaps().keymaps[id: codingID])

    await store.send(.deleteTapped(codingID)) {
      $0.alert = .confirmDelete(coding)
    }
    #expect(try fakes.savedConfiguration()?.keymaps.count == 2)

    await store.send(.alert(.presented(.confirmDelete(codingID)))) {
      $0.alert = nil
      $0.$configuration.withLock { _ = $0.keymaps.remove(id: codingID) }
    }
    #expect(try fakes.savedConfiguration()?.keymaps.map(\.id) == [Keymap.starterID])
  }

  @Test func cancellingDeleteKeepsKeymap() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = makeStore(fakes)
    let coding = try #require(twoKeymaps().keymaps[id: codingID])

    await store.send(.deleteTapped(codingID)) { $0.alert = .confirmDelete(coding) }
    await store.send(.alert(.dismiss)) { $0.alert = nil }
    #expect(store.state.configuration == twoKeymaps())
  }

  @Test func deletingDefaultReassignsDefault() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = makeStore(fakes)
    let starter = Configuration.starter.keymaps[0]

    await store.send(.deleteTapped(Keymap.starterID)) { $0.alert = .confirmDelete(starter) }
    await store.send(.alert(.presented(.confirmDelete(Keymap.starterID)))) {
      $0.alert = nil
      $0.$configuration.withLock {
        _ = $0.keymaps.remove(id: Keymap.starterID)
        $0.defaultKeymapID = codingID
      }
      // The deleted keymap was selected: the new default is.
      $0.selection = codingID
    }
    #expect(try fakes.savedConfiguration()?.defaultKeymapID == codingID)
  }

  @Test func cannotDeleteLastKeymap() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.deleteTapped(Keymap.starterID))
    #expect(store.state.configuration == .starter)
    #expect(!store.state.canDelete)
  }

  @Test func confirmingDeleteAfterFileBecameUnreadableDoesNothing() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = makeStore(fakes)
    let coding = try #require(twoKeymaps().keymaps[id: codingID])
    await store.send(.deleteTapped(codingID)) { $0.alert = .confirmDelete(coding) }

    // While the alert is up, the file is replaced with one that can't be read.
    let corrupt = Data("{".utf8)
    fakes.writeFile(corrupt)
    await #expect(throws: (any Error).self) { try await store.state.$configuration.load() }
    #expect(store.state.isReadOnly)

    await store.send(.alert(.presented(.confirmDelete(codingID)))) { $0.alert = nil }
    await store.send(.addTapped)
    await store.send(.duplicateTapped(codingID))
    await store.send(.setDefaultTapped(codingID))
    #expect(fakes.fileData == corrupt)
  }

  @Test func setDefault() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = makeStore(fakes)

    await store.send(.setDefaultTapped(codingID)) {
      $0.$configuration.withLock { $0.defaultKeymapID = codingID }
    }
    #expect(try fakes.savedConfiguration()?.defaultKeymapID == codingID)
  }

  @Test func selectionIsBindable() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = makeStore(fakes)

    await store.send(.binding(.set(\.selection, codingID))) { $0.selection = codingID }
  }
}
