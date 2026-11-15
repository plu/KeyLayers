import ComposableArchitecture
import KeymapModel
import SwiftUI

/// The sidebar's macros section: a header with a "+" button, then one row per macro.
public struct MacroListView: View {
  @Bindable var store: StoreOf<MacroListFeature>

  public init(store: StoreOf<MacroListFeature>) {
    self.store = store
  }

  public var body: some View {
    // Plain rows rather than `List`: `List` rows are drawn lazily and don't appear in snapshots.
    VStack(alignment: .leading, spacing: 2) {
      SidebarSectionHeader(
        title: "Macros",
        addLabel: "Add Macro",
        addIdentifier: "macros.add",
        isDisabled: store.isReadOnly
      ) {
        store.send(.addTapped)
      }
      ForEach(store.configuration.macros) { macro in
        MacroRow(macro: macro, isSelected: macro.id == store.selection) {
          store.selection = macro.id
        }
        .contextMenu {
          Button("Duplicate") { store.send(.duplicateTapped(macro.id)) }
            .disabled(store.isReadOnly)
          Button("Delete…", role: .destructive) { store.send(.deleteTapped(macro.id)) }
            .disabled(store.isReadOnly)
        }
        .accessibilityIdentifier("macros.row.\(macro.name)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .alert($store.scope(state: \.alert, action: \.alert))
  }
}

private struct MacroRow: View {
  let macro: Macro
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(spacing: 8) {
        Image(systemName: "bolt")
        Text(macro.name)
          .lineLimit(1)
        Spacer(minLength: 4)
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
    .accessibilityLabel(macro.name)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
