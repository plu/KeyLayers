import Foundation

public struct Keymap: Equatable, Identifiable, Sendable, Codable {
  public typealias ID = UUID // swiftlint:disable:this type_name

  public var id: ID
  public var name: String
  public var abbreviation: String
  public var layers: [LayerName: Layer]

  public init(id: ID, name: String, abbreviation: String, layers: [LayerName: Layer] = [:]) {
    self.id = id
    self.name = name
    self.abbreviation = abbreviation
    self.layers = layers
  }

  public static let starterID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

  /// The action bound to `key` on exactly `layer`; no fallthrough to other layers.
  public func action(for key: KeyID, on layer: LayerName) -> KeyAction? {
    layers[layer]?.actions[key]
  }

  /// Sets or (with `nil`) removes an action. Layers left empty are removed.
  public mutating func setAction(_ action: KeyAction?, for key: KeyID, on layer: LayerName) {
    var current = layers[layer] ?? Layer()
    current.actions[key] = action
    layers[layer] = current.actions.isEmpty ? nil : current
  }

  public static func normalizedAbbreviation(_ string: String) -> String {
    String(string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(3))
  }
}
