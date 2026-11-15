import KeymapModel

/// English names of the keys whose cap label alone is ambiguous or hard to search for (symbols,
/// keypad keys, modifiers). Shown next to the label in the key picker and matched by its search.
enum KeyNames {
  static func name(for key: KeyID) -> String? {
    names[key]
  }

  private static let names: [KeyID: String] = {
    var names: [KeyID: String] = [
      .returnOrEnter: "Return", .escape: "Escape", .deleteOrBackspace: "Delete", .tab: "Tab",
      .spacebar: "Space", .hyphen: "Minus", .equalSign: "Equals", .openBracket: "Left Bracket",
      .closeBracket: "Right Bracket", .backslash: "Backslash", .nonUSPound: "Non-US #",
      .semicolon: "Semicolon", .quote: "Quote", .graveAccentAndTilde: "Grave Accent", .comma: "Comma",
      .period: "Period", .slash: "Slash", .capsLock: "Caps Lock", .printScreen: "Print Screen",
      .scrollLock: "Scroll Lock", .pause: "Pause", .insert: "Help / Insert", .home: "Home",
      .pageUp: "Page Up", .deleteForward: "Forward Delete", .end: "End", .pageDown: "Page Down",
      .rightArrow: "Right Arrow", .leftArrow: "Left Arrow", .downArrow: "Down Arrow", .upArrow: "Up Arrow",
      .keypadNumLock: "Keypad Clear", .keypadSlash: "Keypad Divide", .keypadAsterisk: "Keypad Multiply",
      .keypadHyphen: "Keypad Minus", .keypadPlus: "Keypad Plus", .keypadEnter: "Keypad Enter",
      .keypadPeriod: "Keypad Decimal", .keypadEqualSign: "Keypad Equals", .keypadComma: "Keypad Comma",
      .nonUSBackslash: "Section (ISO)", .application: "Contextual Menu", .power: "Power",
      .international1: "Underscore (JIS)", .international2: "Kana / Hiragana", .international3: "Yen (JIS)",
      .international4: "Henkan", .international5: "Muhenkan", .lang1: "Kana", .lang2: "Eisu",
      .leftControl: "Left Control", .leftShift: "Left Shift", .leftAlt: "Left Option",
      .leftGUI: "Left Command", .rightControl: "Right Control", .rightShift: "Right Shift",
      .rightAlt: "Right Option", .rightGUI: "Right Command", .fn: "Fn / Globe",
    ]
    let keypadDigits: [KeyID] = [
      .keypad1, .keypad2, .keypad3, .keypad4, .keypad5, .keypad6, .keypad7, .keypad8, .keypad9, .keypad0,
    ]
    for (index, digit) in "1234567890".enumerated() {
      names[keypadDigits[index]] = "Keypad \(digit)"
    }
    let mediaNames = [
      "Brightness Down", "Brightness Up", "Mission Control", "Spotlight", "Dictation", "Do Not Disturb",
      "Previous Track", "Play/Pause", "Next Track", "Mute", "Volume Down", "Volume Up",
    ]
    for (key, name) in zip(KeyID.mediaKeys, mediaNames) {
      names[key] = name
    }
    return names
  }()
}
