import ComposableArchitecture
@testable import ConfiguratorFeature
import Foundation
import KeyboardLayout
import KeymapModel
import SharedConfig
import Testing

private let compactISO = KeyboardKind(model: .compact, layout: .iso)
private let extendedANSI = KeyboardKind(model: .extended, layout: .ansi)

private func keyboard(_ kind: KeyboardKind, _ name: String) -> DetectedKeyboard {
  DetectedKeyboard(id: name, name: name, kind: kind, isBuiltIn: kind.model == .compact)
}

/// Stores `kind` as the last-used keyboard.
private func select(_ kind: KeyboardKind, _ fakes: Fakes) {
  fakes.makeState { Shared(wrappedValue: KeyboardKind.fallback, .appStorage("selectedKeyboard")) }
    .withLock { $0 = kind }
}

/// Saves `configuration` with keymap `id` renamed to "Elsewhere" (ELS) and reloads it, as another
/// process saving the file would.
@MainActor
private func editFileExternally(
  _ fakes: Fakes,
  _ store: TestStoreOf<KeymapEditorFeature>,
  base configuration: Configuration = twoKeymaps(),
  id: Keymap.ID = codingID
) async throws {
  var configuration = configuration
  configuration.keymaps[id: id]?.name = "Elsewhere"
  configuration.keymaps[id: id]?.abbreviation = "ELS"
  try fakes.writeFile(Configuration.encoder.encode(configuration))
  try await store.state.$configuration.load()
}

