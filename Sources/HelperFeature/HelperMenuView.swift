import ComposableArchitecture
import KeymapModel
import SwiftUI

/// The contents of the helper's menu (`MenuBarExtra` with the `.menu` style).
public struct HelperMenuView: View {
  let store: StoreOf<HelperFeature>

  public init(store: StoreOf<HelperFeature>) {
    self.store = store
  }

  public var body: some View {
    // No stack: a menu turns each top-level view into an item.
    Text(store.statusLine)
    if let error = store.helperStatus.configError {
      Text(error)
    }
    Divider()
    Section("Keymaps") {
      ForEach(store.configuration.keymaps) { keymap in
        Toggle(
          "\(keymap.name) (\(keymap.abbreviation))",
          isOn: Binding(
            get: { store.engineStatus?.activeKeymapID == keymap.id },
            set: { _ in store.send(.keymapSelected(keymap.id)) }
          )
        )
      }
    }
    Divider()
    Button(store.isPaused ? "Resume Remapping" : "Pause Remapping") {
      store.send(.pauseToggled)
    }
    .keyboardShortcut("p")
    Button("Emergency stop: ⌃⌥⌘⎋") {}
      .disabled(true)
    Divider()
    Button("Open KeyLayers…") {
      store.send(.openConfiguratorTapped)
    }
    Button("Quit KeyLayers Helper") {
      store.send(.quitTapped)
    }
    .keyboardShortcut("q")
  }
}
