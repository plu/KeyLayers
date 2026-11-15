import Foundation
import InputDaemonIPC
import KeymapModel
import OSLog
import RemapEngine

/// `KeyInputOutput` on the root input daemon (seized keyboards, raw key events over XPC) and one
/// virtual HID keyboard per seized physical keyboard.
///
/// - Input: the daemon's raw HID usages become `KeyEvent`s unchanged (`PhysicalKeyFixup`) and are
///   handed to the handler one at a time on `inputQueue`, in the daemon's order.
/// - Output: with the keyboards seized nothing reaches the system unless sent here. `.passThrough`
///   emits the original key through its device's virtual keyboard; engine output goes through the
///   keyboard of the device whose key is being handled (`OutputRouter`; outside the handler the most
///   recently active device).
/// - Safety: disabling capture or stopping releases every virtual key before `stopCapture`; a lost
///   daemon connection calls `interrupted`, releases every virtual key and reconnects every 2 s. A
///   keyboard that goes away (unplugged, or released by the daemon) with physical keys down also
///   calls `interrupted`: their ups never come, so the engine would stay in a held layer.
/// - Heartbeats go out from `inputQueue` (a stuck handler stops them, so the daemon hands the
///   keyboards back). Their reply says whether the daemon still captures for us; when it released
///   the keyboards on its own (a missed heartbeat, e.g. across sleep) the backend drops their
///   virtual keyboards and sends `startCapture` again.
/// - `onCaptureChanged` tells whether the daemon actually captures for us: `true` once it reported
///   the devices (or a heartbeat confirmed it) while capture is on; `false` when capture is turned
///   off, the connection is lost, the daemon released the keyboards or a virtual keyboard couldn't
///   be created. Called on `inputQueue`, only on changes.
///
/// `@unchecked Sendable` invariant: every mutable stored property is only touched with `lock` held,
/// except `publishedCapturing`, which only `inputQueue` touches.
/// The handler and `interrupted` are called without `lock` (they call back into `post`). Daemon
/// commands and keyboard reports are issued under `lock` (both return at once), so they keep the
/// order the state changes happened in.
public final class HIDBackend: KeyInputOutput, @unchecked Sendable {
  public static let reconnectInterval: Duration = .seconds(2)

  private let daemon: any DaemonConnection
  private let factory: any VirtualKeyboardFactory
  private let heartbeatInterval: Duration
  private let onDevicesChanged: @Sendable ([InputDevice]) -> Void
  private let onCaptureChanged: @Sendable (Bool) -> Void
  private typealias Ticker = @Sendable (Duration, @escaping @Sendable () -> Bool) -> Task<Void, Never>
  private let ticker: Ticker
  private let logger = Logger(subsystem: "com.plunien.keylayers", category: "KeyIO")

  private let inputQueue: DispatchQueue = {
    let queue = DispatchQueue(label: "com.plunien.keylayers.hid-input")
    queue.setSpecific(key: HIDBackend.inputQueueKey, value: ())
    return queue
  }()

  private static let inputQueueKey = DispatchSpecificKey<Void>()

  private struct Keyboard {
    var device: InputDevice
    var keyboard: any VirtualKeyboard
    var state = VirtualKeyboardState()
  }

  // Guarded by `lock`.
  private let lock = NSLock()
  private var handler: (@Sendable (KeyEvent) -> Disposition)?
  private var interrupted: (@Sendable () -> Void)?
  private var isStarted = false
  /// Bumped on every (re)connect and on stop; callbacks of older connections are ignored.
  private var generation = 0
  /// What the runtime wants.
  private var captureEnabled = false
  /// Whether `startCapture` was sent on the current connection (and not stopped since).
  private var captureActive = false
  /// Bumped whenever `startCapture`/`stopCapture` is sent: a heartbeat reply from before is stale.
  private var captureEpoch = 0
  /// Whether the daemon captures for us (see `onCaptureChanged`).
  private var isCapturing = false
  /// What `onCaptureChanged` was last called with. Only touched on `inputQueue`.
  private var publishedCapturing = false
  private var keyboards: [UInt64: Keyboard] = [:]
  /// Physical keys (page << 16 | usage) the handler saw go down and not up yet, per device. A
  /// keyboard that disappears with keys down never sends their ups, so the engine must start over.
  private var heldKeys: [UInt64: Set<UInt32>] = [:]
  private var router = OutputRouter()
  private var lastActiveDevice: UInt64?
  /// The device whose key the handler is handling (only meaningful on `inputQueue`).
  private var currentSource: UInt64?
  private var heartbeatTask: Task<Void, Never>?
  /// When "daemon released the keyboards" was last logged (guarded by `lock`): a helper the daemon
  /// refuses is told on every heartbeat.
  private var lastReleaseLog: ContinuousClock.Instant?
  private var reconnectTask: Task<Void, Never>?

