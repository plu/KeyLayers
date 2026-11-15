import ComposableArchitecture
import ConfiguratorFeature
import SwiftUI

/// The configurator: edits the shared configuration and registers the embedded helper.
@main
struct ConfiguratorApp: App {
  @NSApplicationDelegateAdaptor(ConfiguratorAppDelegate.self) private var appDelegate
  private let store: StoreOf<AppFeature>

  init() {
    // Before anything reads a dependency or a shared value (the store's state does both).
    #if DEBUG
      if UITestMode.isEnabled {
        prepareDependencies { UITestMode.prepare(&$0) }
      }
    #endif
    store = Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  }

  var body: some Scene {
    Window("KeyLayers", id: "main") {
      AppView(store: store)
    }
    .defaultSize(width: 1000, height: 700)
  }
}
