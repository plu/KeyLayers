import AppKit
import Dependencies
import DependenciesMacros
import KeyIO
import KeymapModel

/// Records the next key the user presses in the configurator.
@DependencyClient
public struct KeyRecorderClient: Sendable {
  /// The next key pressed (a modifier alone counts), or `nil` after 10 s or when cancelled.
  public var record: @Sendable () async -> KeyID?
}

extension KeyRecorderClient: DependencyKey {
  public static let liveValue = KeyRecorderClient(record: { await KeyRecording.record(timeout: .seconds(10)) })

  public static let previewValue = KeyRecorderClient(record: { nil })
}

public extension DependencyValues {
  var keyRecorder: KeyRecorderClient {
    get { self[KeyRecorderClient.self] }
    set { self[KeyRecorderClient.self] = newValue }
  }
}

/// One recording: an `NSEvent` local monitor for key-down and modifier-change events. The first
/// key it can map to a `KeyID` ends it, and that event is swallowed so it doesn't type anywhere.
@MainActor
private final class KeyRecording {
  private var monitor: Any?
  private var continuation: CheckedContinuation<KeyID?, Never>?
  private var timeout: Task<Void, Never>?
  private var isFinished = false

  static func record(timeout: Duration) async -> KeyID? {
    let recording = KeyRecording()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        recording.start(continuation, timeout: timeout)
      }
    } onCancel: {
      Task { @MainActor in recording.finish(nil) }
    }
  }

  private func start(_ continuation: CheckedContinuation<KeyID?, Never>, timeout duration: Duration) {
    guard !isFinished else {
      continuation.resume(returning: nil)
      return
    }
    self.continuation = continuation
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
      guard let key = KeyRecording.pressedKey(in: event) else { return event }
      // Local monitors run on the main thread.
      let recorded = MainActor.assumeIsolated { self?.finish(key) ?? false }
      return recorded ? nil : event
    }
    timeout = Task { [weak self] in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      self?.finish(nil)
    }
  }

  /// Ends the recording with `key`; returns whether this call ended it.
  @discardableResult
  func finish(_ key: KeyID?) -> Bool {
    guard !isFinished else { return false }
    isFinished = true
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    timeout?.cancel()
    timeout = nil
    continuation?.resume(returning: key)
    continuation = nil
    return true
  }

  /// The key pressed in `event`: a key-down, or a modifier-change that pressed (not released) a
  /// modifier. Caps Lock counts on every change, since its flag toggles.
  private nonisolated static func pressedKey(in event: NSEvent) -> KeyID? {
    guard let key = MacKeyCode.keyID(for: event.keyCode) else { return nil }
    switch event.type {
    case .keyDown:
      return key
    case .flagsChanged:
      if key == .capsLock {
        return key
      }
      guard let mask = deviceMask[key] else { return nil }
      return UInt(event.modifierFlags.rawValue) & mask != 0 ? key : nil
    default:
      return nil
    }
  }

  /// The device-dependent modifier bits (IOKit `NX_DEVICE*KEYMASK`), which tell left from right.
  private nonisolated static let deviceMask: [KeyID: UInt] = [
    .leftControl: 0x0001,
    .leftShift: 0x0002,
    .rightShift: 0x0004,
    .leftGUI: 0x0008,
    .rightGUI: 0x0010,
    .leftAlt: 0x0020,
    .rightAlt: 0x0040,
    .rightControl: 0x2000,
    .fn: UInt(NSEvent.ModifierFlags.function.rawValue),
  ]
}
