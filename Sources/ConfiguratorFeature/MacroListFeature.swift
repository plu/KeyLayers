import ComposableArchitecture
import Foundation
import KeymapModel
import SharedConfig

/// The sidebar's macros: add, duplicate, delete.
///
/// Like the keymap list, every mutation is a no-op while the configuration file couldn't be loaded.
@Reducer
public struct MacroListFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    @Shared(.configuration) public var configuration: Configuration
    public var selection: Macro.ID?
    @Presents public var alert: AlertState<Action.Alert>?

    public init(selection: Macro.ID? = nil) {
      self.selection = selection
    }

    public var isReadOnly: Bool {
      $configuration.loadError != nil
    }

    /// "New Macro", then "New Macro 2", "New Macro 3", ...
    func uniqueName(_ base: String) -> String {
      let names = Set(configuration.macros.map(\.name))
      guard names.contains(base) else { return base }
      var number = 2
      while names.contains("\(base) \(number)") {
        number += 1
      }
      return "\(base) \(number)"
    }
  }

  public enum Action: BindableAction, Sendable {
    case binding(BindingAction<State>)
    case addTapped
    case duplicateTapped(Macro.ID)
    case deleteTapped(Macro.ID)
    case alert(PresentationAction<Alert>)

    // The interface nests it here (`MacroListFeature.Action.Alert`), as TCA examples do.
    // swiftlint:disable:next nesting
    public enum Alert: Equatable, Sendable {
      case confirmDelete(Macro.ID)
    }
  }

  @Dependency(\.uuid) var uuid

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .addTapped:
        guard !state.isReadOnly else { return .none }
        let macro = Macro(id: uuid(), name: state.uniqueName("New Macro"), steps: [])
        state.$configuration.withLock { _ = $0.macros.append(macro) }
        state.selection = macro.id
        return .none

      case let .duplicateTapped(id):
        guard !state.isReadOnly, let original = state.configuration.macros[id: id],
              let index = state.configuration.macros.index(id: id)
        else { return .none }
        let copy = Macro(id: uuid(), name: "\(original.name) copy", steps: original.steps)
        state.$configuration.withLock { _ = $0.macros.insert(copy, at: index + 1) }
        state.selection = copy.id
        return .none

      case let .deleteTapped(id):
        guard !state.isReadOnly, let macro = state.configuration.macros[id: id] else { return .none }
        state.alert = .confirmDelete(macro, keyCount: state.configuration.keysUsing(id).count)
        return .none

      case let .alert(.presented(.confirmDelete(id))):
        guard !state.isReadOnly, state.configuration.macros[id: id] != nil else { return .none }
        state.$configuration.withLock { $0.removeMacro(id) }
        if state.selection == id {
          state.selection = nil
        }
        return .none

      case .alert:
        return .none
      }
    }
    .ifLet(\.$alert, action: \.alert)
  }
}

extension AlertState where Action == MacroListFeature.Action.Alert {
  static func confirmDelete(_ macro: Macro, keyCount: Int) -> Self {
    AlertState {
      TextState("Delete “\(macro.name)”?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmDelete(macro.id)) {
        TextState("Delete")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      switch keyCount {
      case 0: TextState("This can't be undone.")
      case 1: TextState("1 key uses this macro and will do nothing. This can't be undone.")
      default: TextState("\(keyCount) keys use this macro and will do nothing. This can't be undone.")
      }
    }
  }
}
