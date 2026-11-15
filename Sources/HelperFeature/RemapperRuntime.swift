import Foundation
import InputDaemonIPC
import KeyIO
import KeymapModel
import RemapEngine

public enum RuntimeEvent: Equatable, Sendable {
  case status(EngineStatus)
  case notification(EngineNotification)
  /// The keyboards the input daemon reports (seized or failed), forwarded by `RuntimeHost`.
  case devices([InputDevice])
  /// Whether the input daemon captures the keyboards for the helper (`HIDBackend.onCaptureChanged`),
  /// forwarded by `RuntimeHost`.
  case captureChanged(Bool)
}

/// Hosts `RemapEngine` on a `KeyInputOutput` backend.
///
/// The backend calls the key handler synchronously on its input thread, so the handler never
/// awaits or hops actors: it takes `lock`, runs the engine, posts the output and yields events.
///
/// `@unchecked Sendable` invariant: every mutable stored property is only touched with `lock`
/// held. `io.post`, `io.setCaptureEnabled` and stream yields also happen under `lock` (all return
/// quickly and never block on the input thread), so output, capture changes and events keep the
/// order the engine produced them in; e.g. a pause's key-ups can't overtake key-downs from a
/// handler call running at the same time, and the last capture change wins.
///
/// Macros play on `MacroPlayer`'s own task, which shares `lock` for its posts but never holds it
/// across an await; the handler only queues runs and never waits for the player. Every path that
/// releases all synthetic keys or changes the keymap or configuration cancels playback first.
///
/// `events` is meant for a single subscriber.
public final class RemapperRuntime: @unchecked Sendable {
  public let events: AsyncStream<RuntimeEvent>

  private let io: any KeyInputOutput
  private let continuation: AsyncStream<RuntimeEvent>.Continuation

  // Guarded by `lock`.
  private let lock: NSLock
  private let player: MacroPlayer
  private var engine: RemapEngine
  private var isPaused = false
  private var isStopped = false
  private var hasStarted = false
  private var lastStatus: EngineStatus?

  public init(io: any KeyInputOutput, configuration: Configuration, macros: MacroEnvironment) {
    self.io = io
    let lock = NSLock()
    self.lock = lock
    player = MacroPlayer(lock: lock, io: io, environment: macros)
    engine = RemapEngine(configuration: configuration)
    (events, continuation) = AsyncStream.makeStream()
  }

  deinit {
    lock.withLock { player.cancel() }
    continuation.finish()
  }

  /// Starts the backend and reports the current status. Throws when the backend can't start
  /// (input daemon unreachable, no virtual keyboard).
  /// Calling it again (a retry) first releases every held synthetic key.
  public func start() throws {
    lock.withLock {
      if hasStarted {
        player.cancel()
        post(engine.releaseAll())
      }
      hasStarted = true
      isStopped = false
      yieldStatus(force: true)
    }
    try io.start(
      handler: { [weak self] event in self?.handle(event) ?? .passThrough },
      interrupted: { [weak self] in self?.inputInterrupted() }
    )
    lock.withLock { syncCapture() }
  }

  /// Releases every synthetic key, hands the keyboards back to the system and stops the backend.
  /// Call before quitting. `start` restarts it.
  public func stop() {
    lock.withLock {
      isStopped = true
      player.cancel()
      post(engine.releaseAll())
      syncCapture()
    }
    // Outside `lock`: a handler call blocked on `lock` must be able to finish.
    io.stop()
  }

  /// Swaps in a new configuration; held keys keep resolving through their press actions. Cancels
  /// macro playback.
  public func update(configuration: Configuration) {
    lock.withLock {
      player.cancel()
      engine.update(configuration: configuration)
      yieldStatus()
    }
  }

  /// Pausing releases every synthetic key, resets to Base and hands the keyboards back to the system.
  /// Resuming starts from a clean engine state (physically held modifiers are not reconstructed).
  public func setPaused(_ paused: Bool) {
    lock.withLock {
      guard paused != isPaused else { return }
      isPaused = paused
      if paused {
        player.cancel()
        post(engine.releaseAll())
        // releaseAll resets to Base without a notification.
        yieldStatus(force: true)
      }
      syncCapture()
    }
  }

  public func selectKeymap(_ id: Keymap.ID) {
    lock.withLock {
      let result = engine.selectKeymap(id)
      post(result.output)
      publish(result.notifications)
    }
  }

  // MARK: - Private

  private func handle(_ event: KeyEvent) -> Disposition {
    lock.withLock {
      guard !isPaused, !isStopped else { return .passThrough }
      let result = engine.handle(event)
      // The output holds the ups of synthetic modifiers released for a macro: post it first.
      post(result.output)
      if !result.macros.isEmpty {
        // The source device is only known during the handler call.
        player.enqueue(result.macros, device: io.currentSourceDevice())
      }
      let emergencyStop = result.notifications.contains(.emergencyStop)
      if emergencyStop {
        // Pause here, before yielding, so safety doesn't depend on the subscriber.
        isPaused = true
        player.cancel()
      }
      publish(result.notifications, forceStatus: emergencyStop)
      if emergencyStop {
        syncCapture()
      }
      return result.disposition
    }
  }

  /// The backend missed input (e.g. the daemon connection dropped), so key-ups of held keys may be
  /// lost: release every synthetic key and go on from a clean engine state.
  private func inputInterrupted() {
    lock.withLock {
      guard !isPaused, !isStopped else { return }
      player.cancel()
      post(engine.releaseAll())
      // releaseAll resets to Base without a notification.
      yieldStatus()
    }
  }

  /// Requires `lock`. The backend takes the keyboards over while the runtime is started and not
  /// paused, and hands them back otherwise.
  private func syncCapture() {
    io.setCaptureEnabled(!isPaused && !isStopped)
  }

  /// Requires `lock`.
  private func post(_ output: [OutputEvent]) {
    if !output.isEmpty {
      io.post(output)
    }
  }

  /// Requires `lock`. Yields the status if it changed (or `forceStatus`), then every notification.
  /// A keymap switch cancels macro playback.
  private func publish(_ notifications: [EngineNotification], forceStatus: Bool = false) {
    if notifications.contains(where: \.isKeymapSwitch) {
      player.cancel()
    }
    yieldStatus(force: forceStatus)
    for notification in notifications {
      continuation.yield(.notification(notification))
    }
  }

  /// Requires `lock`.
  private func yieldStatus(force: Bool = false) {
    let status = engine.status
    guard force || status != lastStatus else { return }
    lastStatus = status
    continuation.yield(.status(status))
  }
}

private extension EngineNotification {
  var isKeymapSwitch: Bool {
    if case .keymapSwitched = self {
      return true
    }
    return false
  }
}