  public init(
    daemon: any DaemonConnection,
    keyboards: any VirtualKeyboardFactory,
    clock: any Clock<Duration>,
    heartbeatInterval: Duration = .milliseconds(500),
    onDevicesChanged: @escaping @Sendable ([InputDevice]) -> Void = { _ in },
    onCaptureChanged: @escaping @Sendable (Bool) -> Void = { _ in }
  ) {
    self.daemon = daemon
    factory = keyboards
    self.heartbeatInterval = heartbeatInterval
    self.onDevicesChanged = onDevicesChanged
    self.onCaptureChanged = onCaptureChanged
    ticker = Self.makeTicker(clock)
  }

  deinit {
    heartbeatTask?.cancel()
    reconnectTask?.cancel()
  }

  /// Fires `tick` every `interval` until it returns false or the task is cancelled. Deadlines are
  /// fixed from the moment the ticker is created (not when its task first runs), so a test clock
  /// advanced right afterwards still fires on time.
  private static func makeTicker(_ clock: some Clock<Duration>) -> Ticker {
    { interval, tick in
      let first = clock.now.advanced(by: interval)
      return Task {
        var deadline = first
        while true {
          do {
            try await clock.sleep(until: deadline, tolerance: nil)
          } catch {
            return
          }
          guard tick() else { return }
          deadline = deadline.advanced(by: interval)
        }
      }
    }
  }

  // MARK: - KeyInputOutput

  public func start(
    handler: @escaping @Sendable (KeyEvent) -> Disposition,
    interrupted: @escaping @Sendable () -> Void
  ) throws {
    if lock.withLock({ isStarted }) {
      stop()
    }
    do {
      try factory.preflight()
    } catch {
      throw KeyIOError.virtualKeyboardUnavailable
    }
    try lock.withLock {
      generation += 1
      do {
        try connect(generation: generation)
      } catch {
        logger.error("input daemon unavailable")
        throw KeyIOError.daemonUnavailable
      }
      self.handler = handler
      self.interrupted = interrupted
      isStarted = true
      if captureEnabled {
        sendStartCapture()
      }
      heartbeatTask = ticker(heartbeatInterval) { [weak self] in self?.scheduleHeartbeat() ?? false }
    }
  }

  public func stop() {
    let tasks: [Task<Void, Never>?] = lock.withLock {
      guard isStarted else { return [] }
      isStarted = false
      generation += 1
      releaseAllKeys()
      sendStopCapture()
      daemon.disconnect()
      keyboards = [:]
      lastActiveDevice = nil
      handler = nil
      interrupted = nil
      defer {
        heartbeatTask = nil
        reconnectTask = nil
      }
      return [heartbeatTask, reconnectTask]
    }
    for task in tasks {
      task?.cancel()
    }
    inputQueue.async { [weak self] in self?.publishCapture() }
  }

  public func post(_ events: [OutputEvent]) {
    let onInputQueue = DispatchQueue.getSpecific(key: Self.inputQueueKey) != nil
    lock.withLock {
      post(events, source: onInputQueue ? currentSource : nil)
    }
  }

  public func post(_ events: [OutputEvent], device: UInt64?) -> Bool {
    lock.withLock {
      if let device, keyboards[device] == nil {
        return false
      }
      post(events, source: device)
      return true
    }
  }

  public func currentSourceDevice() -> UInt64? {
    guard DispatchQueue.getSpecific(key: Self.inputQueueKey) != nil else { return nil }
    return lock.withLock { currentSource }
  }

  public func setCaptureEnabled(_ enabled: Bool) {
    lock.withLock {
      captureEnabled = enabled
      guard isStarted else { return }
      if enabled {
        guard !captureActive else { return }
        sendStartCapture()
      } else {
        releaseAllKeys()
        sendStopCapture()
        inputQueue.async { [weak self] in self?.publishCapture() }
      }
    }
  }

  /// Waits until everything the daemon delivered so far was handled.
  func drain() {
    inputQueue.sync {}
  }

  // MARK: - Daemon callbacks

  /// Requires `lock`.
  private func connect(generation: Int) throws {
    try daemon.connect(
      devicesChanged: { [weak self] devices in
        guard let self else { return }
        inputQueue.async { self.devicesChanged(devices, generation: generation) }
      },
      keyEvents: { [weak self] events in
        guard let self else { return }
        inputQueue.async { self.keyEvents(events, generation: generation) }
      },
      disconnected: { [weak self] in
        guard let self else { return }
        inputQueue.async { self.connectionLost(generation: generation) }
      }
    )
  }

