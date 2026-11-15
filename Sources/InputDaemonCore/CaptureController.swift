import Dispatch
import InputDaemonIPC
import OSLog

/// The daemon's state machine: which client is connected, when keyboards are seized and released,
/// and which input values reach the client.
///
/// Safety rules: keyboards are seized only while a client is connected *and* has started
/// capture. They are released on `stopCapture`, client disconnect or replacement, a missed heartbeat,
/// and `shutdown`. KeyLayers' own virtual keyboards are never seized nor reported.
///
/// Concurrency: all state lives on one serial queue. Commands run synchronously on it (the effect
/// has happened when they return); seizer callbacks hop onto it asynchronously, so the seizer's
/// queue never waits for the controller, and values keep their arrival order. The sink is called on a
/// separate serial delivery queue, in the order the state machine produced the messages.
public final class CaptureController: Sendable {
  /// IOReturn `kIOReturnNotPermitted`: the daemon lacks Input Monitoring.
  public static let notPermitted = Int32(bitPattern: 0xE000_02E2)
  /// Vendor ID reserved for KeyLayers' virtual keyboards ("KL").
  public static let ownVendorID = 0x4B4C
  /// Name/uniqueID prefix of KeyLayers' virtual keyboards.
  public static let ownNamePrefix = "com.plunien.keylayers.virtual."

  private let seizer: any HIDSeizer
  private let heartbeatTimeout: Duration
  private typealias StartTimer = @Sendable (Duration, @escaping @Sendable () -> Void) -> Task<Void, Never>
  private let startTimer: StartTimer
  private let onNotPermitted: @Sendable () -> Void
  private let queue = DispatchQueue(label: "com.plunien.keylayers.inputd.capture")
  private let deliveryQueue: DispatchQueue = {
    let queue = DispatchQueue(label: "com.plunien.keylayers.inputd.delivery")
    queue.setSpecific(key: CaptureController.deliveryQueueKey, value: ())
    return queue
  }()

  private static let deliveryQueueKey = DispatchSpecificKey<Void>()
  /// Only touched on `queue`.
  private let state = State()
  private let logger = Logger(subsystem: "com.plunien.keylayers", category: "InputDaemon")

  private final class State: @unchecked Sendable {
    var sink: (any CaptureSink)?
    var capturing = false
    var isShutDown = false
    /// Present keyboards (own virtual keyboards excluded), by ID.
    var devices: [UInt64: InputDevice] = [:]
    /// Seize outcome per device while capturing: `nil` = seized, otherwise the IOReturn.
    var outcomes: [UInt64: Int32?] = [:]
    var heartbeat: Task<Void, Never>?
    var heartbeatGeneration = 0
    var reportedNotPermitted = false
  }

  public init(
    seizer: any HIDSeizer,
    clock: any Clock<Duration>,
    heartbeatTimeout: Duration = .seconds(2),
    onNotPermitted: @escaping @Sendable () -> Void = {}
  ) {
    self.seizer = seizer
    self.heartbeatTimeout = heartbeatTimeout
    startTimer = Self.timerFactory(clock)
    self.onNotPermitted = onNotPermitted
    seizer.start(
      deviceAdded: { [weak self] device in
        guard let self else { return }
        queue.async { self.deviceAdded(device) }
      },
      deviceRemoved: { [weak self] id in
        guard let self else { return }
        queue.async { self.deviceRemoved(id) }
      },
      value: { [weak self] event in
        guard let self else { return }
        queue.async { self.value(event) }
      }
    )
  }

  /// Fixes the deadline when the timer is created (not when its task first runs), so a test clock
  /// advanced right after `startCapture`/`heartbeat` still fires on time.
  private static func timerFactory(_ clock: some Clock<Duration>) -> StartTimer {
    { timeout, fire in
      let deadline = clock.now.advanced(by: timeout)
      return Task {
        do {
          try await clock.sleep(until: deadline, tolerance: nil)
          fire()
        } catch {}
      }
    }
  }

  /// Replaces any previous sink (releasing its keyboards first). Capture starts off.
  public func clientConnected(_ sink: any CaptureSink) {
    queue.sync {
      releaseAll(report: false)
      state.sink = sink
      logger.notice("client connected")
    }
  }

  public func clientDisconnected() {
    queue.sync {
      releaseAll(report: false)
      state.sink = nil
      logger.notice("client disconnected")
    }
  }

  public func startCapture() {
    queue.sync {
      guard !state.isShutDown, state.sink != nil, !state.capturing else { return }
      state.capturing = true
      for id in state.devices.keys.sorted() {
        seize(id)
      }
      report()
      armHeartbeat()
    }
  }

  public func stopCapture() {
    queue.sync { releaseAll(report: true) }
  }

