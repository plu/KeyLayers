import AppKit
import Dependencies
import DependenciesMacros
import Foundation
import SharedConfig

/// The configurator's connection to the helper.
@DependencyClient
public struct HelperClient: Sendable {
  /// The helper's state: `.notRunning` while it can't be reached, otherwise its latest status.
  public var states: @Sendable () -> AsyncStream<HelperConnectionState> = { .finished }
  /// Throws `HelperNotRunningError` while the helper isn't running (it is never launched for this).
  public var setPaused: @Sendable (_ paused: Bool) async throws -> Void
  /// Launches the helper: connects to its Mach service, which launchd starts it on demand for.
  /// Returns at once; `states` reports the helper once it runs.
  public var start: @Sendable () async -> Void = {}
}

/// The helper isn't running, and the request isn't worth launching it for.
public struct HelperNotRunningError: Error, Equatable {
  public init() {}
}

extension HelperClient: DependencyKey {
  public static let liveValue = HelperClient.live(
    connect: { NSXPCConnection(machServiceName: AppIdentifiers.helperMachService) },
    isRunning: {
      NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentifiers.helperBundleID)
        .contains { !$0.isTerminated }
    }
  )

  public static let testValue = HelperClient()

  public static let previewValue = HelperClient(
    states: {
      AsyncStream { continuation in
        continuation.yield(.running(HelperStatus()))
      }
    },
    setPaused: { _ in },
    start: {}
  )

  /// A client that talks to the helper over the connections `connect` makes.
  ///
  /// Connecting to the helper's Mach service makes launchd launch the helper, so the client only
  /// connects while `isRunning` says the helper process runs (or on an explicit `start`): a helper
  /// the user quit stays quit. It connects on first use, fetches `currentStatus` on every
  /// (re)connect, reports `.notRunning` while the helper doesn't run or the connection fails or is
  /// interrupted, and checks again every `retryInterval` while anyone observes `states`.
  public static func live(
    connect: @escaping @Sendable () -> NSXPCConnection,
    isRunning: @escaping @Sendable () -> Bool,
    retryInterval: Duration = .seconds(2)
  ) -> HelperClient {
    let link = HelperLink(connect: connect, isRunning: isRunning, retryInterval: retryInterval)
    return HelperClient(
      states: { link.states() },
      setPaused: { try await link.setPaused($0) },
      start: { link.start() }
    )
  }
}

public extension DependencyValues {
  var helperClient: HelperClient {
    get { self[HelperClient.self] }
    set { self[HelperClient.self] = newValue }
  }
}

/// Owns the XPC connection. All mutable state (including the non-Sendable `NSXPCConnection`) lives
/// in a `LinkLoop` confined to one task; XPC callbacks and API calls reach it only as `Event`s sent
/// through `inbox`, which keeps them ordered and race-free.
private final class HelperLink: Sendable {
  enum Event: Sendable {
    case subscribe(UUID, AsyncStream<HelperConnectionState>.Continuation)
    case unsubscribe(UUID)
    case status(Data, generation: Int)
    case lost(generation: Int)
    case retry
    case setPaused(Bool, CheckedContinuation<Void, any Error>)
    case start
  }

  private let inbox: AsyncStream<Event>.Continuation

  init(
    connect: @escaping @Sendable () -> NSXPCConnection,
    isRunning: @escaping @Sendable () -> Bool,
    retryInterval: Duration
  ) {
    let (events, inbox) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .unbounded)
    self.inbox = inbox
    Task {
      var loop = LinkLoop(connect: connect, isRunning: isRunning, retryInterval: retryInterval, inbox: inbox)
      for await event in events {
        loop.handle(event)
      }
      loop.shutDown()
    }
  }

  deinit {
    inbox.finish()
  }

  func states() -> AsyncStream<HelperConnectionState> {
    let id = UUID()
    let (stream, continuation) = AsyncStream.makeStream(
      of: HelperConnectionState.self,
      bufferingPolicy: .unbounded
    )
    // Capturing `self` keeps the link alive while the stream is observed.
    continuation.onTermination = { _ in self.inbox.yield(.unsubscribe(id)) }
    inbox.yield(.subscribe(id, continuation))
    return stream
  }

  func setPaused(_ paused: Bool) async throws {
    try await withCheckedThrowingContinuation { continuation in
      inbox.yield(.setPaused(paused, continuation))
    }
  }

  func start() {
    inbox.yield(.start)
  }
}

