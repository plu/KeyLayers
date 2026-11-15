import ComposableArchitecture
import KeyboardLayout
import KeymapModel
import SwiftUI

/// The selected keymap: name, abbreviation, layer selector and keyboard drawing.
public struct KeymapEditorView: View {
  @Bindable var store: StoreOf<KeymapEditorFeature>
  @FocusState private var abbreviationFocused: Bool

  public init(store: StoreOf<KeymapEditorFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      LayerSelector(selection: $store.layer)
      KeyboardView(
        geometry: KeyboardGeometry.make(store.selectedKeyboard),
        keymap: store.keymap,
        layer: store.layer,
        keymaps: store.configuration.keymaps,
        labels: store.labels,
        keyAction: $store.scope(state: \.keyAction, action: \.keyAction)
      ) { key in
        store.send(.keyTapped(key))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .padding(20)
    .toolbar {
      ToolbarItem {
        keyboardPicker
      }
    }
    .task(id: store.keymap.id) { await store.send(.task).finish() }
  }

  private var header: some View {
    HStack(spacing: 12) {
      TextField("Keymap Name", text: $store.name)
        .font(.title2)
        .frame(maxWidth: 320)
        .accessibilityIdentifier("editor.name")
      TextField("ABC", text: $store.abbreviation)
        .font(.title3.monospaced())
        .multilineTextAlignment(.center)
        .frame(width: 64)
        .focused($abbreviationFocused)
        .onSubmit { store.send(.abbreviationSubmitted) }
        .onChange(of: abbreviationFocused) { _, focused in
          if !focused {
            store.send(.abbreviationSubmitted)
          }
        }
        .help("Abbreviation: up to 3 characters, shown in the menu bar")
        .accessibilityLabel("Abbreviation")
        .accessibilityIdentifier("editor.abbreviation")
      Spacer(minLength: 0)
    }
    .textFieldStyle(.roundedBorder)
    .disabled(store.isReadOnly)
  }

  private var keyboardPicker: some View {
    Picker("Keyboard", selection: Binding(store.$selectedKeyboard)) {
      ForEach(keyboardChoices, id: \.kind) { choice in
        Text(choice.name).tag(choice.kind)
      }
    }
    .help("The keyboard to draw")
    .accessibilityIdentifier("editor.keyboardPicker")
  }

  /// The detected keyboards (one per kind), or every supported kind when none is detected; plus the
  /// selected kind, so the picker always shows the current choice.
  private var keyboardChoices: [(kind: KeyboardKind, name: String)] {
    var choices: [(kind: KeyboardKind, name: String)] = []
    if store.detected.isEmpty {
      choices = KeyboardKind.all.map { ($0, $0.displayName) }
    } else {
      for keyboard in store.detected where !choices.contains(where: { $0.kind == keyboard.kind }) {
        choices.append((keyboard.kind, "\(keyboard.name) (\(keyboard.kind.layout.rawValue.uppercased()))"))
      }
    }
    if !choices.contains(where: { $0.kind == store.selectedKeyboard }) {
      choices.append((store.selectedKeyboard, store.selectedKeyboard.displayName))
    }
    return choices
  }
}

/// Segmented buttons for the eight layers (a `Picker` doesn't expose per-segment identifiers).
private struct LayerSelector: View {
  @Binding var selection: LayerName

  var body: some View {
    HStack(spacing: 2) {
      ForEach(LayerName.allCases, id: \.self) { layer in
        let isSelected = layer == selection
        Button {
          selection = layer
        } label: {
          Text(layer.displayName)
            .frame(minWidth: 52)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
              isSelected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear,
              in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("layer.\(layer.rawValue)")
      }
    }
    .padding(2)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Layer")
  }
}
