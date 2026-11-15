import ComposableArchitecture
import KeymapModel
import SwiftUI

/// The configurator window.
public struct AppView: View {
  @Bindable var store: StoreOf<AppFeature>

  public init(store: StoreOf<AppFeature>) {
    self.store = store
  }

  /// Finder-style: the keymaps and macros sections stacked from the top, empty space below.
  private var sidebar: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        KeymapListView(store: store.scope(state: \.keymapList, action: \.keymapList))
        MacroListView(store: store.scope(state: \.macroList, action: \.macroList))
      }
      .padding(10)
    }
    .focusable()
    .focusEffectDisabled()
    .onDeleteCommand {
      if let id = store.keymapList.selection {
        store.send(.keymapList(.deleteTapped(id)))
      } else if let id = store.macroList.selection, !store.macroList.isReadOnly {
        store.send(.macroList(.deleteTapped(id)))
      }
    }
  }

  public var body: some View {
    // A plain split (not NavigationSplitView): its translucent sidebar doesn't render in snapshots.
    HStack(spacing: 0) {
      sidebar
        .frame(width: 230)
      Divider()
      VStack(spacing: 0) {
        if let message = store.loadErrorMessage {
          LoadErrorBanner(message: message)
        }
        detail
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        Divider()
        StatusView(store: store.scope(state: \.status, action: \.status))
      }
    }
    .frame(minWidth: 800, minHeight: 500)
    .toolbar {
      ToolbarItem {
        Button {
          store.send(.settingsButtonTapped)
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)
        .help("Settings")
        .accessibilityIdentifier("app.settings")
      }
    }
    .sheet(item: $store.scope(state: \.settings, action: \.settings)) { settingsStore in
      SettingsView(store: settingsStore)
    }
    .alert($store.scope(state: \.importExport.alert, action: \.importExport.alert))
    .task { await store.send(.task).finish() }
  }

  @ViewBuilder private var detail: some View {
    if let editorStore = store.scope(state: \.editor, action: \.editor) {
      KeymapEditorView(store: editorStore)
    } else if let macroEditorStore = store.scope(state: \.macroEditor, action: \.macroEditor) {
      MacroEditorView(store: macroEditorStore)
    } else {
      ContentUnavailableView("No Keymap Selected", systemImage: "keyboard")
    }
  }
}

/// Shown while the configuration file can't be loaded and the app is read-only.
struct LoadErrorBanner: View {
  let message: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 2) {
        Text(message)
          .fontWeight(.semibold)
        Text("Editing is turned off so the file isn't overwritten. Fix or remove the file, then reopen KeyLayers.")
          .foregroundStyle(.secondary)
      }
      .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.15))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("banner.loadError")
  }
}
