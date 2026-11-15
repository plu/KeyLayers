import Clocks
import Foundation
@testable import HelperFeature
import IdentifiedCollections
import InputDaemonIPC
import KeyIO
import KeymapModel
import RemapEngine
import Synchronization
import Testing

private func down(_ key: KeyID) -> KeyEvent {
  KeyEvent(key: key, phase: .down, timestamp: 0)
}

private func up(_ key: KeyID) -> KeyEvent {
  KeyEvent(key: key, phase: .up, timestamp: 0)
}

private func out(_ key: KeyID, _ isDown: Bool) -> OutputEvent {
  OutputEvent(key: key, isDown: isDown, modifiers: [])
}

private let otherKeymapID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

/// The starter keymap plus a second keymap that maps A to B.
private let twoKeymaps: Configuration = {
  var configuration = Configuration.starter
  configuration.keymaps.append(Keymap(
    id: otherKeymapID,
    name: "Other",
    abbreviation: "OTH",
    layers: [.base: Layer(actions: [.a: .keypress(Keypress(key: .b, modifiers: []))])]
  ))
  return configuration
}()

private func status(_ keymap: Keymap.ID = Keymap.starterID, _ layer: LayerName = .base) -> RuntimeEvent {
  .status(EngineStatus(activeKeymapID: keymap, activeLayer: layer))
}

/// The first `count` events the runtime yielded. Yields are synchronous, so they are already buffered.
private func firstEvents(_ runtime: RemapperRuntime, _ count: Int) async -> [RuntimeEvent] {
  var result: [RuntimeEvent] = []
  for await event in runtime.events.prefix(count) {
    result.append(event)
  }
  return result
}

