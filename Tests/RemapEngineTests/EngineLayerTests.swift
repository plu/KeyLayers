import IdentifiedCollections
import KeymapModel
@testable import RemapEngine
import Testing

struct EngineLayerTests {
  private func engine(_ layers: [LayerName: [KeyID: KeyAction]], timeout: Int = 250) -> RemapEngine {
    var configuration = Configuration.testing(layers)
    configuration.settings.doubleTapTimeoutMilliseconds = timeout
    return RemapEngine(configuration: configuration)
  }

  private struct TwoKeymaps {
    var configuration: Configuration
    var idA: Keymap.ID
    var idB: Keymap.ID
  }

  private func twoKeymaps(
    a: [LayerName: [KeyID: KeyAction]],
    b: [LayerName: [KeyID: KeyAction]]
  ) -> TwoKeymaps {
    let idA = Keymap.starterID
    let idB = Keymap.ID()
    let keymapA = Keymap(id: idA, name: "A", abbreviation: "A", layers: a.mapValues { Layer(actions: $0) })
    let keymapB = Keymap(id: idB, name: "B", abbreviation: "B", layers: b.mapValues { Layer(actions: $0) })
    let configuration = Configuration(
      keymaps: IdentifiedArray(uniqueElements: [keymapA, keymapB]),
      defaultKeymapID: idA
    )
    return TwoKeymaps(configuration: configuration, idA: idA, idB: idB)
  }

  private var modHold: [KeyID: KeyAction] {
    [.capsLock: .switchLayer(.mod, mode: .hold)]
  }

  @Test func fnHoldsModAndFKeysSendMedia() {
    var e = RemapEngine(configuration: .starter)
    _ = e.handle(down(.fn))
    #expect(e.handle(down(.f11)).output == [out(.volumeDown, true)])
    // fn released mid-press: the F-key's up still releases the media key.
    _ = e.handle(up(.fn))
    #expect(e.handle(up(.f11)).output == [out(.volumeDown, false)])
    #expect(e.handle(down(.f11)) == EngineResult(disposition: .passThrough))
    #expect(e.handle(up(.f11)) == EngineResult(disposition: .passThrough))
  }

  @Test func fnKeepsItsMacOSCombosOnMod() {
    var e = RemapEngine(configuration: .starter)
    _ = e.handle(down(.fn))
    #expect(e.handle(down(.deleteOrBackspace)).output == [out(.deleteForward, true)])
    #expect(e.handle(up(.deleteOrBackspace)).output == [out(.deleteForward, false)])
    #expect(e.handle(down(.leftArrow)).output == [out(.home, true)])
    #expect(e.handle(up(.leftArrow)).output == [out(.home, false)])
    #expect(e.handle(down(.downArrow)).output == [out(.pageDown, true)])
    #expect(e.handle(up(.downArrow)).output == [out(.pageDown, false)])
  }

  @Test func holdActivatesWhileHeld() {
    var e = engine([.base: modHold, .mod: [.j: .keypress(.plain(.leftArrow))]])
    #expect(e.handle(down(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.status.activeLayer == .mod)
    #expect(e.handle(down(.j)).output == [out(.leftArrow, true)])
    #expect(e.handle(up(.j)).output == [out(.leftArrow, false)])
    #expect(e.handle(up(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.status.activeLayer == .base)
    #expect(e.handle(down(.k)) == EngineResult(disposition: .passThrough))
  }

  @Test func toggleLatchesAndUnlatches() {
    var e = engine([.base: [.capsLock: .switchLayer(.mod, mode: .toggle)], .mod: [.j: .keypress(.plain(.leftArrow))]])
    let latch = e.handle(down(.capsLock))
    #expect(latch.disposition == .suppress)
    #expect(latch.notifications == [.layerLatched(.mod)])
    #expect(e.handle(up(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.status.activeLayer == .mod)
    #expect(e.handle(down(.j)).output == [out(.leftArrow, true)])
    _ = e.handle(up(.j))
    let unlatch = e.handle(down(.capsLock))
    #expect(unlatch.notifications == [.layerUnlatched(.mod)])
    _ = e.handle(up(.capsLock))
    #expect(e.status.activeLayer == .base)
  }

  @Test func latchingNewLayerReplacesOldOne() {
    var e = engine([.base: [
      .a: .switchLayer(.mod, mode: .toggle),
      .b: .switchLayer(.fn, mode: .toggle),
    ]])
    _ = e.handle(down(.a))
    _ = e.handle(up(.a))
    let second = e.handle(down(.b))
    #expect(second.notifications == [.layerUnlatched(.mod), .layerLatched(.fn)])
    #expect(e.status.activeLayer == .fn)
  }

