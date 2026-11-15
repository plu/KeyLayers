import ComposableArchitecture
@testable import ConfiguratorFeature
import Foundation
import HelperIPC
import KeyboardLayout
import KeymapModel
import SharedConfig
import Testing

private typealias Editor = KeyActionEditorFeature

private func runningHelper(paused: Bool) -> AsyncStream<HelperConnectionState> {
  AsyncStream { $0.yield(.running(HelperStatus(isPaused: paused, permissions: granted))) }
}

private let granted = PermissionStatus(accessibility: true)

@MainActor
private func makeEditorStore(_ fakes: Fakes, id: Keymap.ID = codingID) throws -> TestStoreOf<KeymapEditorFeature> {
  let state = try #require(fakes.makeState { KeymapEditorFeature.State(keymapID: id) })
  return TestStore(initialState: state) {
    KeymapEditorFeature()
  } withDependencies: {
    fakes.apply(to: &$0)
  }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct KeyActionEditorFeatureTests {
  // MARK: Initial state

  @Test func initialTabFollowsAction() {
    let layer = Editor.State(key: .capsLock, layer: .base, action: .switchLayer(.fn, mode: .toggle), keymaps: [])
    #expect(layer.tab == .layer)
    #expect(layer.targetLayer == .fn)
    #expect(layer.layerMode == .toggle)

    let empty = Editor.State(key: .capsLock, layer: .base, action: nil, keymaps: [])
    #expect(empty.tab == .keypress)
    #expect(empty.keypress == Keypress(key: nil, modifiers: []))
    #expect(empty.targetLayer == .mod)
    #expect(empty.layerMode == .holdAndDoubleTapToggle)

    let press = Keypress(key: .b, modifiers: [Modifiers(.leftCommand)], secondaryRole: .modifier(.leftShift))
    let keypress = Editor.State(key: .a, layer: .mod, action: .keypress(press), keymaps: [])
    #expect(keypress.tab == .keypress)
    #expect(keypress.keypress == press)

    let keymaps = twoKeymaps().keymaps.elements
    let keymap = Editor.State(key: .a, layer: .mod, action: .switchKeymap(codingID), keymaps: keymaps)
    #expect(keymap.tab == .keymap)
    #expect(keymap.targetKeymap == codingID)
    #expect(keymap.keymaps == keymaps)

    let block = Editor.State(key: .a, layer: .mod, action: .block, keymaps: [])
    #expect(block.tab == .none)
    #expect(block.noneIsBlock)

    let unsupported = Editor.State(key: .a, layer: .mod, action: .unsupported(type: "playMacro"), keymaps: [])
    #expect(unsupported.tab == .keypress)
  }

  // MARK: Apply

  @Test func applyKeypressWithSecondaryRole() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = try makeEditorStore(fakes)
    await store.send(.binding(.set(\.layer, .fn))) { $0.layer = .fn }
    await store.send(.keyTapped(.capsLock)) {
      $0.keyAction = Editor.State(
        key: .capsLock, layer: .fn, action: nil, keymaps: twoKeymaps().keymaps.elements
      )
    }
    await store.send(\.keyAction.binding.keypress, Keypress(key: .b, modifiers: [])) {
      $0.keyAction?.keypress.key = .b
    }
    await store.send(\.keyAction.binding.keypress, Keypress(key: .b, modifiers: [Modifiers(.leftCommand)])) {
      $0.keyAction?.keypress.modifiers = [Modifiers(.leftCommand)]
    }
    let press = Keypress(key: .b, modifiers: [Modifiers(.leftCommand)], secondaryRole: .layer(.mod))
    await store.send(\.keyAction.binding.keypress, press) {
      $0.keyAction?.keypress.secondaryRole = .layer(.mod)
    }
    #expect(store.state.keyAction?.canApply == true)
    // The delegate action is handled synchronously, so the shared keymap changes during this send.
    await store.send(\.keyAction.applyTapped) {
      $0.$keymap.withLock { $0.setAction(.keypress(press), for: .capsLock, on: .fn) }
    }
    await store.receive(\.keyAction.delegate.apply) { $0.keyAction = nil }
    let saved = try fakes.savedConfiguration()?.keymaps[id: codingID]
    #expect(saved?.action(for: .capsLock, on: .fn) == .keypress(press))
    #expect(saved?.action(for: .capsLock, on: .base) == nil)
  }

  @Test func applyLayerAndKeymap() async {
    let keymaps = twoKeymaps().keymaps.elements
    let store = TestStore(initialState: Editor.State(key: .a, layer: .base, action: nil, keymaps: keymaps)) {
      Editor()
    }
    await store.send(.binding(.set(\.tab, .layer))) { $0.tab = .layer }
    await store.send(.binding(.set(\.targetLayer, .fn2))) { $0.targetLayer = .fn2 }
    await store.send(.binding(.set(\.layerMode, .hold))) { $0.layerMode = .hold }
    await store.send(.applyTapped)
    await store.receive(\.delegate.apply, .switchLayer(.fn2, mode: .hold))

    await store.send(.binding(.set(\.tab, .keymap))) { $0.tab = .keymap }
    #expect(!store.state.canApply)
    await store.send(.binding(.set(\.targetKeymap, codingID))) { $0.targetKeymap = codingID }
    #expect(store.state.canApply)
    await store.send(.applyTapped)
    await store.receive(\.delegate.apply, .switchKeymap(codingID))
  }

  @Test func applyNoneTransparentRemovesAction() async throws {
    var configuration = twoKeymaps()
    configuration.keymaps[id: codingID]?.setAction(.block, for: .capsLock, on: .mod)
    configuration.keymaps[id: codingID]?.setAction(.block, for: .a, on: .mod)
    let fakes = try Fakes(file: configuration)
    let store = try makeEditorStore(fakes)
    await store.send(.binding(.set(\.layer, .mod))) { $0.layer = .mod }
    await store.send(.keyTapped(.capsLock)) {
      $0.keyAction = Editor.State(key: .capsLock, layer: .mod, action: .block, keymaps: configuration.keymaps.elements)
    }
    #expect(store.state.keyAction?.tab == Editor.State.Tab.none)
    await store.send(\.keyAction.binding.noneIsBlock, false) { $0.keyAction?.noneIsBlock = false }
    await store.send(\.keyAction.applyTapped) {
      $0.$keymap.withLock { $0.setAction(nil, for: .capsLock, on: .mod) }
    }
    await store.receive(\.keyAction.delegate.apply, nil) { $0.keyAction = nil }
    let saved = try fakes.savedConfiguration()?.keymaps[id: codingID]
    #expect(saved?.action(for: .capsLock, on: .mod) == nil)
    #expect(saved?.action(for: .a, on: .mod) == .block)
  }

  @Test func applyBlock() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = try makeEditorStore(fakes)
    await store.send(.keyTapped(.q)) {
      $0.keyAction = Editor.State(key: .q, layer: .base, action: nil, keymaps: twoKeymaps().keymaps.elements)
    }
    await store.send(\.keyAction.binding.tab, .none) { $0.keyAction?.tab = .none }
    #expect(store.state.keyAction?.canApply == true)
    await store.send(\.keyAction.binding.noneIsBlock, true) { $0.keyAction?.noneIsBlock = true }
    await store.send(\.keyAction.applyTapped) {
      $0.$keymap.withLock { $0.setAction(.block, for: .q, on: .base) }
    }
    await store.receive(\.keyAction.delegate.apply, .block) { $0.keyAction = nil }
    #expect(try fakes.savedConfiguration()?.keymaps[id: codingID]?.action(for: .q, on: .base) == .block)
  }

  @Test func cannotApplyEmptyKeypress() async {
    let store = TestStore(initialState: Editor.State(key: .a, layer: .base, action: nil, keymaps: [])) {
      Editor()
    }
    #expect(!store.state.canApply)
    // Apply does nothing while it can't apply.
    await store.send(.applyTapped)
    await store.send(.binding(.set(\.keypress, Keypress(key: nil, modifiers: [Modifiers(.leftShift)])))) {
      $0.keypress.modifiers = [Modifiers(.leftShift)]
    }
    #expect(store.state.canApply)
    await store.send(.binding(.set(\.keypress, Keypress(key: .x, modifiers: [])))) {
      $0.keypress = Keypress(key: .x, modifiers: [])
    }
    #expect(store.state.canApply)
  }

  @Test func cancelLeavesKeymapUnchanged() async throws {
    var configuration = twoKeymaps()
    configuration.keymaps[id: codingID]?.setAction(.block, for: .capsLock, on: .base)
    let fakes = try Fakes(file: configuration)
    let before = fakes.fileData
    let store = try makeEditorStore(fakes)
    await store.send(.keyTapped(.capsLock)) {
      $0.keyAction = Editor.State(key: .capsLock, layer: .base, action: .block, keymaps: configuration.keymaps.elements)
    }
    await store.send(\.keyAction.binding.noneIsBlock, false) { $0.keyAction?.noneIsBlock = false }
    await store.send(\.keyAction.cancelTapped)
    await store.receive(\.keyAction.dismiss) { $0.keyAction = nil }
    #expect(store.state.keymap.action(for: .capsLock, on: .base) == .block)
    #expect(fakes.fileData == before)
  }

  // MARK: Read-only

  @Test func loadErrorMakesPopoverReadOnly() async throws {
    let corrupt = Data("{".utf8)
    let fakes = Fakes(fileData: corrupt)
    let store = try makeEditorStore(fakes, id: Keymap.starterID)
    #expect(store.state.isReadOnly)
    let keymap = store.state.keymap
    await store.send(.keyTapped(.capsLock)) {
      var popover = Editor.State(
        key: .capsLock, layer: .base, action: keymap.action(for: .capsLock, on: .base),
        keymaps: $0.configuration.keymaps.elements
      )
      popover.isReadOnly = true
      $0.keyAction = popover
    }
    await store.send(\.keyAction.binding.tab, .none) { $0.keyAction?.tab = .none }
    await store.send(\.keyAction.binding.noneIsBlock, true) { $0.keyAction?.noneIsBlock = true }
    #expect(store.state.keyAction?.canApply == false)
    // Apply is disabled; even if it were sent, nothing is written.
    await store.send(\.keyAction.applyTapped)
    await store.send(\.keyAction.delegate.apply, .block)
    #expect(store.state.keymap == keymap)
    #expect(fakes.fileData == corrupt)
  }

  // MARK: Search

  @Test func searchFiltersKnownKeysByLabelAndName() {
    var state = Editor.State(key: .a, layer: .base, action: nil, keymaps: [])
    state.labels = StaticKeyLabels.usANSI
    #expect(state.searchResults.map(\.key) == KeyID.allKnown)
    state.searchText = "esc"
    #expect(state.searchResults.map(\.key) == [.escape])
    state.searchText = "b"
    #expect(state.searchResults.map(\.key).contains(.b))
    #expect(state.searchResults.first?.key == .b)
    state.searchText = "keypad 1"
    #expect(state.searchResults.map(\.key) == [.keypad1])
    state.searchText = "left command"
    #expect(state.searchResults.map(\.key) == [.leftGUI])
  }

  @Test func pickerOffersAMediaGroupInOrder() {
    var state = Editor.State(key: .a, layer: .base, action: nil, keymaps: [])
    state.labels = StaticKeyLabels.usANSI
    let media = state.searchResults.filter { $0.group == "Media" }
    #expect(media.map(\.key) == KeyID.mediaKeys)
    #expect(state.searchResults.filter { $0.group != nil }.count == media.count)
    #expect(media.map(\.name) == [
      "Brightness Down", "Brightness Up", "Mission Control", "Spotlight", "Dictation", "Do Not Disturb",
      "Previous Track", "Play/Pause", "Next Track", "Mute", "Volume Down", "Volume Up",
    ])
    state.searchText = "volume"
    #expect(state.searchResults.map(\.key) == [KeyID.mediaKeys[10], KeyID.mediaKeys[11]])
    state.searchText = "mute"
    #expect(state.searchResults.map(\.key) == [KeyID.mediaKeys[9]])
    state.searchText = "play"
    #expect(state.searchResults.map(\.key) == [KeyID.mediaKeys[7]])
    state.searchText = ""
    #expect(Array(state.searchResults.map(\.key).suffix(12)) == KeyID.mediaKeys)
    #expect(state.searchResults.last { $0.key == KeyID.mediaKeys[11] }?.accessibilityLabel == "Volume Up")
    #expect(state.searchResults.first { $0.key == .escape }?.accessibilityLabel == "⎋, Escape")
  }

  // MARK: Recording

  @Test func mediaTargetClearsAndDisablesModifiers() async {
    let shiftOption: Modifiers = [Modifiers(.leftShift), Modifiers(.leftOption)]
    let store = TestStore(initialState: Editor.State(key: .a, layer: .base, action: nil, keymaps: [])) {
      Editor()
    }
    await store.send(.binding(.set(\.keypress, Keypress(key: .x, modifiers: shiftOption)))) {
      $0.keypress = Keypress(key: .x, modifiers: shiftOption)
    }
    #expect(store.state.modifiersEnabled)
    // Media keys go out without modifiers: choosing one drops them, and the toggles are disabled.
    let volumeUp = KeyID.mediaKeys[11]
    await store.send(.binding(.set(\.keypress, Keypress(key: volumeUp, modifiers: shiftOption)))) {
      $0.keypress = Keypress(key: volumeUp, modifiers: [])
    }
    #expect(!store.state.modifiersEnabled)
    // Turning a toggle on while a media key is chosen is undone.
    await store.send(.binding(.set(\.keypress, Keypress(key: volumeUp, modifiers: [Modifiers(.leftCommand)]))))
    await store.send(.applyTapped)
    await store.receive(\.delegate, .apply(.keypress(Keypress(key: volumeUp, modifiers: []))))
    // Back to an ordinary key: modifiers are available again.
    await store.send(.binding(.set(\.keypress, Keypress(key: .x, modifiers: [])))) {
      $0.keypress = Keypress(key: .x, modifiers: [])
    }
    #expect(store.state.modifiersEnabled)
  }

  @Test func openingAMediaKeypressWithModifiersDropsThem() {
    let volumeUp = KeyID.mediaKeys[11]
    let state = Editor.State(
      key: .f12, layer: .mod,
      action: .keypress(Keypress(key: volumeUp, modifiers: [Modifiers(.leftShift)])), keymaps: []
    )
    #expect(state.keypress == Keypress(key: volumeUp, modifiers: []))
    #expect(!state.modifiersEnabled)
  }

  @Test func recordingAMediaKeyDropsModifiers() async {
    let volumeUp = KeyID.mediaKeys[11]
    var initial = Editor.State(key: .a, layer: .base, action: nil, keymaps: [])
    initial.keypress = Keypress(key: .x, modifiers: [Modifiers(.leftShift)])
    let store = TestStore(initialState: initial) { Editor() }
    await store.send(.recorded(volumeUp)) {
      $0.keypress = Keypress(key: volumeUp, modifiers: [])
    }
  }

  @Test func recordingPausesAndResumesHelper() async {
    let calls = LockIsolated<[String]>([])
    let clock = TestClock()
    let store = TestStore(initialState: Editor.State(key: .a, layer: .base, action: nil, keymaps: [])) {
      Editor()
    } withDependencies: {
      $0.continuousClock = clock
      $0.helperClient = HelperClient(
        states: { runningHelper(paused: false) },
        // A wedged helper: never replies. Recording must not wait for it.
        setPaused: { paused in
          calls.withValue { $0.append("setPaused(\(paused))") }
          try await Task.never()
        },
        start: {}
      )
      $0.keyRecorder = KeyRecorderClient(record: {
        calls.withValue { $0.append("record") }
        return .k
      })
    }
    await store.send(.recordTapped) { $0.isRecording = true }
    await store.receive(\.recorded, .k) {
      $0.isRecording = false
      $0.keypress.key = .k
    }
    #expect(calls.value == ["setPaused(true)", "record"])
    // The resume waits for the pause request's reply, giving up after a second. (Advanced in steps:
    // the resume task starts its timer asynchronously.)
    var waited = Duration.zero
    while calls.value.count < 3 {
      await clock.advance(by: .milliseconds(100))
      waited += .milliseconds(100)
      await Task.yield()
    }
    #expect(waited >= Editor.pauseReplyTimeout)
    #expect(calls.value == ["setPaused(true)", "record", "setPaused(false)"])
  }

  @Test func resumeWaitsForPauseReply() async {
    let calls = LockIsolated<[String]>([])
    let clock = TestClock()
    let store = TestStore(initialState: Editor.State(key: .a, layer: .base, action: nil, keymaps: [])) {
      Editor()
    } withDependencies: {
      $0.continuousClock = clock
      $0.helperClient = HelperClient(
        states: { runningHelper(paused: false) },
        // The pause request is answered after 0.3 s.
        setPaused: { paused in
          calls.withValue { $0.append("setPaused(\(paused))") }
          if paused {
            try await clock.sleep(for: .milliseconds(300))
            calls.withValue { $0.append("paused") }
          }
        },
        start: {}
      )
      $0.keyRecorder = KeyRecorderClient(record: {
        calls.withValue { $0.append("record") }
        return .k
      })
    }
    await store.send(.recordTapped) { $0.isRecording = true }
    await store.receive(\.recorded, .k) {
      $0.isRecording = false
      $0.keypress.key = .k
    }
    #expect(calls.value == ["setPaused(true)", "record"])
    await clock.advance(by: .milliseconds(300))
    while calls.value.count < 4 {
      await Task.yield()
    }
    #expect(calls.value == ["setPaused(true)", "record", "paused", "setPaused(false)"])
  }

  @Test func closingPopoverWhileRecordingResumesHelper() async throws {
    let calls = LockIsolated<[String]>([])
    let fakes = try Fakes(file: twoKeymaps())
    let state = try #require(fakes.makeState { KeymapEditorFeature.State(keymapID: codingID) })
    let store = TestStore(initialState: state) {
      KeymapEditorFeature()
    } withDependencies: {
      fakes.apply(to: &$0)
      $0.continuousClock = TestClock()
      $0.helperClient = HelperClient(
        states: { runningHelper(paused: false) },
        setPaused: { paused in calls.withValue { $0.append("setPaused(\(paused))") } },
        start: {}
      )
      // Records until cancelled, as the live recorder does.
      $0.keyRecorder = KeyRecorderClient(record: {
        calls.withValue { $0.append("record") }
        try? await Task.never()
        calls.withValue { $0.append("record cancelled") }
        return nil
      })
    }
    await store.send(.keyTapped(.a)) {
      $0.keyAction = Editor.State(key: .a, layer: .base, action: nil, keymaps: twoKeymaps().keymaps.elements)
    }
    await store.send(\.keyAction.recordTapped) { $0.keyAction?.isRecording = true }
    while calls.value.count < 2 {
      await Task.yield()
    }
    await store.send(\.keyAction.cancelTapped)
    await store.receive(\.keyAction.dismiss) { $0.keyAction = nil }
    while calls.value.count < 4 {
      await Task.yield()
    }
    #expect(calls.value == ["setPaused(true)", "record", "record cancelled", "setPaused(false)"])
  }

  @Test func recordingDoesNotTouchPausedHelper() async {
    let calls = LockIsolated<[String]>([])
    let store = TestStore(initialState: Editor.State(key: .a, layer: .base, action: nil, keymaps: [])) {
      Editor()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.helperClient = HelperClient(
        states: { runningHelper(paused: true) },
        setPaused: { paused in calls.withValue { $0.append("setPaused(\(paused))") } },
        start: {}
      )
      $0.keyRecorder = KeyRecorderClient(record: {
        calls.withValue { $0.append("record") }
        return .leftShift
      })
    }
    await store.send(.recordTapped) { $0.isRecording = true }
    await store.receive(\.recorded, .leftShift) {
      $0.isRecording = false
      $0.keypress.key = .leftShift
    }
    #expect(calls.value == ["record"])
  }

  @Test func recordingDoesNotTouchStoppedHelper() async {
    let calls = LockIsolated<[String]>([])
    let store = TestStore(initialState: Editor.State(key: .a, layer: .base, action: nil, keymaps: [])) {
      Editor()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.helperClient = HelperClient(
        states: { AsyncStream { $0.yield(.notRunning) } },
        setPaused: { paused in calls.withValue { $0.append("setPaused(\(paused))") } },
        start: {}
      )
      $0.keyRecorder = KeyRecorderClient(record: {
        calls.withValue { $0.append("record") }
        return .j
      })
    }
    await store.send(.recordTapped) { $0.isRecording = true }
    await store.receive(\.recorded, .j) {
      $0.isRecording = false
      $0.keypress.key = .j
    }
    #expect(calls.value == ["record"])
  }

  @Test func recordingProceedsWhenHelperStateNeverArrives() async {
    let calls = LockIsolated<[String]>([])
    let clock = TestClock()
    let store = TestStore(initialState: Editor.State(key: .a, layer: .base, action: nil, keymaps: [])) {
      Editor()
    } withDependencies: {
      $0.continuousClock = clock
      $0.helperClient = HelperClient(
        states: { AsyncStream { _ in } },
        setPaused: { paused in calls.withValue { $0.append("setPaused(\(paused))") } },
        start: {}
      )
      $0.keyRecorder = KeyRecorderClient(record: {
        calls.withValue { $0.append("record") }
        return .j
      })
    }
    await store.send(.recordTapped) { $0.isRecording = true }
    await clock.advance(by: .seconds(1))
    await store.receive(\.recorded, .j) {
      $0.isRecording = false
      $0.keypress.key = .j
    }
    #expect(calls.value == ["record"])
  }

  @Test func cancelledRecordingKeepsKey() async {
    let pressB = KeyAction.keypress(Keypress(key: .b, modifiers: []))
    let store = TestStore(initialState: Editor.State(key: .a, layer: .base, action: pressB, keymaps: [])) {
      Editor()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.helperClient = HelperClient(states: { AsyncStream { $0.yield(.notRunning) } }, setPaused: { _ in }, start: {})
      $0.keyRecorder = KeyRecorderClient(record: { nil })
    }
    await store.send(.recordTapped) { $0.isRecording = true }
    await store.receive(\.recorded, nil) { $0.isRecording = false }
    #expect(store.state.keypress.key == .b)
  }
}
