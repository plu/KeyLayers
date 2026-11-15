import Foundation
@testable import HelperIPC
import KeymapModel
import Synchronization
import Testing

struct XPCRoundTripTests {
  @Test func clientReceivesPushedStatusAndSendsPause() async throws {
    let listener = NSXPCListener.anonymous()
    let server = HelperXPCServer(listener: listener, peerRequirement: nil)
    server.resume()
    let endpoint = listener.endpoint
    let client = HelperClient.live(connect: { NSXPCConnection(listenerEndpoint: endpoint) }, isRunning: { true })
    let states = client.states()
    server.publish(.fixture(isPaused: false))
    #expect(try await next(states) == .running(.fixture(isPaused: false)))
    try await client.setPaused(true)
    #expect(try await next(server.requests) == .setPaused(true))
  }

  @Test func invalidatedConnectionReportsNotRunning() async throws {
    let client = HelperClient.live(
      connect: { deadConnection() },
      isRunning: { true },
      retryInterval: .seconds(60)
    )
    #expect(try await next(client.states()) == .notRunning)
  }

  @Test func clientFetchesCurrentStatusOnConnect() async throws {
    let listener = NSXPCListener.anonymous()
    let server = HelperXPCServer(listener: listener, peerRequirement: nil)
    server.resume()
    server.publish(.fixture(isPaused: true))
    let endpoint = listener.endpoint
    let client = HelperClient.live(connect: { NSXPCConnection(listenerEndpoint: endpoint) }, isRunning: { true })
    #expect(try await next(client.states()) == .running(.fixture(isPaused: true)))
  }

  @Test func publishPushesToEveryConnectedClient() async throws {
    let listener = NSXPCListener.anonymous()
    let server = HelperXPCServer(listener: listener, peerRequirement: nil)
    server.resume()
    server.publish(.fixture(isPaused: false))
    let endpoint = listener.endpoint
    let connect: @Sendable () -> NSXPCConnection = { NSXPCConnection(listenerEndpoint: endpoint) }
    let first = HelperClient.live(connect: connect, isRunning: { true }).states()
    let second = HelperClient.live(connect: connect, isRunning: { true }).states()
    #expect(try await next(first) == .running(.fixture(isPaused: false)))
    #expect(try await next(second) == .running(.fixture(isPaused: false)))

    server.publish(.fixture(isPaused: false, activeLayer: .fn))
    #expect(try await next(first) == .running(.fixture(isPaused: false, activeLayer: .fn)))
    #expect(try await next(second) == .running(.fixture(isPaused: false, activeLayer: .fn)))
  }

  @Test func clientRetriesUntilHelperIsAvailable() async throws {
    let listener = NSXPCListener.anonymous()
    let server = HelperXPCServer(listener: listener, peerRequirement: nil)
    server.resume()
    server.publish(.fixture(isPaused: false))
    let endpoint = listener.endpoint
    let attempts = Attempts()
    let client = HelperClient.live(
      connect: { attempts.next() == 0 ? deadConnection() : NSXPCConnection(listenerEndpoint: endpoint) },
      isRunning: { true },
      retryInterval: .milliseconds(20)
    )
    let states = client.states()
    #expect(try await next(states) == .notRunning)
    #expect(try await next(states) == .running(.fixture(isPaused: false)))
  }

  @Test func lostConnectionReportsNotRunningThenReconnects() async throws {
    let listener = NSXPCListener.anonymous()
    let server = HelperXPCServer(listener: listener, peerRequirement: nil)
    server.resume()
    server.publish(.fixture(isPaused: false))
    let endpoint = listener.endpoint
    let recorder = ConnectionRecorder()
    let client = HelperClient.live(
      connect: { recorder.record(NSXPCConnection(listenerEndpoint: endpoint)) },
      isRunning: { true },
      retryInterval: .milliseconds(20)
    )
    let states = client.states()
    #expect(try await next(states) == .running(.fixture(isPaused: false)))
    recorder.invalidateAll()
    #expect(try await next(states) == .notRunning)
    #expect(try await next(states) == .running(.fixture(isPaused: false)))
  }

  @Test func serverDropsDeadConnections() async throws {
    let listener = NSXPCListener.anonymous()
    let server = HelperXPCServer(listener: listener, peerRequirement: nil)
    server.resume()
    server.publish(.fixture(isPaused: false))
    let endpoint = listener.endpoint
    let recorder = ConnectionRecorder()
    let client = HelperClient.live(
      connect: { recorder.record(NSXPCConnection(listenerEndpoint: endpoint)) },
      isRunning: { true },
      retryInterval: .seconds(60)
    )
    let states = client.states()
    #expect(try await next(states) == .running(.fixture(isPaused: false)))
    #expect(server.connectionCount == 1)
    recorder.invalidateAll()
    try await waitUntil { server.connectionCount == 0 }
  }

