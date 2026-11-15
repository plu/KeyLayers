import Foundation
import InputDaemonIPC
import OSLog
import Synchronization
import SystemConfiguration

/// The daemon's XPC endpoint. Only the most recent *verified* connection is the controller's client.
///
/// `setCodeSigningRequirement` is enforced on incoming messages only, so merely accepting a
/// connection proves nothing: a connection becomes the client on its `startCapture`, which
/// can only arrive after the peer passed the requirement. A heartbeat never promotes: promotion turns
/// capture off, so a stale connection's heartbeat would silently kill the current client's capture.
/// Until promoted a connection can
/// neither displace the current client nor receive anything. A replaced connection is invalidated;
/// until that lands it can neither drive the controller nor disconnect its successor.
///
/// Fast user switching: `startCapture` is only admitted from a connection whose effective uid is the
/// console user's, so a helper left running in a switched-out session can't take the keyboards (and
/// the console user's helper takes them back with its next `startCapture`). The same check runs on
/// every heartbeat: the current client whose user left the console (or is at the login window) is
/// disconnected from the controller, which releases the keyboards, and gets `false`, so the new
/// user's keystrokes never reach the switched-out helper.
///
/// Every state transition (promotion, disconnect, forwarded command) runs under one lock together
/// with its controller call, so they can't interleave. The controller never calls back into the
/// server, so this can't deadlock.
///
/// The owner must keep the server alive: `NSXPCListener.delegate` is weak.
public final class InputDaemonServer: NSObject, NSXPCListenerDelegate, Sendable {
  /// `nonisolated(unsafe)`: written once in `init`; afterwards only `resume()` is called on it,
  /// which is safe from any thread.
  private nonisolated(unsafe) let listener: NSXPCListener
  private let controller: CaptureController
  private let peerRequirement: String?
  private let consoleUserID: @Sendable () -> uid_t?
  private let executableChanged: @Sendable () -> Bool
  private let onExecutableChanged: @Sendable () -> Void
  /// Set once the executable change was reported, so concurrent accepts report it only once.
  private let updateReported = Mutex(false)
  /// The connection that is currently the controller's client.
  private let current = Mutex<Client?>(nil)
  private let logger = Logger(subsystem: "com.plunien.keylayers", category: "InputDaemon")
  /// When a refused `startCapture` was last logged: a refused helper retries every heartbeat.
  private let lastRefusalLog = Mutex<ContinuousClock.Instant?>(nil)
  private static let refusalLogInterval: Duration = .seconds(60)

  private struct Client: @unchecked Sendable {
    let id: ObjectIdentifier
    /// Only `invalidate()`d and handed to the sink, both safe from any thread.
    let connection: NSXPCConnection
  }

  /// `peerRequirement`: a code signing requirement every peer must satisfy (see
  /// `PeerRequirement.helper`); `nil` only in tests. `consoleUserID`: the uid of the user logged in
  /// at the console, `nil` at the login window. `executableChanged`: whether the daemon's own
  /// executable changed on disk since launch (checked on every new connection); then the connection
  /// is rejected and `onExecutableChanged` is called once (it should exit so launchd starts the new
  /// version). It runs on an XPC queue, outside every server lock.
  public init(
    listener: NSXPCListener,
    controller: CaptureController,
    peerRequirement: String?,
    consoleUserID: @escaping @Sendable () -> uid_t? = InputDaemonServer.liveConsoleUserID,
    executableChanged: @escaping @Sendable () -> Bool = { false },
    onExecutableChanged: @escaping @Sendable () -> Void = {}
  ) {
    self.listener = listener
    self.controller = controller
    self.peerRequirement = peerRequirement
    self.consoleUserID = consoleUserID
    self.executableChanged = executableChanged
    self.onExecutableChanged = onExecutableChanged
    super.init()
    listener.delegate = self
  }

