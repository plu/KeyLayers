import ComposableArchitecture
import Foundation
import KeyboardLayout
import KeymapModel
import SharedConfig

/// The main area: the selected keymap's name and abbreviation, the layer selector and the keyboard
/// drawing with each key's action on that layer.
@Reducer
public struct KeymapEditorFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    @Shared public var keymap: Keymap
    @Shared(.configuration) var configuration: Configuration
    @Shared(.appStorage("selectedKeyboard")) public var selectedKeyboard: KeyboardKind = .fallback
    public var layer: LayerName = .base
    public var detected: [DetectedKeyboard] = []
    public var labels: [KeyID: String] = [:]
    /// The name and abbreviation fields. They're drafts so that edits pass the read-only guard
    /// and the abbreviation is written only once it's committed.
    public var name: String
    public var abbreviation: String
    /// The keymap's name and abbreviation when the drafts were last synced from (or written to)
    /// it. A draft that still equals its synced value hasn't been edited.
    var syncedName: String
    var syncedAbbreviation: String
    /// The popover editing a key's action on `layer`.
    @Presents public var keyAction: KeyActionEditorFeature.State?

    public init(keymap: Shared<Keymap>) {
      _keymap = keymap
      name = keymap.wrappedValue.name
      abbreviation = keymap.wrappedValue.abbreviation
      syncedName = keymap.wrappedValue.name
      syncedAbbreviation = keymap.wrappedValue.abbreviation
    }

    public init?(keymapID: Keymap.ID) {
      @Shared(.configuration) var configuration
      guard let keymap = Shared($configuration.keymaps[id: keymapID]) else { return nil }
      self.init(keymap: keymap)
    }

    public var isReadOnly: Bool {
      $configuration.loadError != nil
    }

    /// Takes the keymap's name and abbreviation into the drafts that aren't being edited.
    mutating func syncDrafts(from keymap: Keymap) {
      if name == syncedName {
        name = keymap.name
      }
      if abbreviation == syncedAbbreviation {
        abbreviation = keymap.abbreviation
      }
      syncedName = keymap.name
      syncedAbbreviation = keymap.abbreviation
    }

    /// Writes an edited name; while read-only, reverts it instead.
    mutating func commitName() {
      guard !isReadOnly else {
        name = keymap.name
        syncedName = keymap.name
        return
      }
      guard name != syncedName else { return }
      let name = name
      $keymap.withLock { $0.name = name }
      syncedName = name
    }

    /// Writes an edited abbreviation, normalized. An unedited, empty or read-only one is reset to
    /// the keymap's, so a stale draft never overwrites a newer abbreviation.
    mutating func commitAbbreviation() {
      let normalized = Keymap.normalizedAbbreviation(abbreviation)
      guard !isReadOnly, !normalized.isEmpty, abbreviation != syncedAbbreviation else {
        abbreviation = keymap.abbreviation
        syncedAbbreviation = keymap.abbreviation
        return
      }
      if normalized != keymap.abbreviation {
        $keymap.withLock { $0.abbreviation = normalized }
      }
      abbreviation = normalized
      syncedAbbreviation = normalized
    }
  }

  public enum Action: BindableAction, Sendable {
    case binding(BindingAction<State>)
    case task
    case labelsChanged([KeyID: String])
    case keyTapped(KeyID)
    case abbreviationSubmitted
    /// The keymap changed underneath the editor (another process saved the file, or it loaded).
    case keymapChanged(Keymap)
    case keyAction(PresentationAction<KeyActionEditorFeature.Action>)
  }

  @Dependency(\.keyboardDetection) var keyboardDetection
  @Dependency(\.keyLabels) var keyLabels

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding(\.name):
        state.commitName()
        return .none

      case .binding(\.abbreviation):
        // Written on commit (`abbreviationSubmitted`), once it's normalized.
        if state.isReadOnly {
          state.abbreviation = state.keymap.abbreviation
        }
        return .none

      case .abbreviationSubmitted:
        state.commitAbbreviation()
        return .none

      case .binding:
        return .none

      case .task:
        let keyboards = keyboardDetection.keyboards()
        state.detected = keyboards
        if let first = keyboards.first, !keyboards.contains(where: { $0.kind == state.selectedKeyboard }) {
          state.$selectedKeyboard.withLock { $0 = first.kind }
        }
        state.labels = keyLabels.labels()
        state.syncDrafts(from: state.keymap)
        let keymap = state.$keymap
        return .merge(
          .run { send in
            for await _ in keyLabels.changes() {
              await send(.labelsChanged(keyLabels.labels()))
            }
          },
          // The publisher starts with the current value, which `syncDrafts` just took. It emits a new
          // value before the shared reference returns it, so the value travels in the action.
          .publisher { keymap.publisher.removeDuplicates().dropFirst().map(Action.keymapChanged) }
        )

      case let .labelsChanged(labels):
        state.labels = labels
        return .none

      case let .keymapChanged(keymap):
        state.syncDrafts(from: keymap)
        return .none

      case let .keyTapped(key):
        var popover = KeyActionEditorFeature.State(
          key: key,
          layer: state.layer,
          action: state.keymap.action(for: key, on: state.layer),
          keymaps: state.configuration.keymaps.elements,
          macros: state.configuration.macros.elements
        )
        popover.labels = state.labels
        // While the configuration can't be loaded the popover only shows the action.
        popover.isReadOnly = state.isReadOnly
        state.keyAction = popover
        return .none

      case let .keyAction(.presented(.delegate(.apply(action)))):
        guard !state.isReadOnly, let popover = state.keyAction else { return .none }
        state.$keymap.withLock { $0.setAction(action, for: popover.key, on: popover.layer) }
        state.keyAction = nil
        return .none

      case .keyAction:
        return .none
      }
    }
    .ifLet(\.$keyAction, action: \.keyAction) {
      KeyActionEditorFeature()
    }
  }
}
