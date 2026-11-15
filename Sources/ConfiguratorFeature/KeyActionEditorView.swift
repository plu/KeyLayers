import ComposableArchitecture
import KeyboardLayout
import KeymapModel
import SwiftUI

/// The key action popover: a header with a preview cap, the Keypress / Layer / Keymap / None tabs
/// and Apply / Cancel.
public struct KeyActionEditorView: View {
  @Bindable var store: StoreOf<KeyActionEditorFeature>

  public init(store: StoreOf<KeyActionEditorFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      TabSelector(selection: $store.tab)
      Group {
        switch store.tab {
        case .keypress: KeypressTab(store: store)
        case .layer: layerTab
        case .keymap: keymapTab
        case .none: noneTab
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .disabled(store.isReadOnly)
      footer
    }
    .padding(14)
    .frame(width: 360, height: 420)
  }

  private var header: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(KeyNames.name(for: store.key) ?? KeyCapContent.label(for: store.key, labels: store.labels))
          .font(.headline)
        Text("\(store.layer.displayName) layer")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      KeyCapView(content: preview, shape: KeyCapShape(cornerRadius: 6), unit: 46)
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }
  }

  /// The cap the key would show with the action being edited.
  private var preview: KeyCapContent {
    var keymap = Keymap(id: UUID(), name: "", abbreviation: "")
    keymap.setAction(store.action, for: store.key, on: store.layer)
    return KeyCapContent.make(
      key: store.key,
      layer: store.layer,
      keymap: keymap,
      keymaps: IdentifiedArray(uniqueElements: store.keymaps),
      labels: store.labels
    )
  }

  private var layerTab: some View {
    Form {
      Picker("Layer", selection: $store.targetLayer) {
        ForEach(LayerName.switchable, id: \.self) { layer in
          Text(layer.displayName).tag(layer)
        }
      }
      .accessibilityIdentifier("popover.layer.target")
      Picker("Mode", selection: $store.layerMode) {
        Text("Hold: active while held").tag(LayerSwitchMode.hold)
        Text("Toggle: tap to switch on and off").tag(LayerSwitchMode.toggle)
        Text("Hold, or double-tap to lock").tag(LayerSwitchMode.holdAndDoubleTapToggle)
      }
      .pickerStyle(.radioGroup)
      .accessibilityIdentifier("popover.layer.mode")
    }
  }

  private var keymapTab: some View {
    Form {
      Picker("Switch to", selection: $store.targetKeymap) {
        Text("Choose a keymap").tag(Keymap.ID?.none)
        ForEach(store.keymaps) { keymap in
          Text("\(keymap.name) (\(keymap.abbreviation))").tag(Keymap.ID?.some(keymap.id))
        }
        if let target = store.targetKeymap, !store.keymaps.contains(where: { $0.id == target }) {
          Text("Deleted keymap").tag(Keymap.ID?.some(target))
        }
      }
      .accessibilityIdentifier("popover.keymap.target")
      Text("Pressing the key makes this keymap active.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private var noneTab: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle("Block the key", isOn: $store.noneIsBlock)
        .accessibilityIdentifier("popover.none.block")
      Text(noneExplanation)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var noneExplanation: String {
    if store.noneIsBlock {
      return "Blocked: the key does nothing on this layer."
    }
    return store.layer == .base
      ? "Transparent: the key types what's printed on it."
      : "Transparent: the key does what it does on the Base layer."
  }

  private var footer: some View {
    HStack {
      if store.isReadOnly {
        Text("Read-only: the configuration file can't be read.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      Button("Cancel") { store.send(.cancelTapped) }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("popover.cancel")
      Button("Apply") { store.send(.applyTapped) }
        .keyboardShortcut(.defaultAction)
        .disabled(!store.canApply)
        .accessibilityIdentifier("popover.apply")
    }
  }
}

/// The Keypress tab: key picker (search list or recording), modifiers, secondary role.
private struct KeypressTab: View {
  @Bindable var store: StoreOf<KeyActionEditorFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text("Key:")
          .foregroundStyle(.secondary)
        Text(selectedKey)
          .fontWeight(.medium)
          .lineLimit(1)
          .accessibilityIdentifier("popover.keypress.selected")
        Spacer(minLength: 0)
        Button {
          store.send(.recordTapped)
        } label: {
          Label(store.isRecording ? "Press a key…" : "Record", systemImage: "record.circle")
        }
        // While recording it stays enabled but prominent; the reducer ignores a second tap.
        .buttonStyle(RecordButtonStyle(isRecording: store.isRecording))
        .help("Record the next key you press")
        .accessibilityIdentifier("popover.keypress.record")
      }
      TextField("Search keys", text: $store.searchText)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("popover.keypress.search")
      results
      modifiers
      HStack(spacing: 8) {
        Text("Secondary role")
        // A `Menu` of buttons rather than a `Picker`: a picker's option identifiers don't reach
        // its menu items, and UI tests pick options by identifier.
        Menu {
          Button("None") { setSecondaryRole(nil) }
            .accessibilityIdentifier("secondary.none")
          Section("Layer while held") {
            ForEach(LayerName.switchable, id: \.self) { layer in
              Button(layer.displayName) { setSecondaryRole(.layer(layer)) }
                .accessibilityIdentifier("secondary.layer.\(layer.rawValue)")
            }
          }
          Section("Modifier while held") {
            ForEach(Modifier.allCases, id: \.self) { modifier in
              Button(Self.name(modifier)) { setSecondaryRole(.modifier(modifier)) }
                .accessibilityIdentifier("secondary.modifier.\(modifier.rawValue)")
            }
          }
        } label: {
          Text(secondaryRoleTitle)
        }
        .fixedSize()
        .help("What the key does when held down together with another key")
        .accessibilityLabel("Secondary role")
        .accessibilityValue(secondaryRoleTitle)
        .accessibilityIdentifier("popover.keypress.secondaryRole")
      }
    }
  }

  private var secondaryRoleTitle: String {
    switch store.keypress.secondaryRole {
    case nil: "None"
    case let .layer(layer): "\(layer.displayName) layer"
    case let .modifier(modifier): Self.name(modifier)
    }
  }

  private func setSecondaryRole(_ role: SecondaryRole?) {
    var keypress = store.keypress
    keypress.secondaryRole = role
    store.keypress = keypress
  }

  /// The chosen key's label and name, or "None" (a modifier-only shortcut).
  private var selectedKey: String {
    guard let key = store.keypress.key else { return "None" }
    let label = KeyCapContent.label(for: key, labels: store.labels)
    guard let name = KeyNames.name(for: key), name != label else { return label }
    return "\(label)  \(name)"
  }

  private var results: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 0) {
          let results = store.searchResults
          ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
            if let group = result.group, index == 0 || results[index - 1].group != group {
              Text(group)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }
            row(result)
          }
        }
      }
      .frame(maxHeight: .infinity)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
      .onAppear {
        if let key = store.keypress.key {
          proxy.scrollTo(key, anchor: .center)
        }
      }
    }
  }

  private func row(_ result: KeySearchResult) -> some View {
    let isSelected = result.key == store.keypress.key
    return Button {
      var keypress = store.keypress
      keypress.key = isSelected ? nil : result.key
      store.keypress = keypress
    } label: {
      HStack(spacing: 8) {
        Text(result.label)
          .font(.body.weight(.medium))
          .frame(minWidth: 44, alignment: .leading)
        if let name = result.name, name != result.label {
          Text(name)
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.secondary))
        }
        Spacer(minLength: 0)
      }
      .lineLimit(1)
      .foregroundStyle(isSelected ? Color.white : Color.primary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .id(result.key)
    .accessibilityLabel(result.accessibilityLabel)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("popover.keypress.result.\(result.key)")
  }

  private var modifiers: some View {
    Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
      GridRow {
        Text("Left")
          .foregroundStyle(.secondary)
        ForEach(Self.left, id: \.self, content: toggle)
      }
      GridRow {
        Text("Right")
          .foregroundStyle(.secondary)
        ForEach(Self.right, id: \.self, content: toggle)
      }
    }
    .font(.callout)
  }

  private func toggle(_ modifier: Modifier) -> some View {
    Toggle(isOn: Binding(
      get: { store.keypress.modifiers.contains(Modifiers(modifier)) },
      set: { isOn in
        var keypress = store.keypress
        if isOn {
          keypress.modifiers.insert(Modifiers(modifier))
        } else {
          keypress.modifiers.remove(Modifiers(modifier))
        }
        store.keypress = keypress
      }
    )) {
      Text("\(Self.symbol(modifier)) \(Self.shortName(modifier))")
        .frame(minWidth: 52)
    }
    .toggleStyle(.button)
    .disabled(!store.modifiersEnabled)
    .help(store.modifiersEnabled ? Self.name(modifier) : "Media keys are sent without modifiers")
    .accessibilityLabel(Self.name(modifier))
    .accessibilityIdentifier("popover.keypress.modifier.\(modifier.rawValue)")
  }

  /// Mac order: Control, Option, Shift, Command.
  private static let left: [Modifier] = [.leftControl, .leftOption, .leftShift, .leftCommand]
  private static let right: [Modifier] = [.rightControl, .rightOption, .rightShift, .rightCommand]

  private static func symbol(_ modifier: Modifier) -> String {
    switch modifier {
    case .leftControl, .rightControl: "⌃"
    case .leftOption, .rightOption: "⌥"
    case .leftShift, .rightShift: "⇧"
    case .leftCommand, .rightCommand: "⌘"
    }
  }

  private static func shortName(_ modifier: Modifier) -> String {
    switch modifier {
    case .leftControl, .rightControl: "ctrl"
    case .leftOption, .rightOption: "opt"
    case .leftShift, .rightShift: "shift"
    case .leftCommand, .rightCommand: "cmd"
    }
  }

  static func name(_ modifier: Modifier) -> String {
    KeyNames.name(for: modifier.keyID) ?? modifier.rawValue
  }
}

/// Bordered, or prominent red while recording.
private struct RecordButtonStyle: PrimitiveButtonStyle {
  let isRecording: Bool

  func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
    if isRecording {
      Button(configuration).buttonStyle(.borderedProminent).tint(.red)
    } else {
      Button(configuration).buttonStyle(.bordered)
    }
  }
}

/// Segmented buttons for the four tabs (a `Picker` doesn't expose per-segment identifiers).
private struct TabSelector: View {
  @Binding var selection: KeyActionEditorFeature.State.Tab

  var body: some View {
    HStack(spacing: 2) {
      ForEach(KeyActionEditorFeature.State.Tab.allCases, id: \.self) { tab in
        let isSelected = tab == selection
        Button {
          selection = tab
        } label: {
          Text(Self.title(tab))
            .frame(maxWidth: .infinity)
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
        .accessibilityIdentifier("popover.tab.\(tab.rawValue)")
      }
    }
    .padding(2)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Action type")
  }

  private static func title(_ tab: KeyActionEditorFeature.State.Tab) -> String {
    switch tab {
    case .keypress: "Keypress"
    case .layer: "Layer"
    case .keymap: "Keymap"
    case .none: "None"
    }
  }
}
