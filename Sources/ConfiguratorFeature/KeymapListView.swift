import ComposableArchitecture
import KeymapModel
import SwiftUI

/// The sidebar: keymaps plus add / duplicate / delete / set default.
public struct KeymapListView: View {
  @Bindable var store: StoreOf<KeymapListFeature>

  public init(store: StoreOf<KeymapListFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Plain rows rather than `List`: `List` rows are drawn lazily and don't appear in snapshots.
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          Text("Keymaps")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
          ForEach(store.configuration.keymaps) { keymap in
            KeymapRow(
              keymap: keymap,
              isDefault: keymap.id == store.configuration.defaultKeymapID,
              isSelected: keymap.id == store.selection
            ) {
              store.selection = keymap.id
            }
            .accessibilityIdentifier("keymap.row.\(keymap.abbreviation)")
          }
        }
        .padding(10)
      }
      Divider()
      toolbar
    }
    .alert($store.scope(state: \.alert, action: \.alert))
  }

  private var toolbar: some View {
    HStack(spacing: 2) {
      button("Add Keymap", systemImage: "plus", identifier: "keymap.add", enabled: !store.isReadOnly) {
        store.send(.addTapped)
      }
      button(
        "Duplicate Keymap",
        systemImage: "plus.square.on.square",
        identifier: "keymap.duplicate",
        enabled: !store.isReadOnly && store.selection != nil
      ) {
        if let id = store.selection {
          store.send(.duplicateTapped(id))
        }
      }
      button(
        "Delete Keymap",
        systemImage: "minus",
        identifier: "keymap.delete",
        enabled: store.canDelete && store.selection != nil
      ) {
        if let id = store.selection {
          store.send(.deleteTapped(id))
        }
      }
      Spacer()
      button(
        "Set as Default",
        systemImage: "star",
        identifier: "keymap.setDefault",
        enabled: !store.isReadOnly && store.selection != nil
          && store.selection != store.configuration.defaultKeymapID
      ) {
        if let id = store.selection {
          store.send(.setDefaultTapped(id))
        }
      }
    }
    .buttonStyle(.borderless)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
  }

  private func button(
    _ title: String,
    systemImage: String,
    identifier: String,
    enabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .frame(width: 22, height: 18)
    }
    .help(title)
    .accessibilityLabel(title)
    .accessibilityIdentifier(identifier)
    .disabled(!enabled)
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
