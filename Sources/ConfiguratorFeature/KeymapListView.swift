import ComposableArchitecture
import KeymapModel
import SwiftUI

/// The sidebar's keymaps section: a header with a "+" button, then one row per keymap.
public struct KeymapListView: View {
  @Bindable var store: StoreOf<KeymapListFeature>

  public init(store: StoreOf<KeymapListFeature>) {
    self.store = store
  }

  public var body: some View {
    // Plain rows rather than `List`: `List` rows are drawn lazily and don't appear in snapshots.
    VStack(alignment: .leading, spacing: 2) {
      SidebarSectionHeader(
        title: "Keymaps",
        addLabel: "Add Keymap",
        addIdentifier: "keymap.add",
        isDisabled: store.isReadOnly
      ) {
        store.send(.addTapped)
      }
      ForEach(store.configuration.keymaps) { keymap in
        let isDefault = keymap.id == store.configuration.defaultKeymapID
        KeymapRow(keymap: keymap, isDefault: isDefault, isSelected: keymap.id == store.selection) {
          store.selection = keymap.id
        }
        .contextMenu {
          Button("Duplicate") { store.send(.duplicateTapped(keymap.id)) }
            .disabled(store.isReadOnly)
          Button("Set as Default") { store.send(.setDefaultTapped(keymap.id)) }
            .disabled(store.isReadOnly || isDefault)
          Button("Delete…", role: .destructive) { store.send(.deleteTapped(keymap.id)) }
            .disabled(!store.canDelete)
        }
        .accessibilityIdentifier("keymap.row.\(keymap.abbreviation)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .alert($store.scope(state: \.alert, action: \.alert))
  }
}

private struct KeymapRow: View {
  let keymap: Keymap
  let isDefault: Bool
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(spacing: 8) {
        Text(keymap.abbreviation)
          .font(.caption.monospaced().weight(.semibold))
          .frame(minWidth: 34)
          .padding(.vertical, 2)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        Text(keymap.name)
          .lineLimit(1)
        Spacer(minLength: 4)
        if isDefault {
          Image(systemName: "star.fill")
            .help("Default keymap")
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .foregroundStyle(isSelected ? Color.white : Color.primary)
      .background(
        isSelected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear,
        in: RoundedRectangle(cornerRadius: 6)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(keymap.name), \(keymap.abbreviation)\(isDefault ? ", default" : "")")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
