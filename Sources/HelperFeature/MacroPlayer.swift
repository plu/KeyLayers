import Foundation
import KeyboardLayout
import KeyIO
import KeymapModel
import RemapEngine

/// What macro playback depends on: the clock for gaps and delays, the current layout's strokes for
/// Text steps, and the Caps Lock state.
public struct MacroEnvironment: Sendable {
  public var clock: any Clock<Duration>
  /// The strokes that type a character with Caps Lock off; nil skips it. Called outside the
  /// runtime's lock.
  public var strokes: @Sendable (Character) -> [TextStroke]?
  /// Called outside the runtime's lock.
  public var capsLockIsOn: @Sendable () -> Bool
  /// Brings the table behind `strokes` up to date with the selected input source. Awaited outside the
  /// runtime's lock before each run that types text; it must never block the calling thread.
  public var refreshStrokes: @Sendable () async -> Void

  public init(
    clock: any Clock<Duration>,
    strokes: @escaping @Sendable (Character) -> [TextStroke]?,
    capsLockIsOn: @escaping @Sendable () -> Bool,
    refreshStrokes: @escaping @Sendable () async -> Void = {}
  ) {
    self.clock = clock
    self.strokes = strokes
    self.capsLockIsOn = capsLockIsOn
    self.refreshStrokes = refreshStrokes
  }
}

/// Plays macros one run at a time, in the order they were requested, each on the virtual keyboard
/// of the device its key was pressed on.
///
/// `@unchecked Sendable` invariant: every mutable stored property is only touched with `lock` held,
/// and `lock` is the owning `RemapperRuntime`'s, so macro posts are ordered with engine output.
/// The playing task takes `lock` only for short sections (never across an await) and posts only
/// while its generation is current: `cancel()` bumps the generation, so a cancelled run never
/// posts again. The runtime never waits for the task.
final class MacroPlayer: @unchecked Sendable {
  /// The pause after every key event, so apps see each event on its own.
  static let eventGap: Duration = .milliseconds(5)

  private struct Run {
    var macro: Macro
    var device: UInt64?
  }

  private let lock: NSLock
  private let io: any KeyInputOutput
  private let environment: MacroEnvironment

  // Guarded by `lock`.
  private var queue: [Run] = []
  private var generation = 0
  private var task: Task<Void, Never>?
  /// The source device of the current run.
  private var device: UInt64?
  /// Downs the current run posted without their up yet, in press order.
  private var held: [OutputEvent] = []
  /// The run turned Caps Lock off for a Text step and has not turned it back on yet.
  private var capsLockNeedsRestore = false

  init(lock: NSLock, io: any KeyInputOutput, environment: MacroEnvironment) {
    self.lock = lock
    self.io = io
    self.environment = environment
  }

  /// Requires `lock`. Queues a run of each macro, pinned to `device`, and starts playing if idle.
  func enqueue(_ macros: [Macro], device: UInt64?) {
    queue += macros.map { Run(macro: $0, device: device) }
    guard task == nil, !queue.isEmpty else { return }
    let generation = generation
    let clock = environment.clock
    task = Task { await self.play(generation, clock: clock) }
  }

  /// Requires `lock`. Stops the current run and drops the queue: releases every key the run holds
  /// and turns Caps Lock back on if a Text step turned it off.
  func cancel() {
    generation += 1
    queue.removeAll()
    releaseHeld()
    task?.cancel()
    task = nil
  }

  // MARK: - Playing (on the task)

  private func play(_ generation: Int, clock: some Clock<Duration>) async {
    while let steps = lock.withLock({ startNextRun(generation) }) {
      if steps.contains(where: MacroScript.typesText) {
        // An input source switch whose notification hasn't arrived yet is caught here.
        await environment.refreshStrokes()
      }
      var deadline = clock.now
      for step in steps {
        guard await perform(step, generation, clock: clock, deadline: &deadline) else { return }
      }
      lock.withLock {
        if generation == self.generation {
          releaseHeld()
        }
      }
    }
  }

