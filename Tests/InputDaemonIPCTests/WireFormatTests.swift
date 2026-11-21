import Foundation
@testable import InputDaemonIPC
import Testing

struct WireFormatTests {
  @Test func rawKeyEventsRoundTrip() throws {
    let events = [
      RawKeyEvent(deviceID: 1, page: 0x07, usage: 0x04, isDown: true, timestamp: 123),
      RawKeyEvent(deviceID: UInt64.max, page: 0xFF, usage: 0x03, isDown: false, timestamp: UInt64.max),
    ]
    let data = RawKeyEvent.encode(events)
    #expect(data.count == 42)
    #expect(try RawKeyEvent.decode(data) == events)
    #expect(RawKeyEvent.encode([]).isEmpty)
  }

  @Test func truncatedDataThrows() {
    #expect(throws: WireFormatError.truncated) {
      try RawKeyEvent.decode(Data(count: 20))
    }
  }

  @Test func devicesRoundTrip() throws {
    let devices = [
      InputDevice(id: 42, name: "K", vendorID: 0x5AC, productID: 0x342, countryCode: 13, seizeError: nil),
      InputDevice(
        id: 43, name: "L", vendorID: 1, productID: 2, countryCode: 0,
        seizeError: Int32(bitPattern: 0xE000_02C5)
      ),
    ]
    #expect(try InputDevice.decode(InputDevice.encode(devices)) == devices)
  }

  @Test func peerRequirementPinsHelperAndTeam() {
    #expect(
      PeerRequirement.helper(bundleID: "com.plunien.keylayers.helper", teamID: "ABCDE12345")
        == #"identifier "com.plunien.keylayers.helper" and anchor apple generic "#
        + #"and certificate leaf[subject.OU] = "ABCDE12345""#
    )
  }
}