@Suite(.timeLimit(.minutes(1)))
struct RemapperRuntimeTests {
  @Test func remapsThroughEngine() throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    #expect(io.send(down(.fn)) == .suppress)
    #expect(io.send(down(.h)) == .suppress)
    #expect(io.posted.contains(out(.leftArrow, true)))
  }

  @Test func startEnablesCapture() throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    #expect(io.captureEnabled.last == true)
  }

  @Test func pauseDisablesCapture() throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    runtime.setPaused(true)
    #expect(io.captureEnabled.last == false)
  }

  @Test func resumeEnablesCapture() throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    runtime.setPaused(true)
    runtime.setPaused(false)
    #expect(io.captureEnabled.last == true)
  }

  @Test func captureStaysOffWhenStartedPaused() throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    runtime.setPaused(true)
    try runtime.start()
    runtime.update(configuration: twoKeymaps)
    runtime.selectKeymap(otherKeymapID)
    #expect(!io.captureEnabled.isEmpty)
    #expect(!io.captureEnabled.contains(true))
  }

  @Test func stopDisablesCapture() throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    runtime.stop()
    #expect(io.captureEnabled.last == false)
    // A configuration update or keymap switch after stopping must not take the keyboards over again.
    runtime.update(configuration: twoKeymaps)
    runtime.selectKeymap(otherKeymapID)
    #expect(io.captureEnabled.last == false)
  }

  @Test func pauseReleasesHeldKeys() throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    _ = io.send(down(.fn))
    _ = io.send(down(.h))
    runtime.setPaused(true)
    #expect(io.posted.last == out(.leftArrow, false))
    let postedWhilePaused = io.posted.count
    #expect(io.send(down(.a)) == .passThrough)
    #expect(io.send(down(.h)) == .passThrough)
    #expect(io.posted.count == postedWhilePaused)
  }

  @Test func interruptedInputReleasesHeldKeys() async throws {
    // The daemon connection dropped: key-ups may have been lost.
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    _ = io.send(down(.fn))
    _ = io.send(down(.h))
    io.interrupt()
    #expect(io.posted.last == out(.leftArrow, false))
    #expect(await firstEvents(runtime, 3) == [status(), status(Keymap.starterID, .mod), status()])
    // Remapping goes on from a clean state.
    _ = io.send(down(.fn))
    #expect(io.send(down(.h)) == .suppress)
  }

  @Test func pauseYieldsBaseLayerStatus() async throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    _ = io.send(down(.fn))
    _ = io.send(down(.h)) // activates Mod
    runtime.setPaused(true)
    #expect(await firstEvents(runtime, 3) == [status(), status(Keymap.starterID, .mod), status()])
  }

  @Test func resumeRemapsAgain() throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    runtime.setPaused(true)
    runtime.setPaused(false)
    _ = io.send(down(.fn))
    #expect(io.send(down(.h)) == .suppress)
    #expect(io.posted.contains(out(.leftArrow, true)))
  }

  @Test func emergencyStopPausesRuntime() async throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    for key in [KeyID.leftControl, .leftAlt, .leftGUI, .escape] {
      _ = io.send(down(key))
    }
    #expect(await firstEvents(runtime, 3) == [status(), status(), .notification(.emergencyStop)])
    #expect(io.captureEnabled.last == false)
    _ = io.send(down(.fn))
    #expect(io.send(down(.h)) == .passThrough)
    #expect(!io.posted.contains(out(.leftArrow, true)))
  }

  @Test func updateKeepsRemappingLive() throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    var configuration = Configuration.starter
    configuration.keymaps[id: Keymap.starterID]?.setAction(
      .keypress(Keypress(key: .b, modifiers: [])), for: .a, on: .base
    )
    runtime.update(configuration: configuration)
    #expect(io.send(down(.a)) == .suppress)
    #expect(io.posted == [out(.b, true)])
  }

  @Test func keymapSwitchKeySwitchesKeymap() async throws {
    let io = FakeKeyIO()
    var configuration = twoKeymaps
    configuration.keymaps[id: Keymap.starterID]?.setAction(.switchKeymap(otherKeymapID), for: .b, on: .base)
    let runtime = RemapperRuntime(io: io, configuration: configuration, macros: .testing(clock: TestClock()))
    try runtime.start()
    _ = io.send(down(.b))
    #expect(io.send(down(.a)) == .suppress)
    #expect(await firstEvents(runtime, 3) == [
      status(), status(otherKeymapID), .notification(.keymapSwitched(otherKeymapID)),
    ])
  }

  @Test func selectKeymapYieldsStatusAndNotification() async throws {
    let runtime = RemapperRuntime(io: FakeKeyIO(), configuration: twoKeymaps, macros: .testing(clock: TestClock()))
    try runtime.start()
    runtime.selectKeymap(otherKeymapID)
    #expect(await firstEvents(runtime, 3) == [
      status(), status(otherKeymapID), .notification(.keymapSwitched(otherKeymapID)),
    ])
  }

  @Test func restartReleasesHeldKeys() async throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    _ = io.send(down(.fn))
    _ = io.send(down(.h))
    try runtime.start()
    #expect(io.posted.last == out(.leftArrow, false))
    #expect(await firstEvents(runtime, 3) == [status(), status(Keymap.starterID, .mod), status()])
  }

  @Test func hostEventsResubscribe() async throws {
    let io = FakeKeyIO()
    let host = RuntimeHost { configuration, _ in
      RemapperRuntime(io: io, configuration: configuration, macros: .testing(clock: TestClock()))
    }
    let first = host.events()
    let second = host.events()
    var firstEvents: [RuntimeEvent] = []
    for await event in first {
      firstEvents.append(event)
    }
    #expect(firstEvents.isEmpty)
    try host.start(.starter)
    var iterator = second.makeAsyncIterator()
    #expect(await iterator.next() == status())
  }

  @Test func hostForwardsBackendEvents() async throws {
    let io = FakeKeyIO()
    let device = InputDevice(
      id: 1, name: "Keyboard", vendorID: 0x05AC, productID: 1, countryCode: 0, seizeError: nil
    )
    let sender = Mutex<(@Sendable (RuntimeEvent) -> Void)?>(nil)
    let host = RuntimeHost { configuration, send in
      sender.withLock { $0 = send }
      return RemapperRuntime(io: io, configuration: configuration, macros: .testing(clock: TestClock()))
    }
    try host.start(.starter)
    // The backend reports its devices (HIDBackend's onDevicesChanged) on its own thread.
    sender.withLock { $0 }?(.devices([device]))
    var events: [RuntimeEvent] = []
    for await event in host.events().prefix(2) {
      events.append(event)
    }
    // The engine's status and the backend's devices take different paths: either may come first.
    #expect(events.contains(.devices([device])))
    #expect(events.contains(status()))
  }

  @Test func stopReleasesHeldKeysAndStopsBackend() throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    _ = io.send(down(.fn))
    _ = io.send(down(.h))
    runtime.stop()
    #expect(io.posted.last == out(.leftArrow, false))
    #expect(io.stopCount == 1)
  }

  @Test func stopTwiceIsHarmless() throws {
    let io = FakeKeyIO()
    let runtime = RemapperRuntime(io: io, configuration: .starter, macros: .testing(clock: TestClock()))
    try runtime.start()
    _ = io.send(down(.fn))
    _ = io.send(down(.h))
    runtime.stop()
    let posted = io.posted.count
    runtime.stop() // e.g. quit from the menu, then applicationWillTerminate
    #expect(io.posted.count == posted)
    #expect(io.stopCount == 2)
    #expect(io.captureEnabled.last == false)
  }

  @Test func hostStopStopsRuntime() throws {
    let io = FakeKeyIO()
    let host = RuntimeHost { configuration, _ in
      RemapperRuntime(io: io, configuration: configuration, macros: .testing(clock: TestClock()))
    }
    host.stop() // before start: nothing to stop
    #expect(io.stopCount == 0)
    try host.start(.starter)
    host.stop()
    #expect(io.stopCount == 1)
  }

  @Test func startFailureThrows() {
    let runtime = RemapperRuntime(
      io: FakeKeyIO(startError: KeyIOError.daemonUnavailable),
      configuration: .starter,
      macros: .testing(clock: TestClock())
    )
    #expect(throws: KeyIOError.daemonUnavailable) { try runtime.start() }
  }
}
