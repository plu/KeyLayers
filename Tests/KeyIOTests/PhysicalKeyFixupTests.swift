import InputDaemonIPC
@testable import KeyIO
import KeymapModel
import Testing

struct PhysicalKeyFixupTests {
  private func event(_ page: UInt16, _ usage: UInt16) -> RawKeyEvent {
    RawKeyEvent(deviceID: 1, page: page, usage: usage, isDown: true, timestamp: 0)
  }

  /// Raw seized usages already match the configurator's ISO convention: mapped unchanged, no swap.
  @Test func appleISOKeysAreNotSwapped() {
    #expect(PhysicalKeyFixup.key(for: event(7, 0x35)) == .graveAccentAndTilde)
    #expect(PhysicalKeyFixup.key(for: event(7, 0x64)) == .nonUSBackslash)
  }

  @Test func fnPassesThrough() {
    #expect(PhysicalKeyFixup.key(for: event(0xFF, 0x03)) == .fn)
  }
}
