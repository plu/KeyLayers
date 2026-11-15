import ComposableArchitecture
@testable import ConfiguratorFeature
import KeyboardLayout
import KeymapModel
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
struct KeyboardSnapshotTests {
  /// Every supported keyboard with the starter keymap and US labels, on Base and on Mod.
  @Test(arguments: KeyboardKind.all, [LayerName.base, .mod])
  func keyboard(_ kind: KeyboardKind, _ layer: LayerName) {
    let geometry = KeyboardGeometry.make(kind)
    let starter = Configuration.starter.keymaps[0]
    let view = KeyboardView(
      geometry: geometry,
      keymap: starter,
      layer: layer,
      keymaps: [starter],
      labels: StaticKeyLabels.usANSI
    ) { _ in }
      .padding(16)
    // About 62 pt per key unit.
    let width = (geometry.size.width * 62).rounded()
    let height = (width * geometry.size.height / geometry.size.width).rounded()
    assertBothAppearances(
      view,
      size: CGSize(width: width + 32, height: height + 32),
      testName: "keyboard_\(kind.model.rawValue)_\(kind.layout.rawValue)_\(layer.rawValue)"
    )
  }

  @Test func keymapEditor() throws {
    let store = try makeStore(KeymapEditorFeature(), dependencies: fixedDependencies()) {
      var state = KeymapEditorFeature.State(keymapID: Keymap.starterID)!
      state.labels = StaticKeyLabels.usANSI
      return state
    }
    assertBothAppearances(KeymapEditorView(store: store), size: CGSize(width: 1000, height: 700))
  }
}
