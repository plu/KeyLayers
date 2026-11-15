import Foundation
import InputDaemonIPC
import OSLog

/// The helper's side of the input daemon's XPC protocol.
public protocol DaemonConnection: Sendable {
  /// Connects (replacing any previous connection). The callbacks arrive serially, in the daemon's
  /// order; `disconnected` fires at most once per connection and never after `disconnect()`.
  func connect(
    devicesChanged: @escaping @Sendable ([InputDevice]) -> Void,
    keyEvents: @escaping @Sendable ([RawKeyEvent]) -> Void,
    disconnected: @escaping @Sendable () -> Void
  ) throws
  func startCapture()
  func stopCapture()
  /// `reply` says whether the daemon is capturing for this connection; it may never come (a dead
  /// connection) and arrives on an arbitrary queue.
  func heartbeat(reply: @escaping @Sendable (Bool) -> Void)
  func disconnect()
}

/// `DaemonConnection` over NSXPC to the daemon's privileged Mach service, admitting only a daemon
/// with signing identifier `daemonIdentifier` signed by `teamID`. Untested (needs the installed
/// daemon); kept thin.
///
/// `connect` doesn't wait for the daemon: NSXPC connects lazily, so an unreachable daemon shows up as
/// `disconnected` once the first message fails.
public final class LiveDaemonConnection: DaemonConnection, @unchecked Sendable {
  private let machServiceName: String
  private let daemonIdentifier: String
  private let teamID: String?
  private let logger = Logger(subsystem: "com.plunien.keylayers", category: "KeyIO")
  // Guarded by `lock`.
  private let lock = NSLock()
  private var connection: NSXPCConnection?

  /// `teamID` `nil` (ad-hoc build): `connect` throws, there's no unauthenticated root connection.
  public init(machServiceName: String, daemonIdentifier: String, teamID: String?) {
    self.machServiceName = machServiceName
    self.daemonIdentifier = daemonIdentifier
    self.teamID = teamID
  }

  public func connect(
    devicesChanged: @escaping @Sendable ([InputDevice]) -> Void,
    keyEvents: @escaping @Sendable ([RawKeyEvent]) -> Void,
    disconnected: @escaping @Sendable () -> Void
  ) throws {
    guard let teamID else {
      logger.error("no signing team: refusing to connect to the input daemon")
      throw KeyIOError.daemonUnavailable
    }
    let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
    connection.setCodeSigningRequirement(PeerRequirement.helper(bundleID: daemonIdentifier, teamID: teamID))
    connection.remoteObjectInterface = .inputDaemon
    connection.exportedInterface = .inputDaemonClient
    connection.exportedObject = ClientReceiver(devicesChanged: devicesChanged, keyEvents: keyEvents)
    let lost = Once(disconnected)
    connection.interruptionHandler = { [weak self, weak connection] in
      self?.logger.notice("input daemon connection interrupted")
      // The daemon exited (e.g. after a not-permitted seize); start over with a fresh connection.
      connection?.invalidate()
      lost.fire()
    }
    connection.invalidationHandler = { [weak self] in
      self?.logger.notice("input daemon connection invalidated")
      lost.fire()
    }
    let previous = lock.withLock {
      defer { self.connection = connection }
      return self.connection
    }
    Self.invalidateQuietly(previous)
    connection.resume()
  }

  public func startCapture() {
    proxy?.startCapture {}
  }

  public func stopCapture() {
    proxy?.stopCapture {}
  }

  public func heartbeat(reply: @escaping @Sendable (Bool) -> Void) {
    proxy?.heartbeat(reply: reply)
  }

  public func disconnect() {
    Self.invalidateQuietly(lock.withLock {
      defer { connection = nil }
      return connection
    })
  }

  private var proxy: (any InputDaemonXPCProtocol)? {
    let connection = lock.withLock { connection }
    return connection?.remoteObjectProxyWithErrorHandler { [logger] error in
      logger.error("input daemon message failed: \(error, privacy: .public)")
    } as? any InputDaemonXPCProtocol
  }

  /// Our own teardown must not look like the daemon going away.
  private static func invalidateQuietly(_ connection: NSXPCConnection?) {
    guard let connection else { return }
    connection.interruptionHandler = nil
    connection.invalidationHandler = nil
    connection.invalidate()
  }
}

/// Exported to the daemon. NSXPC calls it on the connection's serial queue.
private final class ClientReceiver: NSObject, InputDaemonClientXPCProtocol {
  private let onDevicesChanged: @Sendable ([InputDevice]) -> Void
  private let onKeyEvents: @Sendable ([RawKeyEvent]) -> Void
  private let logger = Logger(subsystem: "com.plunien.keylayers", category: "KeyIO")

  init(
    devicesChanged: @escaping @Sendable ([InputDevice]) -> Void,
    keyEvents: @escaping @Sendable ([RawKeyEvent]) -> Void
  ) {
    onDevicesChanged = devicesChanged
    onKeyEvents = keyEvents
  }

  func devicesChanged(_ devices: Data) {
    do {
      onDevicesChanged(try InputDevice.decode(devices))
    } catch {
      logger.error("undecodable device report from the input daemon")
    }
  }

  func keyEvents(_ events: Data) {
    do {
      onKeyEvents(try RawKeyEvent.decode(events))
    } catch {
      logger.error("undecodable key events from the input daemon")
    }
  }
}

/// Calls `action` the first time `fire` is called.
private final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var action: (@Sendable () -> Void)?

  init(_ action: @escaping @Sendable () -> Void) {
    self.action = action
  }

  func fire() {
    lock.withLock {
      defer { action = nil }
      return action
    }?()
  }
}
