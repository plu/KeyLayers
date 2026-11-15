import Foundation
import InputDaemonIPC
import IOKit
import IOKit.hid
import OSLog

/// `HIDSeizer` on IOKit: an `IOHIDManager` matching keyboards and keypads, scheduled on a run loop
/// on its own thread. All callbacks arrive on that thread (the "serial queue" of `HIDSeizer`);
/// `seize`/`release` hop onto it, so IOHID objects are only touched there.
public final class LiveHIDSeizer: HIDSeizer, @unchecked Sendable {
  private struct Callbacks {
    var deviceAdded: @Sendable (InputDevice) -> Void
    var deviceRemoved: @Sendable (UInt64) -> Void
    var value: @Sendable (RawKeyEvent) -> Void
  }

  /// Context handed to IOKit for one device's input value callback.
  private final class DeviceContext {
    let id: UInt64
    unowned let seizer: LiveHIDSeizer
    init(id: UInt64, seizer: LiveHIDSeizer) {
      self.id = id
      self.seizer = seizer
    }
  }

  private struct Entry {
    var device: IOHIDDevice
    var context: DeviceContext
    var seized = false
  }

  private let logger = Logger(subsystem: "com.plunien.keylayers", category: "InputDaemon")
  private let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }()

  // Set once in `start` (before the run loop thread signals readiness), then read-only.
  private var runLoop: CFRunLoop?
  private var callbacks: Callbacks?
  // Run loop thread only.
  private var manager: IOHIDManager?
  private var entries: [UInt64: Entry] = [:]

  public init() {}

  public func start(
    deviceAdded: @escaping @Sendable (InputDevice) -> Void,
    deviceRemoved: @escaping @Sendable (UInt64) -> Void,
    value: @escaping @Sendable (RawKeyEvent) -> Void
  ) {
    precondition(runLoop == nil, "LiveHIDSeizer.start called twice")
    callbacks = Callbacks(deviceAdded: deviceAdded, deviceRemoved: deviceRemoved, value: value)
    let ready = DispatchSemaphore(value: 0)
    let thread = Thread { [self] in
      runLoop = CFRunLoopGetCurrent()
      ready.signal()
      startManager()
      CFRunLoopRun()
    }
    thread.name = "com.plunien.keylayers.inputd.hid"
    thread.qualityOfService = .userInteractive
    thread.start()
    ready.wait()
  }

  public func seize(_ id: UInt64) -> Int32 {
    onRunLoop {
      guard var entry = self.entries[id] else { return kIOReturnNoDevice }
      if entry.seized {
        return kIOReturnSuccess
      }
      let result = IOHIDDeviceOpen(entry.device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
      guard result == kIOReturnSuccess else { return result }
      let context = Unmanaged.passUnretained(entry.context).toOpaque()
      IOHIDDeviceRegisterInputValueCallback(entry.device, Self.inputValueCallback, context)
      IOHIDDeviceScheduleWithRunLoop(entry.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
      entry.seized = true
      self.entries[id] = entry
      return result
    }
  }

  public func release(_ id: UInt64) {
    onRunLoop {
      guard var entry = self.entries[id], entry.seized else { return }
      IOHIDDeviceRegisterInputValueCallback(entry.device, nil, nil)
      // Balances the schedule in `seize`, so seizing again doesn't schedule the device twice.
      IOHIDDeviceUnscheduleFromRunLoop(entry.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
      IOHIDDeviceClose(entry.device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
      entry.seized = false
      self.entries[id] = entry
    }
  }

  // MARK: Run loop thread

  private func startManager() {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [[String: Int]] = [
      [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
      [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad],
    ]
    IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, context)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    self.manager = manager
  }

  private static let matchingCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<LiveHIDSeizer>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
  }

  private static let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<LiveHIDSeizer>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
  }

  private static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else { return }
    let device = Unmanaged<DeviceContext>.fromOpaque(context).takeUnretainedValue()
    device.seizer.inputValue(value, deviceID: device.id)
  }

  private func deviceMatched(_ device: IOHIDDevice) {
    guard let id = Self.registryID(device), entries[id] == nil else { return }
    let name = Self.property(device, kIOHIDProductKey) as String? ?? "Unknown keyboard"
    let uniqueID = Self.property(device, kIOHIDUniqueIDKey) as String? ?? ""
    let vendorID = Self.property(device, kIOHIDVendorIDKey) as Int? ?? 0
    let prefix = CaptureController.ownNamePrefix
    let isOwn = vendorID == CaptureController.ownVendorID || uniqueID.hasPrefix(prefix) || name.hasPrefix(prefix)
    guard !isOwn else { return }
    entries[id] = Entry(device: device, context: DeviceContext(id: id, seizer: self))
    logger.notice(
      "device added: \(name, privacy: .public) vendor=\(String(format: "0x%04x", vendorID), privacy: .public) id=\(id)"
    )
    callbacks?.deviceAdded(InputDevice(
      id: id,
      name: name,
      vendorID: vendorID,
      productID: Self.property(device, kIOHIDProductIDKey) ?? 0,
      countryCode: Self.property(device, kIOHIDCountryCodeKey) ?? 0,
      seizeError: nil
    ))
  }

  private func deviceRemoved(_ device: IOHIDDevice) {
    guard let id = entries.first(where: { $0.value.device == device })?.key ?? Self.registryID(device),
          let entry = entries.removeValue(forKey: id)
    else { return }
    if entry.seized {
      // Balance the open and schedule; harmless on a terminated device.
      IOHIDDeviceRegisterInputValueCallback(entry.device, nil, nil)
      IOHIDDeviceUnscheduleFromRunLoop(entry.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
      IOHIDDeviceClose(entry.device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    }
    logger.notice("device removed: id=\(id)")
    callbacks?.deviceRemoved(id)
  }

  private func inputValue(_ value: IOHIDValue, deviceID: UInt64) {
    let element = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    // Key contents are never logged.
    guard page <= UInt32(UInt16.max), usage <= UInt32(UInt16.max) else { return }
    callbacks?.value(RawKeyEvent(
      deviceID: deviceID,
      page: UInt16(page),
      usage: UInt16(usage),
      isDown: IOHIDValueGetIntegerValue(value) != 0,
      timestamp: nanoseconds(IOHIDValueGetTimeStamp(value))
    ))
  }

  private func nanoseconds(_ machTime: UInt64) -> UInt64 {
    guard timebase.numer != timebase.denom, timebase.denom != 0 else { return machTime }
    let (high, low) = machTime.multipliedFullWidth(by: UInt64(timebase.numer))
    return UInt64(denom: UInt64(timebase.denom), high: high, low: low)
  }

  // MARK: Helpers

  /// Runs `work` on the run loop thread and waits for it (directly when already there).
  private func onRunLoop<T>(_ work: @escaping () -> T) -> T {
    guard let runLoop else { preconditionFailure("LiveHIDSeizer used before start") }
    if CFRunLoopGetCurrent() === runLoop {
      return work()
    }
    // `work` is genuinely escaping: the run loop may still retain the block after `done` is
    // signalled, so it must not be wrapped in `withoutActuallyEscaping` (that traps).
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) let work = work
    CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
      box.value = work()
      done.signal()
    }
    CFRunLoopWakeUp(runLoop)
    done.wait()
    return box.value!
  }

  private static func registryID(_ device: IOHIDDevice) -> UInt64? {
    let service = IOHIDDeviceGetService(device)
    guard service != 0 else { return nil }
    var id: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { return nil }
    return id
  }

  private static func property<T>(_ device: IOHIDDevice, _ key: String) -> T? {
    IOHIDDeviceGetProperty(device, key as CFString) as? T
  }
}

private extension UInt64 {
  /// (high, low) / denom, saturating on overflow.
  init(denom: UInt64, high: UInt64, low: UInt64) {
    guard high < denom else {
      self = .max
      return
    }
    self = denom.dividingFullWidth((high, low)).quotient
  }
}

/// Hands a result from the run loop thread back to the waiting caller (ordered by the semaphore).
private final class ResultBox<T>: @unchecked Sendable {
  var value: T?
}
