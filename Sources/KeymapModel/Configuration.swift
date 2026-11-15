import Foundation
import IdentifiedCollections

public enum ConfigurationError: Error, Equatable, Sendable {
  case newerFormat(Int)
}

public struct Settings: Equatable, Sendable, Codable {
  public var doubleTapTimeoutMilliseconds: Int
  public var showLayerHUD: Bool
  /// Show the active keymap's abbreviation next to the menu bar icon.
  public var menuBarShowsKeymap: Bool
  /// Show the active layer next to the menu bar icon.
  public var menuBarShowsLayer: Bool

  public init(
    doubleTapTimeoutMilliseconds: Int = 250,
    showLayerHUD: Bool = true,
    menuBarShowsKeymap: Bool = false,
    menuBarShowsLayer: Bool = false
  ) {
    self.doubleTapTimeoutMilliseconds = doubleTapTimeoutMilliseconds
    self.showLayerHUD = showLayerHUD
    self.menuBarShowsKeymap = menuBarShowsKeymap
    self.menuBarShowsLayer = menuBarShowsLayer
  }

  private enum CodingKeys: String, CodingKey {
    case doubleTapTimeoutMilliseconds, showLayerHUD, menuBarShowsKeymap, menuBarShowsLayer
  }

  /// Missing keys (files written before a setting existed) take the defaults.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Settings()
    doubleTapTimeoutMilliseconds = try c.decodeIfPresent(Int.self, forKey: .doubleTapTimeoutMilliseconds)
      ?? defaults.doubleTapTimeoutMilliseconds
    showLayerHUD = try c.decodeIfPresent(Bool.self, forKey: .showLayerHUD) ?? defaults.showLayerHUD
    menuBarShowsKeymap = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowsKeymap) ?? defaults.menuBarShowsKeymap
    menuBarShowsLayer = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowsLayer) ?? defaults.menuBarShowsLayer
  }
}

public struct Configuration: Equatable, Sendable, Codable {
  public static let currentFormatVersion = 1

  public var formatVersion: Int
  public var settings: Settings
  public var keymaps: IdentifiedArrayOf<Keymap>
  public var defaultKeymapID: Keymap.ID

  public init(
    formatVersion: Int = Configuration.currentFormatVersion,
    settings: Settings = Settings(),
    keymaps: IdentifiedArrayOf<Keymap>,
    defaultKeymapID: Keymap.ID
  ) {
    self.formatVersion = formatVersion
    self.settings = settings
    self.keymaps = keymaps
    self.defaultKeymapID = defaultKeymapID
  }

  /// The default keymap, or the first keymap if the default ID is dangling.
  /// Precondition: `keymaps` is not empty.
  public var defaultKeymap: Keymap {
    keymaps[id: defaultKeymapID] ?? keymaps[0]
  }

  public static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  public static let decoder = JSONDecoder()

  private enum CodingKeys: String, CodingKey {
    case formatVersion, settings, keymaps, defaultKeymapID
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let version = try c.decode(Int.self, forKey: .formatVersion)
    guard version <= Configuration.currentFormatVersion else {
      throw ConfigurationError.newerFormat(version)
    }
    formatVersion = version
    settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
    let list = try c.decode([Keymap].self, forKey: .keymaps)
    guard !list.isEmpty else {
      throw DecodingError.dataCorruptedError(forKey: .keymaps, in: c, debugDescription: "No keymaps")
    }
    guard Set(list.map(\.id)).count == list.count else {
      throw DecodingError.dataCorruptedError(forKey: .keymaps, in: c, debugDescription: "Duplicate keymap IDs")
    }
    keymaps = IdentifiedArray(uniqueElements: list)
    defaultKeymapID = try c.decode(Keymap.ID.self, forKey: .defaultKeymapID)
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(formatVersion, forKey: .formatVersion)
    try c.encode(settings, forKey: .settings)
    try c.encode(Array(keymaps), forKey: .keymaps)
    try c.encode(defaultKeymapID, forKey: .defaultKeymapID)
  }
}
