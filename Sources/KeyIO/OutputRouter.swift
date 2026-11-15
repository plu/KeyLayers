import KeymapModel
import RemapEngine

/// Decides which virtual keyboard an output event goes to. Downs go to the device whose input
/// caused them (or the fallback); ups follow the device their down went to.
public struct OutputRouter: Sendable {
  private var downDevice: [KeyID: UInt64] = [:]

  public init() {}

  public mutating func route(_ event: OutputEvent, source: UInt64?, fallback: UInt64) -> UInt64 {
    if event.isDown {
      if event.isRepeat, let device = downDevice[event.key] {
        return device
      }
      let device = source ?? fallback
      downDevice[event.key] = device
      return device
    }
    return downDevice.removeValue(forKey: event.key) ?? source ?? fallback
  }

  /// Keys that were down on an unplugged device; they are no longer tracked.
  public mutating func forget(device: UInt64) -> Set<KeyID> {
    let keys = Set(downDevice.filter { $0.value == device }.keys)
    for key in keys {
      downDevice.removeValue(forKey: key)
    }
    return keys
  }
}
