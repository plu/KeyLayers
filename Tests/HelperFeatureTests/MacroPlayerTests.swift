import Foundation
@testable import HelperFeature
import KeyboardLayout
import KeyIO
import KeymapModel
import RemapEngine
import Synchronization
import Testing

extension MacroEnvironment {
  /// Macros on `clock`, with no text table and Caps Lock off unless given.
  static func testing(
    clock: some Clock<Duration>,
    strokes: @escaping @Sendable (Character) -> [TextStroke]? = { _ in nil },
    capsLockIsOn: @escaping @Sendable () -> Bool = { false },
    refreshStrokes: @escaping @Sendable () async -> Void = {}
  ) -> MacroEnvironment {
    MacroEnvironment(clock: clock, strokes: strokes, capsLockIsOn: capsLockIsOn, refreshStrokes: refreshStrokes)
  }
}

private func down(_ key: KeyID) -> KeyEvent {
  KeyEvent(key: key, phase: .down, timestamp: 0)
}

private func up(_ key: KeyID) -> KeyEvent {
  KeyEvent(key: key, phase: .up, timestamp: 0)
}

private func out(_ key: KeyID, _ isDown: Bool, _ modifiers: Modifiers = []) -> OutputEvent {
  OutputEvent(key: key, isDown: isDown, modifiers: modifiers)
}

private func tap(_ key: KeyID) -> MacroStep {
  .key(KeyStep(key: key, modifiers: [], kind: .tap))
}

private func press(_ key: KeyID) -> MacroStep {
  .key(KeyStep(key: key, modifiers: [], kind: .press))
}

private let pressShift = MacroStep.key(KeyStep(key: nil, modifiers: Modifiers(.leftShift), kind: .press))

private let letters: [Character: [TextStroke]] = [
  "l": [TextStroke(key: .l, modifiers: [])],
]

/// Holds ⇧, taps B, waits a second, then presses C: cancelling after B must release ⇧ and never post C.
private let cancellable: [MacroStep] = [pressShift, tap(.b), .delay(milliseconds: 1000), press(.c)]

/// The starter configuration with a macro of `steps` on A.
private func configuration(_ steps: [MacroStep]) -> Configuration {
  let macro = Macro(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, name: "M", steps: steps)
  var configuration = Configuration.starter
  configuration.macros = [macro]
  configuration.keymaps[id: Keymap.starterID]?.setAction(.macro(macro.id), for: .a, on: .base)
  return configuration
}

/// The Caps Lock state the player reads.
private final class CapsLock: Sendable {
  private let state = Mutex(false)

  var isOn: Bool {
    get { state.withLock { $0 } }
    set { state.withLock { $0 = newValue } }
  }
}

/// A text table that is only filled in by a refresh, like one for an input source the player
/// hasn't seen yet.
private final class RefreshedTable: Sendable {
  private let state = Mutex((table: [Character: [TextStroke]](), refreshes: 0))

  var refreshes: Int {
    state.withLock { $0.refreshes }
  }

  func strokes(_ character: Character) -> [TextStroke]? {
    state.withLock { $0.table[character] }
  }

  func refresh() {
    state.withLock {
      $0.table = letters
      $0.refreshes += 1
    }
  }
}

@Suite(.timeLimit(.minutes(1)))
struct MacroPlayerTests {
  let clock = ManualClock()
  let io = FakeKeyIO()
  private let capsLock = CapsLock()

  func start(_ steps: [MacroStep], file: Configuration? = nil) throws -> RemapperRuntime {
    try start(steps, file: file, strokes: { letters[$0] })
  }

  func start(
    _ steps: [MacroStep],
    file: Configuration? = nil,
    strokes: @escaping @Sendable (Character) -> [TextStroke]?,
    refreshStrokes: @escaping @Sendable () async -> Void = {}
  ) throws -> RemapperRuntime {
    let capsLock = capsLock
    let runtime = RemapperRuntime(
      io: io,
      configuration: file ?? configuration(steps),
      macros: .testing(
        clock: clock,
        strokes: strokes,
        capsLockIsOn: { capsLock.isOn },
        refreshStrokes: refreshStrokes
      )
    )
    try runtime.start()
    return runtime
  }

