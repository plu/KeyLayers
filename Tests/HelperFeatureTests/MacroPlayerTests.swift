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
    capsLockIsOn: @escaping @Sendable () -> Bool = { false }
  ) -> MacroEnvironment {
    MacroEnvironment(clock: clock, strokes: strokes, capsLockIsOn: capsLockIsOn)
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

@Suite(.timeLimit(.minutes(1)))
struct MacroPlayerTests {
  let clock = ManualClock()
  let io = FakeKeyIO()
  private let capsLock = CapsLock()

  func start(_ steps: [MacroStep]) throws -> RemapperRuntime {
    let capsLock = capsLock
    let runtime = RemapperRuntime(
      io: io,
      configuration: configuration(steps),
      macros: .testing(
        clock: clock,
        strokes: { letters[$0] },
        capsLockIsOn: { capsLock.isOn }
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
