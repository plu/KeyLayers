import Foundation
@testable import HelperIPC
import KeymapModel
import Synchronization

extension HelperStatus {
  static func fixture(isPaused: Bool, activeLayer: LayerName = .base) -> HelperStatus {
    HelperStatus(
      activeKeymapID: Keymap.starterID,
      activeLayer: activeLayer,
      isPaused: isPaused,
      permissions: PermissionStatus(accessibility: true),
      configError: nil
    )
  }
}

struct TimedOut: Error {}

/// A connection that fails like one to a helper that isn't running: the Mach service doesn't exist.
func deadConnection() -> NSXPCConnection {
  NSXPCConnection(machServiceName: "com.plunien.keylayers.tests.no-such-helper")
}

/// Runs `operation`, failing with `TimedOut` after `timeout`. Unlike a task group this returns on
/// time even when `operation` ignores cancellation (e.g. waits on a reply that never comes).
func withTimeout<T: Sendable>(
  _ timeout: Duration = .seconds(2),
  _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  let once = Once()
  return try await withCheckedThrowingContinuation { continuation in
    let work = Task {
      let result = await Result { try await operation() }
      if once.claim() {
        continuation.resume(with: result)
      }
    }
    Task {
      try? await Task.sleep(for: timeout)
      if once.claim() {
        work.cancel()
        continuation.resume(throwing: TimedOut())
      }
    }
  }
}

private final class Once: Sendable {
  private let claimed = Mutex(false)

  /// True for the first caller only.
  func claim() -> Bool {
    claimed.withLock { claimed in
      defer { claimed = true }
      return !claimed
    }
  }
}

/// The next element of `stream`, or `TimedOut` after `timeout`. Iterators are created per call,
/// which `AsyncStream` allows as long as they are not used concurrently.
func next<T: Sendable>(_ stream: AsyncStream<T>, timeout: Duration = .seconds(2)) async throws -> T? {
  try await withTimeout(timeout) {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
  }
}

/// Polls `condition` every 10 ms until it is true, failing with `TimedOut` after `timeout`.
func waitUntil(timeout: Duration = .seconds(2), _ condition: @escaping @Sendable () -> Bool) async throws {
  try await withTimeout(timeout) {
    while !condition() {
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

/// Records connections created by a test's `connect` closure so the test can kill them.
/// `@unchecked Sendable`: `connections` is only read or written while holding `lock`.
final class ConnectionRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var connections: [NSXPCConnection] = []

  func record(_ connection: NSXPCConnection) -> NSXPCConnection {
    lock.withLock { connections.append(connection) }
    return connection
  }

  func invalidateAll() {
    lock.withLock {
      for connection in connections {
        connection.invalidate()
      }
    }
  }
}
