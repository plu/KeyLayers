import Clocks
import Foundation
import InputDaemonCore
import InputDaemonIPC
import Synchronization
import Testing

/// The helper's end: records what the daemon pushes.
private final class RecordingClient: NSObject, InputDaemonClientXPCProtocol, Sendable {
  private let received = Mutex<[RawKeyEvent]>([])
  private let reports = Mutex<[[InputDevice]]>([])
  var events: [RawKeyEvent] {
    received.withLock { $0 }
  }

  var deviceReports: [[InputDevice]] {
    reports.withLock { $0 }
  }

  func devicesChanged(_ data: Data) {
    guard let decoded = try? InputDevice.decode(data) else { return }
    reports.withLock { $0.append(decoded) }
  }

  func keyEvents(_ events: Data) {
    guard let decoded = try? RawKeyEvent.decode(events) else { return }
    received.withLock { $0.append(contentsOf: decoded) }
  }
}

private final class Box<Value: Sendable>: Sendable {
  private let mutex: Mutex<Value>

  init(_ value: Value) {
    mutex = Mutex(value)
  }

  var value: Value {
    get { mutex.withLock { $0 } }
    set { mutex.withLock { $0 = newValue } }
  }

  /// Changes the value atomically.
  func update(_ body: (inout Value) -> Void) {
    mutex.withLock { body(&$0) }
  }

  /// Sets `newValue`, returning the previous value.
  func swap(_ newValue: Value) -> Value {
    mutex.withLock { value in
      defer { value = newValue }
      return value
    }
  }
}

private struct Peer: Sendable {
  nonisolated(unsafe) let connection: NSXPCConnection
  let client = RecordingClient()
  private let invalidatedFlag = Box(false)

  init(endpoint: NSXPCListenerEndpoint) {
    connection = NSXPCConnection(listenerEndpoint: endpoint)
    connection.remoteObjectInterface = .inputDaemon
    connection.exportedInterface = .inputDaemonClient
    connection.exportedObject = client
    let invalidatedFlag = invalidatedFlag
    connection.invalidationHandler = { invalidatedFlag.value = true }
    connection.interruptionHandler = { invalidatedFlag.value = true }
    connection.resume()
  }

  /// The connection was invalidated or interrupted (by the daemon, or by the test).
  var isInvalidated: Bool {
    invalidatedFlag.value
  }

  var daemon: any InputDaemonXPCProtocol {
    Self.daemonProxy(connection.remoteObjectProxy)
  }

  private static func daemonProxy(_ proxy: Any) -> any InputDaemonXPCProtocol {
    guard let daemon = proxy as? any InputDaemonXPCProtocol else {
      preconditionFailure("the connection's remote interface is InputDaemonXPCProtocol")
    }
    return daemon
  }

  func startCapture() async {
    await withCheckedContinuation { continuation in
      daemon.startCapture { continuation.resume() }
    }
  }

  /// `nil` when the message failed (the daemon dropped the connection).
  func heartbeat() async -> Bool? {
    let once = Box(false)
    return await withCheckedContinuation { continuation in
      @Sendable func resume(_ value: Bool?) {
        let first = once.swap(true) == false
        if first {
          continuation.resume(returning: value)
        }
      }
      let proxy = Self.daemonProxy(connection.remoteObjectProxyWithErrorHandler { _ in resume(nil) })
      proxy.heartbeat { resume($0) }
    }
  }
}

