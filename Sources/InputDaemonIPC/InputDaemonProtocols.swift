import Foundation

/// Vended by the root input daemon.
@objc public protocol InputDaemonXPCProtocol {
  func startCapture(reply: @escaping @Sendable () -> Void)
  func stopCapture(reply: @escaping @Sendable () -> Void)
  /// Replies whether the daemon is capturing for this connection; `false` tells the helper to send
  /// `startCapture` again (its capture ended behind its back, e.g. a heartbeat timeout).
  func heartbeat(reply: @escaping @Sendable (Bool) -> Void)
}

/// Exported by the helper so the daemon can push devices (JSON `[InputDevice]`) and raw key
/// events (`RawKeyEvent.encode`).
@objc public protocol InputDaemonClientXPCProtocol {
  func devicesChanged(_ devices: Data)
  func keyEvents(_ events: Data)
}

public extension NSXPCInterface {
  static var inputDaemon: NSXPCInterface {
    NSXPCInterface(with: InputDaemonXPCProtocol.self)
  }

  static var inputDaemonClient: NSXPCInterface {
    NSXPCInterface(with: InputDaemonClientXPCProtocol.self)
  }
}
