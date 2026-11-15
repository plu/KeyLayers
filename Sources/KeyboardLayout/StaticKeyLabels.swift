import KeymapModel

/// Key cap labels that don't depend on the input source.
public enum StaticKeyLabels {
  /// The symbol for a non-printing key (modifiers, editing and navigation keys, F-keys), or `nil`
  /// for keys whose label comes from the input source. Right-hand modifiers are prefixed "R".
  public static func label(for key: KeyID) -> String? {
    symbols[key]
  }

  /// The static labels plus the US English labels of the printing keys; used by tests and the
  /// UI-test mode, where the input source must not matter.
  public static let usANSI: [KeyID: String] = symbols.merging(usPrintable) { symbol, _ in symbol }

  private static let functionKeys: [KeyID] = [
    .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12,
    .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20, .f21, .f22, .f23, .f24,
  ]

  private static let symbols: [KeyID: String] = {
    var symbols: [KeyID: String] = [
      .escape: "⎋",
      .tab: "⇥",
      .capsLock: "⇪",
      .leftShift: "⇧",
      .rightShift: "R⇧",
      .leftControl: "⌃",
      .rightControl: "R⌃",
      .leftAlt: "⌥",
      .rightAlt: "R⌥",
      .leftGUI: "⌘",
      .rightGUI: "R⌘",
      .returnOrEnter: "⏎",
      .deleteOrBackspace: "⌫",
      .deleteForward: "⌦",
      .spacebar: "space",
      .leftArrow: "←",
      .rightArrow: "→",
      .upArrow: "↑",
      .downArrow: "↓",
      .home: "↖",
      .end: "↘",
      .pageUp: "⇞",
      .pageDown: "⇟",
      .fn: "fn",
      .keypadEnter: "⌤",
      .keypadNumLock: "⌧",
      .application: "☰",
      .insert: "help",
      .lang1: "かな",
      .lang2: "英数",
    ]
    for (index, key) in functionKeys.enumerated() {
      symbols[key] = "F\(index + 1)"
    }
    let mediaLabels = ["🔅", "🔆", "⊞", "🔍", "🎤", "🌙", "⏮", "⏯", "⏭", "🔇", "🔉", "🔊"]
    for (key, label) in zip(KeyID.mediaKeys, mediaLabels) {
      symbols[key] = label
    }
    return symbols
  }()

  private static let usPrintable: [KeyID: String] = {
    var labels: [KeyID: String] = [
      .graveAccentAndTilde: "`", .hyphen: "-", .equalSign: "=", .openBracket: "[", .closeBracket: "]",
      .backslash: "\\", .semicolon: ";", .quote: "'", .comma: ",", .period: ".", .slash: "/",
      .nonUSBackslash: "§", .international1: "_", .international3: "¥",
      .keypadEqualSign: "=", .keypadSlash: "/", .keypadAsterisk: "*", .keypadHyphen: "-",
      .keypadPlus: "+", .keypadPeriod: ".", .keypadComma: ",",
    ]
    let letters: [KeyID] = [
      .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z,
    ]
    for (key, letter) in zip(letters, "ABCDEFGHIJKLMNOPQRSTUVWXYZ") {
      labels[key] = String(letter)
    }
    let digits: [KeyID] = [.digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9, .digit0]
    let keypadDigits: [KeyID] = [
      .keypad1, .keypad2, .keypad3, .keypad4, .keypad5, .keypad6, .keypad7, .keypad8, .keypad9, .keypad0,
    ]
    for (index, digit) in "1234567890".enumerated() {
      labels[digits[index]] = String(digit)
      labels[keypadDigits[index]] = String(digit)
    }
    return labels
  }()
}