  /// Presses and releases A, the macro key.
  func pressMacroKey() {
    #expect(io.send(down(.a)) == .suppress)
    #expect(io.send(up(.a)) == .suppress)
  }

  /// Waits until `condition` holds, yielding to let the player task run (it resumes asynchronously
  /// after `ManualClock.advance`). Bounded by iterations, not wall-clock time.
  func eventually(_ condition: () -> Bool) async {
    for _ in 0 ..< 100_000 {
      if condition() {
        return
      }
      await Task.yield()
    }
  }

  /// Gives the player task plenty of chances to run, for checking that something does *not* happen.
  func settle() async {
    for _ in 0 ..< 1000 {
      await Task.yield()
    }
  }

  /// Expects the first `count` posts, each one gap after the one before. (The first may already be
  /// out: the player starts on its own task.)
  func expectPostsOneGapApart(_ count: Int) async {
    for index in 1 ... count {
      await eventually { io.posted.count == index }
      #expect(io.posted.count == index)
      await settle()
      #expect(io.posted.count == index, "posted before the gap elapsed")
      clock.advance(by: MacroPlayer.eventGap)
    }
  }

  // MARK: Playback

  @Test func playsStepsWithGaps() async throws {
    let runtime = try start([tap(.b), tap(.c)])
    pressMacroKey()
    await expectPostsOneGapApart(4)
    #expect(io.posted == [out(.b, true), out(.b, false), out(.c, true), out(.c, false)])
    withExtendedLifetime(runtime) {}
  }

  @Test func delayWaits() async throws {
    let runtime = try start([tap(.b), .delay(milliseconds: 100), tap(.c)])
    pressMacroKey()
    await expectPostsOneGapApart(1)
    await eventually { io.posted.count == 2 } // B↑
    clock.advance(by: .milliseconds(90))
    await settle()
    #expect(io.posted == [out(.b, true), out(.b, false)])
    clock.advance(by: .milliseconds(15))
    await eventually { io.posted.count == 3 }
    #expect(io.posted == [out(.b, true), out(.b, false), out(.c, true)])
    withExtendedLifetime(runtime) {}
  }

  @Test func textRunRefreshesTheTableFirst() async throws {
    let table = RefreshedTable()
    let runtime = try start([.text("l")], strokes: table.strokes, refreshStrokes: table.refresh)
    pressMacroKey()
    await expectPostsOneGapApart(2)
    #expect(io.posted == [out(.l, true), out(.l, false)])
    #expect(table.refreshes == 1)
    withExtendedLifetime(runtime) {}
  }

  @Test func runWithoutTextDoesNotRefresh() async throws {
    let table = RefreshedTable()
    let runtime = try start([tap(.b), .text("")], strokes: table.strokes, refreshStrokes: table.refresh)
    pressMacroKey()
    await expectPostsOneGapApart(2)
    #expect(io.posted == [out(.b, true), out(.b, false)])
    #expect(table.refreshes == 0)
    withExtendedLifetime(runtime) {}
  }

  @Test func doubledLetters() async throws {
    let runtime = try start([.text("ll")])
    pressMacroKey()
    await expectPostsOneGapApart(4)
    #expect(io.posted == [out(.l, true), out(.l, false), out(.l, true), out(.l, false)])
    withExtendedLifetime(runtime) {}
  }

  @Test func pressWithoutReleaseIsReleasedAtEnd() async throws {
    let runtime = try start([pressShift, tap(.b)])
    pressMacroKey()
    await expectPostsOneGapApart(3)
    await eventually { io.posted.count == 4 }
    #expect(io.posted == [out(.leftShift, true), out(.b, true), out(.b, false), out(.leftShift, false)])
    withExtendedLifetime(runtime) {}
  }

