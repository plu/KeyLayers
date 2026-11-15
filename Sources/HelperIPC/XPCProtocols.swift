import Foundation

/// Vended by the helper. `currentStatus` replies with a JSON-encoded `HelperStatus`.
@objc public protocol RemapperXPCProtocol {
  func currentStatus(reply: @escaping @Sendable (Data) -> Void)
  func setPaused(_ paused: Bool, reply: @escaping @Sendable () -> Void)
}

/// Exported by the configurator so the helper can push status changes (JSON-encoded `HelperStatus`).
@objc public protocol RemapperObserverXPCProtocol {
  func statusDidChange(_ status: Data)
}

extension NSXPCInterface {
  static var remapper: NSXPCInterface {
    NSXPCInterface(with: RemapperXPCProtocol.self)
  }

  static var remapperObserver: NSXPCInterface {
    NSXPCInterface(with: RemapperObserverXPCProtocol.self)
  }
}
