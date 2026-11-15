import Foundation
import KeyIO
import KeymapModel
import RemapEngine

/// A `KeyInputOutput` that records what the runtime posts and lets tests deliver key events.
final class FakeKeyIO: KeyInputOutput, @unchecked Sendable {
  // Guarded by `lock`.
  private let lock = NSLock()
  private var handler: (@Sendable (KeyEvent) -> Disposition)?
  private var interruptionHandler: (@Sendable () -> Void)?
  private var postedEvents: [OutputEvent] = []
  private var capture: [Bool] = []
  private var stops = 0
  private let startError: (any Error)?

  init(startError: (any Error)? = nil) {
    self.startError = startError
  }

  var posted: [OutputEvent] {
    lock.withLock { postedEvents }
  }

  var stopCount: Int {
    lock.withLock { stops }
  }

  /// Every `setCaptureEnabled` value, in order.
  var captureEnabled: [Bool] {
    lock.withLock { capture }
  }

  func start(
    handler: @escaping @Sendable (KeyEvent) -> Disposition,
    interrupted: @escaping @Sendable () -> Void
  ) throws {
    if let startError {
      throw startError
    }
    lock.withLock {
      self.handler = handler
      interruptionHandler = interrupted
    }
  }

  func stop() {
    lock.withLock {
      handler = nil
      interruptionHandler = nil
      stops += 1
    }
  }

  func post(_ events: [OutputEvent]) {
    lock.withLock { postedEvents += events }
  }

  func setCaptureEnabled(_ enabled: Bool) {
    lock.withLock { capture.append(enabled) }
  }

  /// Reports lost input, as the backend does when the daemon connection drops.
  func interrupt() {
    lock.withLock { interruptionHandler }?()
  }

  /// Delivers `event` the way the input thread would; an unstarted backend passes everything through.
  func send(_ event: KeyEvent) -> Disposition {
    let handler = lock.withLock { self.handler }
    return handler?(event) ?? .passThrough
  }
}
