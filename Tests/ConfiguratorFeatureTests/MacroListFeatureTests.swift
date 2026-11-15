import ComposableArchitecture
@testable import ConfiguratorFeature
import Foundation
import KeymapModel
import SharedConfig
import Testing

private let macroID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
private let otherMacroID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

/// What `.incrementing` yields: 0, 1, ...
private func uuid(_ value: Int) -> UUID {
  UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", value))")!
}

private let sampleSteps: [MacroStep] = [.text("hi"), .delay(milliseconds: 50)]

private func configuration(bindingKeys: Int = 0) -> Configuration {
  var configuration = Configuration.starter
  configuration.macros = [Macro(id: macroID, name: "Greet", steps: sampleSteps)]
  for index in 0 ..< bindingKeys {
    let key = KeyID(page: 7, usage: UInt16(4 + index))
    configuration.keymaps[id: Keymap.starterID]?.setAction(.macro(macroID), for: key, on: .base)
  }
  return configuration
}

@MainActor
private func makeStore(_ fakes: Fakes, ids: Bool = true) -> TestStoreOf<MacroListFeature> {
  TestStore(initialState: fakes.makeState { MacroListFeature.State() }) {
    MacroListFeature()
  } withDependencies: {
    fakes.apply(to: &$0)
    if ids {
      $0.uuid = .incrementing
    }
  }
}

@MainActor
struct MacroListFeatureTests {
  @Test func addCreatesAndSelects() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)
    let first = uuid(0)
    let second = uuid(1)

    await store.send(.addTapped) {
      $0.$configuration.withLock { _ = $0.macros.append(Macro(id: first, name: "New Macro", steps: [])) }
      $0.selection = first
    }
    await store.send(.addTapped) {
      $0.$configuration.withLock { _ = $0.macros.append(Macro(id: second, name: "New Macro 2", steps: [])) }
      $0.selection = second
    }
    #expect(try fakes.savedConfiguration()?.macros.map(\.name) == ["New Macro", "New Macro 2"])
  }

  @Test func duplicateCopies() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)
    let copyID = uuid(0)

    await store.send(.duplicateTapped(macroID)) {
      $0.$configuration.withLock {
        _ = $0.macros.insert(Macro(id: copyID, name: "Greet copy", steps: sampleSteps), at: 1)
      }
      $0.selection = copyID
    }
  }

  @Test func deleteUnusedAsksThenDeletes() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)
    let macro = try #require(store.state.configuration.macros[id: macroID])
    await store.send(.binding(.set(\.selection, macroID))) { $0.selection = macroID }

    await store.send(.deleteTapped(macroID)) { $0.alert = .confirmDelete(macro, keyCount: 0) }
    #expect(store.state.alert?.title == TextState("Delete “Greet”?"))
    #expect(store.state.alert?.message == TextState("This can't be undone."))

    await store.send(.alert(.presented(.confirmDelete(macroID)))) {
      $0.alert = nil
      $0.$configuration.withLock { $0.removeMacro(macroID) }
      $0.selection = nil
    }
    #expect(try fakes.savedConfiguration()?.macros.isEmpty == true)
  }

  @Test func deleteUsedMentionsKeys() async throws {
    let fakes = try Fakes(file: configuration(bindingKeys: 2))
    let store = makeStore(fakes)
    let macro = try #require(store.state.configuration.macros[id: macroID])
    #expect(store.state.configuration.keysUsing(macroID).count == 2)

    await store.send(.deleteTapped(macroID)) { $0.alert = .confirmDelete(macro, keyCount: 2) }
    #expect(
      store.state.alert?.message == TextState("2 keys use this macro and will do nothing. This can't be undone.")
    )
    await store.send(.alert(.presented(.confirmDelete(macroID)))) {
      $0.alert = nil
      $0.$configuration.withLock { $0.removeMacro(macroID) }
    }
    #expect(store.state.configuration.keysUsing(macroID).isEmpty)
    #expect(try fakes.savedConfiguration()?.keysUsing(macroID).isEmpty == true)
  }

  @Test func readOnlyIgnoresEdits() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)
    let corrupt = Data("{".utf8)
    fakes.writeFile(corrupt)
    await #expect(throws: (any Error).self) { try await store.state.$configuration.load() }
    #expect(store.state.isReadOnly)

    await store.send(.addTapped)
    await store.send(.duplicateTapped(macroID))
    await store.send(.deleteTapped(macroID))
    #expect(fakes.fileData == corrupt)
  }
}
