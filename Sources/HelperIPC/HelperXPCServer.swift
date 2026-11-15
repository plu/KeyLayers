import Foundation
import Synchronization

/// The helper's end of the status channel. Accepts any number of configurator connections,
/// pushes every published status to all of them and forwards their requests to `requests`.
///
/// The owner must keep the server alive for as long as it should accept connections:
/// `NSXPCListener.delegate` is weak.
///
/// Ordering: every status send (pushes and `currentStatus` replies) happens while holding `state`'s
/// lock, so the order in which a configurator receives statuses is the order of `publish` calls and
/// it can never be handed an older status after a newer one. XPC sends are asynchronous, so holding
/// the lock across them only costs the enqueue. Because `Mutex` isn't re-entrant, nothing that takes
/// the lock (notably `drop`, run from connection interruption/invalidation handlers) may ever be
/// reached synchronously from a send; XPC calls those handlers on the connection's own queue.
public final class HelperXPCServer: NSObject, NSXPCListenerDelegate, Sendable {
  private struct State {
    var connections: [ObjectIdentifier: NSXPCConnection] = [:]
    var latestStatus: Data?
    /// `currentStatus` calls that arrived before the first `publish`.
    var pendingReplies: [@Sendable (Data) -> Void] = []
  }

  /// `nonisolated(unsafe)`: written once in `init`; afterwards only `resume()` is called on it,
  /// and NSXPCListener's `resume` is safe to call from any thread.
  private nonisolated(unsafe) let listener: NSXPCListener
  private let peerRequirement: String?
  private let state = Mutex(State())
  private let requestContinuation: AsyncStream<HelperRequest>.Continuation

  /// Requests from configurators, in arrival order. Single consumer.
  public let requests: AsyncStream<HelperRequest>

  /// `peerRequirement`: a code signing requirement every connecting process must satisfy (see
  /// `configuratorRequirement`); `nil` accepts any peer (in-process tests, ad-hoc dev builds).
  public init(listener: NSXPCListener, peerRequirement: String?) {
    self.listener = listener
    self.peerRequirement = peerRequirement
    (requests, requestContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    super.init()
    listener.delegate = self
  }

  public func resume() {
    listener.resume()
  }

  /// Stores `status` as the current status and pushes it to every connected configurator.
  public func publish(_ status: HelperStatus) {
    guard let data = try? status.encoded() else { return }
    state.withLock { state in
      state.latestStatus = data
      for connection in state.connections.values {
        // A dead peer is removed by its invalidation handler, never from inside this send.
        (connection.remoteObjectProxy as? RemapperObserverXPCProtocol)?.statusDidChange(data)
      }
      for reply in state.pendingReplies {
        reply(data)
      }
      state.pendingReplies = []
    }
  }

  var connectionCount: Int {
    state.withLock { $0.connections.count }
  }

  public func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    let id = ObjectIdentifier(connection)
    if let peerRequirement {
      // XPC checks the peer on every message and invalidates the connection when it doesn't match.
      connection.setCodeSigningRequirement(peerRequirement)
    }
    connection.exportedInterface = .remapper
    connection.exportedObject = RemapperService(server: self)
    connection.remoteObjectInterface = .remapperObserver
    connection.interruptionHandler = { [weak self] in self?.drop(id) }
    connection.invalidationHandler = { [weak self] in self?.drop(id) }
    // Register before resuming: once resumed, the connection can be invalidated at any time, and
    // `drop` must find it registered or a dead connection would stay in the table forever.
    state.withLock { $0.connections[id] = connection }
    connection.resume()
    return true
  }

  /// The requirement that admits only the configurator: its bundle identifier, signed by `teamID`.
  /// Without a team (ad-hoc signed dev builds) there is nothing to pin: anyone can sign ad hoc with
  /// any identifier, so an identifier-only requirement would add no protection; returns `nil`.
  public static func configuratorRequirement(bundleID: String, teamID: String?) -> String? {
    guard let teamID, !teamID.isEmpty else { return nil }
    return #"identifier "\#(bundleID)" and anchor apple generic"#
      + #" and certificate leaf[subject.OU] = "\#(teamID)""#
  }

  fileprivate func currentStatus(reply: @escaping @Sendable (Data) -> Void) {
    // Reply under the lock so a concurrent `publish` can't push a newer status before this
    // (older) one is sent.
    state.withLock { state in
      if let latest = state.latestStatus {
        reply(latest)
      } else {
        state.pendingReplies.append(reply)
      }
    }
  }

  fileprivate func receive(_ request: HelperRequest) {
    requestContinuation.yield(request)
  }

  private func drop(_ id: ObjectIdentifier) {
    state.withLock { _ = $0.connections.removeValue(forKey: id) }
  }
}

/// The object exported on each configurator connection.
private final class RemapperService: NSObject, RemapperXPCProtocol {
  private weak var server: HelperXPCServer?

  init(server: HelperXPCServer) {
    self.server = server
  }

  func currentStatus(reply: @escaping @Sendable (Data) -> Void) {
    server?.currentStatus(reply: reply)
  }

  func setPaused(_ paused: Bool, reply: @escaping @Sendable () -> Void) {
    server?.receive(.setPaused(paused))
    reply()
  }
}
