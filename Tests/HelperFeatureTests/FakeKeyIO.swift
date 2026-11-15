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
  private var devices: [UInt64?] = []
  private var source: UInt64?
  private var removed: Set<UInt64> = []
  private var stops = 0
  private let startError: (any Error)?

  init(startError: (any Error)? = nil) {
    self.startError = startError
  }

  var posted: [OutputEvent] {
    lock.withLock { postedEvents }
  }

  /// The source device of each event in `posted`; `nil` for `post(_:)` and fallback posts.
  var postedDevices: [UInt64?] {
    lock.withLock { devices }
  }

  /// Returned by `currentSourceDevice()`.
  var sourceDevice: UInt64? {
    get { lock.withLock { source } }
    set { lock.withLock { source = newValue } }
  }

  /// Devices for which `post(_:device:)` returns `false`.
  var removedDevices: Set<UInt64> {
    get { lock.withLock { removed } }
    set { lock.withLock { removed = newValue } }
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
    lock.withLock {
      postedEvents += events
      devices += events.map { _ in nil }
    }
  }

  func currentSourceDevice() -> UInt64? {
    sourceDevice
  }

  func post(_ events: [OutputEvent], device: UInt64?) -> Bool {
    lock.withLock {
      if let device, removed.contains(device) {
        return false
      }
      postedEvents += events
      devices += events.map { _ in device }
      return true
    }
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
