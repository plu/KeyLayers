import ComposableArchitecture
@testable import ConfiguratorFeature
import Foundation
import KeyboardLayout
import KeymapModel
import Testing

private let starter = Configuration.starter.keymaps[0]

/// Caps Lock is Escape on tap and the Mod layer on hold (the starter keymap leaves it unmapped).
private let capsAsMod: Keymap = {
  var keymap = Keymap(id: UUID(), name: "Caps", abbreviation: "CAP")
  keymap.setAction(
    .keypress(Keypress(key: .escape, modifiers: [], secondaryRole: .layer(.mod))), for: .capsLock, on: .base
  )
  return keymap
}()

/// The cap of `key` on `layer` of `keymap` with `action` set there; `keymaps` also holds the starter.
private func cap(
  _ action: KeyAction?,
  key: KeyID = .a,
  layer: LayerName = .base,
  in keymap: Keymap = Keymap(id: UUID(), name: "Test", abbreviation: "TST"),
  macros: IdentifiedArrayOf<Macro> = [],
  labels: [KeyID: String] = StaticKeyLabels.usANSI
) -> KeyCapContent {
  var keymap = keymap
  if let action {
    keymap.setAction(action, for: key, on: layer)
  }
  return KeyCapContent.make(
    key: key,
    layer: layer,
    keymap: keymap,
    keymaps: IdentifiedArray([keymap, starter], uniquingIDsWith: { first, _ in first }),
    macros: macros,
    labels: labels
  )
}

struct KeyCapContentTests {
  @Test func shortcutCap() {
    let content = cap(.keypress(Keypress(key: .digit4, modifiers: [Modifiers(.leftCommand), Modifiers(.leftShift)])))
    #expect(content == KeyCapContent(primary: "⇧⌘4", badge: nil, style: .normal))
  }

  @Test func modifiersInMacOrderWithRightHandPrefix() {
    let modifiers: Modifiers = [
      Modifiers(.rightCommand), Modifiers(.leftShift), Modifiers(.rightOption), Modifiers(.leftControl),
    ]
    #expect(cap(.keypress(Keypress(key: .k, modifiers: modifiers))).primary == "⌃R⌥⇧R⌘K")
  }

