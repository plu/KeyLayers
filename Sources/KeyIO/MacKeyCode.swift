import KeymapModel

/// Translates macOS virtual keycodes (Carbon `kVK_*`, HIToolbox Events.h) to and from HID usages.
///
/// Covers every `kVK_*` constant that has a HID keyboard-page (or Apple fn) equivalent. The volume
/// keys (`kVK_VolumeUp/Down`, `kVK_Mute`) are left out: they arrive as system-defined media events,
/// not as key codes.
public enum MacKeyCode {
  public static func keyID(for code: UInt16) -> KeyID? {
    keyIDByCode[code]
  }

  public static func code(for key: KeyID) -> UInt16? {
    codeByKeyID[key]
  }

  private static let table: [(code: UInt16, key: KeyID)] = [
    (0x00, .a), // kVK_ANSI_A
    (0x01, .s), // kVK_ANSI_S
    (0x02, .d), // kVK_ANSI_D
    (0x03, .f), // kVK_ANSI_F
    (0x04, .h), // kVK_ANSI_H
    (0x05, .g), // kVK_ANSI_G
    (0x06, .z), // kVK_ANSI_Z
    (0x07, .x), // kVK_ANSI_X
    (0x08, .c), // kVK_ANSI_C
    (0x09, .v), // kVK_ANSI_V
    (0x0A, .nonUSBackslash), // kVK_ISO_Section
    (0x0B, .b), // kVK_ANSI_B
    (0x0C, .q), // kVK_ANSI_Q
    (0x0D, .w), // kVK_ANSI_W
    (0x0E, .e), // kVK_ANSI_E
    (0x0F, .r), // kVK_ANSI_R
    (0x10, .y), // kVK_ANSI_Y
    (0x11, .t), // kVK_ANSI_T
    (0x12, .digit1), // kVK_ANSI_1
    (0x13, .digit2), // kVK_ANSI_2
    (0x14, .digit3), // kVK_ANSI_3
    (0x15, .digit4), // kVK_ANSI_4
    (0x16, .digit6), // kVK_ANSI_6
    (0x17, .digit5), // kVK_ANSI_5
    (0x18, .equalSign), // kVK_ANSI_Equal
    (0x19, .digit9), // kVK_ANSI_9
    (0x1A, .digit7), // kVK_ANSI_7
    (0x1B, .hyphen), // kVK_ANSI_Minus
    (0x1C, .digit8), // kVK_ANSI_8
    (0x1D, .digit0), // kVK_ANSI_0
    (0x1E, .closeBracket), // kVK_ANSI_RightBracket
    (0x1F, .o), // kVK_ANSI_O
    (0x20, .u), // kVK_ANSI_U
    (0x21, .openBracket), // kVK_ANSI_LeftBracket
    (0x22, .i), // kVK_ANSI_I
    (0x23, .p), // kVK_ANSI_P
    (0x24, .returnOrEnter), // kVK_Return
    (0x25, .l), // kVK_ANSI_L
    (0x26, .j), // kVK_ANSI_J
    (0x27, .quote), // kVK_ANSI_Quote
    (0x28, .k), // kVK_ANSI_K
    (0x29, .semicolon), // kVK_ANSI_Semicolon
    (0x2A, .backslash), // kVK_ANSI_Backslash
    (0x2B, .comma), // kVK_ANSI_Comma
    (0x2C, .slash), // kVK_ANSI_Slash
    (0x2D, .n), // kVK_ANSI_N
    (0x2E, .m), // kVK_ANSI_M
    (0x2F, .period), // kVK_ANSI_Period
    (0x30, .tab), // kVK_Tab
    (0x31, .spacebar), // kVK_Space
    (0x32, .graveAccentAndTilde), // kVK_ANSI_Grave
    (0x33, .deleteOrBackspace), // kVK_Delete
    (0x35, .escape), // kVK_Escape
    (0x36, .rightGUI), // kVK_RightCommand
    (0x37, .leftGUI), // kVK_Command
    (0x38, .leftShift), // kVK_Shift
    (0x39, .capsLock), // kVK_CapsLock
    (0x3A, .leftAlt), // kVK_Option
    (0x3B, .leftControl), // kVK_Control
    (0x3C, .rightShift), // kVK_RightShift
    (0x3D, .rightAlt), // kVK_RightOption
    (0x3E, .rightControl), // kVK_RightControl
    (0x3F, .fn), // kVK_Function
    (0x40, .f17), // kVK_F17
    (0x41, .keypadPeriod), // kVK_ANSI_KeypadDecimal
    (0x43, .keypadAsterisk), // kVK_ANSI_KeypadMultiply
    (0x45, .keypadPlus), // kVK_ANSI_KeypadPlus
    (0x47, .keypadNumLock), // kVK_ANSI_KeypadClear (HID "Keypad Num Lock and Clear")
    (0x4B, .keypadSlash), // kVK_ANSI_KeypadDivide
    (0x4C, .keypadEnter), // kVK_ANSI_KeypadEnter
    (0x4E, .keypadHyphen), // kVK_ANSI_KeypadMinus
    (0x4F, .f18), // kVK_F18
    (0x50, .f19), // kVK_F19
    (0x51, .keypadEqualSign), // kVK_ANSI_KeypadEquals
    (0x52, .keypad0), // kVK_ANSI_Keypad0
    (0x53, .keypad1), // kVK_ANSI_Keypad1
    (0x54, .keypad2), // kVK_ANSI_Keypad2
    (0x55, .keypad3), // kVK_ANSI_Keypad3
    (0x56, .keypad4), // kVK_ANSI_Keypad4
    (0x57, .keypad5), // kVK_ANSI_Keypad5
    (0x58, .keypad6), // kVK_ANSI_Keypad6
    (0x59, .keypad7), // kVK_ANSI_Keypad7
    (0x5A, .f20), // kVK_F20
    (0x5B, .keypad8), // kVK_ANSI_Keypad8
    (0x5C, .keypad9), // kVK_ANSI_Keypad9
    (0x5D, .international3), // kVK_JIS_Yen
    (0x5E, .international1), // kVK_JIS_Underscore
    (0x5F, .keypadComma), // kVK_JIS_KeypadComma
    (0x60, .f5), // kVK_F5
    (0x61, .f6), // kVK_F6
    (0x62, .f7), // kVK_F7
    (0x63, .f3), // kVK_F3
    (0x64, .f8), // kVK_F8
    (0x65, .f9), // kVK_F9
    (0x66, .lang2), // kVK_JIS_Eisu
    (0x67, .f11), // kVK_F11
    (0x68, .lang1), // kVK_JIS_Kana
    (0x69, .f13), // kVK_F13
    (0x6A, .f16), // kVK_F16
    (0x6B, .f14), // kVK_F14
    (0x6D, .f10), // kVK_F10
    (0x6E, .application), // kVK_ContextualMenu
    (0x6F, .f12), // kVK_F12
    (0x71, .f15), // kVK_F15
    (0x72, .insert), // kVK_Help (the Insert position on Apple extended keyboards)
    (0x73, .home), // kVK_Home
    (0x74, .pageUp), // kVK_PageUp
    (0x75, .deleteForward), // kVK_ForwardDelete
    (0x76, .f4), // kVK_F4
    (0x77, .end), // kVK_End
    (0x78, .f2), // kVK_F2
    (0x79, .pageDown), // kVK_PageDown
    (0x7A, .f1), // kVK_F1
    (0x7B, .leftArrow), // kVK_LeftArrow
    (0x7C, .rightArrow), // kVK_RightArrow
    (0x7D, .downArrow), // kVK_DownArrow
    (0x7E, .upArrow), // kVK_UpArrow
  ]

  private static let keyIDByCode: [UInt16: KeyID] = Dictionary(uniqueKeysWithValues: table.map { ($0.code, $0.key) })
  private static let codeByKeyID: [KeyID: UInt16] = Dictionary(uniqueKeysWithValues: table.map { ($0.key, $0.code) })
}
