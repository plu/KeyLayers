import Foundation

/// A physical key, identified by HID usage page and usage.
public struct KeyID: Hashable, Sendable, Codable, CodingKeyRepresentable, CustomStringConvertible {
  public let page: UInt16
  public let usage: UInt16

  public init(page: UInt16, usage: UInt16) {
    self.page = page
    self.usage = usage
  }

  /// Parses the `"<page>:<usage>"` form produced by `description`.
  public init?(string: String) {
    let parts = string.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, let page = UInt16(parts[0]), let usage = UInt16(parts[1]) else {
      return nil
    }
    self.init(page: page, usage: usage)
  }

  public var description: String {
    "\(page):\(usage)"
  }

  public init(from decoder: any Decoder) throws {
    let string = try decoder.singleValueContainer().decode(String.self)
    guard let key = KeyID(string: string) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid key ID \"\(string)\"")
      )
    }
    self = key
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }

  public var codingKey: any CodingKey {
    StringCodingKey(stringValue: description)
  }

  public init?(codingKey: some CodingKey) {
    self.init(string: codingKey.stringValue)
  }
}

private struct StringCodingKey: CodingKey {
  let stringValue: String
  var intValue: Int? {
    nil
  }

  init(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue _: Int) {
    nil
  }
}
