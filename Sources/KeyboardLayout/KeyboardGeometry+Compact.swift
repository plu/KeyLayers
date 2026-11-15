import CoreGraphics

extension KeyboardGeometry {
  /// MacBook (2021 and later) built-in keyboard and Magic Keyboard with Touch ID.
  static func compact(_ layout: PhysicalLayout) -> KeyboardGeometry {
    let bottomRow: [Slot] = switch layout {
    case .ansi, .iso:
      [
        .key(.fn), .key(.leftControl), .key(.leftAlt), .key(.leftGUI, 1.25), .key(.spacebar, 5),
        .key(.rightGUI, 1.25), .key(.rightAlt), .invertedT,
      ]
    case .jis:
      [
        .key(.capsLock), .key(.leftAlt), .key(.leftGUI, 1.25), .key(.lang2, 1.25), .key(.spacebar, 3.5),
        .key(.lang1, 1.25), .key(.rightGUI, 1.25), .key(.fn), .invertedT,
      ]
    }
    return KeyboardGeometry(
      kind: KeyboardKind(model: .compact, layout: layout),
      keys: place(upperMainRows(layout) + [bottomRow])
    )
  }
}
