import CoreGraphics

extension KeyboardGeometry {
  /// Magic Keyboard with Touch ID and Numeric Keypad: the compact main block with a wider bottom
  /// row, plus F13–F19, the navigation cluster, full-size arrows and the keypad.
  static func extended(_ layout: PhysicalLayout) -> KeyboardGeometry {
    let bottomRow: [Slot] = switch layout {
    case .ansi, .iso:
      [
        .key(.fn), .key(.leftControl), .key(.leftAlt), .key(.leftGUI, 1.25), .key(.spacebar, 6),
        .key(.rightGUI, 1.5), .key(.rightAlt, 1.25), .key(.rightControl, 1.5),
      ]
    case .jis:
      [
        .key(.capsLock), .key(.leftAlt), .key(.leftGUI, 1.25), .key(.lang2, 1.25), .key(.spacebar, 3.5),
        .key(.lang1, 1.25), .key(.rightGUI, 1.25), .key(.rightAlt, 1.5), .key(.rightControl, 1.5), .key(.fn),
      ]
    }
    let navigationX = mainBlockWidth + blockGap
    let keypadX = navigationX + 3 + blockGap
    return KeyboardGeometry(
      kind: KeyboardKind(model: .extended, layout: layout),
      keys: place(upperMainRows(layout) + [bottomRow])
        + place(navigationRows, x: navigationX)
        + place(keypadRows(layout), x: keypadX)
    )
  }

  /// The top-left key is the Contextual Menu key (HID Application).
  static let navigationRows: [[Slot]] = [
    keys([.f13, .f14, .f15]),
    keys([.application, .home, .pageUp]),
    keys([.deleteForward, .end, .pageDown]),
    [],
    [.gap(1), .key(.upArrow)],
    keys([.leftArrow, .downArrow, .rightArrow]),
  ]

  static func keypadRows(_ layout: PhysicalLayout) -> [[Slot]] {
    let bottomRow: [Slot] = layout == .jis
      ? keys([.keypad0, .keypadComma, .keypadPeriod])
      : [.key(.keypad0, 2), .key(.keypadPeriod)]
    return [
      keys([.f16, .f17, .f18, .f19]),
      keys([.keypadNumLock, .keypadEqualSign, .keypadSlash, .keypadAsterisk]),
      keys([.keypad7, .keypad8, .keypad9, .keypadHyphen]),
      keys([.keypad4, .keypad5, .keypad6, .keypadPlus]),
      keys([.keypad1, .keypad2, .keypad3]) + [.tall(.keypadEnter)],
      bottomRow,
    ]
  }
}