@MainActor
private func makeStore(_ fakes: Fakes, id: Keymap.ID = Keymap.starterID) throws -> TestStoreOf<KeymapEditorFeature> {
  let state = try #require(fakes.makeState { KeymapEditorFeature.State(keymapID: id) })
  return TestStore(initialState: state) {
    KeymapEditorFeature()
  } withDependencies: {
    fakes.apply(to: &$0)
  }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct KeymapEditorFeatureTests {
  @Test func stateFollowsTheKeymap() throws {
    let fakes = try Fakes(file: twoKeymaps())
    let state = try #require(fakes.makeState { KeymapEditorFeature.State(keymapID: codingID) })
    #expect(state.keymap.name == "Coding")
    #expect(state.name == "Coding")
    #expect(state.abbreviation == "COD")
    #expect(state.layer == .base)
    #expect(state.selectedKeyboard == .fallback)
    #expect(fakes.makeState { KeymapEditorFeature.State(keymapID: UUID()) } == nil)
  }

  @Test func taskPicksDetectedKeyboard() async throws {
    let fakes = try Fakes()
    fakes.detectedKeyboards.setValue([keyboard(compactISO, "Apple Internal Keyboard")])
    let store = try makeStore(fakes)

    let task = await store.send(.task) {
      $0.detected = [keyboard(compactISO, "Apple Internal Keyboard")]
      $0.$selectedKeyboard.withLock { $0 = compactISO }
      $0.labels = StaticKeyLabels.usANSI
    }
    #expect(store.state.selectedKeyboard == compactISO)
    await task.cancel()
  }

  @Test func taskKeepsDetectedLastUsedKeyboard() async throws {
    let fakes = try Fakes()
    let detected = [keyboard(compactISO, "Apple Internal Keyboard"), keyboard(extendedANSI, "Magic Keyboard")]
    fakes.detectedKeyboards.setValue(detected)
    select(extendedANSI, fakes)
    let store = try makeStore(fakes)
    #expect(store.state.selectedKeyboard == extendedANSI)

    let task = await store.send(.task) {
      $0.detected = detected
      $0.labels = StaticKeyLabels.usANSI
    }
    await task.cancel()
  }

  @Test func taskKeepsSelectionWhenNothingIsDetected() async throws {
    let fakes = try Fakes()
    select(extendedANSI, fakes)
    let store = try makeStore(fakes)

    let task = await store.send(.task) { $0.labels = StaticKeyLabels.usANSI }
    #expect(store.state.selectedKeyboard == extendedANSI)
    await task.cancel()
  }

  @Test func labelsFollowInputSourceChanges() async throws {
    let fakes = try Fakes()
    let store = try makeStore(fakes)
    let task = await store.send(.task) { $0.labels = StaticKeyLabels.usANSI }

    let azerty = StaticKeyLabels.usANSI.merging([.a: "Q", .q: "A"]) { _, new in new }
    fakes.labels.setValue(azerty)
    fakes.labelChangesContinuation.yield()
    await store.receive(\.labelsChanged) { $0.labels = azerty }
    await task.cancel()
  }

  @Test func layerIsBindable() async throws {
    let fakes = try Fakes()
    let store = try makeStore(fakes)
    await store.send(.binding(.set(\.layer, .mod))) { $0.layer = .mod }
  }

  @Test func renameWritesThroughToConfiguration() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = try makeStore(fakes, id: codingID)

    await store.send(.binding(.set(\.name, "Work"))) {
      $0.name = "Work"
      $0.syncedName = "Work"
      $0.$keymap.withLock { $0.name = "Work" }
    }
    #expect(store.state.configuration.keymaps[id: codingID]?.name == "Work")
    #expect(try fakes.savedConfiguration()?.keymaps[id: codingID]?.name == "Work")
  }

  @Test func abbreviationIsNormalized() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = try makeStore(fakes, id: codingID)

    // Typing only changes the field; the keymap changes on commit.
    await store.send(.binding(.set(\.abbreviation, " wrk1 "))) { $0.abbreviation = " wrk1 " }
    #expect(store.state.keymap.abbreviation == "COD")
    await store.send(.abbreviationSubmitted) {
      $0.abbreviation = "WRK"
      $0.syncedAbbreviation = "WRK"
      $0.$keymap.withLock { $0.abbreviation = "WRK" }
    }
    #expect(store.state.configuration.keymaps[id: codingID]?.abbreviation == "WRK")
    #expect(try fakes.savedConfiguration()?.keymaps[id: codingID]?.abbreviation == "WRK")
  }

  @Test func emptyAbbreviationIsReverted() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = try makeStore(fakes, id: codingID)

    await store.send(.binding(.set(\.abbreviation, "   "))) { $0.abbreviation = "   " }
    await store.send(.abbreviationSubmitted) { $0.abbreviation = "COD" }
    #expect(try fakes.savedConfiguration()?.keymaps[id: codingID]?.abbreviation == "COD")
  }

  @Test func loadErrorMakesNameAndAbbreviationReadOnly() async throws {
    let corrupt = Data("{".utf8)
    let fakes = Fakes(fileData: corrupt)
    let store = try makeStore(fakes)
    #expect(store.state.isReadOnly)

    // Each edit is undone and nothing is written.
    await store.send(.binding(.set(\.name, "Work")))
    await store.send(.binding(.set(\.abbreviation, "wrk")))
    await store.send(.abbreviationSubmitted)
    // Layers can still be browsed.
    await store.send(.binding(.set(\.layer, .mod))) { $0.layer = .mod }
    // Keys still open the popover, read-only.
    await store.send(.keyTapped(.a)) {
      var popover = KeyActionEditorFeature.State(
        key: .a, layer: .mod, action: nil, keymaps: $0.configuration.keymaps.elements
      )
      popover.isReadOnly = true
      $0.keyAction = popover
    }
    #expect(store.state.keymap == Configuration.starter.keymaps[0])
    #expect(fakes.fileData == corrupt)
  }

  @Test func externalChangeResyncsDrafts() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = try makeStore(fakes, id: codingID)
    let task = await store.send(.task) { $0.labels = StaticKeyLabels.usANSI }

    try await editFileExternally(fakes, store)
    await store.receive(\.keymapChanged) {
      $0.name = "Elsewhere"
      $0.abbreviation = "ELS"
      $0.syncedName = "Elsewhere"
      $0.syncedAbbreviation = "ELS"
    }
    // Leaving the abbreviation field doesn't write anything back.
    await store.send(.abbreviationSubmitted)
    #expect(try fakes.savedConfiguration()?.keymaps[id: codingID]?.abbreviation == "ELS")
    await task.cancel()
  }

  @Test func abbreviationBeingEditedSurvivesExternalChange() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = try makeStore(fakes, id: codingID)
    let task = await store.send(.task) { $0.labels = StaticKeyLabels.usANSI }

    await store.send(.binding(.set(\.abbreviation, "xy"))) { $0.abbreviation = "xy" }
    try await editFileExternally(fakes, store)
    await store.receive(\.keymapChanged) {
      $0.name = "Elsewhere"
      $0.syncedName = "Elsewhere"
      $0.syncedAbbreviation = "ELS"
    }
    await store.send(.abbreviationSubmitted) {
      $0.abbreviation = "XY"
      $0.syncedAbbreviation = "XY"
      $0.$keymap.withLock { $0.abbreviation = "XY" }
    }
    await store.receive(\.keymapChanged)
    #expect(try fakes.savedConfiguration()?.keymaps[id: codingID]?.abbreviation == "XY")
    #expect(try fakes.savedConfiguration()?.keymaps[id: codingID]?.name == "Elsewhere")
    await task.cancel()
  }

  @Test func submitAfterExternalChangeWritesNothing() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    // No `.task`: the change isn't observed, as when it lands before the subscription.
    let store = try makeStore(fakes, id: codingID)

    try await editFileExternally(fakes, store)
    await store.send(.abbreviationSubmitted) {
      $0.abbreviation = "ELS"
      $0.syncedAbbreviation = "ELS"
    }
    #expect(store.state.keymap.abbreviation == "ELS")
    #expect(try fakes.savedConfiguration()?.keymaps[id: codingID]?.abbreviation == "ELS")
  }

  @Test func clearedLoadErrorResyncsDrafts() async throws {
    let fakes = Fakes(fileData: Data("{".utf8))
    let store = try makeStore(fakes)
    let task = await store.send(.task) { $0.labels = StaticKeyLabels.usANSI }
    #expect(store.state.isReadOnly)

    // The user fixes the file; the in-memory starter is replaced by their own keymap.
    try await editFileExternally(fakes, store, base: .starter, id: Keymap.starterID)
    #expect(!store.state.isReadOnly)
    await store.receive(\.keymapChanged) {
      $0.name = "Elsewhere"
      $0.abbreviation = "ELS"
      $0.syncedName = "Elsewhere"
      $0.syncedAbbreviation = "ELS"
    }
    await store.send(.abbreviationSubmitted)
    #expect(try fakes.savedConfiguration()?.keymaps[id: Keymap.starterID]?.abbreviation == "ELS")
    await task.cancel()
  }
}