  /// Pushes the deadline while capturing. Returns whether capture is on, so a client whose capture
  /// ended behind its back (a missed heartbeat, e.g. across sleep) learns it and starts it again.
  /// Never captures by itself.
  @discardableResult
  public func heartbeat() -> Bool {
    queue.sync {
      guard state.capturing else { return false }
      armHeartbeat()
      return true
    }
  }

  /// SIGTERM: releases everything, tells the client, and refuses to capture again. Returns after the
  /// client's messages were handed to the sink.
  public func shutdown() {
    queue.sync {
      releaseAll(report: true)
      state.isShutDown = true
      logger.notice("shut down")
    }
    waitForDelivery()
  }

  /// Waits until everything the seizer reported so far was processed and handed to the sink.
  public func drain() {
    queue.sync {}
    waitForDelivery()
  }

  /// Waits for pending sink calls. Called from one of them (a sink or `onNotPermitted` calling
  /// `shutdown`/`drain`), it returns at once: waiting on the own queue would deadlock. Messages
  /// enqueued meanwhile (e.g. shutdown's final `devicesChanged([])`) then run after the caller returns.
  private func waitForDelivery() {
    guard DispatchQueue.getSpecific(key: Self.deliveryQueueKey) == nil else { return }
    deliveryQueue.sync {}
  }

  public static func isOwnVirtualKeyboard(_ device: InputDevice) -> Bool {
    device.vendorID == ownVendorID || device.name.hasPrefix(ownNamePrefix)
  }

  /// Keyboard/Keypad page usages a–z … right GUI, and the Apple vendor top-case `fn`.
  public static func isForwarded(page: UInt16, usage: UInt16) -> Bool {
    (page == 0x07 && (0x04 ... 0xE7).contains(usage)) || (page == 0xFF && usage == 0x03)
  }

  // MARK: On `queue`

  private func deviceAdded(_ device: InputDevice) {
    guard !Self.isOwnVirtualKeyboard(device) else { return }
    state.devices[device.id] = device
    guard state.capturing else { return }
    seize(device.id)
    report()
  }

  private func deviceRemoved(_ id: UInt64) {
    guard state.devices.removeValue(forKey: id) != nil else { return }
    // The device is gone; the seizer drops its own handle.
    let wasCaptured = state.outcomes.removeValue(forKey: id) != nil
    if state.capturing, wasCaptured {
      report()
    }
  }

  private func value(_ event: RawKeyEvent) {
    guard state.capturing, let sink = state.sink,
          case .some(.none) = state.outcomes[event.deviceID],
          Self.isForwarded(page: event.page, usage: event.usage)
    else { return }
    deliveryQueue.async { sink.keyEvents([event]) }
  }

  private func seize(_ id: UInt64) {
    guard let device = state.devices[id] else { return }
    let result = seizer.seize(id)
    if result == 0 {
      state.outcomes[id] = .some(nil)
      logger.notice("seized \(device.name, privacy: .public)")
    } else {
      state.outcomes[id] = .some(result)
      let code = String(format: "0x%08x", UInt32(bitPattern: result))
      logger.error("seize \(device.name, privacy: .public) failed: \(code, privacy: .public)")
    }
  }

  private func releaseAll(report shouldReport: Bool) {
    state.heartbeat?.cancel()
    state.heartbeat = nil
    state.heartbeatGeneration += 1
    let wasCapturing = state.capturing
    state.capturing = false
    for (id, outcome) in state.outcomes.sorted(by: { $0.key < $1.key }) where outcome == nil {
      seizer.release(id)
      logger.notice("released \(self.state.devices[id]?.name ?? String(id), privacy: .public)")
    }
    state.outcomes = [:]
    if shouldReport, wasCapturing {
      report()
    }
  }

  /// Sends the current capture state; afterwards fires `onNotPermitted` once if a seize was refused for
  /// lack of Input Monitoring.
  private func report() {
    guard let sink = state.sink else { return }
    let devices = state.outcomes.keys.sorted().compactMap { id -> InputDevice? in
      guard var device = state.devices[id], let outcome = state.outcomes[id] else { return nil }
      device.seizeError = outcome
      return device
    }
    deliveryQueue.async { sink.devicesChanged(devices) }
    if !state.reportedNotPermitted, devices.contains(where: { $0.seizeError == Self.notPermitted }) {
      state.reportedNotPermitted = true
      logger.error("seize not permitted: the daemon needs Input Monitoring")
      let handler = onNotPermitted
      deliveryQueue.async { handler() }
    }
  }

  private func armHeartbeat() {
    state.heartbeat?.cancel()
    state.heartbeatGeneration += 1
    let generation = state.heartbeatGeneration
    state.heartbeat = startTimer(heartbeatTimeout) { [weak self] in
      guard let self else { return }
      queue.async { self.heartbeatExpired(generation) }
    }
  }

  private func heartbeatExpired(_ generation: Int) {
    guard generation == state.heartbeatGeneration, state.capturing else { return }
    logger.error("heartbeat timed out, releasing keyboards")
    releaseAll(report: true)
  }
}
