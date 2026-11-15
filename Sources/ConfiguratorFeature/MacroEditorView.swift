import ComposableArchitecture
import KeymapModel
import SwiftUI

/// The detail pane for a macro: its name, an add menu and the steps, which can be dragged by their
/// handle to reorder and deleted with their button or ⌫ once selected.
public struct MacroEditorView: View {
  let store: StoreOf<MacroEditorFeature>
  @State private var selectedStep: Int?
  @FocusState private var stepsFocused: Bool

  public init(store: StoreOf<MacroEditorFeature>) {
    self.store = store
  }

  public var body: some View {
    Group {
      if let macro = store.macro {
        VStack(alignment: .leading, spacing: 0) {
          header
            .padding(16)
          Divider()
          steps(macro.steps)
        }
      } else {
        ContentUnavailableView("No Macro Selected", systemImage: "bolt")
      }
    }
    .task { await store.send(.task).finish() }
  }

  private var header: some View {
    HStack(spacing: 10) {
      TextField("Name", text: Binding(get: { store.name }, set: { store.send(.nameChanged($0)) }))
        .textFieldStyle(.roundedBorder)
        .font(.title3)
        .onSubmit { store.send(.nameSubmitted) }
        .accessibilityLabel("Macro name")
        .accessibilityIdentifier("macro.name")
      Menu {
        Button("Key") { add(.key) }
          .accessibilityIdentifier("macro.add.key")
        Button("Text") { add(.text) }
          .accessibilityIdentifier("macro.add.text")
        Button("Delay") { add(.delay) }
          .accessibilityIdentifier("macro.add.delay")
      } label: {
        Label("Add Step", systemImage: "plus")
      }
      .fixedSize()
      .help("Add a step")
      .accessibilityIdentifier("macro.add")
    }
    .disabled(store.isReadOnly)
  }

  private func add(_ kind: MacroStepKind) {
    store.send(.addStep(kind))
    selectedStep = store.macro.map { $0.steps.count - 1 }
  }

  private func steps(_ steps: [MacroStep]) -> some View {
    // Plain rows rather than `List`, which draws its rows lazily and not in snapshots.
    ScrollView {
      VStack(spacing: 0) {
        if steps.isEmpty {
          Text("No steps yet. Add keys, text and delays with “Add Step”.")
            .foregroundStyle(.secondary)
            .padding(24)
        }
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
          MacroStepRow(
            store: store,
            index: index,
            step: step,
            isSelected: selectedStep == index
          ) {
            selectedStep = index
            stepsFocused = true
          }
          .dropDestination(for: String.self) { items, _ in
            guard let source = items.first.flatMap(Int.init), source != index else { return false }
            // `moveSteps` takes the position before which the step lands.
            store.send(.moveSteps(IndexSet(integer: source), source < index ? index + 1 : index))
            selectedStep = index
            return true
          }
          Divider()
        }
      }
      .padding(.horizontal, 8)
    }
    .focusable()
    .focusEffectDisabled()
    .focused($stepsFocused)
    .onDeleteCommand {
      guard let selectedStep, !store.isReadOnly else { return }
      store.send(.deleteStep(selectedStep))
      self.selectedStep = nil
    }
  }
}

/// One step: drag handle, number, kind and the kind's editor, delete button.
private struct MacroStepRow: View {
  let store: StoreOf<MacroEditorFeature>
  let index: Int
  let step: MacroStep
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: "line.3.horizontal")
        .foregroundStyle(.secondary)
        .frame(width: 16)
        .draggable(String(index))
        .help("Drag to reorder")
        .accessibilityHidden(true)
      Text("\(index + 1)")
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(minWidth: 20, alignment: .trailing)
      Text(kindLabel)
        .fontWeight(.medium)
        .frame(width: 44, alignment: .leading)
      editor
        .disabled(store.isReadOnly)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        store.send(.deleteStep(index))
      } label: {
        Image(systemName: "minus.circle")
      }
      .buttonStyle(.borderless)
      .disabled(store.isReadOnly)
      .help("Delete step")
      .accessibilityLabel("Delete step \(index + 1)")
      .accessibilityIdentifier("macro.step.\(index).delete")
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 8)
    .background(
      isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear,
      in: RoundedRectangle(cornerRadius: 6)
    )
    .contentShape(Rectangle())
    // Simultaneous, so that clicks still reach the row's controls.
    .simultaneousGesture(TapGesture().onEnded(select))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Step \(index + 1), \(kindLabel)")
    .accessibilityIdentifier("macro.step.\(index)")
  }

  private var kindLabel: String {
    switch step {
    case .key: "Key"
    case .text: "Text"
    case .delay: "Delay"
    case .unsupported: "Other"
    }
  }

  @ViewBuilder private var editor: some View {
    switch step {
    case let .key(keyStep):
      KeyStepEditor(store: store, index: index, step: keyStep)
    case let .text(text):
      TextStepEditor(store: store, index: index, text: text)
    case let .delay(milliseconds):
      DelayStepEditor(store: store, index: index, milliseconds: milliseconds)
    case let .unsupported(type):
      Text("Unsupported step")
        .foregroundStyle(.secondary)
        .help("A “\(type)” step from a newer version of KeyLayers. It's kept as it is.")
    }
  }
}

