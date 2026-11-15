import Clocks
import CoreHID
import Foundation
import InputDaemonIPC
@testable import KeyIO
import KeymapModel
import RemapEngine
import Testing

struct HIDBackendTests {
  let log = CallLog()
  let clock = TestClock()
  let runtime = FakeRuntime()
  let daemon: FakeDaemon
  let factory: FakeVirtualKeyboardFactory
  let backend: HIDBackend
  let reportedDevices = DeviceReports()
  let captureStates = CaptureStates()

  init(connectFailures: Int = 0, preflightError: (any Error)? = nil, failingDevices: Set<UInt64> = []) {
    daemon = FakeDaemon(log: log, connectFailures: connectFailures)
    factory = FakeVirtualKeyboardFactory(log: log, preflightError: preflightError, failingDevices: failingDevices)
    let reportedDevices = reportedDevices
    let captureStates = captureStates
    backend = HIDBackend(
      daemon: daemon, keyboards: factory, clock: clock,
      onDevicesChanged: { reportedDevices.append($0) },
      onCaptureChanged: { captureStates.append($0) }
    )
  }

  /// Starts the backend with capture on and `devices` reported.
  func startCapturing(_ devices: [InputDevice] = [keyboard(1)]) throws {
    let runtime = runtime
    try backend.start(handler: { runtime.handle($0) }, interrupted: { runtime.interrupted() })
    backend.setCaptureEnabled(true)
    daemon.report(devices)
    backend.drain()
  }

  /// Waits until `condition` holds, yielding to let the heartbeat/reconnect tasks run (they resume
  /// asynchronously after `TestClock.advance`). Bounded by iterations, not wall-clock time.
  func eventually(_ condition: () -> Bool) async {
    for _ in 0 ..< 10000 {
      backend.drain()
      if condition() {
        return
      }
      await Task.yield()
    }
  }

  /// Gives the timer tasks plenty of chances to run, for checking that something does *not* happen.
  func settle() async {
    for _ in 0 ..< 1000 {
      backend.drain()
      await Task.yield()
    }
  }

  // MARK: Start

  @Test func startConnectsAfterPreflightAndCapturesOnlyWhenEnabled() throws {
    let runtime = runtime
    try backend.start(handler: { runtime.handle($0) }, interrupted: { runtime.interrupted() })
    #expect(log.commands == [.preflight, .connect])
    backend.setCaptureEnabled(true)
    #expect(log.commands == [.preflight, .connect, .startCapture])
  }

  @Test func captureEnabledBeforeStartCapturesOnStart() throws {
    backend.setCaptureEnabled(true)
    #expect(log.commands.isEmpty)
    let runtime = runtime
    try backend.start(handler: { runtime.handle($0) }, interrupted: { runtime.interrupted() })
    #expect(log.commands == [.preflight, .connect, .startCapture])
  }

  @Test func createsKeyboardWhenDeviceIsReported() throws {
    try startCapturing([keyboard(1, name: "Magic Keyboard", countryCode: 9)])
    #expect(factory.made.map(\.id) == [1])
    daemon.send([raw(1, 0x04), raw(1, 0x04, down: false)])
    backend.drain()
    #expect(log.reports(1) == [report(0x04), emptyReport])
    // Reported again (e.g. another device came): the keyboard is kept.
    daemon.report([keyboard(1, name: "Magic Keyboard", countryCode: 9), keyboard(2)])
    backend.drain()
    #expect(factory.made.map(\.id) == [1, 2])
  }

  @Test func seizeFailedDeviceGetsNoKeyboard() throws {
    try startCapturing([keyboard(1, seizeError: CaptureNotPermitted.code)])
    #expect(factory.made.isEmpty)
  }

