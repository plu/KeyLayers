import Foundation
import KeymapModel
@testable import RemapEngine
import Testing

struct EngineMacroTests {
  private let macro = Macro(id: UUID(), name: "Hello", steps: [.text("hello")])

  /// A: the macro.
  private func engine(base extraBase: [KeyID: KeyAction] = [:]) -> RemapEngine {
    let base: [KeyID: KeyAction] = [.a: .macro(macro.id)]
    return RemapEngine(configuration: .testing([.base: base.merging(extraBase) { $1 }], macros: [macro]))
  }

  @Test func macroKeyDownYieldsMacro() {
    var e = engine()
    #expect(e.handle(down(.a)) == EngineResult(disposition: .suppress, macros: [macro]))
  }

  @Test func macroRepeatAndUpSuppressed() {
    var e = engine()
    _ = e.handle(down(.a))
    #expect(e.handle(rep(.a)) == EngineResult(disposition: .suppress))
    #expect(e.handle(up(.a)) == EngineResult(disposition: .suppress))
  }

  @Test func danglingMacroBlocks() {
    var e = engine(base: [.a: .macro(UUID())])
    #expect(e.handle(down(.a)) == EngineResult(disposition: .suppress))
    #expect(e.handle(up(.a)) == EngineResult(disposition: .suppress))
  }

  @Test func macroReleasesSyntheticModifier() {
    var e = engine(base: [.capsLock: .keypress(.plain(.leftShift))])
    #expect(e.handle(down(.capsLock)).output == [out(.leftShift, true, Modifiers(.leftShift))])
    #expect(e.handle(down(.a)) == EngineResult(
      disposition: .suppress,
      output: [out(.leftShift, false)],
      macros: [macro]
    ))
    #expect(e.handle(up(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.handle(up(.a)) == EngineResult(disposition: .suppress))
  }

  @Test func macroActivatesPendingRoleThenReleasesIt() {
    let command = Modifiers(.leftCommand)
    var e = engine(base: [.f: .keypress(Keypress(key: .f, modifiers: [], secondaryRole: .modifier(.leftCommand)))])
    #expect(e.handle(down(.f)) == EngineResult(disposition: .suppress))
    // Activation's down first, then the up before the macro plays.
    #expect(e.handle(down(.a)) == EngineResult(
      disposition: .suppress,
      output: [out(.leftGUI, true, command), out(.leftGUI, false)],
      macros: [macro]
    ))
    #expect(e.handle(up(.a)) == EngineResult(disposition: .suppress))
    #expect(e.handle(up(.f)) == EngineResult(disposition: .suppress))
  }

  @Test func physicalModifierUntouched() {
    var e = engine()
    #expect(e.handle(down(.leftShift)).disposition == .passThrough)
    #expect(e.handle(down(.a)) == EngineResult(disposition: .suppress, macros: [macro]))
    #expect(e.handle(up(.a)) == EngineResult(disposition: .suppress))
    #expect(e.handle(up(.leftShift)).disposition == .passThrough)
  }

  @Test func syntheticModifierAlsoHeldPhysicallyStaysDown() {
    var e = engine(base: [.capsLock: .keypress(.plain(.leftShift))])
    _ = e.handle(down(.leftShift))
    _ = e.handle(down(.capsLock))
    #expect(e.handle(down(.a)) == EngineResult(disposition: .suppress, macros: [macro]))
  }
}