  private var doubleTap: [LayerName: [KeyID: KeyAction]] {
    [.base: [.capsLock: .switchLayer(.mod, mode: .holdAndDoubleTapToggle)]]
  }

  @Test func doubleTapLocksWithinTimeout() {
    var e = engine(doubleTap)
    #expect(e.handle(down(.capsLock, at: 0)).notifications == [])
    #expect(e.handle(up(.capsLock, at: ms(50))).notifications == [])
    #expect(e.status.activeLayer == .base)
    #expect(e.handle(down(.capsLock, at: ms(200))).notifications == [.layerLatched(.mod)])
    _ = e.handle(up(.capsLock, at: ms(250)))
    #expect(e.status.activeLayer == .mod)
    #expect(e.handle(down(.capsLock, at: ms(1000))).notifications == [.layerUnlatched(.mod)])
    #expect(e.status.activeLayer == .base)
    // The unlatching press is not a hold.
    _ = e.handle(up(.capsLock, at: ms(1050)))
    #expect(e.status.activeLayer == .base)
  }

  @Test func doubleTapOutsideTimeoutDoesNotLock() {
    var e = engine(doubleTap)
    _ = e.handle(down(.capsLock, at: 0))
    _ = e.handle(up(.capsLock, at: ms(50)))
    #expect(e.handle(down(.capsLock, at: ms(260))).notifications == [])
    #expect(e.status.activeLayer == .mod)
    _ = e.handle(up(.capsLock, at: ms(300)))
    #expect(e.status.activeLayer == .base)
  }

  @Test func doubleTapInterruptedByOtherKeyDoesNotLock() {
    var e = engine(doubleTap)
    _ = e.handle(down(.capsLock, at: 0))
    _ = e.handle(down(.j, at: ms(10)))
    _ = e.handle(up(.j, at: ms(20)))
    _ = e.handle(up(.capsLock, at: ms(30)))
    #expect(e.handle(down(.capsLock, at: ms(100))).notifications == [])
    _ = e.handle(up(.capsLock, at: ms(120)))
    #expect(e.status.activeLayer == .base)
  }

  @Test func doubleTapInterruptedBetweenReleaseAndSecondPressDoesNotLock() {
    var e = engine(doubleTap)
    _ = e.handle(down(.capsLock, at: 0))
    _ = e.handle(up(.capsLock, at: ms(30)))
    _ = e.handle(down(.j, at: ms(40)))
    _ = e.handle(up(.j, at: ms(50)))
    #expect(e.handle(down(.capsLock, at: ms(100))).notifications == [])
  }

  @Test func transparentKeyFallsThroughToBase() {
    var e = engine([.base: modHold.merging([.a: .keypress(.plain(.b))]) { $1 }, .mod: [.j: .block]])
    _ = e.handle(down(.capsLock))
    #expect(e.handle(down(.a)).output == [out(.b, true)])
    #expect(e.handle(down(.j)) == EngineResult(disposition: .suppress))
  }

  @Test func layerKeyIsResolvedThroughActiveLayer() {
    var e = engine([
      .base: modHold.merging([.tab: .switchLayer(.fn, mode: .hold)]) { $1 },
      .mod: [.tab: .keypress(.plain(.c))],
      .fn: [.j: .keypress(.plain(.downArrow))],
    ])
    _ = e.handle(down(.capsLock))
    // Tab is remapped on Mod, so it does not activate Fn.
    #expect(e.handle(down(.tab)).output == [out(.c, true)])
    #expect(e.status.activeLayer == .mod)
  }

  @Test func transparentLayerKeyReachesBaseLayerKey() {
    var e = engine([
      .base: modHold.merging([.tab: .switchLayer(.fn, mode: .hold)]) { $1 },
      .fn: [.j: .keypress(.plain(.downArrow))],
    ])
    _ = e.handle(down(.capsLock))
    _ = e.handle(down(.tab))
    #expect(e.status.activeLayer == .fn)
    #expect(e.handle(down(.j)).output == [out(.downArrow, true)])
  }

  @Test func mostRecentHeldLayerWins() {
    var e = engine([
      .base: modHold.merging([.tab: .switchLayer(.fn, mode: .hold)]) { $1 },
      .mod: [.j: .keypress(.plain(.leftArrow))],
      .fn: [.j: .keypress(.plain(.downArrow))],
    ])
    _ = e.handle(down(.capsLock))
    _ = e.handle(down(.tab))
    #expect(e.status.activeLayer == .fn)
    #expect(e.handle(down(.j)).output == [out(.downArrow, true)])
    _ = e.handle(up(.j))
    _ = e.handle(up(.tab))
    #expect(e.status.activeLayer == .mod)
    #expect(e.handle(down(.j)).output == [out(.leftArrow, true)])
  }

