import Foundation

public struct KeyStep: Equatable, Hashable, Sendable {
  public enum Kind: String, Codable, Sendable { case tap, press, release }

  public var key: KeyID?
  public var modifiers: Modifiers
  public var kind: Kind

  public init(key: KeyID?, modifiers: Modifiers, kind: Kind) {
    self.key = key
    self.modifiers = modifiers
    self.kind = kind
  }
}

public enum MacroStep: Equatable, Hashable, Sendable, Codable {
  case key(KeyStep)
  case text(String)
  case delay(milliseconds: Int)
  /// A step type this version does not understand; preserved as `{"type": ...}`.
  case unsupported(type: String)

  private enum CodingKeys: String, CodingKey {
    case type, key, modifiers, kind, text, milliseconds
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let type = try c.decode(String.self, forKey: .type)
    switch type {
    case "key":
      self = try .key(KeyStep(
        key: c.decodeIfPresent(KeyID.self, forKey: .key),
        modifiers: c.decodeIfPresent(Modifiers.self, forKey: .modifiers) ?? [],
        kind: c.decode(KeyStep.Kind.self, forKey: .kind)
      ))
    case "text":
      self = try .text(c.decode(String.self, forKey: .text))
    case "delay":
      self = try .delay(milliseconds: c.decode(Int.self, forKey: .milliseconds))
    default:
      self = .unsupported(type: type)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .key(step):
      try c.encode("key", forKey: .type)
      try c.encodeIfPresent(step.key, forKey: .key)
      try c.encode(step.modifiers, forKey: .modifiers)
      try c.encode(step.kind, forKey: .kind)
    case let .text(text):
      try c.encode("text", forKey: .type)
      try c.encode(text, forKey: .text)
    case let .delay(milliseconds):
      try c.encode("delay", forKey: .type)
      try c.encode(milliseconds, forKey: .milliseconds)
    case let .unsupported(type):
      try c.encode(type, forKey: .type)
    }
  }
}

public struct Macro: Identifiable, Equatable, Hashable, Sendable, Codable {
  public typealias ID = UUID // swiftlint:disable:this type_name

  public var id: ID
  public var name: String
  public var steps: [MacroStep]

  public init(id: ID, name: String, steps: [MacroStep]) {
    self.id = id
    self.name = name
    self.steps = steps
  }
}
