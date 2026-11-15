import CoreGraphics
import KeyboardLayout
import KeyIO
import KeymapModel
import Testing

struct GeometryTests {
  @Test(arguments: KeyboardKind.all) func geometryInvariants(kind: KeyboardKind) {
    let g = KeyboardGeometry.make(kind)
    #expect(!g.keys.isEmpty)
    let ids = g.keys.compactMap(\.keyID)
    #expect(Set(ids).count == ids.count)
    for (i, a) in g.keys.enumerated() {
      for b in g.keys[(i + 1)...] where a.shape == .rect && b.shape == .rect {
        #expect(
          !a.frame.insetBy(dx: 0.01, dy: 0.01).intersects(b.frame),
          "\(String(describing: a.keyID)) overlaps \(String(describing: b.keyID))"
        )
      }
    }
    #expect(g.keys.allSatisfy { CGRect(origin: .zero, size: g.size).contains($0.frame) })
    #expect(ids.allSatisfy { MacKeyCode.code(for: $0) != nil })
  }

  @Test(arguments: KeyboardKind.all) func mainBlockRowsAreGapless(kind: KeyboardKind) {
    // Every row of an Apple keyboard's main block is 14.5 keys wide with no holes.
    let g = KeyboardGeometry.make(kind)
    for row in 0 ..< 6 {
      let band = CGRect(x: 0, y: CGFloat(row) + 0.25, width: 14.5, height: 0.5)
      let spans = g.keys.filter { $0.frame.intersects(band) && $0.frame.minX < 14.5 }.map { key in
        let isLowerISOEnter = key.shape == .isoEnter && row == Int(key.frame.maxY) - 1
        return (key.frame.minX + (isLowerISOEnter ? PhysicalKey.isoEnterNotch : 0), key.frame.maxX)
      }.sorted { $0.0 < $1.0 }
      var x: CGFloat = 0
      for (minX, maxX) in spans where maxX > x {
        #expect(abs(minX - x) < 0.001, "hole or overlap at \(x) in row \(row) of \(kind.displayName)")
        x = maxX
      }
      #expect(abs(x - 14.5) < 0.001, "row \(row) of \(kind.displayName) ends at \(x)")
    }
  }

  @Test func compactANSIKeyCount() {
    #expect(KeyboardGeometry.make(.init(model: .compact, layout: .ansi)).keys.compactMap(\.keyID).count == 77)
  }

  @Test func compactISOAddsOneKey() {
    #expect(KeyboardGeometry.make(.init(model: .compact, layout: .iso)).keys.compactMap(\.keyID).count == 78)
  }

  @Test func compactHasDecorativeTouchID() {
    let g = KeyboardGeometry.make(.fallback)
    let touchID = g.keys.filter { $0.keyID == nil }
    #expect(touchID.count == 1)
    #expect(touchID.first?.frame == CGRect(x: 13.5, y: 0, width: 1, height: 1))
    #expect(g.size == CGSize(width: 14.5, height: 6))
  }

  @Test func compactArrowsAreAnInvertedT() throws {
    let g = KeyboardGeometry.make(.fallback)
    let up = try #require(g.key(.upArrow))
    let down = try #require(g.key(.downArrow))
    let left = try #require(g.key(.leftArrow))
    let right = try #require(g.key(.rightArrow))
    #expect(up.frame == CGRect(x: 12.5, y: 5, width: 1, height: 0.5))
    #expect(down.frame == CGRect(x: 12.5, y: 5.5, width: 1, height: 0.5))
    #expect(left.frame == CGRect(x: 11.5, y: 5, width: 1, height: 1))
    #expect(right.frame == CGRect(x: 13.5, y: 5, width: 1, height: 1))
    #expect(g.key(.fn)?.frame.origin == CGPoint(x: 0, y: 5))
  }

  @Test func isoHasIsoEnterAndSectionKey() throws {
    let g = KeyboardGeometry.make(.init(model: .compact, layout: .iso))
    let enter = try #require(g.key(.returnOrEnter))
    #expect(enter.shape == .isoEnter)
    #expect(enter.frame == CGRect(x: 13.5, y: 2, width: 1, height: 2))
    let section = try #require(g.key(.nonUSBackslash))
    let one = try #require(g.key(.digit1))
    #expect(section.frame.maxX == one.frame.minX && section.frame.minY == one.frame.minY)
    let leftShift = try #require(g.key(.leftShift))
    let grave = try #require(g.key(.graveAccentAndTilde))
    #expect(grave.frame.minX == leftShift.frame.maxX && grave.frame.minY == leftShift.frame.minY)
    let backslash = try #require(g.key(.backslash))
    #expect(backslash.frame.minY == 3)
    #expect(backslash.frame.maxX == enter.frame.minX + PhysicalKey.isoEnterNotch)
    #expect(g.keys.filter { $0.shape == .isoEnter }.count == 1)
    #expect(KeyboardGeometry.make(.fallback).keys.allSatisfy { $0.shape == .rect })
  }

  @Test func jisFollowsApplesJapaneseLayout() throws {
    let g = KeyboardGeometry.make(.init(model: .compact, layout: .jis))
    #expect(g.keys.compactMap(\.keyID).count == 79) // ANSI + ¥ _ 英数 かな − ` R⌥
    let space = try #require(g.key(.spacebar))
    #expect(g.key(.lang2)?.frame.maxX == space.frame.minX)
    #expect(g.key(.lang1)?.frame.minX == space.frame.maxX)
    #expect(g.key(.international3)?.frame.maxX == g.key(.deleteOrBackspace)?.frame.minX)
    #expect(g.key(.international1)?.frame.minX == g.key(.slash)?.frame.maxX)
    #expect(g.key(.openBracket)?.frame.minX == g.key(.p)?.frame.maxX) // @
    #expect(g.key(.quote)?.frame.minX == g.key(.semicolon)?.frame.maxX) // :
    #expect(g.key(.leftControl)?.frame.origin == CGPoint(x: 0, y: 3))
    #expect(g.key(.capsLock)?.frame.origin == CGPoint(x: 0, y: 5))
    #expect(g.key(.graveAccentAndTilde) == nil)
    let enter = try #require(g.key(.returnOrEnter))
    #expect(enter.shape == .isoEnter)
    #expect(enter.frame == CGRect(x: 13, y: 2, width: 1.5, height: 2))
  }

  @Test func extendedContainsKeypadAndF19() {
    let g = KeyboardGeometry.make(.init(model: .extended, layout: .ansi))
    let ids = Set(g.keys.compactMap(\.keyID))
    let expected: [KeyID] = [
      .f13, .f14, .f15, .f16, .f17, .f18, .f19,
      .application, .home, .pageUp, .deleteForward, .end, .pageDown, .fn,
      .upArrow, .leftArrow, .downArrow, .rightArrow,
      .keypadNumLock, .keypadEqualSign, .keypadSlash, .keypadAsterisk,
      .keypad7, .keypad8, .keypad9, .keypadHyphen,
      .keypad4, .keypad5, .keypad6, .keypadPlus,
      .keypad1, .keypad2, .keypad3, .keypadEnter,
      .keypad0, .keypadPeriod, .rightControl,
    ]
    for key in expected {
      #expect(ids.contains(key), "missing \(key)")
    }
    #expect(g.keys.filter { $0.keyID != nil && $0.frame.minX >= 14.5 }.allSatisfy { $0.frame.height >= 1 })
    #expect(g.key(.keypadEnter)?.frame.height == 2)
    #expect(g.key(.keypad0)?.frame.width == 2)
    #expect(g.size.height == 6 && g.size.width > 21.5)
  }

  @Test func extendedJISHasKeypadComma() {
    let g = KeyboardGeometry.make(.init(model: .extended, layout: .jis))
    #expect(g.key(.keypadComma) != nil)
    #expect(g.key(.keypad0)?.frame.width == 1)
    #expect(KeyboardGeometry.make(.init(model: .extended, layout: .ansi)).key(.keypadComma) == nil)
  }

  @Test func allListsEveryKind() {
    #expect(KeyboardKind.all.count == 6)
    #expect(Set(KeyboardKind.all).count == 6)
    #expect(KeyboardKind.fallback == KeyboardKind(model: .compact, layout: .ansi))
  }
}

extension KeyboardGeometry {
  func key(_ id: KeyID) -> PhysicalKey? {
    keys.first { $0.keyID == id }
  }
}