  @Test func heldLayerBeatsLatchedLayer() {
    var e = engine([
      .base: modHold.merging([.tab: .switchLayer(.fn, mode: .toggle)]) { $1 },
    ])
    _ = e.handle(down(.tab))
    _ = e.handle(up(.tab))
    #expect(e.status.activeLayer == .fn)
    _ = e.handle(down(.capsLock))
    #expect(e.status.activeLayer == .mod)
    _ = e.handle(up(.capsLock))
    #expect(e.status.activeLayer == .fn)
  }

  @Test func keyReleasedAfterLayerChangeUsesPressResolution() {
    var e = engine([.base: modHold, .mod: [.j: .keypress(.plain(.leftArrow))]])
    _ = e.handle(down(.capsLock))
    #expect(e.handle(down(.j)).output == [out(.leftArrow, true)])
    _ = e.handle(up(.capsLock))
    #expect(e.handle(up(.j)).output == [out(.leftArrow, false)])
  }

  @Test func switchKeymapResetsLayers() {
    let maps = twoKeymaps(
      a: [.base: modHold.merging([.a: .switchKeymap(Keymap.ID())]) { $1 }],
      b: [.base: [.k: .keypress(.plain(.c))]]
    )
    let (configuration, idB) = (maps.configuration, maps.idB)
    var config = configuration
    config.keymaps[id: Keymap.starterID]?.setAction(.switchKeymap(idB), for: .a, on: .base)
    var e = RemapEngine(configuration: config)
    _ = e.handle(down(.capsLock))
    let result = e.handle(down(.a))
    #expect(result.disposition == .suppress)
    #expect(result.notifications == [.keymapSwitched(idB)])
    #expect(e.status.activeKeymapID == idB)
    #expect(e.status.activeLayer == .base)
    // Releasing the layer key that was held before the switch is harmless.
    #expect(e.handle(up(.capsLock)) == EngineResult(disposition: .suppress))
    #expect(e.handle(up(.a)) == EngineResult(disposition: .suppress))
    #expect(e.status.activeLayer == .base)
    #expect(e.handle(down(.k)).output == [out(.c, true)])
  }

  @Test func switchToMissingKeymapActsAsBlock() {
    var e = engine([.base: [.a: .switchKeymap(Keymap.ID())]])
    #expect(e.handle(down(.a)) == EngineResult(disposition: .suppress))
    #expect(e.handle(up(.a)) == EngineResult(disposition: .suppress))
    #expect(e.status.activeKeymapID == Keymap.starterID)
  }

  @Test func deletedActiveKeymapFallsBackToDefault() {
    let maps = twoKeymaps(a: [:], b: [.base: modHold])
    let (configuration, idA, idB) = (maps.configuration, maps.idA, maps.idB)
    var e = RemapEngine(configuration: configuration)
    #expect(e.selectKeymap(idB).notifications == [.keymapSwitched(idB)])
    #expect(e.status.activeKeymapID == idB)
    _ = e.handle(down(.capsLock))
    #expect(e.status.activeLayer == .mod)
    var reduced = configuration
    reduced.keymaps.remove(id: idB)
    e.update(configuration: reduced)
    #expect(e.status.activeKeymapID == idA)
    #expect(e.status.activeLayer == .base)
  }

  @Test func updateKeepsExistingActiveKeymap() {
    let maps = twoKeymaps(a: [:], b: [:])
    let (configuration, idB) = (maps.configuration, maps.idB)
    var e = RemapEngine(configuration: configuration)
    _ = e.selectKeymap(idB)
    e.update(configuration: configuration)
    #expect(e.status.activeKeymapID == idB)
  }

  @Test func selectKeymapSwitchesAndResets() {
    let maps = twoKeymaps(a: [.base: [.capsLock: .switchLayer(.mod, mode: .toggle)]], b: [:])
    let (configuration, idB) = (maps.configuration, maps.idB)
    var e = RemapEngine(configuration: configuration)
    _ = e.handle(down(.capsLock))
    #expect(e.status.activeLayer == .mod)
    let result = e.selectKeymap(idB)
    #expect(result == EngineResult(disposition: .suppress, output: [], notifications: [.keymapSwitched(idB)]))
    #expect(e.status.activeLayer == .base)
  }

  @Test func selectKeymapIgnoresUnknownID() {
    var e = engine([.base: [.capsLock: .switchLayer(.mod, mode: .toggle)]])
    _ = e.handle(down(.capsLock))
    #expect(e.selectKeymap(Keymap.ID()) == EngineResult(disposition: .passThrough))
    #expect(e.status.activeKeymapID == Keymap.starterID)
    #expect(e.status.activeLayer == .mod)
  }
}