  /// On `inputQueue`.
  private func devicesChanged(_ devices: [InputDevice], generation: Int) {
    enum Outcome { case stale, ok, keyboardFailed }
    let (outcome, lostHeldKeys): (Outcome, Bool) = lock.withLock {
      guard isStarted, generation == self.generation else { return (.stale, false) }
      let seized = devices.filter { $0.seizeError == nil }
      let seizedIDs = Set(seized.map(\.id))
      var lostHeldKeys = false
      for id in keyboards.keys.sorted() where !seizedIDs.contains(id) {
        lostHeldKeys = removeKeyboard(id) || lostHeldKeys
      }
      for device in seized {
        if keyboards[device.id] != nil {
          keyboards[device.id]?.device = device
          continue
        }
        do {
          keyboards[device.id] = try Keyboard(device: device, keyboard: factory.make(for: device))
          logger.notice("virtual keyboard for \(device.name, privacy: .public) created")
        } catch {
          logger.error("virtual keyboard for \(device.name, privacy: .public) failed; stopping capture")
          releaseAllKeys()
          sendStopCapture()
          return (.keyboardFailed, lostHeldKeys)
        }
      }
      if captureActive {
        isCapturing = true
      }
      return (.ok, lostHeldKeys)
    }
    guard outcome != .stale else { return }
    onDevicesChanged(devices)
    publishCapture()
    if outcome == .keyboardFailed || lostHeldKeys {
      lock.withLock { interrupted }?()
    }
  }

  /// On `inputQueue`.
  private func keyEvents(_ events: [RawKeyEvent], generation: Int) {
    for event in events {
      let prepared: (KeyEvent, @Sendable (KeyEvent) -> Disposition)? = lock.withLock {
        // Events the daemon sent before capture stopped are dropped: their ups go to the system.
        guard isStarted, captureActive, generation == self.generation, let handler,
              keyboards[event.deviceID] != nil
        else { return nil }
        currentSource = event.deviceID
        lastActiveDevice = event.deviceID
        let code = UInt32(event.page) << 16 | UInt32(event.usage)
        if event.isDown {
          heldKeys[event.deviceID, default: []].insert(code)
        } else {
          heldKeys[event.deviceID]?.remove(code)
        }
        let key = PhysicalKeyFixup.key(for: event)
        return (KeyEvent(key: key, phase: event.isDown ? .down : .up, timestamp: event.timestamp), handler)
      }
      guard let prepared else { continue }
      let (keyEvent, handler) = prepared
      let disposition = handler(keyEvent)
      lock.withLock {
        currentSource = nil
        // Capture may have stopped while the handler ran (it may stop it itself, e.g. the
        // emergency stop pausing the runtime).
        if disposition == .passThrough, isStarted, captureActive, generation == self.generation {
          emit(OutputEvent(key: keyEvent.key, isDown: event.isDown, modifiers: []), on: event.deviceID)
        }
      }
    }
  }

  /// On `inputQueue`.
  private func connectionLost(generation: Int) {
    let interrupted: (@Sendable () -> Void)? = lock.withLock {
      guard isStarted, generation == self.generation else { return nil }
      logger.notice("input daemon connection lost; reconnecting")
      // Ignore anything else the lost connection still delivers.
      self.generation += 1
      captureActive = false
      isCapturing = false
      return self.interrupted
    }
    guard let interrupted else { return }
    publishCapture()
    interrupted()
    lock.withLock {
      guard isStarted else { return }
      releaseAllKeys()
      reconnectTask?.cancel()
      reconnectTask = ticker(Self.reconnectInterval) { [weak self] in self?.reconnect() ?? false }
    }
  }

  /// From the reconnect task. Returns whether to try again.
  private func reconnect() -> Bool {
    lock.withLock {
      guard isStarted else { return false }
      generation += 1
      do {
        try connect(generation: generation)
      } catch {
        logger.error("input daemon still unavailable")
        return true
      }
      reconnectTask = nil
      if captureEnabled {
        sendStartCapture()
      }
      return false
    }
  }

  /// From the heartbeat ticker: queues a heartbeat behind the input being handled. Returns whether
  /// to keep ticking.
  private func scheduleHeartbeat() -> Bool {
    guard lock.withLock({ isStarted }) else { return false }
    inputQueue.async { [weak self] in self?.sendHeartbeat() }
    return true
  }

