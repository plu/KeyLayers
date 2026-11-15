import Dependencies
import DependenciesMacros
import Foundation
import KeyIO
import KeymapModel
import SharedConfig

/// The helper's remapper: one `RemapperRuntime` on the HID backend (input daemon + virtual keyboards).
@DependencyClient
public struct RemapperRuntimeClient: Sendable {
  /// Starts remapping with `configuration`; throws when the backend can't start. Callable again
  /// (e.g. after permissions are granted) to retry.
  public var start: @Sendable (_ configuration: Configuration) throws -> Void
  public var update: @Sendable (_ configuration: Configuration) -> Void
  public var setPaused: @Sendable (_ paused: Bool) -> Void
  public var selectKeymap: @Sendable (_ id: Keymap.ID) -> Void
  /// Releases held keys, hands the keyboards back and stops the backend. Call before quitting.
  public var stop: @Sendable () -> Void
  /// The runtime's events. Subscribe once for the helper's lifetime: each call starts a new stream
  /// and finishes the previous one.
  public var events: @Sendable () -> AsyncStream<RuntimeEvent> = { .finished }
}

extension RemapperRuntimeClient: DependencyKey {
  public static let liveValue: RemapperRuntimeClient = {
    let host = RuntimeHost { configuration, send in
      let backend = HIDBackend(
        daemon: LiveDaemonConnection(
          machServiceName: AppIdentifiers.inputDaemonMachService,
          daemonIdentifier: AppIdentifiers.inputDaemonBundleID,
          teamID: AppIdentifiers.teamID
        ),
        keyboards: LiveVirtualKeyboardFactory(),
        clock: ContinuousClock(),
        onDevicesChanged: { send(.devices($0)) },
        onCaptureChanged: { send(.captureChanged($0)) }
      )
      return RemapperRuntime(io: backend, configuration: configuration)
    }
    let activity = RemappingActivity()
    return RemapperRuntimeClient(
      start: {
        try host.start($0)
        activity.begin()
      },
      update: { host.runtime?.update(configuration: $0) },
      setPaused: { host.setPaused($0) },
      selectKeymap: { host.runtime?.selectKeymap($0) },
      stop: {
        host.stop()
        activity.end()
      },
      events: { host.events() }
    )
  }()

  public static let testValue = RemapperRuntimeClient()
}

/// Keeps App Nap away while remapping runs: a napping helper would delay its heartbeats (the daemon
/// then hands the keyboards back) and add latency to every key.
///
/// `@unchecked Sendable`: `token` is only touched with `lock` held.
private final class RemappingActivity: @unchecked Sendable {
  private let lock = NSLock()
  private var token: (any NSObjectProtocol)?

  func begin() {
    lock.withLock {
      guard token == nil else { return }
      token = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiated, .latencyCritical],
        reason: "Keyboard remapping"
      )
    }
  }

  func end() {
    lock.withLock {
      defer { token = nil }
      return token
    }.map(ProcessInfo.processInfo.endActivity)
  }
}

public extension DependencyValues {
  var remapperRuntime: RemapperRuntimeClient {
    get { self[RemapperRuntimeClient.self] }
    set { self[RemapperRuntimeClient.self] = newValue }
  }
}

/// Creates the runtime on the first `start`, so the engine begins on that configuration's default
/// keymap, and forwards its events, and those the backend sends through the closure `makeRuntime`
/// gets (e.g. `.devices`), to the current subscriber (events with no subscriber are buffered until
/// one arrives). Before the first start, `update` and `selectKeymap` are dropped
/// (start brings the configuration) and the paused state is remembered.
///
/// `@unchecked Sendable`: every `var` is only touched with `lock` held.
final class RuntimeHost: @unchecked Sendable {
  /// Makes the runtime for a configuration; the second argument forwards backend events. It must
  /// not be called from within `makeRuntime` (the host's lock is held there).
  private let makeRuntime: @Sendable (Configuration, @escaping @Sendable (RuntimeEvent) -> Void) -> RemapperRuntime

  private let lock = NSLock()
  private var storedRuntime: RemapperRuntime?
  private var isPaused = false
  private var stream: AsyncStream<RuntimeEvent>?
  private var continuation: AsyncStream<RuntimeEvent>.Continuation

  init(
    makeRuntime: @escaping @Sendable (Configuration, @escaping @Sendable (RuntimeEvent) -> Void) -> RemapperRuntime
  ) {
    self.makeRuntime = makeRuntime
    let (stream, continuation) = AsyncStream<RuntimeEvent>.makeStream()
    self.stream = stream
    self.continuation = continuation
  }

  /// A stream of the runtime's events for one subscriber; finishes the stream handed out before.
  func events() -> AsyncStream<RuntimeEvent> {
    lock.withLock {
      if let stream {
        // The first subscriber gets the stream that buffered events since `init`.
        self.stream = nil
        return stream
      }
      continuation.finish()
      let (stream, continuation) = AsyncStream<RuntimeEvent>.makeStream()
      self.continuation = continuation
      return stream
    }
  }

  private func forward(_ event: RuntimeEvent) {
    lock.withLock { continuation }.yield(event)
  }

  var runtime: RemapperRuntime? {
    lock.withLock { storedRuntime }
  }

  func start(_ configuration: Configuration) throws {
    let runtime = lock.withLock {
      if let storedRuntime {
        storedRuntime.update(configuration: configuration)
        return storedRuntime
      }
      let runtime = makeRuntime(configuration) { [weak self] event in self?.forward(event) }
      runtime.setPaused(isPaused)
      storedRuntime = runtime
      Task { [weak self] in
        for await event in runtime.events {
          self?.forward(event)
        }
      }
      return runtime
    }
    try runtime.start()
  }

  func stop() {
    runtime?.stop()
  }

  func setPaused(_ paused: Bool) {
    lock.withLock {
      isPaused = paused
      return storedRuntime
    }?.setPaused(paused)
  }
}
