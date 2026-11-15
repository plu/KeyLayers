import Clocks
import Foundation
import InputDaemonCore
import InputDaemonIPC
import Synchronization
import Testing

struct CaptureControllerTests {
  let seizer = FakeHIDSeizer(devices: [keyboard(1), keyboard(2)])
  let clock = TestClock()

  func makeController(onNotPermitted: @escaping @Sendable () -> Void = {}) -> CaptureController {
    CaptureController(seizer: seizer, clock: clock, onNotPermitted: onNotPermitted)
  }

  @Test func seizesOnlyAfterStartCaptureWithClient() {
    let controller = makeController()
    controller.drain()
    #expect(seizer.seizeCalls.isEmpty)

    controller.startCapture()
    #expect(seizer.seizeCalls.isEmpty, "no client yet")
    controller.stopCapture()

    let sink = RecordingSink()
    controller.clientConnected(sink)
    #expect(seizer.seizeCalls.isEmpty, "client but no startCapture")

    controller.startCapture()
    #expect(seizer.seizeCalls.sorted() == [1, 2])
    controller.drain()
    #expect(sink.deviceReports.last?.map(\.id) == [1, 2])
    #expect(sink.deviceReports.last?.allSatisfy { $0.seizeError == nil } == true)
  }

  @Test func neverSeizesOwnVirtualKeyboards() {
    seizer.addDevice(keyboard(3, name: "KeyLayers Virtual", vendorID: 0x4B4C))
    seizer.addDevice(keyboard(4, name: "com.plunien.keylayers.virtual.5", vendorID: 0x1234))
    let controller = makeController()
    let sink = RecordingSink()
    controller.clientConnected(sink)
    controller.startCapture()
    seizer.addDevice(keyboard(6, vendorID: 0x4B4C))
    controller.drain()

    #expect(seizer.seizeCalls.sorted() == [1, 2])
    #expect(!sink.deviceReports.isEmpty)
    for report in sink.deviceReports {
      #expect(report.allSatisfy { [1, 2].contains($0.id) })
    }
  }