  /// The cleanup ups of one run and the first down of the next are a gap apart, so a key released
  /// at the end of a run and pressed again at the start of the next isn't doubled.
  @Test func backToBackRunsKeepTheGap() async throws {
    let runtime = try start([pressShift, tap(.b)])
    pressMacroKey()
    pressMacroKey()
    await expectPostsOneGapApart(8)
    let run = [out(.leftShift, true), out(.b, true), out(.b, false), out(.leftShift, false)]
    #expect(io.posted == run + run)
    withExtendedLifetime(runtime) {}
  }

  /// Engine output of the macro key's down (here the ⇧ up of a held Caps Lock-as-⇧) is posted
  /// before anything the macro plays.
  @Test func engineOutputComesBeforeTheMacro() async throws {
    var file = configuration([tap(.b)])
    let shift = KeyAction.keypress(Keypress(key: .leftShift, modifiers: []))
    file.keymaps[id: Keymap.starterID]?.setAction(shift, for: .capsLock, on: .base)
    let runtime = try start([tap(.b)], file: file)
    #expect(io.send(down(.capsLock)) == .suppress)
    #expect(io.posted.map(\.key) == [.leftShift])
    pressMacroKey()
    await eventually { io.posted.count == 3 }
    #expect(io.posted.dropFirst().map(\.key) == [.leftShift, .b])
    #expect(io.posted.dropFirst().map(\.isDown) == [false, true])
    withExtendedLifetime(runtime) {}
  }

  @Test func secondPressQueues() async throws {
    let runtime = try start([tap(.b), tap(.c)])
    pressMacroKey()
    pressMacroKey()
    await expectPostsOneGapApart(8)
    let run = [out(.b, true), out(.b, false), out(.c, true), out(.c, false)]
    #expect(io.posted == run + run)
    withExtendedLifetime(runtime) {}
  }

  @Test func pinnedToSourceDevice() async throws {
    let runtime = try start([tap(.b), tap(.c)])
    io.sourceDevice = 7
    pressMacroKey()
    io.sourceDevice = 9
    await expectPostsOneGapApart(4)
    #expect(io.posted.count == 4)
    #expect(io.postedDevices == [7, 7, 7, 7])
    withExtendedLifetime(runtime) {}
  }

  @Test func removedDeviceCancels() async throws {
    let runtime = try start([tap(.b), .delay(milliseconds: 1000), tap(.c)])
    io.sourceDevice = 7
    pressMacroKey()
    pressMacroKey() // queued
    await expectPostsOneGapApart(2)
    io.removedDevices = [7]
    clock.advance(by: .seconds(2))
    await settle()
    io.removedDevices = []
    clock.advance(by: .seconds(5))
    await settle()
    #expect(io.posted == [out(.b, true), out(.b, false)])
    withExtendedLifetime(runtime) {}
  }

  // MARK: Caps Lock

