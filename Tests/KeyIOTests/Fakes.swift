import Foundation
import InputDaemonIPC
@testable import KeyIO
import RemapEngine

/// Everything the fakes saw, in one order, so tests can check what happened before what.
final class CallLog: @unchecked Sendable {
  enum Entry: Equatable {
    case preflight
    case make(UInt64)
    case connect
    case startCapture
    case stopCapture
    case heartbeat
    case disconnect
    case report(UInt64, Data)
  }

  // Guarded by `lock`.
  private let lock = NSLock()
  private var storage: [Entry] = []

  var entries: [Entry] {
    lock.withLock { storage }
  }

  func append(_ entry: Entry) {
    lock.withLock { storage.append(entry) }
  }

  /// Daemon commands only (no reports, no heartbeats).
  var commands: [Entry] {
    entries.filter {
      switch $0 {
      case .report, .heartbeat: false
      default: true
      }
    }
  }

  func count(_ entry: Entry) -> Int {
    entries.filter { $0 == entry }.count
  }

  func reports(_ device: UInt64) -> [Data] {
    entries.compactMap {
      if case let .report(id, data) = $0, id == device { return data }
      return nil
    }
  }
}

struct FakeError: Error {}

final class FakeDaemon: DaemonConnection, @unchecked Sendable {
  private let log: CallLog
  // Guarded by `lock`.
  private let lock = NSLock()
  private var connectFailures: Int
  private var devicesChanged: (@Sendable ([InputDevice]) -> Void)?
  private var keyEvents: (@Sendable ([RawKeyEvent]) -> Void)?
  private var disconnected: (@Sendable () -> Void)?
  private var capturing = true

  /// The first `connectFailures` connects throw.
  init(log: CallLog, connectFailures: Int = 0) {
    self.log = log
    self.connectFailures = connectFailures
  }

  func connect(
    devicesChanged: @escaping @Sendable ([InputDevice]) -> Void,
    keyEvents: @escaping @Sendable ([RawKeyEvent]) -> Void,
    disconnected: @escaping @Sendable () -> Void
  ) throws {
    log.append(.connect)
    try lock.withLock {
      if connectFailures > 0 {
        connectFailures -= 1
        throw FakeError()
      }
      self.devicesChanged = devicesChanged
      self.keyEvents = keyEvents
      self.disconnected = disconnected
    }
  }

  func failNextConnects(_ count: Int) {
    lock.withLock { connectFailures = count }
  }

  func startCapture() { log.append(.startCapture) }
  func stopCapture() { log.append(.stopCapture) }
  /// Replies at once with `isCapturing` (default `true`).
  func heartbeat(reply: @escaping @Sendable (Bool) -> Void) {
    log.append(.heartbeat)
    reply(lock.withLock { capturing })
  }

  /// What the next heartbeats reply: `false` after the daemon released the keyboards on its own.
  var isCapturing: Bool {
    get { lock.withLock { capturing } }
    set { lock.withLock { capturing = newValue } }
  }
  func disconnect() { log.append(.disconnect) }

  func report(_ devices: [InputDevice]) {
    lock.withLock { devicesChanged }?(devices)
  }

  func send(_ events: [RawKeyEvent]) {
    lock.withLock { keyEvents }?(events)
  }

  func dropConnection() {
    lock.withLock { disconnected }?()
  }
}

final class FakeVirtualKeyboard: VirtualKeyboard {
  let deviceID: UInt64
  private let log: CallLog

  init(deviceID: UInt64, log: CallLog) {
    self.deviceID = deviceID
    self.log = log
  }

  func send(_ report: Data) {
    log.append(.report(deviceID, report))
  }
}

final class FakeVirtualKeyboardFactory: VirtualKeyboardFactory, @unchecked Sendable {
  private let log: CallLog
  private let preflightError: (any Error)?
  private let failingDevices: Set<UInt64>
  // Guarded by `lock`.
  private let lock = NSLock()
  private var madeDevices: [InputDevice] = []

  init(log: CallLog, preflightError: (any Error)? = nil, failingDevices: Set<UInt64> = []) {
    self.log = log
    self.preflightError = preflightError
    self.failingDevices = failingDevices
  }

  var made: [InputDevice] {
    lock.withLock { madeDevices }
  }

  func preflight() throws {
    log.append(.preflight)
    if let preflightError { throw preflightError }
  }

  func make(for device: InputDevice) throws -> any VirtualKeyboard {
    log.append(.make(device.id))
    if failingDevices.contains(device.id) { throw KeyIOError.virtualKeyboardUnavailable }
    lock.withLock { madeDevices.append(device) }
    return FakeVirtualKeyboard(deviceID: device.id, log: log)
  }
}

/// Records the key events the backend hands to the runtime and answers with `response`.
final class FakeRuntime: @unchecked Sendable {
  // Guarded by `lock`.
  private let lock = NSLock()
  private var receivedEvents: [KeyEvent] = []
  private var interruptions = 0
  private var response: @Sendable (KeyEvent) -> Disposition

  init(response: @escaping @Sendable (KeyEvent) -> Disposition = { _ in .passThrough }) {
    self.response = response
  }

  var received: [KeyEvent] {
    lock.withLock { receivedEvents }
  }

  var interruptionCount: Int {
    lock.withLock { interruptions }
  }

  func respond(_ response: @escaping @Sendable (KeyEvent) -> Disposition) {
    lock.withLock { self.response = response }
  }

  func handle(_ event: KeyEvent) -> Disposition {
    let response = lock.withLock {
      receivedEvents.append(event)
      return self.response
    }
    return response(event)
  }

  func interrupted() {
    lock.withLock { interruptions += 1 }
  }
}

func keyboard(
  _ id: UInt64,
  name: String = "Keyboard",
  vendorID: Int = 0x1234,
  productID: Int = 0x0001,
  countryCode: Int = 0,
  seizeError: Int32? = nil
) -> InputDevice {
  InputDevice(
    id: id, name: name, vendorID: vendorID, productID: productID, countryCode: countryCode,
    seizeError: seizeError
  )
}

func raw(_ device: UInt64, _ usage: UInt16, down: Bool = true, at timestamp: UInt64 = 0) -> RawKeyEvent {
  let page: UInt16 = 0x07
  return RawKeyEvent(deviceID: device, page: page, usage: usage, isDown: down, timestamp: timestamp)
}

/// A report with `modifiers` and `keys` in the slots, fn byte 0.
func report(modifiers: UInt8 = 0, _ keys: UInt8...) -> Data {
  var data = Data(repeating: 0, count: 10)
  data[0] = 1
  data[1] = modifiers
  for (slot, key) in keys.enumerated() { data[3 + slot] = key }
  return data
}

let emptyReport = Data([1, 0, 0, 0, 0, 0, 0, 0, 0, 0])