  @Test func setPausedThrowsWhenHelperIsNotRunning() async throws {
    let client = HelperClient.live(
      connect: { deadConnection() },
      isRunning: { true },
      retryInterval: .seconds(60)
    )
    await #expect(throws: (any Error).self) {
      try await withTimeout { try await client.setPaused(true) }
    }
  }

  @Test func clientNeverConnectsWhileHelperIsNotRunning() async throws {
    // Connecting to the registered Mach service would make launchd launch the helper, undoing
    // the user's Quit.
    let attempts = Attempts()
    let client = HelperClient.live(
      connect: {
        _ = attempts.next()
        return deadConnection()
      },
      isRunning: { false },
      retryInterval: .milliseconds(20)
    )
    let states = client.states()
    #expect(try await next(states) == .notRunning)
    try await Task.sleep(for: .milliseconds(200))
    await #expect(throws: HelperNotRunningError.self) {
      try await withTimeout { try await client.setPaused(true) }
    }
    #expect(attempts.count == 0)
  }

  @Test func clientConnectsOnceHelperRuns() async throws {
    let listener = NSXPCListener.anonymous()
    let server = HelperXPCServer(listener: listener, peerRequirement: nil)
    server.resume()
    server.publish(.fixture(isPaused: false))
    let endpoint = listener.endpoint
    let running = Flag()
    let client = HelperClient.live(
      connect: { NSXPCConnection(listenerEndpoint: endpoint) },
      isRunning: { running.value },
      retryInterval: .milliseconds(20)
    )
    let states = client.states()
    #expect(try await next(states) == .notRunning)
    running.set()
    #expect(try await next(states) == .running(.fixture(isPaused: false)))
  }

  @Test func startConnectsAlthoughHelperIsNotRunning() async throws {
    // Connecting is what launches the helper (launchd starts it on demand for its Mach service).
    let listener = NSXPCListener.anonymous()
    let server = HelperXPCServer(listener: listener, peerRequirement: nil)
    server.resume()
    server.publish(.fixture(isPaused: false))
    let endpoint = listener.endpoint
    let client = HelperClient.live(
      connect: { NSXPCConnection(listenerEndpoint: endpoint) },
      isRunning: { false },
      retryInterval: .seconds(60)
    )
    let states = client.states()
    #expect(try await next(states) == .notRunning)
    await client.start()
    #expect(try await next(states) == .running(.fixture(isPaused: false)))
  }

  @Test func serverRejectsPeersNotMatchingTheRequirement() async throws {
    let listener = NSXPCListener.anonymous()
    // The test runner isn't the configurator, so its connection is refused.
    let server = HelperXPCServer(listener: listener, peerRequirement: #"identifier "com.plunien.keylayers.no-such-app""#)
    server.resume()
    server.publish(.fixture(isPaused: false))
    let endpoint = listener.endpoint
    let client = HelperClient.live(
      connect: { NSXPCConnection(listenerEndpoint: endpoint) },
      isRunning: { true },
      retryInterval: .seconds(60)
    )
    #expect(try await next(client.states()) == .notRunning)
  }

  @Test func configuratorRequirementPinsTeamWhenSigned() {
    #expect(
      HelperXPCServer.configuratorRequirement(bundleID: "com.plunien.keylayers.configurator", teamID: "ABCDE12345")
        == #"identifier "com.plunien.keylayers.configurator" and anchor apple generic"#
        + #" and certificate leaf[subject.OU] = "ABCDE12345""#
    )
    // Ad-hoc dev builds have no team: an identifier alone proves nothing, so no requirement.
    #expect(HelperXPCServer.configuratorRequirement(bundleID: "com.plunien.keylayers.configurator", teamID: nil) == nil)
  }

  @Test func statusRoundTripsThroughJSON() throws {
    let status = HelperStatus(
      activeKeymapID: nil,
      activeLayer: .mouse,
      isPaused: true,
      permissions: PermissionStatus(accessibility: false),
      configError: "bad file",
      inputServiceNeedsInputMonitoring: true
    )
    #expect(try HelperStatus.decode(status.encoded()) == status)
    #expect(!status.permissions.allGranted)
    #expect(HelperStatus.fixture(isPaused: false).permissions.allGranted)
  }
}

/// Counts `connect` calls. `@unchecked Sendable`: `count` is only touched while holding `lock`.
private final class Attempts: @unchecked Sendable {
  private let lock = NSLock()
  private var calls = 0

  var count: Int {
    lock.withLock { calls }
  }

  func next() -> Int {
    lock.withLock {
      defer { calls += 1 }
      return calls
    }
  }
}

/// A thread-safe boolean that tests can turn on.
private final class Flag: Sendable {
  private let storage = Mutex(false)

  var value: Bool {
    storage.withLock { $0 }
  }

  func set() {
    storage.withLock { $0 = true }
  }
}
