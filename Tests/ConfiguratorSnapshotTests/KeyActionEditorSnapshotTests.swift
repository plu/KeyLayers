import ComposableArchitecture
@testable import ConfiguratorFeature
import KeyboardLayout
import KeymapModel
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
struct KeyActionEditorSnapshotTests {
  private static let size = CGSize(width: 360, height: 420)

  private func snapshot(
    _ action: KeyAction?,
    layer: LayerName = .mod,
    testName: String = #function,
    configure: (inout KeyActionEditorFeature.State) -> Void = { _ in }
  ) throws {
    var configuration = Configuration.starter
    configuration.keymaps.append(Keymap(id: codingID, name: "Coding", abbreviation: "COD"))
    let keymaps = configuration.keymaps.elements
    let store = try makeStore(KeyActionEditorFeature(), dependencies: fixedDependencies()) {
      var state = KeyActionEditorFeature.State(key: .capsLock, layer: layer, action: action, keymaps: keymaps)
      state.labels = StaticKeyLabels.usANSI
      configure(&state)
      return state
    }
    assertBothAppearances(KeyActionEditorView(store: store), size: Self.size, testName: testName)
  }

  @Test func keypressTab() throws {
    try snapshot(nil)
  }

  @Test func keypressTabWithRoleAndModifiers() throws {
    let press = Keypress(
      key: .escape,
      modifiers: [Modifiers(.leftCommand), Modifiers(.rightShift)],
      secondaryRole: .layer(.mod)
    )
    try snapshot(.keypress(press), layer: .base)
  }

  @Test func keypressTabSearching() throws {
    try snapshot(.keypress(Keypress(key: .b, modifiers: []))) { $0.searchText = "b" }
  }

  @Test func keypressTabMediaGroup() throws {
    try snapshot(.keypress(Keypress(key: KeyID.mediaKeys[10], modifiers: []))) { $0.searchText = "volume" }
  }

  @Test func keypressTabRecording() throws {
    try snapshot(nil) { $0.isRecording = true }
  }

  @Test func layerTab() throws {
    try snapshot(.switchLayer(.fn, mode: .holdAndDoubleTapToggle), layer: .base)
  }

  @Test func keymapTab() throws {
    try snapshot(.switchKeymap(codingID))
  }

  @Test func keymapTabWithoutTarget() throws {
    try snapshot(nil) { $0.tab = .keymap }
  }

  @Test func noneTab() throws {
    try snapshot(nil) { $0.tab = .none }
  }

  @Test func noneTabBlock() throws {
    try snapshot(.block)
  }

  @Test func readOnly() throws {
    try snapshot(.block) { $0.isReadOnly = true }
  }
}
