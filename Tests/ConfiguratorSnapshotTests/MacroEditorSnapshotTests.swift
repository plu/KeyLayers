import ComposableArchitecture
@testable import ConfiguratorFeature
import KeyboardLayout
import KeymapModel
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
struct MacroEditorSnapshotTests {
  private func snapshot(
    testName: String = #function,
    configure: (inout MacroEditorFeature.State) -> Void = { _ in }
  ) throws {
    let store = try makeStore(
      MacroEditorFeature(),
      dependencies: fixedDependencies(macros: [coffeeMacro])
    ) {
      var state = MacroEditorFeature.State(macroID: coffeeMacroID)
      state.labels = StaticKeyLabels.usANSI
      configure(&state)
      return state
    }
    // The view asks the text client directly, outside the store's dependencies.
    withDependencies { $0.textKeystrokes = asciiTextKeystrokes } operation: {
      assertBothAppearances(MacroEditorView(store: store), size: CGSize(width: 600, height: 420), testName: testName)
    }
  }

  @Test func macroEditor() throws {
    try snapshot()
  }

  @Test func macroEditorRecording() throws {
    try snapshot { $0.recordingStep = 0 }
  }
}
