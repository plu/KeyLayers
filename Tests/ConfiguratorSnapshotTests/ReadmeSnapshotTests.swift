import ComposableArchitecture
@testable import ConfiguratorFeature
import HelperIPC
import KeyboardLayout
import KeymapModel
import SnapshotTesting
import SwiftUI
import Testing

/// The README and website screenshots: the starter configuration only, running and active, US labels.
/// `scripts/update-readme-images.sh` copies the light references to `docs/images/`; `mise run site:images`
/// copies both appearances to the website.
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
    try assertBothAppearances(window(layer: .base), size: Self.size)
  }

  @Test func readmeMod() throws {
    try assertBothAppearances(window(layer: .mod), size: Self.size)
  }

  private static let size = CGSize(width: 1000, height: 700)
}
