import ComposableArchitecture
@testable import ConfiguratorFeature
import HelperIPC
import KeyboardLayout
import KeymapModel
import SnapshotTesting
import SwiftUI
import Testing

/// The README screenshots: the starter configuration only, running and active, US labels.
/// `scripts/update-readme-images.sh` copies the light references to `docs/images/`.
@MainActor
struct ReadmeSnapshotTests {
  private func window(layer: LayerName) throws -> some View {
    let store = try makeStore(AppFeature(), dependencies: fixedDependencies(starterOnly: true)) {
      var state = AppFeature.State(status: StatusFeature.State(
        helper: .running(HelperStatus(activeKeymapID: Keymap.starterID, permissions: granted)),
        registration: .enabled,
        daemonRegistration: .enabled
      ))
      state.editor?.labels = StaticKeyLabels.usANSI
      state.editor?.layer = layer
      return state
    }
    return AppView(store: store)
  }

  @Test func readmeBase() throws {
    try assertLight(window(layer: .base))
  }

  @Test func readmeMod() throws {
    try assertLight(window(layer: .mod))
  }

  private func assertLight(_ view: some View, testName: String = #function) {
    assertSnapshot(
      of: host(view, size: CGSize(width: 1000, height: 700), dark: false),
      as: .image(precision: 0.995, perceptualPrecision: 0.98),
      named: "light",
      testName: testName
    )
  }
}
