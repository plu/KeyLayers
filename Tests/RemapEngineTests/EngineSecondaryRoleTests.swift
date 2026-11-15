import KeymapModel
@testable import RemapEngine
import Testing

struct EngineSecondaryRoleTests {
  private let shift = Modifiers(.leftShift)

  /// capsLock: Escape, secondary role Mod layer. Space: Space, secondary role Left Shift.
  private func engine(
    base extraBase: [KeyID: KeyAction] = [:],
    mod extraMod: [KeyID: KeyAction] = [:]
  ) -> RemapEngine {
    let base: [KeyID: KeyAction] = [
      .capsLock: .keypress(Keypress(key: .escape, modifiers: [], secondaryRole: .layer(.mod))),
      .spacebar: .keypress(Keypress(key: .spacebar, modifiers: [], secondaryRole: .modifier(.leftShift))),
    ]
    let mod: [KeyID: KeyAction] = [.j: .keypress(.plain(.leftArrow))]
    return RemapEngine(configuration: .testing([
      .base: base.merging(extraBase) { $1 },
      .mod: mod.merging(extraMod) { $1 },
    ]))
  }

  @Test func tapSendsPrimary() {
    var e = engine()
    #expect(e.handle(down(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.status.activeLayer == .base)
    #expect(e.handle(up(.capsLock)) == EngineResult(
      disposition: .suppress,
      output: [out(.escape, true), out(.escape, false)]
    ))
  }

  @Test func tapIncludesEffectiveAndShortcutModifiers() {
    let command = Modifiers(.leftCommand)
    var e = engine(base: [
      .tab: .keypress(Keypress(key: .a, modifiers: command, secondaryRole: .layer(.mod))),
    ])
    #expect(e.handle(down(.leftShift)).disposition == .passThrough)
    #expect(e.handle(down(.tab)) == EngineResult(disposition: .suppress))
    // The physical shift down activated nothing: it came before the tab press.
    #expect(e.handle(up(.tab)).output == [out(.a, true, shift.union(command)), out(.a, false, shift.union(command))])
  }

  @Test func holdWithOtherKeyUsesLayer() {
    var e = engine()
    #expect(e.handle(down(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.handle(down(.j)) == EngineResult(disposition: .suppress, output: [out(.leftArrow, true)]))
    #expect(e.status.activeLayer == .mod)
    #expect(e.handle(up(.j)) == EngineResult(disposition: .suppress, output: [out(.leftArrow, false)]))
    #expect(e.handle(up(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.status.activeLayer == .base)
    #expect(e.handle(down(.j)) == EngineResult(disposition: .passThrough))
  }

  @Test func modifierRoleWrapsFollowingKeys() {
    var e = engine()
    #expect(e.handle(down(.spacebar)) == EngineResult(disposition: .suppress))
    #expect(e.handle(down(.a)) == EngineResult(
      disposition: .suppress,
      output: [out(.leftShift, true, shift), out(.a, true, shift)]
    ))
    #expect(e.handle(up(.a)).output == [out(.a, false, shift)])
    #expect(e.handle(down(.b)).output == [out(.b, true, shift)])
    #expect(e.handle(up(.b)).output == [out(.b, false, shift)])
    #expect(e.handle(up(.spacebar)) == EngineResult(disposition: .suppress, output: [out(.leftShift, false)]))
    #expect(e.handle(down(.a)) == EngineResult(disposition: .passThrough))
  }

  @Test func rolloverUpDoesNotTriggerRole() {
    var e = engine()
    #expect(e.handle(down(.a)) == EngineResult(disposition: .passThrough))
    #expect(e.handle(down(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.handle(up(.a)) == EngineResult(disposition: .passThrough))
    #expect(e.status.activeLayer == .base)
    #expect(e.handle(up(.capsLock)).output == [out(.escape, true), out(.escape, false)])
  }

  @Test func pendingRepeatIsIgnored() {
    var e = engine()
    _ = e.handle(down(.capsLock))
    for _ in 0 ..< 3 {
      #expect(e.handle(rep(.capsLock)) == EngineResult(disposition: .suppress))
    }
    #expect(e.status.activeLayer == .base)
    #expect(e.handle(up(.capsLock)).output == [out(.escape, true), out(.escape, false)])
  }

  @Test func activatedRepeatIsIgnored() {
    var e = engine()
    _ = e.handle(down(.capsLock))
    _ = e.handle(down(.j))
    #expect(e.handle(rep(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.status.activeLayer == .mod)
    _ = e.handle(down(.spacebar))
    _ = e.handle(down(.a))
    #expect(e.handle(rep(.spacebar)) == EngineResult(disposition: .suppress))
  }

  @Test func repeatOfOtherKeyDoesNotActivate() {
    var e = engine()
    _ = e.handle(down(.a))
    _ = e.handle(down(.capsLock))
    #expect(e.handle(rep(.a)) == EngineResult(disposition: .passThrough))
    #expect(e.status.activeLayer == .base)
    #expect(e.handle(up(.capsLock)).output == [out(.escape, true), out(.escape, false)])
  }

  @Test func activatedLayerRoleKeySendsNoPrimaryOnRelease() {
    var e = engine()
    _ = e.handle(down(.capsLock))
    _ = e.handle(down(.k))
    _ = e.handle(up(.k))
    #expect(e.handle(up(.capsLock)) == EngineResult(disposition: .suppress))
  }

  @Test func pendingRoleKeyActivatesEarlierPendingRole() {
    var e = engine(mod: [.k: .keypress(.plain(.c))])
    _ = e.handle(down(.spacebar))
    // Caps goes down while space is pending: activates Shift, caps itself becomes pending.
    #expect(e.handle(down(.capsLock)).output == [out(.leftShift, true, shift)])
    #expect(e.handle(down(.k)).output == [out(.c, true, shift)])
    #expect(e.status.activeLayer == .mod)
  }

  @Test func modifierRoleDoesNotClobberPhysicalModifier() {
    var e = engine()
    #expect(e.handle(down(.leftShift)).disposition == .passThrough)
    _ = e.handle(down(.spacebar))
    // Shift is already down physically: no synthetic down.
    #expect(e.handle(down(.a)).output == [out(.a, true, shift)])
    _ = e.handle(up(.a))
    // Releasing the role must not release the physical shift.
    #expect(e.handle(up(.spacebar)) == EngineResult(disposition: .suppress))
    #expect(e.handle(down(.b)) == EngineResult(disposition: .passThrough))
  }

  @Test func pendingRoleCancelsDoubleTapCandidate() {
    var e = engine(base: [.tab: .switchLayer(.fn, mode: .holdAndDoubleTapToggle)])
    _ = e.handle(down(.tab, at: 0))
    _ = e.handle(up(.tab, at: ms(20)))
    _ = e.handle(down(.capsLock, at: ms(40)))
    _ = e.handle(up(.capsLock, at: ms(60)))
    #expect(e.handle(down(.tab, at: ms(100))).notifications == [])
    _ = e.handle(up(.tab, at: ms(120)))
    #expect(e.status.activeLayer == .base)
  }

  @Test func keyReleasedAfterRoleReleaseUsesPressResolution() {
    var e = engine()
    _ = e.handle(down(.capsLock))
    #expect(e.handle(down(.j)).output == [out(.leftArrow, true)])
    _ = e.handle(up(.capsLock))
    #expect(e.handle(up(.j)).output == [out(.leftArrow, false)])
  }
}