/// Tap / press / release, the key (picked from a searchable list or recorded) and its modifiers.
private struct KeyStepEditor: View {
  let store: StoreOf<MacroEditorFeature>
  let index: Int
  let step: KeyStep
  @State private var isPicking = false
  @State private var searchText = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Picker("Kind", selection: Binding(get: { step.kind }, set: { kind in write { $0.kind = kind } })) {
          Text("Tap").tag(KeyStep.Kind.tap)
          Text("Press").tag(KeyStep.Kind.press)
          Text("Release").tag(KeyStep.Kind.release)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("macro.step.\(index).kind")
        Button(keyTitle) { isPicking = true }
          .help("Choose the key")
          .accessibilityLabel("Key: \(keyTitle)")
          .accessibilityIdentifier("macro.step.\(index).key")
          .popover(isPresented: $isPicking, arrowEdge: .bottom) { picker }
        let isRecording = store.recordingStep == index
        Button {
          store.send(.recordTapped(index))
        } label: {
          Label(isRecording ? "Press a key…" : "Record", systemImage: "record.circle")
        }
        .buttonStyle(RecordButtonStyle(isRecording: isRecording))
        .help("Record the next key you press")
        .accessibilityIdentifier("macro.step.\(index).record")
      }
      ModifierToggles(
        modifiers: Binding(get: { step.modifiers }, set: { modifiers in write { $0.modifiers = modifiers } }),
        identifierPrefix: "macro.step.\(index)"
      )
      .controlSize(.small)
    }
  }

  private var picker: some View {
    VStack(spacing: 8) {
      TextField("Search keys", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("macro.step.\(index).search")
      KeyPickerList(
        results: KeySearchResult.search(searchText, labels: store.labels),
        selection: step.key,
        identifierPrefix: "macro.step.\(index)"
      ) { key in
        write { $0.key = key }
        isPicking = false
      }
    }
    .padding(10)
    .frame(width: 280, height: 320)
  }

  /// The chosen key's label and name, or "No Key" (a modifier-only stroke).
  private var keyTitle: String {
    guard let key = step.key else { return "No Key" }
    let label = KeyCapContent.label(for: key, labels: store.labels)
    guard let name = KeyNames.name(for: key), name != label else { return label }
    return "\(label)  \(name)"
  }

  /// Writes the step with `change` applied.
  private func write(_ change: (inout KeyStep) -> Void) {
    var updated = step
    change(&updated)
    store.send(.stepChanged(index, .key(updated)))
  }
}

/// The text field, with the characters the current layout can't type.
private struct TextStepEditor: View {
  let store: StoreOf<MacroEditorFeature>
  let index: Int
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField(
        "Text to type",
        text: Binding(get: { text }, set: { store.send(.stepChanged(index, .text($0))) })
      )
      .textFieldStyle(.roundedBorder)
      .accessibilityIdentifier("macro.step.\(index).text")
      let untypeable = MacroEditorFeature().untypeable(text)
      if !untypeable.isEmpty {
        Label(
          "Can't be typed on this layout: \(untypeable.map(String.init).joined(separator: " "))",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.callout)
        .foregroundStyle(.orange)
        .accessibilityIdentifier("macro.step.\(index).warning")
      }
    }
  }
}

/// The delay in milliseconds: a number field and a stepper.
private struct DelayStepEditor: View {
  let store: StoreOf<MacroEditorFeature>
  let index: Int
  let milliseconds: Int

  var body: some View {
    let value = Binding(get: { milliseconds }, set: { store.send(.stepChanged(index, .delay(milliseconds: $0))) })
    HStack(spacing: 6) {
      TextField("Milliseconds", value: value, format: .number)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 80)
        .accessibilityIdentifier("macro.step.\(index).milliseconds")
      Stepper("Milliseconds", value: value, in: 0 ... 60000, step: 10)
        .labelsHidden()
      Text("ms")
        .foregroundStyle(.secondary)
    }
  }
}
