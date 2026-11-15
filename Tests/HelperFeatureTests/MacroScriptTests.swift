@testable import HelperFeature
import KeyboardLayout
import KeyIO
import KeymapModel
import RemapEngine
import Testing

private func ev(_ key: KeyID, _ isDown: Bool, _ modifiers: Modifiers = []) -> MacroAction {
  .event(OutputEvent(key: key, isDown: isDown, modifiers: modifiers))
}

private let shift = Modifiers(.leftShift)

private func actions(_ step: MacroStep, table: [Character: [TextStroke]] = [:]) -> [MacroAction] {
  MacroScript.actions(for: step) { table[$0] }
}

struct MacroScriptTests {
  @Test func tapWithKeyCarriesModifiersAsExtras() {
    let step = MacroStep.key(KeyStep(key: .a, modifiers: shift, kind: .tap))
    #expect(actions(step) == [ev(.a, true, shift), ev(.a, false, shift)])
  }

  @Test func pressAndReleaseWithKey() {
    #expect(actions(.key(KeyStep(key: .a, modifiers: shift, kind: .press))) == [ev(.a, true, shift)])
    #expect(actions(.key(KeyStep(key: .a, modifiers: shift, kind: .release))) == [ev(.a, false, shift)])
  }

  @Test func modifierOnlyTapReleasesInReverse() {
    let mods: Modifiers = [Modifiers(.leftCommand), Modifiers(.leftShift)]
    let step = MacroStep.key(KeyStep(key: nil, modifiers: mods, kind: .tap))
    #expect(actions(step) == [
      ev(.leftShift, true), ev(.leftGUI, true), ev(.leftGUI, false), ev(.leftShift, false),
    ])
  }

  @Test func modifierKeyActsAsModifierOnly() {
    let step = MacroStep.key(KeyStep(key: .leftAlt, modifiers: shift, kind: .tap))
    #expect(actions(step) == [
      ev(.leftShift, true), ev(.leftAlt, true), ev(.leftAlt, false), ev(.leftShift, false),
    ])
  }

  @Test func textTapsEachCharacterAndSkipsUnknown() {
    let table: [Character: [TextStroke]] = [
      "h": [TextStroke(key: .h, modifiers: [])],
      "i": [TextStroke(key: .i, modifiers: [])],
      "\n": [TextStroke(key: .returnOrEnter, modifiers: [])],
    ]
    #expect(actions(.text("hi\n☕"), table: table) == [
      ev(.h, true), ev(.h, false), ev(.i, true), ev(.i, false), ev(.returnOrEnter, true), ev(.returnOrEnter, false),
    ])
  }

  @Test func deadKeyCharacterTypesTwoStrokes() {
    let table: [Character: [TextStroke]] = [
      "é": [TextStroke(key: .e, modifiers: Modifiers(.leftOption)), TextStroke(key: .e, modifiers: [])],
    ]
    #expect(actions(.text("é"), table: table) == [
      ev(.e, true, Modifiers(.leftOption)), ev(.e, false, Modifiers(.leftOption)),
      ev(.e, true), ev(.e, false),
    ])
  }

  @Test func delayIsClamped() {
    #expect(actions(.delay(milliseconds: 50)) == [.wait(.milliseconds(50))])
    #expect(actions(.delay(milliseconds: -5)) == [.wait(.zero)])
    #expect(actions(.delay(milliseconds: 100_000)) == [.wait(.milliseconds(60000))])
  }

  @Test func unsupportedIsEmpty() {
    #expect(actions(.unsupported(type: "x")).isEmpty)
  }

  @Test func onlyNonEmptyTextTypesText() {
    #expect(MacroScript.typesText(.text("a")))
    #expect(!MacroScript.typesText(.text("")))
    #expect(!MacroScript.typesText(.delay(milliseconds: 1)))
  }
}
