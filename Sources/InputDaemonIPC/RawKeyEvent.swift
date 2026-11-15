import Foundation

public enum WireFormatError: Error, Equatable {
  case truncated
}

public struct RawKeyEvent: Equatable, Sendable {
  public var deviceID: UInt64
  public var page: UInt16
  public var usage: UInt16
  public var isDown: Bool
  /// Nanoseconds, monotonic.
  public var timestamp: UInt64

  public init(deviceID: UInt64, page: UInt16, usage: UInt16, isDown: Bool, timestamp: UInt64) {
    self.deviceID = deviceID
    self.page = page
    self.usage = usage
    self.isDown = isDown
    self.timestamp = timestamp
  }
}

extension RawKeyEvent {
  /// Size of one encoded event: 8 + 2 + 2 + 1 + 8.
  static let recordSize = 21

  /// Fixed-size little-endian records: deviceID, page, usage, isDown, timestamp.
  public static func encode(_ events: [RawKeyEvent]) -> Data {
    var data = Data()
    data.reserveCapacity(events.count * recordSize)
    for event in events {
      append(event.deviceID, to: &data)
      append(event.page, to: &data)
      append(event.usage, to: &data)
      data.append(event.isDown ? 1 : 0)
      append(event.timestamp, to: &data)
    }
    return data
  }

  public static func decode(_ data: Data) throws -> [RawKeyEvent] {
    guard data.count % recordSize == 0 else { throw WireFormatError.truncated }
    let bytes = [UInt8](data)
    return stride(from: 0, to: bytes.count, by: recordSize).map { start in
      RawKeyEvent(
        deviceID: read(UInt64.self, bytes, start),
        page: read(UInt16.self, bytes, start + 8),
        usage: read(UInt16.self, bytes, start + 10),
        isDown: bytes[start + 12] != 0,
        timestamp: read(UInt64.self, bytes, start + 13)
      )
    }
  }

  private static func append(_ value: some FixedWidthInteger, to data: inout Data) {
    withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
  }

  private static func read<T: FixedWidthInteger>(_: T.Type, _ bytes: [UInt8], _ offset: Int) -> T {
    var value: T = 0
    for i in 0 ..< MemoryLayout<T>.size {
      value |= T(truncatingIfNeeded: bytes[offset + i]) << (8 * i)
    }
    return value
  }
}
