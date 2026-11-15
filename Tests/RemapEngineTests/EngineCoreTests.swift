import KeymapModel
@testable import RemapEngine
import Testing

struct EngineCoreTests {
  private func engine(_ base: [KeyID: KeyAction]) -> RemapEngine {
    RemapEngine(configuration: .testing([.base: base]))
  }

  @Test func unmappedKeyPassesThrough() {
    var e = RemapEngine(configuration: .testing([:]))
    #expect(e.handle(down(.a)) == EngineResult(disposition: .passThrough, output: [], notifications: []))
    #expect(e.handle(up(.a)) == EngineResult(disposition: .passThrough, output: [], notifications: []))
  }

  @Test func keypressRemapsWithShortcutModifiers() {
    let shortcut: Modifiers = [Modifiers(.leftCommand), Modifiers(.leftShift)]
    var e = engine([.a: .keypress(.plain(.digit4, shortcut))])
    let pressed = e.handle(down(.a))
    #expect(pressed.disposition == .suppress)
    #expect(pressed.output == [out(.digit4, true, shortcut)])
    let released = e.handle(up(.a))
    #expect(released.disposition == .suppress)
    #expect(released.output == [out(.digit4, false, shortcut)])
  }

  @Test func physicalModifiersAreIncludedInOutput() {
    let shift = Modifiers(.leftShift)
    var e = engine([.j: .keypress(.plain(.leftArrow))])
    #expect(e.handle(down(.leftShift)).disposition == .passThrough)
    #expect(e.handle(down(.j)).output == [out(.leftArrow, true, shift)])
    #expect(e.handle(up(.j)).output == [out(.leftArrow, false, shift)])
    #expect(e.handle(up(.leftShift)).disposition == .passThrough)
    #expect(e.handle(down(.j)).output == [out(.leftArrow, true)])
  }

  @Test func repeatOfMappedKeyEmitsRepeatOutput() {
    var e = engine([.j: .keypress(.plain(.leftArrow))])
    #expect(e.handle(down(.j)).output == [out(.leftArrow, true)])
    for _ in 0 ..< 2 {
      let result = e.handle(rep(.j))
      #expect(result.disposition == .suppress)
      #expect(result.output == [out(.leftArrow, true, repeat: true)])
    }
  }

  @Test func repeatOfUnmappedKeyPassesThrough() {
    var e = RemapEngine(configuration: .testing([:]))
    _ = e.handle(down(.a))
    #expect(e.handle(rep(.a)) == EngineResult(disposition: .passThrough))
  }

  @Test func blockSuppressesWithoutOutput() {
    var e = engine([.a: .block])
    for event in [down(.a), rep(.a), up(.a)] {
      #expect(e.handle(event) == EngineResult(disposition: .suppress))
    }
  }

  @Test func unsupportedActsAsBlock() {
    var e = engine([.a: .unsupported(type: "playMacro")])
    for event in [down(.a), rep(.a), up(.a)] {
      #expect(e.handle(event) == EngineResult(disposition: .suppress))
    }
  }

  @Test func modifierOnlyKeypressHoldsModifier() {
    let control = Modifiers(.leftControl)
    var e = engine([.capsLock: .keypress(.plain(.leftControl))])
    let pressed = e.handle(down(.capsLock))
    #expect(pressed.disposition == .suppress)
    #expect(pressed.output == [out(.leftControl, true, control)])
    #expect(e.handle(rep(.capsLock)) == EngineResult(disposition: .suppress))

    let other = e.handle(down(.a))
    #expect(other.disposition == .suppress)
    #expect(other.output == [out(.a, true, control)])

    let released = e.handle(up(.capsLock))
    #expect(released.disposition == .suppress)
    #expect(released.output == [out(.leftControl, false)])
    #expect(e.handle(up(.a)).disposition == .passThrough)
  }

  @Test func modifierKeypressWithShortcutModifiersHoldsAll() {
    let both: Modifiers = [Modifiers(.leftControl), Modifiers(.leftShift)]
    var e = engine([.capsLock: .keypress(.plain(.leftControl, Modifiers(.leftShift)))])
    #expect(e.handle(down(.capsLock)).output == [
      out(.leftControl, true, both), out(.leftShift, true, both),
    ])
    #expect(e.handle(up(.capsLock)).output == [out(.leftControl, false), out(.leftShift, false)])
  }

  @Test func keyReleasedAfterConfigurationChangeUsesPressResolution() {
    var e = engine([.a: .keypress(.plain(.b))])
    _ = e.handle(down(.a))
    e.update(configuration: .testing([.base: [.a: .keypress(.plain(.c))]]))
    #expect(e.handle(up(.a)).output == [out(.b, false)])
    #expect(e.handle(down(.a)).output == [out(.c, true)])
  }

  @Test func syntheticModifierReleaseKeepsPhysicalModifier() {
    let shift = Modifiers(.leftShift)
    var e = engine([.capsLock: .keypress(.plain(.leftShift)), .j: .keypress(.plain(.leftArrow))])
    #expect(e.handle(down(.leftShift)).disposition == .passThrough)
    #expect(e.handle(down(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.handle(up(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.handle(down(.j)).output == [out(.leftArrow, true, shift)])
  }

  @Test func overlappingSyntheticModifiersEmitOnce() {
    let shift = Modifiers(.leftShift)
    var e = engine([.capsLock: .keypress(.plain(.leftShift)), .tab: .keypress(.plain(.leftShift))])
    #expect(e.handle(down(.capsLock)).output == [out(.leftShift, true, shift)])
    #expect(e.handle(down(.tab)).output == [])
    #expect(e.handle(up(.capsLock)).output == [])
    #expect(e.handle(up(.tab)).output == [out(.leftShift, false)])
  }
}