  /// The console user's uid from the dynamic store; `nil` when nobody is logged in at the console.
  @Sendable public static func liveConsoleUserID() -> uid_t? {
    var uid: uid_t = 0
    guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, nil) as String?, name != "loginwindow"
    else { return nil }
    return uid
  }

  public func resume() {
    listener.resume()
  }

  public func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    if executableChanged() {
      let first = updateReported.withLock { reported in
        defer { reported = true }
        return !reported
      }
      if first {
        logger.notice("executable changed on disk; exiting so launchd starts the new version")
        onExecutableChanged()
      }
      return false
    }
    let id = ObjectIdentifier(connection)
    if let peerRequirement {
      connection.setCodeSigningRequirement(peerRequirement)
    }
    connection.exportedInterface = .inputDaemon
    connection.exportedObject = Service(server: self, id: id, connection: connection)
    connection.remoteObjectInterface = .inputDaemonClient
    connection.interruptionHandler = { [weak self] in self?.disconnected(id) }
    connection.invalidationHandler = { [weak self] in self?.disconnected(id) }
    connection.resume()
    return true
  }

  private func disconnected(_ id: ObjectIdentifier) {
    current.withLock { current in
      guard current?.id == id else { return }
      current = nil
      controller.clientDisconnected()
    }
  }

  /// Makes the connection the client if it isn't (dropping the one it replaces) and starts capture,
  /// unless it doesn't belong to the console user.
  fileprivate func startCapture(from id: ObjectIdentifier, connection: NSXPCConnection?) {
    guard let connection else { return }
    // Outside the lock: it asks configd.
    let consoleUser = consoleUserID()
    guard connection.effectiveUserIdentifier == consoleUser else {
      let now = ContinuousClock.now
      let shouldLog = lastRefusalLog.withLock { last in
        if let last, now - last < Self.refusalLogInterval {
          return false
        }
        last = now
        return true
      }
      if shouldLog {
        let console = consoleUser.map(String.init) ?? "none"
        logger.notice(
          "startCapture from uid \(connection.effectiveUserIdentifier) ignored: not the console user (\(console, privacy: .public)); repeats are not logged for a minute"
        )
      }
      return
    }
    let replaced: NSXPCConnection? = current.withLock { current in
      var replaced: NSXPCConnection?
      if current?.id != id {
        replaced = current?.connection
        current = Client(id: id, connection: connection)
        controller.clientConnected(ConnectionSink(connection: connection))
      }
      controller.startCapture()
      return replaced
    }
    // Outside the lock: its invalidation handler calls `disconnected` (a no-op now).
    if let replaced {
      logger.notice("dropping the replaced client connection")
      replaced.invalidate()
    }
  }

  /// Waits (at most `timeout`) until every message handed to the current client's connection so far
  /// has been sent. Call before `exit`: `remoteObjectProxy` sends are asynchronous, so a message
  /// sent right before exiting may never leave the process. Returns `false` on timeout; `true` at
  /// once without a client.
  public func flush(timeout: Duration) -> Bool {
    guard let connection = current.withLock({ $0?.connection }) else { return true }
    let sent = DispatchSemaphore(value: 0)
    connection.scheduleSendBarrierBlock { sent.signal() }
    let (seconds, attoseconds) = timeout.components
    let nanoseconds = Double(seconds) * 1e9 + Double(attoseconds) / 1e9
    return sent.wait(timeout: .now() + .nanoseconds(Int(nanoseconds))) == .success
  }

  /// The current client's heartbeat: `false` for any other connection. A client whose user is no
  /// longer the console user loses the keyboards (the controller's disconnect path) and gets `false`;
  /// it stays connected and is admitted again by a `startCapture` once its user is back.
  fileprivate func heartbeat(from id: ObjectIdentifier, connection: NSXPCConnection?) -> Bool {
    // Outside the lock: it asks configd.
    let consoleUser = consoleUserID()
    return current.withLock { current in
      guard current?.id == id else { return false }
      guard connection?.effectiveUserIdentifier == consoleUser else {
        current = nil
        controller.clientDisconnected()
        logger.notice("client's user is no longer on the console; keyboards released")
        return false
      }
      return controller.heartbeat()
    }
  }

  /// Runs `command` if `id` is the current client; otherwise ignores it and returns `nil`.
  fileprivate func perform<T>(from id: ObjectIdentifier, _ command: (CaptureController) -> T) -> T? {
    current.withLock { current in
      guard current?.id == id else { return nil }
      return command(controller)
    }
  }
}

/// Exported on each connection.
private final class Service: NSObject, InputDaemonXPCProtocol {
  private weak var server: InputDaemonServer?
  private weak var connection: NSXPCConnection?
  private let id: ObjectIdentifier

  init(server: InputDaemonServer, id: ObjectIdentifier, connection: NSXPCConnection) {
    self.server = server
    self.id = id
    self.connection = connection
  }

  /// Replies even when not admitted (another user's helper): the next heartbeat tells it.
  func startCapture(reply: @escaping @Sendable () -> Void) {
    server?.startCapture(from: id, connection: connection)
    reply()
  }

  func stopCapture(reply: @escaping @Sendable () -> Void) {
    server?.perform(from: id) { $0.stopCapture() }
    reply()
  }

  /// A non-current connection isn't capturing: `false`.
  func heartbeat(reply: @escaping @Sendable (Bool) -> Void) {
    reply(server?.heartbeat(from: id, connection: connection) ?? false)
  }
}

/// The controller's sink for one connection. `remoteObjectProxy` sends are asynchronous and keep
/// their order; sends to a dead connection are dropped.
private final class ConnectionSink: CaptureSink {
  private nonisolated(unsafe) let connection: NSXPCConnection

  init(connection: NSXPCConnection) {
    self.connection = connection
  }

  private var client: (any InputDaemonClientXPCProtocol)? {
    connection.remoteObjectProxy as? any InputDaemonClientXPCProtocol
  }

  func devicesChanged(_ devices: [InputDevice]) {
    guard let data = try? InputDevice.encode(devices) else { return }
    client?.devicesChanged(data)
  }

  func keyEvents(_ events: [RawKeyEvent]) {
    client?.keyEvents(RawKeyEvent.encode(events))
  }
}
