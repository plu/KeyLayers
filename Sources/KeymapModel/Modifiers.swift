import Foundation

public enum Modifier: String, CaseIterable, Codable, Sendable {
  case leftControl, leftShift, leftOption, leftCommand
  case rightControl, rightShift, rightOption, rightCommand

  public var keyID: KeyID {
    switch self {
    case .leftControl: .leftControl
    case .leftShift: .leftShift
    case .leftOption: .leftAlt
    case .leftCommand: .leftGUI
    case .rightControl: .rightControl
    case .rightShift: .rightShift
    case .rightOption: .rightAlt
    case .rightCommand: .rightGUI
    }
  }
}

public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public init(_ modifier: Modifier) {
    let index = Modifier.allCases.firstIndex(of: modifier)!
    self.init(rawValue: 1 << UInt8(index))
  }

  /// Members in `Modifier.allCases` order.
  public var members: [Modifier] {
    Modifier.allCases.filter { contains(Modifiers($0)) }
  }

  public init(from decoder: any Decoder) throws {
    let list = try decoder.singleValueContainer().decode([Modifier].self)
    self = list.reduce(into: []) { $0.insert(Modifiers($1)) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(members)
  }
}

public extension KeyID {
  var modifier: Modifier? {
    Modifier.allCases.first { $0.keyID == self }
  }
}
