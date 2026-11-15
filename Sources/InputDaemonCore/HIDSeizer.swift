import InputDaemonIPC

/// Access to the physical keyboards. `LiveHIDSeizer` in the daemon, a fake in tests.
public protocol HIDSeizer: AnyObject, Sendable {
  /// Calls `deviceAdded` for present and future keyboards, `deviceRemoved` on unplug, `value` for every key input
  /// value of seized devices, all on one serial queue.
  func start(
    deviceAdded: @escaping @Sendable (InputDevice) -> Void,
    deviceRemoved: @escaping @Sendable (UInt64) -> Void,
    value: @escaping @Sendable (RawKeyEvent) -> Void
  )
  /// Opens the device exclusively. Returns the IOReturn (`kIOReturnSuccess` = 0).
  func seize(_ id: UInt64) -> Int32
  /// Gives a seized device back to the system. No-op for unknown or unseized IDs.
  func release(_ id: UInt64)
}

/// The connected client (the helper). Called on the controller's delivery queue, in order.
public protocol CaptureSink: AnyObject, Sendable {
  /// The devices being captured: seized ones (`seizeError == nil`) and failed seizes. Empty when not capturing.
  func devicesChanged(_ devices: [InputDevice])
  func keyEvents(_ events: [RawKeyEvent])
}