  /// On `inputQueue`. Only while capturing: the daemon releases everything 2 s after the last one.
  private func sendHeartbeat() {
    lock.withLock {
      guard isStarted, captureActive else { return }
      let generation = generation
      let epoch = captureEpoch
      daemon.heartbeat { [weak self] capturing in
        guard let self else { return }
        inputQueue.async { self.heartbeatReplied(capturing: capturing, generation: generation, epoch: epoch) }
      }
    }
  }

  /// On `inputQueue`. The daemon no longer captures for us although we want it to: its keyboards
  /// are gone (their virtual keyboards go too, the next report recreates them), so capture again.
  private func heartbeatReplied(capturing: Bool, generation: Int, epoch: Int) {
    let interrupted: (@Sendable () -> Void)? = lock.withLock {
      guard isStarted, captureActive, generation == self.generation, epoch == captureEpoch else { return nil }
      isCapturing = capturing
      guard !capturing else { return nil }
      let now = ContinuousClock.now
      if lastReleaseLog.map({ now - $0 >= .seconds(60) }) ?? true {
        lastReleaseLog = now
        logger.notice("input daemon released the keyboards; capturing again (repeats are not logged for a minute)")
      }
      var lostHeldKeys = false
      for id in keyboards.keys.sorted() {
        lostHeldKeys = removeKeyboard(id) || lostHeldKeys
      }
      sendStartCapture()
      return lostHeldKeys ? self.interrupted : nil
    }
    publishCapture()
    interrupted?()
  }

  /// On `inputQueue` (so changes are reported in order), without `lock`.
  private func publishCapture() {
    let capturing = lock.withLock { isCapturing }
    guard capturing != publishedCapturing else { return }
    publishedCapturing = capturing
    onCaptureChanged(capturing)
  }

  // MARK: - Daemon commands (require `lock`)

  private func sendStartCapture() {
    captureActive = true
    captureEpoch += 1
    daemon.startCapture()
  }

  private func sendStopCapture() {
    captureActive = false
    isCapturing = false
    captureEpoch += 1
    daemon.stopCapture()
  }

  // MARK: - Output (require `lock`)

  private func fallbackDevice() -> UInt64? {
    if let lastActiveDevice, keyboards[lastActiveDevice] != nil {
      return lastActiveDevice
    }
    return keyboards.keys.min()
  }

  /// Routes `events` as if `source` were the device being handled (`nil`: the fallback device).
  private func post(_ events: [OutputEvent], source: UInt64?) {
    for event in events {
      // Capture off: the physical keys belong to the system again, so a down sent now would never
      // see its up. Ups and releases still go out.
      if event.isDown, !captureActive {
        continue
      }
      guard let fallback = fallbackDevice() else { return }
      emit(event, on: router.route(event, source: source, fallback: fallback))
    }
  }

  private func emit(_ event: OutputEvent, on device: UInt64) {
    guard keyboards[device] != nil else { return }
    // macOS merges modifier state across keyboards.
    let heldElsewhere = keyboards.reduce(into: Modifiers()) { result, entry in
      if entry.key != device {
        result.formUnion(entry.value.state.explicitModifiers)
      }
    }
    if let report = keyboards[device]?.state.apply(event, heldElsewhere: heldElsewhere) {
      keyboards[device]?.keyboard.send(report)
    }
  }

  /// Releases every key on every virtual keyboard; their downs are forgotten, and so are the held
  /// physical keys (their ups go to the system, or the caller interrupts the engine).
  private func releaseAllKeys() {
    for id in keyboards.keys.sorted() {
      for report in keyboards[id]?.state.releaseAll() ?? [] {
        keyboards[id]?.keyboard.send(report)
      }
    }
    router = OutputRouter()
    heldKeys = [:]
  }

  /// Releases the keyboard's virtual keys and drops it. Returns whether physical keys were held on
  /// it: their ups will never come, so the caller must interrupt the engine (outside `lock`).
  private func removeKeyboard(_ id: UInt64) -> Bool {
    let hadHeldKeys = heldKeys.removeValue(forKey: id).map { !$0.isEmpty } ?? false
    _ = router.forget(device: id)
    for report in keyboards[id]?.state.releaseAll() ?? [] {
      keyboards[id]?.keyboard.send(report)
    }
    if let name = keyboards.removeValue(forKey: id)?.device.name {
      logger.notice("virtual keyboard for \(name, privacy: .public) removed")
    }
    if lastActiveDevice == id {
      lastActiveDevice = nil
    }
    return hadHeldKeys
  }
}
