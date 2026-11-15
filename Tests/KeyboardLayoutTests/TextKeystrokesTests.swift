import Carbon
@testable import KeyboardLayout
import KeymapModel
import Testing

struct TextKeystrokesTests {
  private static func table(_ inputSourceID: String) throws -> TextKeystrokes {
    let data = try #require(KeyboardLayoutData.layoutData(inputSourceID: inputSourceID))
    return TextKeystrokes(layoutData: data, keyboardType: UInt32(LMGetKbdType()))
  }

  @Test func usLayout() throws {
    let us = try Self.table("com.apple.keylayout.US")
    #expect(us.strokes(for: "a") == [TextStroke(key: .a, modifiers: [])])
    #expect(us.strokes(for: "A") == [TextStroke(key: .a, modifiers: [Modifiers(.leftShift)])])
    #expect(us.strokes(for: "@") == [TextStroke(key: .digit2, modifiers: [Modifiers(.leftShift)])])
    let acuteE = [TextStroke(key: .e, modifiers: [Modifiers(.leftOption)]), TextStroke(key: .e, modifiers: [])]
    #expect(us.strokes(for: "é") == acuteE)
    #expect(us.strokes(for: "\n") == [TextStroke(key: .returnOrEnter, modifiers: [])])
    #expect(us.strokes(for: "\r\n") == [TextStroke(key: .returnOrEnter, modifiers: [])])
    #expect(us.strokes(for: "\t") == [TextStroke(key: .tab, modifiers: [])])
    #expect(us.strokes(for: "☕") == nil)
  }

  @Test func germanLayout() throws {
    let german = try Self.table("com.apple.keylayout.German")
    #expect(german.strokes(for: "z") == [TextStroke(key: .y, modifiers: [])])
    #expect(german.strokes(for: "ö") == [TextStroke(key: .semicolon, modifiers: [])])
    #expect(german.strokes(for: "@") == [TextStroke(key: .l, modifiers: [Modifiers(.leftOption)])])
  }
}
