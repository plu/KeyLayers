import Foundation
@testable import KeyIO
import KeymapModel
import RemapEngine
import Testing

struct VirtualKeyboardStateTests {
  private func down(_ key: KeyID, _ modifiers: Modifiers = []) -> OutputEvent {
    OutputEvent(key: key, isDown: true, modifiers: modifiers)
  }

  private func up(_ key: KeyID, _ modifiers: Modifiers = []) -> OutputEvent {
    OutputEvent(key: key, isDown: false, modifiers: modifiers)
  }

  @Test func pressAndReleaseLetter() {
    var state = VirtualKeyboardState()
    #expect(state.apply(down(.a)) == Data([1, 0, 0, 4, 0, 0, 0, 0, 0, 0]))
    #expect(state.apply(up(.a)) == Data([1, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
  }

  @Test func keyboardReportHasID1() {
    var state = VirtualKeyboardState()
    let report = state.apply(down(.a))
    #expect(report == Data([1, 0, 0, 4, 0, 0, 0, 0, 0, 0]))
    #expect(report?.count == 10)
  }

  @Test func consumerKeyReport() {
    var state = VirtualKeyboardState()
    #expect(state.apply(down(.volumeUp)) == Data([2, 0xE9, 0x00]))
    #expect(state.apply(up(.volumeUp)) == Data([2, 0, 0]))
    #expect(state.apply(down(.missionControl)) == Data([2, 0x9F, 0x02]))
  }

  @Test func systemKeyReport() {
    var state = VirtualKeyboardState()
    #expect(state.apply(down(.doNotDisturb)) == Data([3, 0x9B]))
    #expect(state.apply(up(.doNotDisturb)) == Data([3, 0]))
  }

  @Test func secondConsumerKeyReplacesFirst() {
    var state = VirtualKeyboardState()
    _ = state.apply(down(.volumeUp))
    #expect(state.apply(down(.mute)) == Data([2, 0xE2, 0]))
    #expect(state.apply(up(.volumeUp)) == nil)
    #expect(state.apply(up(.mute)) == Data([2, 0, 0]))
  }

  @Test func releaseAllReleasesMediaSlots() {
    var state = VirtualKeyboardState()
    _ = state.apply(down(.volumeUp))
    _ = state.apply(down(.doNotDisturb))
    #expect(state.releaseAll() == [Data([2, 0, 0]), Data([3, 0])])
    #expect(state.releaseAll().isEmpty)
  }

  @Test func descriptorDeclaresThreeReports() {
    // Walk the short items: report ID (0x85) and, per report, the input size in bits.
    let bytes = [UInt8](VirtualKeyboardState.descriptor)
    var index = 0
    var currentID = 0
    var size = 0
    var count = 0
    var sizes: [Int: Int] = [:]
    while index < bytes.count {
      let prefix = bytes[index]
      let length = prefix & 0x03 == 3 ? 4 : Int(prefix & 0x03)
      let data = bytes[(index + 1)..<(index + 1 + length)]
      let value = data.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
      switch prefix & 0xFC {
      case 0x84: currentID = value
      case 0x74: size = value
      case 0x94: count = value
      case 0x80: sizes[currentID, default: 0] += size * count
      default: break
      }
      index += 1 + length
    }
    #expect(sizes == [1: 72, 2: 16, 3: 8])
  }

  @Test func modifierKeysSetBits() {
    var state = VirtualKeyboardState()
    #expect(state.apply(down(.leftShift))?[1] == 0x02)
    #expect(state.apply(up(.leftShift))?[1] == 0)
  }

  @Test func extraModifiersOnlyWhileKeyDown() {
    var state = VirtualKeyboardState()
    let report = state.apply(down(.c, Modifiers(.leftCommand)))
    #expect(report?[1] == 0x08)
    #expect(report?[3] == 0x06)
    #expect(state.apply(up(.c, Modifiers(.leftCommand)))?[1] == 0)
  }

  @Test func releasedPhysicalModifierClearsWhileKeyHeld() {
    var state = VirtualKeyboardState()
    _ = state.apply(down(.leftShift))
    _ = state.apply(down(.a, Modifiers(.leftShift)))
    let report = state.apply(up(.leftShift))
    #expect(report?[1] == 0)
    #expect(report?[3] == 0x04)
  }

  @Test func modifierHeldOnAnotherKeyboardIsNotAnExtra() {
    var state = VirtualKeyboardState()
    let report = state.apply(down(.a, Modifiers(.leftShift)), heldElsewhere: Modifiers(.leftShift))
    #expect(report?[1] == 0)
  }

  @Test func fnUsesVendorByte() {
    var state = VirtualKeyboardState()
    #expect(state.apply(down(.fn))?[9] == 1)
    #expect(state.apply(up(.fn))?[9] == 0)
  }

  @Test func repeatIsIgnored() {
    var state = VirtualKeyboardState()
    _ = state.apply(down(.a))
    #expect(state.apply(OutputEvent(key: .a, isDown: true, isRepeat: true, modifiers: [])) == nil)
  }

  @Test func rolloverNeverLosesKeyUps() {
    var state = VirtualKeyboardState()
    let keys: [KeyID] = [.a, .b, .c, .d, .e, .f, .g]
    var downs: [Data?] = []
    for key in keys { downs.append(state.apply(down(key))) }
    #expect(downs[6] == nil)
    var ups: [Data?] = []
    for key in keys { ups.append(state.apply(up(key))) }
    #expect(ups[6] == nil)
    #expect(ups[5] == Data([1, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
  }

  @Test func releaseAllClearsEverything() {
    var state = VirtualKeyboardState()
    _ = state.apply(down(.leftShift))
    _ = state.apply(down(.a))
    #expect(state.releaseAll() == [Data([1, 0, 0, 0, 0, 0, 0, 0, 0, 0])])
    #expect(state.releaseAll().isEmpty)
  }

  @Test func descriptorIsNonEmpty() {
    #expect(VirtualKeyboardState.descriptor.count > 0)
  }

  @Test func getReportReplyIsSizedPerReportID() {
    #expect(VirtualKeyboardState.getReportReply(id: 1, maxSize: 64) == Data([1] + [UInt8](repeating: 0, count: 9)))
    #expect(VirtualKeyboardState.getReportReply(id: 2, maxSize: 64) == Data([2, 0, 0]))
    #expect(VirtualKeyboardState.getReportReply(id: 3, maxSize: 64) == Data([3, 0]))
    // No report ID: the keyboard report.
    #expect(VirtualKeyboardState.getReportReply(id: nil, maxSize: 64) == Data([1] + [UInt8](repeating: 0, count: 9)))
  }

  @Test func getReportReplyIsCappedAtMaxSize() {
    #expect(VirtualKeyboardState.getReportReply(id: 1, maxSize: 4) == Data([1, 0, 0, 0]))
    #expect(VirtualKeyboardState.getReportReply(id: 2, maxSize: 1) == Data([2]))
    #expect(VirtualKeyboardState.getReportReply(id: 3, maxSize: 0) == Data())
  }
}
