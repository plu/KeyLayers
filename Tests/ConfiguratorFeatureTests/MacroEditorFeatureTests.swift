import ComposableArchitecture
@testable import ConfiguratorFeature
import Foundation
import HelperIPC
import KeyboardLayout
import KeymapModel
import SharedConfig
import Testing

private let macroID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!

private let sampleSteps: [MacroStep] = [
  .text("hi"),
  .delay(milliseconds: 50),
  .unsupported(type: "mouse"),
  .key(KeyStep(key: .a, modifiers: [], kind: .tap)),
]

private func configuration(steps: [MacroStep] = sampleSteps) -> Configuration {
  var configuration = Configuration.starter
  configuration.macros = [Macro(id: macroID, name: "Greet", steps: steps)]
  return configuration
}

@MainActor
private func makeStore(
  _ fakes: Fakes,
  dependencies: @escaping (inout DependencyValues) -> Void = { _ in }
) -> TestStoreOf<MacroEditorFeature> {
  TestStore(initialState: fakes.makeState { MacroEditorFeature.State(macroID: macroID) }) {
    MacroEditorFeature()
  } withDependencies: {
    fakes.apply(to: &$0)
    dependencies(&$0)
  }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MacroEditorFeatureTests {
  @Test func addAppendsEachKind() async throws {
    let fakes = try Fakes(file: configuration(steps: []))
    let store = makeStore(fakes)

    await store.send(.addStep(.key)) {
      $0.$configuration.withLock {
        $0.macros[id: macroID]?.steps = [.key(KeyStep(key: nil, modifiers: [], kind: .tap))]
      }
    }
    await store.send(.addStep(.text)) {
      $0.$configuration.withLock { $0.macros[id: macroID]?.steps.append(.text("")) }
    }
    await store.send(.addStep(.delay)) {
      $0.$configuration.withLock { $0.macros[id: macroID]?.steps.append(.delay(milliseconds: 100)) }
    }
    #expect(try fakes.savedConfiguration()?.macros[id: macroID]?.steps == [
      .key(KeyStep(key: nil, modifiers: [], kind: .tap)),
      .text(""),
      .delay(milliseconds: 100),
    ])
  }

  @Test func stepChangedWritesTheStep() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)
    let step = MacroStep.key(KeyStep(key: .b, modifiers: Modifiers(.leftShift), kind: .press))

    await store.send(.stepChanged(3, step)) {
      $0.$configuration.withLock { $0.macros[id: macroID]?.steps[3] = step }
    }
    await store.send(.stepChanged(0, .text("hello"))) {
      $0.$configuration.withLock { $0.macros[id: macroID]?.steps[0] = .text("hello") }
    }
    // A negative delay is stored as 0.
    await store.send(.stepChanged(1, .delay(milliseconds: -5))) {
      $0.$configuration.withLock { $0.macros[id: macroID]?.steps[1] = .delay(milliseconds: 0) }
    }
    // Unsupported steps are preserved; out-of-range indices are ignored.
    await store.send(.stepChanged(2, .text("x")))
    await store.send(.stepChanged(9, .text("x")))
    #expect(try fakes.savedConfiguration()?.macros[id: macroID]?.steps == [
      .text("hello"), .delay(milliseconds: 0), .unsupported(type: "mouse"), step,
    ])
  }

  @Test func delayIsKeptWithinTheMinute() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)
    // Playback never waits longer than 60 000 ms, so a longer delay isn't stored either.
    await store.send(.stepChanged(1, .delay(milliseconds: 70000))) {
      $0.$configuration.withLock { $0.macros[id: macroID]?.steps[1] = .delay(milliseconds: 60000) }
    }
    await store.send(.stepChanged(1, .delay(milliseconds: 60000)))
  }

  @Test func mediaKeyStepsHaveNoModifiers() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)
    // Media keys are sent without modifiers: choosing one clears them, as the key action editor does.
    let media = KeyStep(key: .volumeUp, modifiers: Modifiers(.leftCommand), kind: .tap)
    await store.send(.stepChanged(3, .key(media))) {
      $0.$configuration.withLock {
        $0.macros[id: macroID]?.steps[3] = .key(KeyStep(key: .volumeUp, modifiers: [], kind: .tap))
      }
    }
    #expect(!KeyStep(key: .volumeUp, modifiers: [], kind: .tap).modifiersEnabled)
    #expect(KeyStep(key: .a, modifiers: [], kind: .tap).modifiersEnabled)
    #expect(KeyStep(key: nil, modifiers: [], kind: .tap).modifiersEnabled)
  }

  @Test func deleteAndMoveReorderSteps() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)

    // Move the key step to the front.
    await store.send(.moveSteps(IndexSet(integer: 3), 0)) {
      $0.$configuration.withLock {
        $0.macros[id: macroID]?.steps = [sampleSteps[3], sampleSteps[0], sampleSteps[1], sampleSteps[2]]
      }
    }
    // Move the first two to the end.
    await store.send(.moveSteps(IndexSet([0, 1]), 4)) {
      $0.$configuration.withLock {
        $0.macros[id: macroID]?.steps = [sampleSteps[1], sampleSteps[2], sampleSteps[3], sampleSteps[0]]
      }
    }
    await store.send(.deleteStep(0)) {
      $0.$configuration.withLock { _ = $0.macros[id: macroID]?.steps.remove(at: 0) }
    }
    await store.send(.deleteStep(7))
    #expect(try fakes.savedConfiguration()?.macros[id: macroID]?.steps == [
      sampleSteps[2], sampleSteps[3], sampleSteps[0],
    ])
  }

  @Test func renameWritesTrimmedNameAndKeepsOldWhenEmpty() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)

    await store.send(.nameChanged("Sign ")) {
      $0.name = "Sign "
      $0.$configuration.withLock { $0.macros[id: macroID]?.name = "Sign" }
    }
    await store.send(.nameChanged("  ")) { $0.name = "  " }
    #expect(try fakes.savedConfiguration()?.macros[id: macroID]?.name == "Sign")
    // Committing an empty draft brings back the saved name.
    await store.send(.nameSubmitted) { $0.name = "Sign" }
  }

  @Test func recordingSetsTheStepsKey() async throws {
    let fakes = try Fakes(file: configuration())
    // A running helper is paused while recording, as in the key action editor.
    let status = HelperStatus(isPaused: false, permissions: PermissionStatus(accessibility: true))
    fakes.statesContinuation.yield(.running(status))
    let store = makeStore(fakes) {
      $0.continuousClock = TestClock()
      $0.keyRecorder = KeyRecorderClient(record: { .b })
    }

    await store.send(.recordTapped(3)) { $0.recordingStep = 3 }
    await store.receive(\.recorded) {
      $0.recordingStep = nil
      $0.$configuration.withLock {
        $0.macros[id: macroID]?.steps[3] = .key(KeyStep(key: .b, modifiers: [], kind: .tap))
      }
    }
    // Only key steps record.
    await store.send(.recordTapped(0))
    while fakes.pauseRequests.value.count < 2 {
      await Task.yield()
    }
    #expect(fakes.pauseRequests.value == [true, false])
  }

  @Test func recordedIsAppliedToTheGivenStep() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)
    await store.send(.recorded(3, .b)) {
      $0.$configuration.withLock {
        $0.macros[id: macroID]?.steps[3] = .key(KeyStep(key: .b, modifiers: [], kind: .tap))
      }
    }
    // No key (timeout or cancel) leaves the step alone.
    await store.send(.recorded(3, nil))
  }

  @Test func untypeableListsUniqueCharactersInOrder() {
    let feature = withDependencies {
      $0.textKeystrokes = TextKeystrokeClient(strokes: { $0.isASCII ? [] : nil }, capsLockIsOn: { false }, refresh: {})
    } operation: {
      MacroEditorFeature()
    }
    #expect(feature.untypeable("Cheers ☕☕") == ["☕"])
    #expect(feature.untypeable("é☕e☕é") == ["é", "☕"])
    #expect(feature.untypeable("plain").isEmpty)
  }

  @Test func untypeableCharactersAreKeptPerTextStep() async throws {
    let fakes = try Fakes(file: configuration(steps: [.text("Coffee ☕"), .delay(milliseconds: 5), .text("ok")]))
    let store = makeStore(fakes)

    // Known as soon as the editor appears.
    let task = await store.send(.task) {
      $0.labels = StaticKeyLabels.usANSI
      $0.untypeable = [0: ["☕"]]
    }
    // Text edits recompute it.
    await store.send(.stepChanged(2, .text("tea é"))) {
      $0.$configuration.withLock { $0.macros[id: macroID]?.steps[2] = .text("tea é") }
      $0.untypeable = [0: ["☕"], 2: ["é"]]
    }
    await store.receive(\.macroChanged)
    // Steps that move take their characters along.
    await store.send(.moveSteps(IndexSet(integer: 2), 0)) {
      $0.$configuration.withLock {
        $0.macros[id: macroID]?.steps = [.text("tea é"), .text("Coffee ☕"), .delay(milliseconds: 5)]
      }
      $0.untypeable = [0: ["é"], 1: ["☕"]]
    }
    await store.receive(\.macroChanged)

    // A new input source: the text table is brought up to date before the characters are checked.
    fakes.typeable.setValue { $0 != "☕" }
    fakes.labelChangesContinuation.yield()
    await store.receive(\.labelsChanged) { $0.untypeable = [1: ["☕"]] }
    #expect(fakes.textRefreshes.value == 1)

    // A change saved elsewhere too.
    store.state.$configuration.withLock { $0.macros[id: macroID]?.steps[1] = .text("Coffee") }
    await store.receive(\.macroChanged) { $0.untypeable = [:] }
    await task.cancel()
  }

  @Test func readOnlyIgnoresEdits() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes) {
      $0.keyRecorder = KeyRecorderClient(record: { .b })
    }
    // The file breaks after the macro was loaded: the macro stays in memory, read-only.
    let corrupt = Data("{".utf8)
    fakes.writeFile(corrupt)
    try? await store.state.$configuration.load()
    #expect(store.state.isReadOnly)
    let macro = try #require(store.state.macro)
    #expect(macro.steps == sampleSteps)

    await store.send(.nameChanged("New"))
    await store.send(.addStep(.text))
    await store.send(.deleteStep(0))
    await store.send(.moveSteps(IndexSet(integer: 0), 2))
    await store.send(.stepChanged(0, .text("x")))
    await store.send(.recordTapped(3))
    await store.send(.recorded(3, .b))
    #expect(store.state.macro == macro)
    #expect(fakes.fileData == corrupt)
  }

  @Test func changesOfAnotherMacroAreIgnored() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)
    // A watcher left over from a previously edited macro reports that macro gone.
    await store.send(.macroChanged(UUID(), nil))
    await store.send(.macroChanged(UUID(), Macro(id: UUID(), name: "Other", steps: [])))
  }

  @Test func removedMacroIsReported() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)

    let task = await store.send(.task) { $0.labels = StaticKeyLabels.usANSI }
    store.state.$configuration.withLock { $0.macros = [] }
    await store.receive(\.macroChanged)
    await store.receive(\.delegate.macroRemoved)
    await task.cancel()
  }

  @Test func externalRenameUpdatesTheNameField() async throws {
    let fakes = try Fakes(file: configuration())
    let store = makeStore(fakes)

    let task = await store.send(.task) { $0.labels = StaticKeyLabels.usANSI }
    store.state.$configuration.withLock { $0.macros[id: macroID]?.name = "Hello" }
    await store.receive(\.macroChanged) { $0.name = "Hello" }
    await task.cancel()
  }
}
