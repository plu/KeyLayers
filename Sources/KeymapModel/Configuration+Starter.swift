import Foundation

public extension Configuration {
  /// fn holds the Mod layer; Mod gives vim-style navigation, fn's own Forward Delete/Home/End/Page Up/
  /// Page Down combos and the Mac media functions on F1…F12.
  static let starter: Configuration = {
    // Vim arrows on H/J/K/L, and directly above them Home, Page Down, Page Up, End.
    let navigation: [KeyID: KeyID] = [
      .h: .leftArrow, .j: .downArrow, .k: .upArrow, .l: .rightArrow,
      .y: .home, .u: .pageDown, .i: .pageUp, .o: .end,
    ]
    // fn's own macOS combos, which fn as the Mod key would otherwise take away.
    let fnCombos: [KeyID: KeyID] = [
      .deleteOrBackspace: .deleteForward,
      .leftArrow: .home, .rightArrow: .end, .upArrow: .pageUp, .downArrow: .pageDown,
    ]
    let fRow: [KeyID] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
    var modActions: [KeyID: KeyAction] = navigation.merging(fnCombos) { $1 }
      .mapValues { .keypress(Keypress(key: $0, modifiers: [])) }
    for (key, media) in zip(fRow, KeyID.mediaKeys) {
      modActions[key] = .keypress(Keypress(key: media, modifiers: []))
    }
    let keymap = Keymap(
      id: Keymap.starterID,
      name: "Default",
      abbreviation: "DEF",
      layers: [
        .base: Layer(actions: [
          .fn: .switchLayer(.mod, mode: .hold),
        ]),
        .mod: Layer(actions: modActions),
      ]
    )
    return Configuration(keymaps: [keymap], defaultKeymapID: Keymap.starterID)
  }()
}