  @Test func virtualKeyboardFailureFailsStart() {
    let test = HIDBackendTests(preflightError: KeyIOError.virtualKeyboardUnavailable)
    let runtime = test.runtime
    #expect(throws: KeyIOError.virtualKeyboardUnavailable) {
      try test.backend.start(handler: { runtime.handle($0) }, interrupted: { runtime.interrupted() })
    }
    test.backend.setCaptureEnabled(true)
    #expect(!test.log.entries.contains(.startCapture))
    #expect(!test.log.entries.contains(.connect))
  }

  @Test func daemonConnectFailureFailsStart() {
    let test = HIDBackendTests(connectFailures: 1)
    let runtime = test.runtime
    #expect(throws: KeyIOError.daemonUnavailable) {
      try test.backend.start(handler: { runtime.handle($0) }, interrupted: { runtime.interrupted() })
    }
    test.backend.setCaptureEnabled(true)
    #expect(!test.log.entries.contains(.startCapture))
  }

  // MARK: Input and output

  @Test func keyEventsReachTheHandlerInOrder() throws {
    try startCapturing()
    daemon.send([raw(1, 0x04, at: 10), raw(1, 0x05, at: 11), raw(1, 0x04, down: false, at: 12)])
    backend.drain()
    #expect(runtime.received == [
      KeyEvent(key: .a, phase: .down, timestamp: 10),
      KeyEvent(key: .b, phase: .down, timestamp: 11),
      KeyEvent(key: .a, phase: .up, timestamp: 12),
    ])
  }

  @Test func doesNotSwapISOKeys() throws {
    try startCapturing([keyboard(1, vendorID: 0x05AC, countryCode: 13)])
    daemon.send([raw(1, 0x35)])
    backend.drain()
    #expect(runtime.received.map(\.key) == [.graveAccentAndTilde])
    // Passed through unchanged: raw usages already match the configurator's convention.
    #expect(log.reports(1) == [report(0x35)])
  }

  @Test func passThroughEmitsOriginalKey() throws {
    try startCapturing()
    daemon.send([raw(1, 0xE1), raw(1, 0x04), raw(1, 0x04, down: false), raw(1, 0xE1, down: false)])
    backend.drain()
    #expect(log.reports(1) == [
      report(modifiers: 0x02), report(modifiers: 0x02, 0x04), report(modifiers: 0x02), emptyReport,
    ])
  }

  @Test func suppressEmitsOnlyEngineOutput() throws {
    try startCapturing()
    let backend = backend
    runtime.respond { event in
      backend.post([OutputEvent(key: .b, isDown: event.phase == .down, modifiers: [])])
      return .suppress
    }
    daemon.send([raw(1, 0x04), raw(1, 0x04, down: false)])
    backend.drain()
    #expect(log.reports(1) == [report(0x05), emptyReport])
  }

  @Test func outputGoesToSourceDevicesKeyboard() throws {
    try startCapturing([keyboard(1), keyboard(2)])
    let backend = backend
    runtime.respond { event in
      backend.post([OutputEvent(key: .b, isDown: event.phase == .down, modifiers: [])])
      return .suppress
    }
    daemon.send([raw(2, 0x04)])
    backend.drain()
    #expect(log.reports(1).isEmpty)
    #expect(log.reports(2) == [report(0x05)])

    // Outside the handler: the most recently active device.
    backend.post([OutputEvent(key: .c, isDown: true, modifiers: [])])
    #expect(log.reports(2).last == report(0x05, 0x06))
    // The up follows its down, wherever it comes from.
    daemon.send([raw(1, 0x04, down: false)])
    backend.drain()
    #expect(log.reports(1).isEmpty)
    #expect(log.reports(2).last == report(0x06))
  }

  @Test func modifiersHeldOnAnotherKeyboardAreNotExtras() throws {
    try startCapturing([keyboard(1), keyboard(2)])
    let backend = backend
    daemon.send([raw(1, 0xE1)]) // Shift on keyboard 1, passed through.
    backend.drain()
    runtime.respond { event in
      backend.post([OutputEvent(key: .b, isDown: event.phase == .down, modifiers: Modifiers(.leftShift))])
      return .suppress
    }
    daemon.send([raw(2, 0x04)])
    backend.drain()
    runtime.respond { _ in .passThrough }
    daemon.send([raw(1, 0xE1, down: false)])
    backend.drain()
    // macOS merges modifiers across keyboards: keyboard 2 sends B without its own Shift, so
    // releasing Shift on keyboard 1 releases it.
    #expect(log.reports(1) == [report(modifiers: 0x02), emptyReport])
    #expect(log.reports(2) == [report(0x05)])
  }

  @Test func outputWithoutKeyboardsIsDropped() throws {
    try startCapturing([])
    backend.post([OutputEvent(key: .a, isDown: true, modifiers: [])])
    #expect(log.entries.allSatisfy {
      if case .report = $0 {
        false
      } else {
        true
      }
    })
  }

  // MARK: Capture, heartbeat, disconnects

  @Test func heartbeatEvery500ms() async throws {
    try startCapturing()
    await clock.advance(by: .milliseconds(499))
    backend.drain()
    #expect(log.count(.heartbeat) == 0)
    await clock.advance(by: .milliseconds(1))
    await eventually { log.count(.heartbeat) == 1 }
    #expect(log.count(.heartbeat) == 1)
    await clock.advance(by: .milliseconds(500))
    await eventually { log.count(.heartbeat) == 2 }
    #expect(log.count(.heartbeat) == 2)

    // Not while capture is off: the daemon ignores them.
    backend.setCaptureEnabled(false)
    await clock.advance(by: .milliseconds(500))
    await settle()
    backend.drain()
    #expect(log.count(.heartbeat) == 2)
    backend.setCaptureEnabled(true)
    await clock.advance(by: .milliseconds(500))
    await eventually { log.count(.heartbeat) == 3 }
    #expect(log.count(.heartbeat) == 3)

    backend.stop()
    await clock.advance(by: .seconds(5))
    await settle()
    #expect(log.count(.heartbeat) == 3)
  }

  /// The daemon released the keyboards on its own (heartbeat timeout, e.g. across sleep): the next
  /// heartbeat's reply says so, and the backend starts capture again.
  @Test func reCapturesAfterDaemonTimeout() async throws {
    try startCapturing()
    #expect(factory.made.map(\.id) == [1])
    // What the daemon sends when it times out.
    daemon.isCapturing = false
    daemon.report([])
    backend.drain()
    #expect(log.count(.startCapture) == 1)

    await clock.advance(by: .milliseconds(500))
    await eventually { log.count(.startCapture) == 2 }
    #expect(log.count(.startCapture) == 2)
    #expect(log.count(.stopCapture) == 0)

    // The daemon seized again: the keyboard is recreated and keys flow.
    daemon.isCapturing = true
    daemon.report([keyboard(1)])
    backend.drain()
    #expect(factory.made.map(\.id) == [1, 1])
    daemon.send([raw(1, 0x04)])
    backend.drain()
    #expect(log.reports(1).last == report(0x04))

    // Capturing again: no more startCaptures.
    await clock.advance(by: .milliseconds(1000))
    await eventually { log.count(.heartbeat) >= 3 }
    await settle()
    #expect(log.count(.startCapture) == 2)
  }

  @Test func heartbeatReplyBeforeTheDevicesReportAlsoDropsTheKeyboards() async throws {
    try startCapturing()
    daemon.isCapturing = false
    await clock.advance(by: .milliseconds(500))
    await eventually { log.count(.startCapture) == 2 }
    daemon.isCapturing = true
    // The keyboards were dropped with the lost capture; the next report recreates them.
    daemon.report([keyboard(1)])
    backend.drain()
    #expect(factory.made.map(\.id) == [1, 1])
  }

  @Test func disablingCaptureReleasesAllKeys() throws {
    try startCapturing([keyboard(1), keyboard(2)])
    daemon.send([raw(1, 0x04), raw(2, 0xE0)])
    backend.drain()
    backend.setCaptureEnabled(false)
    #expect(log.reports(1).last == emptyReport)
    #expect(log.reports(2).last == emptyReport)
    let entries = log.entries
    let lastReport = try #require(entries.lastIndex {
      if case .report = $0 {
        true
      } else {
        false
      }
    })
    let stop = try #require(entries.firstIndex(of: .stopCapture))
    #expect(lastReport < stop, "release first, then hand the keyboards back")

    backend.setCaptureEnabled(true)
    #expect(log.count(.startCapture) == 2)
  }

  @Test func disablingCaptureReleasesMediaKeys() throws {
    try startCapturing()
    backend.post([
      OutputEvent(key: .volumeUp, isDown: true, modifiers: []),
      OutputEvent(key: .doNotDisturb, isDown: true, modifiers: []),
    ])
    #expect(log.reports(1) == [Data([2, 0xE9, 0]), Data([3, 0x9B])])
    backend.setCaptureEnabled(false)
    #expect(log.reports(1).suffix(2) == [Data([2, 0, 0]), Data([3, 0])])
  }

  @Test func noPassThroughAfterCaptureDisabled() throws {
    try startCapturing()
    daemon.send([raw(1, 0x04)])
    backend.drain()
    backend.setCaptureEnabled(false)
    #expect(log.reports(1) == [report(0x04), emptyReport])
    // Already sent by the daemon before it released the keyboard: its up goes to the system now.
    daemon.send([raw(1, 0x05)])
    backend.drain()
    #expect(log.reports(1) == [report(0x04), emptyReport])
  }

  @Test func captureDisabledFromInsideHandlerSuppressesPassThrough() throws {
    try startCapturing()
    let backend = backend
    runtime.respond { _ in
      backend.setCaptureEnabled(false) // e.g. the emergency stop pausing the runtime
      return .passThrough
    }
    daemon.send([raw(1, 0x04)])
    backend.drain()
    #expect(log.reports(1).isEmpty)
    #expect(log.count(.stopCapture) == 1)
  }

  @Test func engineDownsAreDroppedWhileCaptureIsOff() throws {
    try startCapturing()
    backend.post([OutputEvent(key: .b, isDown: true, modifiers: [])])
    #expect(log.reports(1) == [report(0x05)])
    backend.setCaptureEnabled(false)
    backend.post([OutputEvent(key: .c, isDown: true, modifiers: [])])
    backend.post([OutputEvent(key: .b, isDown: false, modifiers: [])])
    #expect(log.reports(1) == [report(0x05), emptyReport])
  }

  @Test func noPassThroughAfterKeyboardCreationFailure() throws {
    let test = HIDBackendTests(failingDevices: [2])
    try test.startCapturing([keyboard(1)])
    test.daemon.report([keyboard(1), keyboard(2)])
    test.daemon.send([raw(1, 0x04)])
    test.backend.drain()
    #expect(test.log.reports(1).isEmpty)
  }

  @Test func stopReleasesStopsCaptureAndDisconnects() throws {
    try startCapturing()
    daemon.send([raw(1, 0x04)])
    backend.drain()
    backend.stop()
    #expect(log.reports(1).last == emptyReport)
    #expect(Array(log.commands.suffix(2)) == [.stopCapture, .disconnect])
  }

  @Test func daemonDisconnectInterrupts() throws {
    try startCapturing()
    daemon.send([raw(1, 0x04)])
    backend.drain()
    daemon.dropConnection()
    backend.drain()
    #expect(runtime.interruptionCount == 1)
    #expect(log.reports(1).last == emptyReport)
  }

  @Test func reconnectsAfterDisconnectWithBackoff() async throws {
    try startCapturing()
    daemon.dropConnection()
    backend.drain()
    await clock.advance(by: .milliseconds(1999))
    backend.drain()
    #expect(log.count(.connect) == 1)

    await clock.advance(by: .milliseconds(1))
    await eventually { log.count(.startCapture) == 2 }
    #expect(log.count(.connect) == 2)
    #expect(log.count(.startCapture) == 2)
    #expect(Array(log.commands.suffix(2)) == [.connect, .startCapture])
  }

  @Test func reconnectWithoutCaptureDoesNotStartCapture() async throws {
    let test = HIDBackendTests(connectFailures: 0)
    try test.startCapturing()
    test.backend.setCaptureEnabled(false)
    test.daemon.dropConnection()
    test.backend.drain()
    await test.clock.advance(by: .seconds(2))
    await test.eventually { test.log.count(.connect) == 2 }
    #expect(test.log.count(.connect) == 2)
    // Capture is off: no startCapture after reconnecting.
    #expect(test.log.count(.startCapture) == 1)
  }

  @Test func reconnectRetriesWhileConnectThrows() async throws {
    let test = HIDBackendTests()
    try test.startCapturing()
    test.daemon.failNextConnects(1)
    test.daemon.dropConnection()
    test.backend.drain()
    await test.clock.advance(by: .seconds(2))
    await test.eventually { test.log.count(.connect) == 2 }
    #expect(test.log.count(.startCapture) == 1)
    await test.clock.advance(by: .milliseconds(1999))
    test.backend.drain()
    #expect(test.log.count(.connect) == 2)
    await test.clock.advance(by: .milliseconds(1))
    await test.eventually { test.log.count(.startCapture) == 2 }
    #expect(test.log.count(.connect) == 3)
    #expect(test.log.count(.startCapture) == 2)
  }

  @Test func devicesChangedIsForwarded() throws {
    let devices = [keyboard(1), keyboard(2, seizeError: CaptureNotPermitted.code)]
    try startCapturing(devices)
    #expect(reportedDevices.all == [devices])
  }

  @Test func unpluggedDeviceReleasesItsKeys() throws {
    try startCapturing([keyboard(1), keyboard(2)])
    let backend = backend
    runtime.respond { event in
      backend.post([OutputEvent(key: .b, isDown: event.phase == .down, modifiers: [])])
      return .suppress
    }
    daemon.send([raw(1, 0x04)])
    backend.drain()
    #expect(log.reports(1) == [report(0x05)])

    daemon.report([keyboard(2)])
    backend.drain()
    #expect(log.reports(1) == [report(0x05), emptyReport])

    // The up of the key held on the unplugged keyboard goes nowhere.
    backend.post([OutputEvent(key: .b, isDown: false, modifiers: [])])
    #expect(log.reports(1) == [report(0x05), emptyReport])
    #expect(log.reports(2).isEmpty)
  }

  /// A layer key held on an unplugged keyboard never sends its up: the engine must start over.
  @Test func unpluggingAKeyboardWithAHeldKeyInterrupts() throws {
    try startCapturing([keyboard(1), keyboard(2)])
    runtime.respond { _ in .suppress } // e.g. a layer key: nothing reaches the virtual keyboard
    daemon.send([raw(1, 0x2C)])
    backend.drain()
    #expect(log.reports(1).isEmpty)

    daemon.report([keyboard(2)])
    backend.drain()
    #expect(runtime.interruptionCount == 1)
  }

  @Test func unpluggingAnIdleKeyboardDoesNotInterrupt() throws {
    try startCapturing([keyboard(1), keyboard(2)])
    daemon.send([raw(1, 0x04), raw(1, 0x04, down: false), raw(2, 0x05)])
    backend.drain()
    daemon.report([keyboard(2)])
    backend.drain()
    #expect(runtime.interruptionCount == 0, "only keyboard 2 has a key down")
  }

  @Test func daemonSideReleaseWithAHeldKeyInterrupts() async throws {
    try startCapturing()
    runtime.respond { _ in .suppress }
    daemon.send([raw(1, 0x2C)])
    backend.drain()
    daemon.isCapturing = false
    await clock.advance(by: .milliseconds(500))
    await eventually { runtime.interruptionCount == 1 }
    #expect(runtime.interruptionCount == 1)
    #expect(log.count(.startCapture) == 2)
  }

  @Test func daemonSideReleaseReportFirstAlsoInterrupts() throws {
    try startCapturing()
    runtime.respond { _ in .suppress }
    daemon.send([raw(1, 0x2C)])
    // The daemon's report of the release arrives before the heartbeat reply.
    daemon.report([])
    backend.drain()
    #expect(runtime.interruptionCount == 1)
  }

  // MARK: Capture state

  @Test func capturingOnceTheDaemonReportsDevices() throws {
    let runtime = runtime
    try backend.start(handler: { runtime.handle($0) }, interrupted: { runtime.interrupted() })
    backend.setCaptureEnabled(true)
    backend.drain()
    #expect(captureStates.all.isEmpty, "startCapture sent, but the daemon hasn't answered")
    daemon.report([keyboard(1)])
    backend.drain()
    #expect(captureStates.all == [true])
    daemon.report([keyboard(1), keyboard(2)])
    backend.drain()
    #expect(captureStates.all == [true], "only changes are reported")

    backend.setCaptureEnabled(false)
    backend.drain()
    #expect(captureStates.all == [true, false])
  }

  @Test func notCapturingWhileTheDaemonIsUnreachable() throws {
    try startCapturing()
    daemon.dropConnection()
    backend.drain()
    #expect(captureStates.all == [true, false])
  }

  @Test func notCapturingAfterTheDaemonReleasedTheKeyboards() async throws {
    try startCapturing()
    daemon.isCapturing = false
    await clock.advance(by: .milliseconds(500))
    await eventually { captureStates.all == [true, false] }
    #expect(captureStates.all == [true, false])
    daemon.isCapturing = true
    daemon.report([keyboard(1)])
    backend.drain()
    #expect(captureStates.all == [true, false, true])
  }

  @Test func notCapturingAfterKeyboardCreationFailure() throws {
    let test = HIDBackendTests(failingDevices: [2])
    try test.startCapturing([keyboard(1)])
    test.daemon.report([keyboard(1), keyboard(2)])
    test.backend.drain()
    #expect(test.captureStates.all == [true, false])
  }

  @Test func keyboardCreationFailureStopsCapture() throws {
    let test = HIDBackendTests(failingDevices: [2])
    try test.startCapturing([keyboard(1)])
    test.daemon.send([raw(1, 0x04)])
    test.backend.drain()
    test.daemon.report([keyboard(1), keyboard(2)])
    test.backend.drain()
    #expect(test.log.count(.stopCapture) == 1)
    #expect(test.runtime.interruptionCount == 1)
    #expect(test.log.reports(1).last == emptyReport)
  }
}