  /// Plays one step; false when the run is over (cancelled).
  private func perform<C: Clock<Duration>>(
    _ step: MacroStep,
    _ generation: Int,
    clock: C,
    deadline: inout C.Instant
  ) async -> Bool {
    let turnsCapsLockOff = MacroScript.typesText(step) && environment.capsLockIsOn()
    if turnsCapsLockOff {
      guard await tapCapsLock(needsRestore: true, generation, clock: clock, deadline: &deadline) else {
        return false
      }
    }
    for action in MacroScript.actions(for: step, strokes: environment.strokes) {
      switch action {
      case let .event(event):
        guard await post(event, generation, clock: clock, deadline: &deadline) else { return false }
      case let .wait(duration):
        deadline = deadline.advanced(by: duration)
        guard await sleep(until: deadline, clock: clock) else { return false }
      }
    }
    if turnsCapsLockOff {
      return await tapCapsLock(needsRestore: false, generation, clock: clock, deadline: &deadline)
    }
    return true
  }

  private func tapCapsLock<C: Clock<Duration>>(
    needsRestore: Bool,
    _ generation: Int,
    clock: C,
    deadline: inout C.Instant
  ) async -> Bool {
    let down = OutputEvent(key: .capsLock, isDown: true, modifiers: [])
    let up = OutputEvent(key: .capsLock, isDown: false, modifiers: [])
    guard await post(down, generation, clock: clock, deadline: &deadline, capsLockNeedsRestore: needsRestore) else {
      return false
    }
    return await post(up, generation, clock: clock, deadline: &deadline)
  }

  /// Posts `event` if the run is still current, then waits the gap; false when the run is over.
  /// `capsLockNeedsRestore` is recorded with the post, so a cancel restores exactly what was changed.
  private func post<C: Clock<Duration>>(
    _ event: OutputEvent,
    _ generation: Int,
    clock: C,
    deadline: inout C.Instant,
    capsLockNeedsRestore: Bool? = nil
  ) async -> Bool {
    let posted = lock.withLock { () -> Bool in
      guard generation == self.generation else { return false }
      // Read before posting: once the event is visible the gap already runs (and a test clock
      // advanced right after it can't be missed).
      deadline = clock.now.advanced(by: Self.eventGap)
      guard io.post([event], device: device) else {
        // The run's keyboard is gone.
        cancel()
        return false
      }
      track(event)
      if let capsLockNeedsRestore {
        self.capsLockNeedsRestore = capsLockNeedsRestore
      }
      return true
    }
    guard posted else { return false }
    return await sleep(until: deadline, clock: clock)
  }

  private func sleep<C: Clock<Duration>>(until deadline: C.Instant, clock: C) async -> Bool {
    do {
      try await clock.sleep(until: deadline, tolerance: nil)
      return true
    } catch {
      return false
    }
  }

  // MARK: - Guarded by `lock`

  /// Requires `lock`. The steps of the next queued run, or nil when the queue is empty (the player
  /// is idle again) or `generation` was cancelled.
  private func startNextRun(_ generation: Int) -> [MacroStep]? {
    guard generation == self.generation else { return nil }
    guard !queue.isEmpty else {
      task = nil
      return nil
    }
    let run = queue.removeFirst()
    device = run.device
    return run.macro.steps
  }

  /// Requires `lock`.
  private func track(_ event: OutputEvent) {
    held.removeAll { $0.key == event.key }
    if event.isDown {
      held.append(event)
    }
  }

  /// Requires `lock`. Ups for everything the run holds, last pressed first, then a Caps Lock tap if
  /// the run turned it off.
  private func releaseHeld() {
    var output = held.reversed().map { OutputEvent(key: $0.key, isDown: false, modifiers: $0.modifiers) }
    held = []
    if capsLockNeedsRestore {
      capsLockNeedsRestore = false
      output += [
        OutputEvent(key: .capsLock, isDown: true, modifiers: []),
        OutputEvent(key: .capsLock, isDown: false, modifiers: []),
      ]
    }
    if !output.isEmpty {
      // A gone device has nothing left to release.
      _ = io.post(output, device: device)
    }
  }
}