private struct LinkLoop {
  let connect: @Sendable () -> NSXPCConnection
  let isRunning: @Sendable () -> Bool
  let retryInterval: Duration
  let inbox: AsyncStream<HelperLink.Event>.Continuation

  var connection: NSXPCConnection?
  /// Incremented per connection so callbacks from a replaced connection are ignored.
  var generation = 0
  var current: HelperConnectionState?
  var subscribers: [UUID: AsyncStream<HelperConnectionState>.Continuation] = [:]
  var retryScheduled = false

  mutating func handle(_ event: HelperLink.Event) {
    switch event {
    case let .subscribe(id, continuation): subscribe(id, continuation)
    case let .unsubscribe(id): subscribers[id] = nil
    case let .status(data, generation): receive(data, generation: generation)
    case let .lost(generation): lose(generation: generation)
    case .retry: retry()
    case let .setPaused(paused, continuation): setPaused(paused, continuation)
    case .start: start()
    }
  }

  private mutating func subscribe(_ id: UUID, _ continuation: AsyncStream<HelperConnectionState>.Continuation) {
    subscribers[id] = continuation
    if let current {
      continuation.yield(current)
    }
    if connection == nil, !retryScheduled {
      openIfRunning()
    }
  }

  private mutating func receive(_ data: Data, generation: Int) {
    guard generation == self.generation, connection != nil,
          let status = try? HelperStatus.decode(data)
    else { return }
    update(.running(status))
  }

  private mutating func lose(generation: Int) {
    guard generation == self.generation, let lost = connection else { return }
    connection = nil
    lost.invalidate()
    update(.notRunning)
    scheduleRetry()
  }

  private mutating func retry() {
    retryScheduled = false
    if connection == nil, !subscribers.isEmpty {
      openIfRunning()
    }
  }

  private mutating func start() {
    if connection == nil {
      open()
    }
  }

  private mutating func setPaused(_ paused: Bool, _ continuation: CheckedContinuation<Void, any Error>) {
    if connection == nil {
      guard isRunning() else {
        continuation.resume(throwing: HelperNotRunningError())
        return
      }
      open()
    }
    let proxy = connection?.remoteObjectProxyWithErrorHandler { continuation.resume(throwing: $0) }
    guard let proxy = proxy as? RemapperXPCProtocol else {
      continuation.resume(throwing: CocoaError(.featureUnsupported))
      return
    }
    proxy.setPaused(paused) { continuation.resume() }
  }

  mutating func shutDown() {
    connection?.invalidate()
    connection = nil
    for subscriber in subscribers.values {
      subscriber.finish()
    }
    subscribers = [:]
  }

  /// Connects only to a running helper: connecting would make launchd launch it. Otherwise reports
  /// `.notRunning` and checks again later.
  private mutating func openIfRunning() {
    guard isRunning() else {
      update(.notRunning)
      scheduleRetry()
      return
    }
    open()
  }

  private mutating func open() {
    generation += 1
    let generation = generation
    let inbox = inbox
    let connection = connect()
    connection.remoteObjectInterface = .remapper
    connection.exportedInterface = .remapperObserver
    connection.exportedObject = StatusObserver { inbox.yield(.status($0, generation: generation)) }
    connection.interruptionHandler = { inbox.yield(.lost(generation: generation)) }
    connection.invalidationHandler = { inbox.yield(.lost(generation: generation)) }
    connection.resume()
    let proxy = connection.remoteObjectProxyWithErrorHandler { _ in inbox.yield(.lost(generation: generation)) }
    (proxy as? RemapperXPCProtocol)?.currentStatus { inbox.yield(.status($0, generation: generation)) }
    self.connection = connection
  }

  private mutating func update(_ state: HelperConnectionState) {
    guard state != current else { return }
    current = state
    for subscriber in subscribers.values {
      subscriber.yield(state)
    }
  }

  private mutating func scheduleRetry() {
    guard !retryScheduled, !subscribers.isEmpty else { return }
    retryScheduled = true
    let inbox = inbox
    let retryInterval = retryInterval
    Task {
      try? await Task.sleep(for: retryInterval)
      inbox.yield(.retry)
    }
  }
}

/// Exported on the configurator's connection; receives the helper's status pushes.
private final class StatusObserver: NSObject, RemapperObserverXPCProtocol {
  private let onStatus: @Sendable (Data) -> Void

  init(onStatus: @escaping @Sendable (Data) -> Void) {
    self.onStatus = onStatus
  }

  func statusDidChange(_ status: Data) {
    onStatus(status)
  }
}