enum CaptureNotPermitted {
  static let code = Int32(bitPattern: 0xE000_02E2)
}

final class CaptureStates: @unchecked Sendable {
  private let lock = NSLock()
  private var states: [Bool] = []

  var all: [Bool] {
    lock.withLock { states }
  }

  func append(_ capturing: Bool) {
    lock.withLock { states.append(capturing) }
  }
}

final class DeviceReports: @unchecked Sendable {
  private let lock = NSLock()
  private var reports: [[InputDevice]] = []

  var all: [[InputDevice]] {
    lock.withLock { reports }
  }

  func append(_ devices: [InputDevice]) {
    lock.withLock { reports.append(devices) }
  }
}

struct VirtualKeyboardIdentityTests {
  @Test func identityOfAVirtualKeyboard() {
    let identity = VirtualKeyboardIdentity(for: keyboard(42, name: "Magic Keyboard", countryCode: 9))
    #expect(identity.vendorID == 0x4B4C)
    #expect(identity.productID == 0x4C01)
    #expect(identity.uniqueID == "com.plunien.keylayers.virtual.42")
    #expect(identity.product == "KeyLayers Magic Keyboard")
    #expect(identity.countryCode == 9)
  }
}

struct LocalizationCodeTests {
  @Test func mirrorsHIDCountryCodes() {
    #expect(LiveVirtualKeyboardFactory.localizationCode(forCountryCode: 0) == .unsupported)
    #expect(LiveVirtualKeyboardFactory.localizationCode(forCountryCode: 9) == .germany)
    #expect(LiveVirtualKeyboardFactory.localizationCode(forCountryCode: 13) == .unitedStatesISO)
    #expect(LiveVirtualKeyboardFactory.localizationCode(forCountryCode: 15) == .japan)
    #expect(LiveVirtualKeyboardFactory.localizationCode(forCountryCode: 33) == .unitedStates)
    #expect(LiveVirtualKeyboardFactory.localizationCode(forCountryCode: 35) == .turkeyStandard)
    #expect(LiveVirtualKeyboardFactory.localizationCode(forCountryCode: 36) == nil)
    #expect(LiveVirtualKeyboardFactory.localizationCode(forCountryCode: -1) == nil)
  }
}
