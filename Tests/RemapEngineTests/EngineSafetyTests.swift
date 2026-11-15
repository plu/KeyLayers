import KeymapModel
@testable import RemapEngine
import Testing

struct EngineSafetyTests {
  private let shift = Modifiers(.leftShift)
  private let control = Modifiers(.leftControl)

  private var secondaryRoles: [KeyID: KeyAction] {
    [
      .capsLock: .keypress(Keypress(key: .escape, modifiers: [], secondaryRole: .layer(.mod))),
      .spacebar: .keypress(Keypress(key: .spacebar, modifiers: [], secondaryRole: .modifier(.leftShift))),
    ]
  }

  private func engine(_ layers: [LayerName: [KeyID: KeyAction]], timeout: Int = 250) -> RemapEngine {
    var configuration = Configuration.testing(layers)
    configuration.settings.doubleTapTimeoutMilliseconds = timeout
    return RemapEngine(configuration: configuration)
  }

  /// Presses physical Left Control, Left Option and Left Command.
  private func holdEmergencyModifiers(_ e: inout RemapEngine) {
    for key in [KeyID.leftControl, .leftAlt, .leftGUI] {
      _ = e.handle(down(key))
    }
  }

  // MARK: - Emergency combo

  @Test func emergencyComboStopsAndReleases() {
    var e = engine([.base: secondaryRoles, .mod: [.j: .keypress(.plain(.leftArrow))]])
    _ = e.handle(down(.capsLock))
    holdEmergencyModifiers(&e)
    // The modifier downs activated the Mod layer role.
    #expect(e.status.activeLayer == .mod)
    let result = e.handle(down(.escape))
    #expect(result.disposition == .suppress)
    #expect(result.notifications == [.emergencyStop])
    #expect(result.output == [])
    #expect(e.status.activeLayer == .base)
    // Escape's own release and repeat do not leak to the system.
    #expect(e.handle(rep(.escape)) == EngineResult(disposition: .suppress))
    #expect(e.handle(up(.escape)) == EngineResult(disposition: .suppress))
    // Caps' role was cleared: its release sends nothing.
    #expect(e.handle(up(.capsLock)) == EngineResult(disposition: .passThrough))
  }

  @Test func emergencyComboReleasesSyntheticKeys() {
    var e = engine([.base: secondaryRoles.merging([.j: .keypress(.plain(.leftArrow))]) { $1 }])
    _ = e.handle(down(.spacebar))
    _ = e.handle(down(.j))
    let all: Modifiers = [Modifiers(.leftControl), Modifiers(.leftOption), Modifiers(.leftCommand)]
    holdEmergencyModifiers(&e)
    let result = e.handle(down(.escape))
    #expect(result.notifications == [.emergencyStop])
    #expect(result.output == [out(.leftArrow, false, all.union(shift)), out(.leftShift, false, all)])
  }

  @Test func emergencyComboWorksWhenEscapeIsRemapped() {
    var e = engine([.base: [.escape: .block]])
    holdEmergencyModifiers(&e)
    let result = e.handle(down(.escape))
    #expect(result.disposition == .suppress)
    #expect(result.notifications == [.emergencyStop])
  }

  @Test func emergencyComboUsesPhysicalModifiersEvenWhenRemapped() {
    var e = engine([.base: [
      .leftControl: .block,
      .leftAlt: .keypress(.plain(.b)),
      .leftGUI: .switchLayer(.mod, mode: .hold),
    ]])
    holdEmergencyModifiers(&e)
    #expect(e.handle(down(.escape)).notifications == [.emergencyStop])
  }

  @Test func escapeWithoutFullComboIsNormal() {
    var e = engine([:])
    _ = e.handle(down(.leftControl))
    _ = e.handle(down(.leftAlt))
    #expect(e.handle(down(.escape)) == EngineResult(disposition: .passThrough))
    _ = e.handle(up(.escape))
    _ = e.handle(down(.leftGUI))
    _ = e.handle(up(.leftAlt))
    #expect(e.handle(down(.escape)) == EngineResult(disposition: .passThrough))
  }

  @Test func physicalKeyTrackingIsClearedByReleaseAll() {
    var e = engine([:])
    holdEmergencyModifiers(&e)
    #expect(e.handle(down(.escape)).notifications == [.emergencyStop])
    // After a pause the modifier ups are never seen; the engine must not
    // think they are still down.
    _ = e.handle(up(.escape))
    #expect(e.handle(down(.escape)) == EngineResult(disposition: .passThrough))
  }

  // MARK: - releaseAll

