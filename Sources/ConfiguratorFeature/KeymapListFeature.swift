import ComposableArchitecture
import Foundation
import KeymapModel
import SharedConfig

/// The sidebar: the keymaps, with add, duplicate, delete and set default.
///
/// While the configuration file couldn't be loaded, every mutation is a no-op: the in-memory value
/// is then swift-sharing's default, and saving it would overwrite the user's file.
@Reducer
public struct KeymapListFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    @Shared(.configuration) public var configuration: Configuration
    public var selection: Keymap.ID?
    @Presents public var alert: AlertState<Action.Alert>?

    /// `selection` defaults to the default keymap.
    public init(selection: Keymap.ID? = nil) {
      self.selection = selection
      if selection == nil {
        self.selection = configuration.defaultKeymapID
      }
    }

    public var isReadOnly: Bool {
      $configuration.loadError != nil
    }

    var abbreviations: Set<String> {
      Set(configuration.keymaps.map(\.abbreviation))
    }

    /// The last keymap can't be deleted.
    public var canDelete: Bool {
      !isReadOnly && configuration.keymaps.count > 1
    }
  }

  public enum Action: BindableAction, Sendable {
    case binding(BindingAction<State>)
    case addTapped
    case duplicateTapped(Keymap.ID)
    case deleteTapped(Keymap.ID)
    case setDefaultTapped(Keymap.ID)
    case alert(PresentationAction<Alert>)

    // The interface nests it here (`KeymapListFeature.Action.Alert`), as TCA examples do.
    // swiftlint:disable:next nesting
    public enum Alert: Equatable, Sendable {
      case confirmDelete(Keymap.ID)
    }
  }

  @Dependency(\.uuid) var uuid

  /// `base`, or if that's taken its first two characters plus the first free digit 2…9
  /// ("NEW" → "NE2"); `base` again when all of those are taken too.
  static func uniqueAbbreviation(_ base: String, existing: Set<String>) -> String {
    guard existing.contains(base) else { return base }
    let prefix = base.prefix(2)
    return (2 ... 9).lazy.map { "\(prefix)\($0)" }.first { !existing.contains($0) } ?? base
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .addTapped:
        guard !state.isReadOnly else { return .none }
        let abbreviation = Self.uniqueAbbreviation("NEW", existing: state.abbreviations)
        let keymap = Keymap(id: uuid(), name: "New Keymap", abbreviation: abbreviation, layers: [:])
        state.$configuration.withLock { _ = $0.keymaps.append(keymap) }
        state.selection = keymap.id
        return .none

      case let .duplicateTapped(id):
        guard !state.isReadOnly, let original = state.configuration.keymaps[id: id],
              let index = state.configuration.keymaps.index(id: id)
        else { return .none }
        var copy = original
        copy.id = uuid()
        copy.name = "\(original.name) Copy"
        copy.abbreviation = Self.uniqueAbbreviation(original.abbreviation, existing: state.abbreviations)
        state.$configuration.withLock { _ = $0.keymaps.insert(copy, at: index + 1) }
        state.selection = copy.id
        return .none

      case let .deleteTapped(id):
        guard state.canDelete, let keymap = state.configuration.keymaps[id: id] else { return .none }
        state.alert = .confirmDelete(keymap)
        return .none

      case let .alert(.presented(.confirmDelete(id))):
        guard state.canDelete, state.configuration.keymaps[id: id] != nil else { return .none }
        state.$configuration.withLock { configuration in
          configuration.keymaps.remove(id: id)
          if configuration.defaultKeymapID == id {
            configuration.defaultKeymapID = configuration.keymaps[0].id
          }
        }
        if state.selection == id {
          state.selection = state.configuration.defaultKeymapID
        }
        return .none

      case .alert:
        return .none

      case let .setDefaultTapped(id):
        guard !state.isReadOnly, state.configuration.keymaps[id: id] != nil,
              state.configuration.defaultKeymapID != id
        else { return .none }
        state.$configuration.withLock { $0.defaultKeymapID = id }
        return .none
      }
    }
    .ifLet(\.$alert, action: \.alert)
  }
}

extension AlertState where Action == KeymapListFeature.Action.Alert {
  static func confirmDelete(_ keymap: Keymap) -> Self {
    AlertState {
      TextState("Delete “\(keymap.name)”?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmDelete(keymap.id)) {
        TextState("Delete")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("Keys that switch to this keymap will do nothing. This can't be undone.")
    }
  }
}
