import Foundation

public struct Layer: Equatable, Sendable, Codable {
  public var actions: [KeyID: KeyAction]

  public init(actions: [KeyID: KeyAction] = [:]) {
    self.actions = actions
  }

  public init(from decoder: any Decoder) throws {
    actions = try decoder.singleValueContainer().decode([KeyID: KeyAction].self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(actions)
  }
}
