import ComposableArchitecture
import Foundation
import KeyboardLayout
import KeymapModel

/// What a key cap shows for one key on one layer.
public struct KeyCapContent: Equatable, Sendable {
  public enum Style: Sendable {
    /// An action on this layer.
    case normal
    /// No action on this layer: the key does what it does on Base.
    case inherited
    /// Blocked: the key does nothing.
    case blocked
    /// An action this version can't show or perform (or a Switch Keymap to a deleted keymap).
    case unsupported
    /// No action on Base: the key types what's printed on it.
    case unmapped
  }

  public var primary: String
  public var badge: String?
  public var style: Style
  /// What VoiceOver reads instead of `primary` (the key's name, where the label is a glyph).
  public var spokenPrimary: String?

  public init(primary: String, badge: String? = nil, style: Style, spokenPrimary: String? = nil) {
    self.spokenPrimary = spokenPrimary
    self.primary = primary
    self.badge = badge
    self.style = style
  }

  /// The cap of `key` on `layer`. A key without an action on an upper layer shows its Base cap,
  /// dimmed; without an action on Base it shows its own label (`labels`, from the input source).
  public static func make(
    key: KeyID,
    layer: LayerName,
    keymap: Keymap,
    keymaps: IdentifiedArrayOf<Keymap>,
    labels: [KeyID: String]
  ) -> KeyCapContent {
    if let action = keymap.action(for: key, on: layer) {
      return make(action, keymaps: keymaps, labels: labels)
    }
    guard layer == .base else {
      var content = make(key: key, layer: .base, keymap: keymap, keymaps: keymaps, labels: labels)
      content.style = .inherited
      return content
    }
    return KeyCapContent(
      primary: label(for: key, labels: labels), style: .unmapped,
      spokenPrimary: spokenName(for: key)
    )
  }

  /// What's printed on `key`: its input-source label, else its symbol, else its usage.
  static func label(for key: KeyID, labels: [KeyID: String]) -> String {
    if KeyID.mediaKeys.contains(key) {
      return StaticKeyLabels.label(for: key) ?? key.description
    }
    return labels[key] ?? StaticKeyLabels.label(for: key) ?? key.description
  }

  /// The name VoiceOver reads for a glyph-labelled (media) key; other keys are read from their cap.
  private static func spokenName(for key: KeyID) -> String? {
    KeyID.mediaKeys.contains(key) ? KeyNames.name(for: key) : nil
  }

  /// What VoiceOver reads for `key`. Non-printing keys (those with a static symbol, which the live labels
  /// also carry) and media keys are read by name (Escape, not "⎋"). Printing keys read the input source's
  /// label first (Ö, not "Semicolon", on German), then the key's name, then the static label.
  static func spokenLabel(for key: KeyID, labels: [KeyID: String]) -> String {
    let isNonPrinting = KeyID.mediaKeys.contains(key) || StaticKeyLabels.label(for: key) != nil
    if isNonPrinting, let name = KeyNames.name(for: key) {
      return name
    }
    if !KeyID.mediaKeys.contains(key), let label = labels[key] {
      return label
    }
    return KeyNames.name(for: key) ?? label(for: key, labels: labels)
  }

  /// The VoiceOver value of a cap: the primary text, then the badge.
  public var accessibilityValue: String {
    let text = spokenPrimary ?? primary
    return badge.map { "\(text) \($0)" } ?? text
  }

  private static func make(
    _ action: KeyAction,
    keymaps: IdentifiedArrayOf<Keymap>,
    labels: [KeyID: String]
  ) -> KeyCapContent {
    switch action {
    case let .keypress(press):
      let primary = symbols(press.modifiers) + (press.key.map { label(for: $0, labels: labels) } ?? "")
      let spoken = press.key.flatMap(spokenName).map { symbols(press.modifiers) + $0 }
      return KeyCapContent(
        primary: primary, badge: press.secondaryRole.map(badge), style: .normal, spokenPrimary: spoken
      )

    case let .switchLayer(layer, mode):
      return KeyCapContent(primary: layer.displayName, badge: badge(mode), style: .normal)

    case let .switchKeymap(id):
      guard let target = keymaps[id: id] else { return KeyCapContent(primary: "?", style: .unsupported) }
      return KeyCapContent(primary: target.abbreviation, badge: "keymap", style: .normal)

    case .block:
      return KeyCapContent(primary: "✕", style: .blocked)

    case .unsupported:
      return KeyCapContent(primary: "?", style: .unsupported)

    case .macro:
      // Showing the macro's name comes with the macro editor.
      return KeyCapContent(primary: "?", style: .unsupported)
    }
  }

  private static func badge(_ role: SecondaryRole) -> String {
    switch role {
    case let .layer(layer): layer.displayName
    case let .modifier(modifier): symbol(modifier)
    }
  }

  private static func badge(_ mode: LayerSwitchMode) -> String {
    switch mode {
    case .hold: "hold"
    case .toggle: "toggle"
    case .holdAndDoubleTapToggle: "2×lock"
    }
  }

  /// Mac order: Control, Option, Shift, Command; each left-hand before right-hand ("R⌘").
  private static let modifierOrder: [Modifier] = [
    .leftControl, .rightControl, .leftOption, .rightOption, .leftShift, .rightShift, .leftCommand, .rightCommand,
  ]

  private static func symbols(_ modifiers: Modifiers) -> String {
    modifierOrder.filter { modifiers.contains(Modifiers($0)) }.map(symbol).joined()
  }

  private static func symbol(_ modifier: Modifier) -> String {
    label(for: modifier.keyID, labels: [:])
  }
}
