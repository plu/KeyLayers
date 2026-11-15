import KeymapModel
import RemapEngine

/// The seam between the engine and the OS. `HIDBackend` (seized keyboards via the input daemon,
/// virtual HID keyboards for output) is the live conformance.
public protocol KeyInputOutput: AnyObject, Sendable {
  /// `handler` is called synchronously on the input thread; it must return quickly.
  /// `interrupted` is called (on the input thread) after the backend missed input, e.g. the daemon
  /// connection dropped: key-ups may have been lost, so held keys must be released.
  func start(
    handler: @escaping @Sendable (KeyEvent) -> Disposition,
    interrupted: @escaping @Sendable () -> Void
  ) throws
  func stop()
  func post(_ events: [OutputEvent])
  /// The device whose event the handler is processing; `nil` outside the handler.
  func currentSourceDevice() -> UInt64?
  /// Like `post(_:)`, but routes as if `device` were the source (`nil`: the fallback device), from
  /// any thread. Returns `false` and posts nothing when a non-nil `device` is no longer present.
  /// Downs are still dropped while capture is off.
  func post(_ events: [OutputEvent], device: UInt64?) -> Bool
  /// `true` while the runtime is started and not paused: the backend takes the keyboards over;
  /// `false` hands them back to the system after releasing every key it holds.
  /// May be called from the handler; must return quickly.
  func setCaptureEnabled(_ enabled: Bool)
}

public enum KeyIOError: Error, Equatable {
  /// The input daemon can't be reached (not installed, not approved, or no signing team).
  case daemonUnavailable
  /// No virtual keyboard can be created (missing entitlement or Accessibility).
  case virtualKeyboardUnavailable
}
