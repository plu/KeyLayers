import InputDaemonIPC
import KeymapModel

/// Maps raw seized HID usages to `KeyID`s.
public enum PhysicalKeyFixup {
  public static func key(for event: RawKeyEvent) -> KeyID {
    // Raw seized usages already match the configurator's ISO convention (0x64 = the key top-left,
    // 0x35 = the key next to left Shift); no Apple-ISO swap is needed. Verified on hardware
    // 2026-11-15 (German MacBook ISO keyboard, country code 13). JIS and external Apple ISO
    // keyboards are not yet verified.
    KeyID(page: event.page, usage: event.usage)
  }
}
