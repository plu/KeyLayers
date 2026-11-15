import CoreGraphics
import KeymapModel

/// One key cap of a keyboard drawing.
public struct PhysicalKey: Equatable, Sendable {
  public enum Shape: Sendable {
    case rect
    /// The tall Return of ISO and JIS keyboards. `frame` is its bounding box (two rows tall); the
    /// lower part is right-aligned and `PhysicalKey.isoEnterNotch` narrower than the upper part.
    case isoEnter
  }

  /// How much narrower the lower part of an ISO/JIS Return is than its upper part, on every Apple
  /// keyboard (ISO 1u over 0.75u, JIS 1.5u over 1.25u).
  public static let isoEnterNotch: CGFloat = 0.25

  /// `nil` for decorative caps (Touch ID).
  public var keyID: KeyID?
  /// In key units: 1u is a standard key's width (and a row's height).
  public var frame: CGRect
  public var shape: Shape

  public init(keyID: KeyID?, frame: CGRect, shape: Shape = .rect) {
    self.keyID = keyID
    self.frame = frame
    self.shape = shape
  }
}

/// The drawing of one supported Apple keyboard.
public struct KeyboardGeometry: Equatable, Sendable {
  public var kind: KeyboardKind
  public var keys: [PhysicalKey]
  /// The bounding size of all keys, in key units.
  public var size: CGSize

  public init(kind: KeyboardKind, keys: [PhysicalKey]) {
    self.kind = kind
    self.keys = keys
    size = CGSize(
      width: keys.map(\.frame.maxX).max() ?? 0,
      height: keys.map(\.frame.maxY).max() ?? 0
    )
  }

  public static func make(_ kind: KeyboardKind) -> KeyboardGeometry {
    switch kind.model {
    case .compact: compact(kind.layout)
    case .extended: extended(kind.layout)
    }
  }
}

// MARK: - Row specs

// Measured from Apple's product images of the Magic Keyboard with Touch ID (with and without
// Numeric Keypad) in US, British and Japanese layouts; the MacBook Pro/Air keyboards share the
// compact geometry. Every row of the main block is 14.5u wide and 1u tall.

/// One slot of a row spec, laid out left to right.
enum Slot {
  case key(KeyID, CGFloat = 1)
  /// A cap without a key code (Touch ID).
  case decorative(CGFloat = 1)
  case gap(CGFloat)
  /// The ISO/JIS Return: `top` wide on this row, `top - isoEnterNotch` on the row below, which
  /// leaves that room free.
  case isoEnter(top: CGFloat)
  /// A key two rows tall (keypad Enter).
  case tall(KeyID)
  /// MacBook / Magic Keyboard arrows: full-height ← and →, half-height ↑ over ↓ between them.
  case invertedT
}

extension KeyboardGeometry {
  static let mainBlockWidth: CGFloat = 14.5
  /// The space between the main block, the navigation cluster and the keypad.
  static let blockGap: CGFloat = 0.15

  /// Lays out `rows` (row 0 at the top) starting at `x`.
  static func place(_ rows: [[Slot]], x originX: CGFloat = 0) -> [PhysicalKey] {
    var keys: [PhysicalKey] = []
    for (row, slots) in rows.enumerated() {
      let y = CGFloat(row)
      var x = originX
      for slot in slots {
        switch slot {
        case let .key(id, width):
          keys.append(PhysicalKey(keyID: id, frame: CGRect(x: x, y: y, width: width, height: 1)))
          x += width
        case let .decorative(width):
          keys.append(PhysicalKey(keyID: nil, frame: CGRect(x: x, y: y, width: width, height: 1)))
          x += width
        case let .gap(width):
          x += width
        case let .isoEnter(top):
          let frame = CGRect(x: x, y: y, width: top, height: 2)
          keys.append(PhysicalKey(keyID: .returnOrEnter, frame: frame, shape: .isoEnter))
          x += top
        case let .tall(id):
          keys.append(PhysicalKey(keyID: id, frame: CGRect(x: x, y: y, width: 1, height: 2)))
          x += 1
        case .invertedT:
          keys += [
            PhysicalKey(keyID: .leftArrow, frame: CGRect(x: x, y: y, width: 1, height: 1)),
            PhysicalKey(keyID: .upArrow, frame: CGRect(x: x + 1, y: y, width: 1, height: 0.5)),
            PhysicalKey(keyID: .downArrow, frame: CGRect(x: x + 1, y: y + 0.5, width: 1, height: 0.5)),
            PhysicalKey(keyID: .rightArrow, frame: CGRect(x: x + 2, y: y, width: 1, height: 1)),
          ]
          x += 3
        }
      }
    }
    return keys
  }

  static func keys(_ ids: [KeyID]) -> [Slot] {
    ids.map { .key($0) }
  }

  /// Rows 0–4 of the main block (function row to Shift row); only the bottom row differs between
  /// the compact and extended keyboards.
  static func upperMainRows(_ layout: PhysicalLayout) -> [[Slot]] {
    let functionRow: [Slot] = [.key(.escape, 1.5)]
      + keys([.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12])
      + [.decorative()]
    let digits = keys([
      .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9, .digit0, .hyphen, .equalSign,
    ])
    let qwerty = keys([.q, .w, .e, .r, .t, .y, .u, .i, .o, .p, .openBracket, .closeBracket])
    let home = keys([.a, .s, .d, .f, .g, .h, .j, .k, .l, .semicolon, .quote])
    let bottomLetters = keys([.z, .x, .c, .v, .b, .n, .m, .comma, .period, .slash])

    switch layout {
    case .ansi:
      return [
        functionRow,
        [.key(.graveAccentAndTilde), .key(.digit1)] + digits + [.key(.deleteOrBackspace, 1.5)],
        [.key(.tab, 1.5)] + qwerty + [.key(.backslash)],
        [.key(.capsLock, 1.75)] + home + [.key(.returnOrEnter, 1.75)],
        [.key(.leftShift, 2.25)] + bottomLetters + [.key(.rightShift, 2.25)],
      ]
    case .iso:
      return [
        functionRow,
        [.key(.nonUSBackslash), .key(.digit1)] + digits + [.key(.deleteOrBackspace, 1.5)],
        [.key(.tab, 1.5)] + qwerty + [.isoEnter(top: 1)],
        [.key(.capsLock, 1.75)] + home + [.key(.backslash)],
        [.key(.leftShift, 1.25), .key(.graveAccentAndTilde)] + bottomLetters + [.key(.rightShift, 2.25)],
      ]
    case .jis:
      // Apple JIS: no ` key; ^ is the = usage, ¥ is international3; @ [ sit on the [ ] usages,
      // : ] on the ' \ usages (as macOS reports them: kVK_ANSI_LeftBracket … kVK_ANSI_Backslash);
      // _ (ろ) is international1. Control takes the Caps Lock position.
      return [
        functionRow,
        [.key(.digit1, 1.25)] + digits + [.key(.international3), .key(.deleteOrBackspace, 1.25)],
        [.key(.tab)] + qwerty + [.isoEnter(top: 1.5)],
        [.key(.leftControl, 1.25)] + home + [.key(.backslash)],
        [.key(.leftShift, 1.75)] + bottomLetters + [.key(.international1), .key(.rightShift, 1.75)],
      ]
    }
  }
}