  @Test func plainKeypressShowsOutputKeyLabel() {
    #expect(cap(.keypress(Keypress(key: .leftArrow, modifiers: []))) == KeyCapContent(
      primary: "←", badge: nil, style: .normal
    ))
  }

  @Test func secondaryRoleBadge() {
    let content = KeyCapContent.make(
      key: .capsLock, layer: .base, keymap: capsAsMod, keymaps: [capsAsMod], labels: StaticKeyLabels.usANSI
    )
    #expect(content == KeyCapContent(primary: "⎋", badge: "Mod", style: .normal))
  }

  @Test func modifierSecondaryRoleBadge() {
    let press = Keypress(key: .f, modifiers: [], secondaryRole: .modifier(.rightShift))
    #expect(cap(.keypress(press)) == KeyCapContent(primary: "F", badge: "R⇧", style: .normal))
  }

  @Test func layerCap() {
    #expect(cap(.switchLayer(.fn, mode: .holdAndDoubleTapToggle)) == KeyCapContent(
      primary: "Fn", badge: "2×lock", style: .normal
    ))
    #expect(cap(.switchLayer(.mouse, mode: .hold)) == KeyCapContent(primary: "Mouse", badge: "hold", style: .normal))
    #expect(cap(.switchLayer(.fn2, mode: .toggle)) == KeyCapContent(primary: "Fn2", badge: "toggle", style: .normal))
  }

  @Test func keymapCapShowsAbbreviation() {
    #expect(cap(.switchKeymap(Keymap.starterID)) == KeyCapContent(primary: "DEF", badge: "keymap", style: .normal))
  }

  @Test func danglingKeymapActionShowsUnsupported() {
    let content = cap(.switchKeymap(UUID()))
    #expect(content.primary == "?")
    #expect(content.style == .unsupported)
  }

  @Test func macroCapShowsName() {
    let macro = Macro(id: UUID(), name: "Sign off", steps: [])
    #expect(cap(.macro(macro.id), macros: [macro]) == KeyCapContent(
      primary: "Sign off", badge: "macro", style: .normal
    ))
  }

  @Test func danglingMacroActionShowsUnsupported() {
    let content = cap(.macro(UUID()))
    #expect(content.primary == "?")
    #expect(content.style == .unsupported)
  }

  @Test func blockAndUnsupportedCaps() {
    #expect(cap(.block) == KeyCapContent(primary: "✕", badge: nil, style: .blocked))
    #expect(cap(.unsupported(type: "playMacro")) == KeyCapContent(primary: "?", badge: nil, style: .unsupported))
  }

  @Test func inheritedCap() {
    let content = KeyCapContent.make(
      key: .capsLock, layer: .fn, keymap: capsAsMod, keymaps: [capsAsMod], labels: StaticKeyLabels.usANSI
    )
    #expect(content == KeyCapContent(primary: "⎋", badge: "Mod", style: .inherited))
  }

  @Test func inheritedUnmappedCapShowsPhysicalLabel() {
    #expect(cap(nil, key: .w, layer: .mod) == KeyCapContent(primary: "W", badge: nil, style: .inherited))
  }

  @Test func blockOnUpperLayerIsNotInherited() {
    #expect(cap(.block, key: .capsLock, layer: .mod, in: starter).style == .blocked)
  }

  @Test func unmappedBaseCapUsesLabel() {
    // AZERTY-ish: the A position types Q.
    let content = cap(nil, key: .a, labels: [.a: "Q"])
    #expect(content == KeyCapContent(primary: "Q", badge: nil, style: .unmapped))
  }

  @Test func missingLabelFallsBackToStaticSymbolThenKeyID() {
    #expect(cap(nil, key: .escape, labels: [:]).primary == "⎋")
    #expect(cap(nil, key: KeyID(page: 0xFF00, usage: 1), labels: [:]).primary == "65280:1")
  }

  @Test func accessibilityValueIsPrimaryThenBadge() {
    #expect(KeyCapContent(primary: "⎋", badge: "Mod", style: .normal).accessibilityValue == "⎋ Mod")
    #expect(KeyCapContent(primary: "W", style: .unmapped).accessibilityValue == "W")
  }

  @Test func mappedMediaCapIsSpokenByName() {
    let content = cap(.keypress(Keypress(key: KeyID.mediaKeys[0], modifiers: [])), key: .f1, layer: .mod)
    #expect(content.primary == "🔅")
    #expect(content.accessibilityValue == "Brightness Down")
    #expect(KeyCapContent.spokenLabel(for: .f1, labels: [:]) == "F1")
    #expect(KeyCapContent.spokenLabel(for: KeyID.mediaKeys[11], labels: [:]) == "Volume Up")
  }

  @Test func layoutLabelsAreSpokenAsLabelledNotByUSName() {
    // German: Ö on 7:51, Ä on 7:52, Ü on 7:47, < on 7:100.
    let labels: [KeyID: String] = [.semicolon: "Ö", .quote: "Ä", .openBracket: "Ü", .nonUSBackslash: "<"]
    #expect(KeyCapContent.spokenLabel(for: .semicolon, labels: labels) == "Ö")
    #expect(KeyCapContent.spokenLabel(for: .quote, labels: labels) == "Ä")
    #expect(KeyCapContent.spokenLabel(for: .openBracket, labels: labels) == "Ü")
    #expect(KeyCapContent.spokenLabel(for: .nonUSBackslash, labels: labels) == "<")
    // Without a layout label, the key's name.
    #expect(KeyCapContent.spokenLabel(for: .semicolon, labels: [:]) == "Semicolon")
    // Media keys are always spoken by name, even if a layout labelled them.
    let media = KeyID.mediaKeys[11]
    #expect(KeyCapContent.spokenLabel(for: media, labels: [media: "X"]) == "Volume Up")
  }

  @Test func nonPrintingKeysAreSpokenByNameDespiteLiveSymbols() {
    // The live client labels printing keys from the layout and non-printing keys with static symbols.
    var labels: [KeyID: String] = [.semicolon: "Ö"]
    labels[.escape] = "⎋"
    labels[.rightShift] = "R⇧"
    let media = KeyID.mediaKeys[0]
    labels[media] = "🔅"
    #expect(KeyCapContent.spokenLabel(for: .semicolon, labels: labels) == "Ö")
    #expect(KeyCapContent.spokenLabel(for: .escape, labels: labels) == "Escape")
    #expect(KeyCapContent.spokenLabel(for: .rightShift, labels: labels) == KeyNames.name(for: .rightShift))
    #expect(KeyCapContent.spokenLabel(for: media, labels: labels) == "Brightness Down")
  }

  @Test func layoutLabelsNeverOverrideMediaGlyphs() {
    let key = KeyID.mediaKeys[11]
    #expect(KeyCapContent.label(for: key, labels: [key: "X"]) == "🔊")
  }
}