  @Test func releaseAllReleasesSyntheticKeys() {
    var e = engine([.base: secondaryRoles])
    _ = e.handle(down(.spacebar))
    _ = e.handle(down(.a))
    let output = e.releaseAll()
    #expect(output == [out(.a, false, shift), out(.leftShift, false)])
    #expect(e.status.activeLayer == .base)
    // The released keys' later ups do not emit again.
    #expect(e.handle(up(.a)) == EngineResult(disposition: .passThrough))
    #expect(e.handle(up(.spacebar)) == EngineResult(disposition: .passThrough))
  }

  @Test func releaseAllReleasesRemappedKeysAndHeldModifiers() {
    var e = engine([.base: [
      .capsLock: .keypress(.plain(.leftControl)),
      .j: .keypress(.plain(.leftArrow, shift)),
    ]])
    _ = e.handle(down(.capsLock))
    _ = e.handle(down(.j))
    #expect(e.releaseAll() == [out(.leftArrow, false, control.union(shift)), out(.leftControl, false)])
  }

  @Test func releaseAllDoesNotReleasePhysicalModifiers() {
    var e = engine([:])
    _ = e.handle(down(.leftShift))
    _ = e.handle(down(.a))
    #expect(e.releaseAll() == [out(.a, false, shift)])
  }

  @Test func releaseAllClearsLayersButKeepsKeymap() {
    var e = engine([.base: [
      .capsLock: .switchLayer(.mod, mode: .toggle),
      .tab: .switchLayer(.fn, mode: .hold),
    ]])
    _ = e.handle(down(.capsLock))
    _ = e.handle(up(.capsLock))
    _ = e.handle(down(.tab))
    #expect(e.status.activeLayer == .fn)
    #expect(e.releaseAll() == [])
    #expect(e.status.activeLayer == .base)
    #expect(e.status.activeKeymapID == Keymap.starterID)
    _ = e.handle(up(.tab))
    #expect(e.status.activeLayer == .base)
  }

  @Test func releaseAllDropsPendingRoles() {
    var e = engine([.base: secondaryRoles])
    _ = e.handle(down(.capsLock))
    #expect(e.releaseAll() == [])
    #expect(e.handle(up(.capsLock)) == EngineResult(disposition: .passThrough))
  }

  // MARK: - Physical modifiers vs synthetic modifiers

  @Test func physicalModifierUpWhileSyntheticallyHeldIsSuppressed() {
    var e = engine([.base: secondaryRoles])
    #expect(e.handle(down(.leftShift)) == EngineResult(disposition: .passThrough))
    _ = e.handle(down(.spacebar))
    // Shift already down physically: the role emits no down.
    #expect(e.handle(down(.a)).output == [out(.a, true, shift)])
    #expect(e.handle(up(.leftShift)) == EngineResult(disposition: .suppress))
    // Still shifted by the role.
    #expect(e.handle(down(.b)).output == [out(.b, true, shift)])
    // Role release now releases shift, which the system still thinks is down.
    #expect(e.handle(up(.spacebar)).output == [out(.leftShift, false)])
  }

  @Test func physicalModifierDownWhileSyntheticallyHeldEmitsNothing() {
    var e = engine([.base: secondaryRoles])
    _ = e.handle(down(.spacebar))
    #expect(e.handle(down(.a)).output == [out(.leftShift, true, shift), out(.a, true, shift)])
    #expect(e.handle(down(.leftShift)) == EngineResult(disposition: .suppress))
    #expect(e.handle(down(.b)).output == [out(.b, true, shift)])
    // The role release keeps the physically held shift down.
    #expect(e.handle(up(.spacebar)) == EngineResult(disposition: .suppress))
    // Only the physical shift remains; the system applies it to pass-through keys.
    #expect(e.handle(down(.c)) == EngineResult(disposition: .passThrough))
    _ = e.handle(up(.c))
    // Nothing holds shift synthetically any more: the physical up reaches the system.
    #expect(e.handle(up(.leftShift)) == EngineResult(disposition: .passThrough))
    #expect(e.handle(down(.d)) == EngineResult(disposition: .passThrough))
  }

  // MARK: - Robustness

  @Test func hugeDoubleTapTimeoutDoesNotTrap() {
    var e = engine([.base: [.capsLock: .switchLayer(.mod, mode: .holdAndDoubleTapToggle)]], timeout: .max)
    _ = e.handle(down(.capsLock, at: 0))
    _ = e.handle(up(.capsLock, at: ms(50)))
    #expect(e.handle(down(.capsLock, at: ms(100))).notifications == [.layerLatched(.mod)])
  }
}