  @Test func forwardsOnlyKeyboardUsages() {
    let controller = makeController()
    let sink = RecordingSink()
    controller.clientConnected(sink)
    controller.startCapture()

    seizer.inject(device: 1, page: 0x07, usage: 0x04, timestamp: 1)
    seizer.inject(device: 1, page: 0xFF, usage: 0x03, timestamp: 2)
    seizer.inject(device: 1, page: 0x0C, usage: 0xE9, timestamp: 3)
    seizer.inject(device: 1, page: 0x07, usage: 0x01, timestamp: 4)
    seizer.inject(device: 2, page: 0x07, usage: 0xE7, isDown: false, timestamp: 5)
    seizer.inject(device: 2, page: 0x07, usage: 0xE8, timestamp: 6)
    controller.drain()

    #expect(sink.keyEvents == [
      RawKeyEvent(deviceID: 1, page: 0x07, usage: 0x04, isDown: true, timestamp: 1),
      RawKeyEvent(deviceID: 1, page: 0xFF, usage: 0x03, isDown: true, timestamp: 2),
      RawKeyEvent(deviceID: 2, page: 0x07, usage: 0xE7, isDown: false, timestamp: 5),
    ])
  }

  @Test func doesNotForwardWhileNotCapturing() {
    let controller = makeController()
    let sink = RecordingSink()
    controller.clientConnected(sink)
    seizer.inject(device: 1, page: 0x07, usage: 0x04)
    controller.startCapture()
    controller.stopCapture()
    seizer.inject(device: 1, page: 0x07, usage: 0x05)
    controller.drain()
    #expect(sink.keyEvents.isEmpty)
  }

  @Test func releasesOnStopCapture() {
    let controller = makeController()
    let sink = RecordingSink()
    controller.clientConnected(sink)
    controller.startCapture()
    controller.stopCapture()
    controller.drain()
    #expect(seizer.releaseCalls.sorted() == [1, 2])
    #expect(sink.deviceReports.last == [])
  }

  @Test func releasesOnClientDisconnect() {
    let controller = makeController()
    let sink = RecordingSink()
    controller.clientConnected(sink)
    controller.startCapture()
    #expect(seizer.seized == [1, 2])

    controller.clientDisconnected()
    #expect(seizer.releaseCalls.sorted() == [1, 2])
    #expect(seizer.seized.isEmpty)

    // A keyboard plugged in afterwards stays with the system.
    seizer.addDevice(keyboard(7))
    controller.drain()
    #expect(seizer.seizeCalls.sorted() == [1, 2])
  }

  @Test func releasesOnHeartbeatTimeout() async {
    let controller = makeController()
    let sink = RecordingSink()
    controller.clientConnected(sink)
    controller.startCapture()

    await clock.advance(by: .milliseconds(1900))
    controller.drain()
    #expect(seizer.releaseCalls.isEmpty)

    await clock.advance(by: .milliseconds(200))
    await eventually(controller) { seizer.releaseCalls.sorted() == [1, 2] }
    #expect(seizer.releaseCalls.sorted() == [1, 2])
    #expect(sink.deviceReports.last == [])

    // Capture is off now: values are dropped until the client starts capture again.
    seizer.inject(device: 1, page: 0x07, usage: 0x04)
    controller.drain()
    #expect(sink.keyEvents.isEmpty)
  }

  @Test func heartbeatPushesTheDeadline() async {
    let controller = makeController()
    controller.clientConnected(RecordingSink())
    controller.startCapture()

    await clock.advance(by: .milliseconds(1500))
    controller.heartbeat()
    await clock.advance(by: .milliseconds(1900)) // 3.4 s: 1.9 s after the heartbeat
    controller.drain()
    #expect(seizer.releaseCalls.isEmpty)

    await clock.advance(by: .milliseconds(200)) // 3.6 s
    await eventually(controller) { seizer.releaseCalls.sorted() == [1, 2] }
    #expect(seizer.releaseCalls.sorted() == [1, 2])
  }

  @Test func heartbeatReportsWhetherCapturing() async {
    let controller = makeController()
    #expect(!controller.heartbeat(), "no client")
    controller.clientConnected(RecordingSink())
    #expect(!controller.heartbeat(), "client but no startCapture")
    controller.startCapture()
    #expect(controller.heartbeat())

    // Timed out (e.g. the Mac slept): the client learns it from the next heartbeat's reply…
    await clock.advance(by: .milliseconds(2100))
    await eventually(controller) { seizer.releaseCalls.sorted() == [1, 2] }
    #expect(!controller.heartbeat())
    #expect(seizer.seized.isEmpty, "a heartbeat doesn't recapture")
    // …and starts capture again.
    controller.startCapture()
    #expect(controller.heartbeat())
    #expect(seizer.seized == [1, 2])

    controller.stopCapture()
    #expect(!controller.heartbeat())
  }

  @Test func seizesHotPluggedKeyboard() {
    let controller = makeController()
    let sink = RecordingSink()
    controller.clientConnected(sink)
    controller.startCapture()

    seizer.addDevice(keyboard(9, name: "Hot"))
    seizer.inject(device: 9, page: 0x07, usage: 0x04)
    controller.drain()

    #expect(seizer.seizeCalls.last == 9)
    let reportIndex = sink.messages.firstIndex {
      if case let .devices(devices) = $0 {
        return devices.contains { $0.id == 9 && $0.seizeError == nil }
      }
      return false
    }
    let keyIndex = sink.messages.firstIndex {
      if case let .keys(events) = $0 {
        return events.contains { $0.deviceID == 9 }
      }
      return false
    }
    #expect(reportIndex != nil)
    #expect(keyIndex != nil)
    if let reportIndex, let keyIndex {
      #expect(reportIndex < keyIndex)
    }
  }

  @Test func reportsUnplugWhileCapturing() {
    let controller = makeController()
    let sink = RecordingSink()
    controller.clientConnected(sink)
    controller.startCapture()
    seizer.removeDevice(2)
    seizer.inject(device: 2, page: 0x07, usage: 0x04)
    controller.drain()
    #expect(sink.deviceReports.last?.map(\.id) == [1])
    #expect(sink.keyEvents.isEmpty)
  }

  @Test func newClientReplacesOld() {
    let controller = makeController()
    let old = RecordingSink()
    controller.clientConnected(old)
    controller.startCapture()
    controller.drain()
    let oldCount = old.messages.count

    let new = RecordingSink()
    controller.clientConnected(new)
    #expect(seizer.seized.isEmpty, "old client's capture ends with it")
    seizer.inject(device: 1, page: 0x07, usage: 0x04)
    controller.drain()
    #expect(new.keyEvents.isEmpty)

    controller.startCapture()
    #expect(seizer.seized == [1, 2])
    seizer.inject(device: 1, page: 0x07, usage: 0x05)
    controller.drain()

    #expect(old.messages.count == oldCount, "old sink gets nothing further")
    #expect(new.keyEvents.map(\.usage) == [0x05])
  }

  @Test func reportsSeizeFailure() {
    let busy = Int32(bitPattern: 0xE000_02C5)
    seizer.setSeizeResult(busy, for: 2)
    let handlerCalls = Mutex(0)
    let controller = makeController(onNotPermitted: { handlerCalls.withLock { $0 += 1 } })
    let sink = RecordingSink()
    controller.clientConnected(sink)
    controller.startCapture()
    controller.drain()

    #expect(seizer.seized == [1])
    let report = sink.deviceReports.last ?? []
    #expect(report.first { $0.id == 1 }?.seizeError == nil)
    #expect(report.first { $0.id == 2 }?.seizeError == busy)
    #expect(report.count == 2)
    #expect(handlerCalls.withLock { $0 } == 0, "only not-permitted triggers the handler")

    // Values of the unseized keyboard are not forwarded.
    seizer.inject(device: 2, page: 0x07, usage: 0x04)
    controller.drain()
    #expect(sink.keyEvents.isEmpty)
  }

  @Test func notPermittedSeizeCallsHandlerAfterReporting() {
    let notPermitted = Int32(bitPattern: 0xE000_02E2)
    seizer.setSeizeResult(notPermitted, for: 1)
    seizer.setSeizeResult(notPermitted, for: 2)
    let sink = RecordingSink()
    let log = Mutex<[String]>([])
    let controller = makeController(onNotPermitted: {
      let reported = sink.deviceReports.contains { $0.contains { $0.seizeError == notPermitted } }
      log.withLock { $0.append(reported ? "handler after report" : "handler before report") }
    })
    controller.clientConnected(sink)
    controller.startCapture()
    controller.stopCapture()
    controller.startCapture()
    controller.drain()

    #expect(sink.deviceReports.contains { $0.contains { $0.seizeError == notPermitted } })
    #expect(log.withLock { $0 } == ["handler after report"])
  }

  @Test func shutdownFromNotPermittedHandlerReturns() async {
    seizer.setSeizeResult(Int32(bitPattern: 0xE000_02E2), for: 1)
    let controllerBox = Mutex<CaptureController?>(nil)
    let returned = Mutex(false)
    let controller = makeController(onNotPermitted: {
      // What the daemon's main does (R5): shut down, then exit.
      controllerBox.withLock { $0 }?.shutdown()
      controllerBox.withLock { $0 }?.drain()
      returned.withLock { $0 = true }
    })
    controllerBox.withLock { $0 = controller }
    controller.clientConnected(RecordingSink())
    controller.startCapture()

    // Poll without touching the delivery queue, so a deadlock fails the test instead of hanging it.
    for _ in 0 ..< 200 where !returned.withLock({ $0 }) {
      try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(returned.withLock { $0 }, "shutdown() from the handler must not deadlock")
    #expect(seizer.releaseCalls == [2])
    #expect(seizer.seized.isEmpty)
    controllerBox.withLock { $0 = nil }
  }

  @Test func shutdownReleasesEverything() {
    let controller = makeController()
    let sink = RecordingSink()
    controller.clientConnected(sink)
    controller.startCapture()
    controller.shutdown()
    #expect(seizer.releaseCalls.sorted() == [1, 2])
    #expect(seizer.seized.isEmpty)
    #expect(sink.deviceReports.last == [])

    // Nothing is seized again after shutdown.
    controller.startCapture()
    seizer.addDevice(keyboard(8))
    controller.drain()
    #expect(seizer.seizeCalls.sorted() == [1, 2])
  }
}

/// Polls (draining the controller each time) until `condition` holds or ~1 s passed. For effects of
/// the heartbeat task, which resumes asynchronously after `TestClock.advance`.
func eventually(_ controller: CaptureController, _ condition: () -> Bool) async {
  for _ in 0 ..< 200 {
    controller.drain()
    if condition() {
      return
    }
    try? await Task.sleep(for: .milliseconds(5))
  }
}
