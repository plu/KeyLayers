import Foundation
import InputDaemonCore
import InputDaemonIPC
import Synchronization

/// In-memory `HIDSeizer`: tests add/remove keyboards and inject values; seize/release calls are
/// recorded. Callbacks are invoked synchronously on the calling thread (one test thread acts as the
/// seizer's serial queue).
final class FakeHIDSeizer: HIDSeizer {
  private struct Callbacks {
    var deviceAdded: @Sendable (InputDevice) -> Void
    var deviceRemoved: @Sendable (UInt64) -> Void
    var value: @Sendable (RawKeyEvent) -> Void
  }

  private struct State {
    var callbacks: Callbacks?
    var devices: [InputDevice] = []
    var seizeResults: [UInt64: Int32] = [:]
    var seizeCalls: [UInt64] = []
    var releaseCalls: [UInt64] = []
    var seized: Set<UInt64> = []
  }

  private let state = Mutex(State())

  init(devices: [InputDevice] = []) {
    state.withLock { $0.devices = devices }
  }

  /// IDs passed to `seize`, in call order.
  var seizeCalls: [UInt64] {
    state.withLock { $0.seizeCalls }
  }

  /// IDs passed to `release`, in call order.
  var releaseCalls: [UInt64] {
    state.withLock { $0.releaseCalls }
  }

  /// Currently seized (successful seize, not yet released or removed).
  var seized: Set<UInt64> {
    state.withLock { $0.seized }
  }

  /// The IOReturn `seize` returns for `id` (default `kIOReturnSuccess`).
  func setSeizeResult(_ result: Int32, for id: UInt64) {
    state.withLock { $0.seizeResults[id] = result }
  }

  /// Plugs in a keyboard (reported immediately when started, otherwise on `start`).
  func addDevice(_ device: InputDevice) {
    let callbacks = state.withLock { state -> Callbacks? in
      state.devices.append(device)
      return state.callbacks
    }
    callbacks?.deviceAdded(device)
  }

  func removeDevice(_ id: UInt64) {
    let callbacks = state.withLock { state -> Callbacks? in
      state.devices.removeAll { $0.id == id }
      state.seized.remove(id)
      return state.callbacks
    }
    callbacks?.deviceRemoved(id)
  }

  /// Delivers an input value as the live seizer would (regardless of seize state, so tests can
  /// check the controller's own filtering).
  func inject(_ event: RawKeyEvent) {
    state.withLock { $0.callbacks }?.value(event)
  }

  func inject(device: UInt64, page: UInt16, usage: UInt16, isDown: Bool = true, timestamp: UInt64 = 0) {
    inject(RawKeyEvent(deviceID: device, page: page, usage: usage, isDown: isDown, timestamp: timestamp))
  }

  // MARK: HIDSeizer

  func start(
    deviceAdded: @escaping @Sendable (InputDevice) -> Void,
    deviceRemoved: @escaping @Sendable (UInt64) -> Void,
    value: @escaping @Sendable (RawKeyEvent) -> Void
  ) {
    let devices = state.withLock { state in
      state.callbacks = Callbacks(deviceAdded: deviceAdded, deviceRemoved: deviceRemoved, value: value)
      return state.devices
    }
    devices.forEach(deviceAdded)
  }

  func seize(_ id: UInt64) -> Int32 {
    state.withLock { state in
      state.seizeCalls.append(id)
      let result = state.seizeResults[id] ?? 0
      if result == 0 {
        state.seized.insert(id)
      }
      return result
    }
  }

  func release(_ id: UInt64) {
    state.withLock { state in
      state.releaseCalls.append(id)
      state.seized.remove(id)
    }
  }
}

/// Records everything the controller sends.
final class RecordingSink: CaptureSink {
  enum Message: Equatable {
    case devices([InputDevice])
    case keys([RawKeyEvent])
  }

  private let state = Mutex<[Message]>([])
  private let onMessage: @Sendable (Message) -> Void

  init(onMessage: @escaping @Sendable (Message) -> Void = { _ in }) {
    self.onMessage = onMessage
  }

  var messages: [Message] {
    state.withLock { $0 }
  }

  var keyEvents: [RawKeyEvent] {
    messages.flatMap { message -> [RawKeyEvent] in
      if case let .keys(events) = message {
        return events
      }
      return []
    }
  }

  var deviceReports: [[InputDevice]] {
    messages.compactMap { message in
      if case let .devices(devices) = message {
        return devices
      }
      return nil
    }
  }

  func devicesChanged(_ devices: [InputDevice]) {
    state.withLock { $0.append(.devices(devices)) }
    onMessage(.devices(devices))
  }

  func keyEvents(_ events: [RawKeyEvent]) {
    state.withLock { $0.append(.keys(events)) }
    onMessage(.keys(events))
  }
}

func keyboard(_ id: UInt64, name: String = "Keyboard", vendorID: Int = 0x05AC) -> InputDevice {
  InputDevice(id: id, name: name, vendorID: vendorID, productID: 0x0342, countryCode: 0, seizeError: nil)
}