private func eventually(_ condition: @Sendable () -> Bool) async -> Bool {
  for _ in 0 ..< 200 {
    if condition() {
      return true
    }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return condition()
}

struct InputDaemonServerTests {
  let seizer = FakeHIDSeizer(devices: [keyboard(1), keyboard(2)])
  let controller: CaptureController
  let listener = NSXPCListener.anonymous()
  let server: InputDaemonServer
  /// The console user's uid the server sees; the test process's own by default.
  private let consoleUser = Box<uid_t?>(getuid())

  init() {
    controller = CaptureController(seizer: seizer, clock: TestClock())
    let consoleUser = consoleUser
    server = InputDaemonServer(
      listener: listener, controller: controller, peerRequirement: nil,
      consoleUserID: { consoleUser.value }
    )
    server.resume()
  }

  @Test func clientReceivesKeyEventsAfterStartCapture() async {
    let peer = Peer(endpoint: listener.endpoint)
    await peer.startCapture()
    let event = RawKeyEvent(deviceID: 1, page: 0x07, usage: 0x04, isDown: true, timestamp: 42)
    seizer.inject(event)
    #expect(await eventually { peer.client.events == [event] })
    peer.connection.invalidate()
  }

  @Test func heartbeatReplyReflectsCapture() async {
    let peer = Peer(endpoint: listener.endpoint)
    #expect(await peer.heartbeat() == false, "not yet a client")
    await peer.startCapture()
    #expect(await peer.heartbeat() == true)
    controller.stopCapture()
    #expect(await peer.heartbeat() == false)
    peer.connection.invalidate()
  }

  @Test func flushWithoutClientReturnsAtOnce() {
    #expect(server.flush(timeout: .seconds(1)))
  }

  /// What the daemon does before exiting: the client's last messages must leave the process.
  @Test func flushSendsPendingMessages() async {
    let peer = Peer(endpoint: listener.endpoint)
    await peer.startCapture()
    controller.shutdown() // hands `devicesChanged([])` to the connection
    #expect(server.flush(timeout: .seconds(1)))
    #expect(await eventually { peer.client.deviceReports.last == [] })
    peer.connection.invalidate()
  }

  @Test func newClientReplacesOldOne() async {
    let first = Peer(endpoint: listener.endpoint)
    await first.startCapture()
    let second = Peer(endpoint: listener.endpoint)
    await second.startCapture()
    let event = RawKeyEvent(deviceID: 1, page: 0x07, usage: 0x05, isDown: true, timestamp: 1)
    seizer.inject(event)
    #expect(await eventually { second.client.events == [event] })
    #expect(first.client.events.isEmpty)
    // The replaced connection going away must not release the new client's keyboards.
    first.connection.invalidate()
    try? await Task.sleep(for: .milliseconds(100))
    #expect(seizer.seized == [1, 2])
    second.connection.invalidate()
  }

  @Test func replacedConnectionIsDropped() async {
    let first = Peer(endpoint: listener.endpoint)
    await first.startCapture()
    let second = Peer(endpoint: listener.endpoint)
    await second.startCapture()
    // The daemon dropped it: the peer sees the connection interrupted on its next message, which
    // doesn't reach a capturing client (it fails, or lands on a fresh, unpromoted connection).
    #expect(await first.heartbeat() != true)
    #expect(await eventually { first.isInvalidated })
    #expect(await second.heartbeat() == true)
    #expect(!second.isInvalidated)
    #expect(seizer.seized == [1, 2], "dropping the replaced connection keeps the new client's capture")
    second.connection.invalidate()
  }

  /// Fast user switching: only the console user's helper may capture.
  @Test func helperOfAnotherUserCannotCapture() async {
    consoleUser.value = getuid() + 1
    let peer = Peer(endpoint: listener.endpoint)
    await peer.startCapture()
    #expect(seizer.seizeCalls.isEmpty)
    #expect(await peer.heartbeat() == false)

    // Switched to this user: its helper's next startCapture (prompted by that reply) is admitted.
    consoleUser.value = getuid()
    await peer.startCapture()
    #expect(seizer.seized == [1, 2])
    peer.connection.invalidate()
  }

  @Test func helperOfAnotherUserCannotDisplaceTheClient() async {
    let first = Peer(endpoint: listener.endpoint)
    await first.startCapture()
    consoleUser.value = getuid() + 1
    let second = Peer(endpoint: listener.endpoint)
    await second.startCapture()
    let event = RawKeyEvent(deviceID: 1, page: 0x07, usage: 0x0A, isDown: true, timestamp: 7)
    seizer.inject(event)
    #expect(await eventually { first.client.events == [event] })
    #expect(second.client.events.isEmpty)
    #expect(seizer.releaseCalls.isEmpty)
    first.connection.invalidate()
    second.connection.invalidate()
  }

  /// Fast user switching: the helper that was capturing loses the keyboards at its next heartbeat.
  @Test func heartbeatFromSwitchedOutUserReleasesKeyboards() async {
    let peer = Peer(endpoint: listener.endpoint)
    await peer.startCapture()
    #expect(await peer.heartbeat() == true)
    consoleUser.value = getuid() + 1
    #expect(await peer.heartbeat() == false)
    let seizer = seizer
    #expect(await eventually { seizer.seized.isEmpty })
    #expect(Set(seizer.releaseCalls) == [1, 2])
    seizer.inject(RawKeyEvent(deviceID: 1, page: 0x07, usage: 0x0B, isDown: true, timestamp: 9))
    controller.drain()
    #expect(peer.client.events.isEmpty)
    peer.connection.invalidate()
  }

  @Test func heartbeatAtLoginWindowReleasesKeyboards() async {
    let peer = Peer(endpoint: listener.endpoint)
    await peer.startCapture()
    consoleUser.value = nil
    #expect(await peer.heartbeat() == false)
    let seizer = seizer
    #expect(await eventually { seizer.seized.isEmpty })
    #expect(Set(seizer.releaseCalls) == [1, 2])
    seizer.inject(RawKeyEvent(deviceID: 1, page: 0x07, usage: 0x0B, isDown: true, timestamp: 9))
    controller.drain()
    #expect(peer.client.events.isEmpty)
    peer.connection.invalidate()
  }

  @Test func noCaptureAtTheLoginWindow() async {
    consoleUser.value = nil
    let peer = Peer(endpoint: listener.endpoint)
    await peer.startCapture()
    #expect(seizer.seizeCalls.isEmpty)
    peer.connection.invalidate()
  }

  @Test func disconnectReleasesDevices() async {
    let peer = Peer(endpoint: listener.endpoint)
    await peer.startCapture()
    #expect(seizer.seized == [1, 2])
    peer.connection.invalidate()
    let seizer = seizer
    #expect(await eventually { seizer.seized.isEmpty })
    #expect(Set(seizer.releaseCalls) == [1, 2])
  }

  @Test func acceptingAConnectionDoesNotDisplaceCurrentClient() async {
    let first = Peer(endpoint: listener.endpoint)
    await first.startCapture()
    let second = Peer(endpoint: listener.endpoint)
    // The second connection is accepted but has sent nothing, so it must not displace the first.
    try? await Task.sleep(for: .milliseconds(100))
    let event = RawKeyEvent(deviceID: 1, page: 0x07, usage: 0x06, isDown: true, timestamp: 3)
    seizer.inject(event)
    #expect(await eventually { first.client.events == [event] })
    #expect(seizer.releaseCalls.isEmpty)
    first.connection.invalidate()
    second.connection.invalidate()
  }

  @Test func firstMessagePromotesConnection() async {
    let first = Peer(endpoint: listener.endpoint)
    await first.startCapture()
    let second = Peer(endpoint: listener.endpoint)
    await second.startCapture()
    let event = RawKeyEvent(deviceID: 2, page: 0x07, usage: 0x07, isDown: true, timestamp: 4)
    seizer.inject(event)
    #expect(await eventually { second.client.events == [event] })
    #expect(first.client.events.isEmpty)
    first.connection.invalidate()
    second.connection.invalidate()
  }

  @Test func oldConnectionInvalidationDoesNotDisconnectNewClient() async {
    let first = Peer(endpoint: listener.endpoint)
    await first.startCapture()
    let second = Peer(endpoint: listener.endpoint)
    await second.startCapture()
    first.connection.invalidate()
    try? await Task.sleep(for: .milliseconds(100))
    let event = RawKeyEvent(deviceID: 1, page: 0x07, usage: 0x08, isDown: true, timestamp: 5)
    seizer.inject(event)
    #expect(await eventually { second.client.events == [event] })
    #expect(seizer.seized == [1, 2])
    second.connection.invalidate()
  }

  @Test func staleClientHeartbeatDoesNotStealCapture() async {
    let first = Peer(endpoint: listener.endpoint)
    await first.startCapture()
    let second = Peer(endpoint: listener.endpoint)
    await second.startCapture()
    let releasesBefore = seizer.releaseCalls.count
    #expect(await first.heartbeat() != true, "the replaced client isn't capturing (and was dropped)")
    let event = RawKeyEvent(deviceID: 1, page: 0x07, usage: 0x09, isDown: true, timestamp: 6)
    seizer.inject(event)
    #expect(await eventually { second.client.events == [event] })
    #expect(first.client.events.isEmpty)
    #expect(seizer.releaseCalls.count == releasesBefore)
    first.connection.invalidate()
    second.connection.invalidate()
  }
}

/// Self-update: a daemon whose executable changed on disk refuses connections and exits.
struct InputDaemonServerUpdateTests {
  let controller = CaptureController(seizer: FakeHIDSeizer(devices: [keyboard(1)]), clock: TestClock())
  let listener = NSXPCListener.anonymous()
  private let changed = Box(false)
  private let handlerCalls = Box(0)
  let server: InputDaemonServer

  init() {
    let changed = changed
    let handlerCalls = handlerCalls
    server = InputDaemonServer(
      listener: listener, controller: controller, peerRequirement: nil,
      consoleUserID: { getuid() },
      executableChanged: { changed.value },
      onExecutableChanged: { handlerCalls.update { $0 += 1 } }
    )
    server.resume()
  }

  @Test func unchangedExecutableAcceptsConnections() async {
    let peer = Peer(endpoint: listener.endpoint)
    await peer.startCapture()
    #expect(await peer.heartbeat() == true)
    #expect(handlerCalls.value == 0)
    peer.connection.invalidate()
  }

  @Test func changedExecutableRejectsConnectionAndCallsHandlerOnce() async {
    changed.value = true
    // Two connections arriving at the same time (XPC connects on the first message): the handler
    // still runs once.
    let first = Peer(endpoint: listener.endpoint)
    let second = Peer(endpoint: listener.endpoint)
    async let firstReply = first.heartbeat()
    async let secondReply = second.heartbeat()
    let replies = await (firstReply, secondReply)
    #expect(replies.0 == nil, "the connection was rejected")
    #expect(replies.1 == nil)
    let calls = handlerCalls
    #expect(await eventually { calls.value >= 1 })
    try? await Task.sleep(for: .milliseconds(100))
    #expect(handlerCalls.value == 1)
    first.connection.invalidate()
    second.connection.invalidate()
  }
}
