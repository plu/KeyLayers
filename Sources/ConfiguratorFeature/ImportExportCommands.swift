import ComposableArchitecture
import SwiftUI

/// File → Import Configuration… (⇧⌘I) and Export Configuration… (⇧⌘E).
public struct ImportExportCommands: Commands {
  let store: StoreOf<AppFeature>

  public init(store: StoreOf<AppFeature>) {
    self.store = store
  }

  public var body: some Commands {
    CommandGroup(after: .newItem) {
      Divider()
      Button("Import Configuration…") {
        store.send(.importExport(.importTapped))
      }
      .keyboardShortcut("i", modifiers: [.command, .shift])
      Button("Export Configuration…") {
        store.send(.importExport(.exportTapped))
      }
      .keyboardShortcut("e", modifiers: [.command, .shift])
      // While the configuration file can't be read there is nothing to export.
      .disabled(!store.importExport.canExport)
    }
  }
}
