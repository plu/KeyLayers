import KeyboardLayout
import KeymapModel
import Testing

struct StaticKeyLabelsTests {
  @Test func staticLabels() {
    #expect(StaticKeyLabels.label(for: .leftGUI) == "⌘")
    #expect(StaticKeyLabels.label(for: .rightGUI) == "R⌘")
    #expect(StaticKeyLabels.label(for: .escape) == "⎋")
    #expect(StaticKeyLabels.label(for: .spacebar) == "space")
    #expect(StaticKeyLabels.label(for: .fn) == "fn")
    #expect(StaticKeyLabels.label(for: .f19) == "F19")
    #expect(StaticKeyLabels.label(for: .rightShift) == "R⇧")
    #expect(StaticKeyLabels.label(for: .pageDown) == "⇟")
  }

  @Test func mediaKeyLabels() {
    let expected = ["🔅", "🔆", "⊞", "🔍", "🎤", "🌙", "⏮", "⏯", "⏭", "🔇", "🔉", "🔊"]
    #expect(KeyID.mediaKeys.map { StaticKeyLabels.label(for: $0) } == expected)
  }

  @Test func printableKeysHaveNoStaticLabel() {
    #expect(StaticKeyLabels.label(for: .a) == nil)
    #expect(StaticKeyLabels.label(for: .digit1) == nil)
    #expect(StaticKeyLabels.label(for: .slash) == nil)
  }

  @Test func usANSILabelsEveryKeyOfEveryGeometry() {
    #expect(StaticKeyLabels.usANSI[.a] == "A")
    #expect(StaticKeyLabels.usANSI[.quote] == "'")
    #expect(StaticKeyLabels.usANSI[.leftGUI] == "⌘")
    for kind in KeyboardKind.all {
      for key in KeyboardGeometry.make(kind).keys.compactMap(\.keyID) {
        #expect(StaticKeyLabels.usANSI[key] != nil, "no label for \(key) on \(kind.displayName)")
      }
    }
  }
}