  @Test func capsLockRestoredAroundText() async throws {
    capsLock.isOn = true
    let runtime = try start([.text("ll")])
    pressMacroKey()
    await expectPostsOneGapApart(8)
    #expect(io.posted == [
      out(.capsLock, true), out(.capsLock, false),
      out(.l, true), out(.l, false), out(.l, true), out(.l, false),
      out(.capsLock, true), out(.capsLock, false),
    ])
    withExtendedLifetime(runtime) {}
  }

  /// A Text step that types nothing (no table yet, or nothing the layout can type) leaves Caps Lock
  /// alone.
  @Test func capsLockIsLeftAloneWhenTextTypesNothing() async throws {
    capsLock.isOn = true
    let runtime = try start([.text("☕"), tap(.b)])
    pressMacroKey()
    await expectPostsOneGapApart(2)
    clock.advance(by: .seconds(1))
    await settle()
    #expect(io.posted == [out(.b, true), out(.b, false)])
    withExtendedLifetime(runtime) {}
  }

  /// Caps Lock is system-wide: when the run's keyboard is gone, it's turned back on through the
  /// fallback keyboard.
  @Test func capsLockIsRestoredWhenTheDeviceIsGone() async throws {
    capsLock.isOn = true
    let runtime = try start([.text("ll")])
    io.sourceDevice = 7
    pressMacroKey()
    await expectPostsOneGapApart(2) // Caps Lock tap
    await eventually { io.posted.count == 3 } // L↓
    io.removedDevices = [7]
    clock.advance(by: MacroPlayer.eventGap)
    await eventually { io.posted.count == 5 }
    await settle()
    #expect(io.posted == [
      out(.capsLock, true), out(.capsLock, false), out(.l, true),
      out(.capsLock, true), out(.capsLock, false),
    ])
    #expect(io.postedDevices == [7, 7, 7, nil, nil])
    withExtendedLifetime(runtime) {}
  }

  @Test func capsLockOffLeavesItAlone() async throws {
    let runtime = try start([.text("l")])
    pressMacroKey()
    await expectPostsOneGapApart(2)
    clock.advance(by: .seconds(1))
    await settle()
    #expect(io.posted == [out(.l, true), out(.l, false)])
    withExtendedLifetime(runtime) {}
  }

  @Test func cancelMidTextRestoresCapsLock() async throws {
    capsLock.isOn = true
    let runtime = try start([.text("ll")])
    pressMacroKey()
    await expectPostsOneGapApart(3) // Caps Lock tap, L↓
    runtime.setPaused(true)
    clock.advance(by: .seconds(2))
    await settle()
    #expect(io.posted == [
      out(.capsLock, true), out(.capsLock, false), out(.l, true),
      out(.l, false), out(.capsLock, true), out(.capsLock, false),
    ])
    withExtendedLifetime(runtime) {}
  }

  // MARK: Cancel

  /// Plays `cancellable` twice (the second run queued), cancels after B with `cancel` and expects
  /// ⇧ released and nothing more posted, ever.
  func expectCancel(_ cancel: (RemapperRuntime) -> Void) async throws {
    let runtime = try start(cancellable)
    pressMacroKey()
    pressMacroKey() // queued
    await expectPostsOneGapApart(3) // ⇧↓, B↓, B↑
    let macroOutput = io.posted
    #expect(macroOutput == [out(.leftShift, true), out(.b, true), out(.b, false)])
    cancel(runtime)
    #expect(io.posted.filter { $0.key == .leftShift } == [out(.leftShift, true), out(.leftShift, false)])
    let posted = io.posted.count
    clock.advance(by: .seconds(2))
    await settle()
    clock.advance(by: .seconds(5))
    await settle()
    #expect(io.posted.count == posted)
    #expect(!io.posted.contains { $0.key == .c })
    #expect(io.posted.filter { $0.key == .b }.count == 2)
    withExtendedLifetime(runtime) {}
  }

  @Test func pauseCancels() async throws {
    try await expectCancel { $0.setPaused(true) }
  }

  @Test func emergencyStopCancels() async throws {
    try await expectCancel { _ in
      for key in [KeyID.leftControl, .leftAlt, .leftGUI, .escape] {
        _ = io.send(down(key))
      }
    }
  }

  @Test func updateConfigurationCancels() async throws {
    try await expectCancel { $0.update(configuration: configuration(cancellable)) }
  }

  @Test func selectKeymapCancels() async throws {
    try await expectCancel { $0.selectKeymap(Keymap.starterID) }
  }

  @Test func stopCancels() async throws {
    try await expectCancel { $0.stop() }
  }

  @Test func inputInterruptedCancels() async throws {
    try await expectCancel { _ in io.interrupt() }
  }

  @Test func playsAgainAfterCancel() async throws {
    let runtime = try start([tap(.b)])
    runtime.setPaused(true)
    runtime.setPaused(false)
    pressMacroKey()
    await expectPostsOneGapApart(2)
    #expect(io.posted == [out(.b, true), out(.b, false)])
    withExtendedLifetime(runtime) {}
  }
}
