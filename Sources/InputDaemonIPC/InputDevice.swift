import Foundation

public struct InputDevice: Codable, Equatable, Sendable, Identifiable {
  /// IORegistry entry ID.
  public var id: UInt64
  public var name: String
  public var vendorID: Int
  public var productID: Int
  public var countryCode: Int
  /// `nil` = seized; otherwise the IOReturn code of the failed seize.
  public var seizeError: Int32?

  public init(
    id: UInt64, name: String, vendorID: Int, productID: Int, countryCode: Int, seizeError: Int32?
  ) {
    self.id = id
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.countryCode = countryCode
    self.seizeError = seizeError
  }
}

public extension InputDevice {
  static func encode(_ devices: [InputDevice]) throws -> Data {
    try JSONEncoder().encode(devices)
  }

  static func decode(_ data: Data) throws -> [InputDevice] {
    try JSONDecoder().decode([InputDevice].self, from: data)
  }
}
