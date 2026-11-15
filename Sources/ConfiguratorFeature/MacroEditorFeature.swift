import ComposableArchitecture
import Foundation
import HelperIPC
import KeyboardLayout
import KeymapModel
import SharedConfig

/// What the editor's add menu appends.
public enum MacroStepKind: Sendable, CaseIterable {
  case key, text, delay
}

/// The detail pane for the selected macro: its name and its steps (add, edit, delete, reorder).
///
/// Edits write the shared configuration immediately; while it couldn't be loaded every edit is
/// ignored. Steps of a type this version doesn't know are kept as they are.
@Reducer
public struct MacroEditorFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Identifiable {
    public let macroID: Macro.ID
    @Shared(.configuration) var configuration: Configuration
    /// The name field. A draft, so that it can be empty while typing; the saved name never is.
    public var name: String
    /// The step whose key is being recorded.
    public var recordingStep: Int?
    /// Key labels of the current input source, for the key picker.
    public var labels: [KeyID: String] = [:]
    /// The characters each Text step (by index) can't type on the current input source; only steps
    /// with any are listed. Recomputed when the steps or the input source change.
    public var untypeable: [Int: [Character]] = [:]

    public init(macroID: Macro.ID) {
      self.macroID = macroID
      @Shared(.configuration) var configuration
      name = configuration.macros[id: macroID]?.name ?? ""
    }

    /// Identifies the editor by its macro, so that the parent's `ifLet` cancels the effects of the
    /// previous macro's editor when another macro is selected.
    public var id: Macro.ID {
      macroID
    }

    /// The macro being edited; `nil` once it's gone (deleted, or the file was reloaded without it).
    public var macro: Macro? {
      configuration.macros[id: macroID]
    }

    public var isReadOnly: Bool {
      $configuration.loadError != nil
    }

    /// Changes the macro's steps, unless read-only or the macro is gone.
    mutating func editSteps(_ edit: (inout [MacroStep]) -> Void) {
      guard !isReadOnly, macro != nil else { return }
      let id = macroID
      $configuration.withLock { configuration in
        guard var macro = configuration.macros[id: id] else { return }
        edit(&macro.steps)
        configuration.macros[id: id] = macro
      }
    }
  }

  public enum Action: Sendable {
    case task
    case labelsChanged([KeyID: String])
    /// The macro with this ID changed underneath the editor (another process saved the file, or it
    /// loaded). The ID guards against a watcher started for a previously edited macro.
    case macroChanged(Macro.ID, Macro?)
    case nameChanged(String)
    /// The name field was committed: an empty draft shows the saved name again.
    case nameSubmitted
    case addStep(MacroStepKind)
    case deleteStep(Int)
    case moveSteps(IndexSet, Int)
    case stepChanged(Int, MacroStep)
    case recordTapped(Int)
    case recorded(Int, KeyID?)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable { // swiftlint:disable:this nesting
      /// The macro no longer exists; the editor should close.
      case macroRemoved
    }
  }

  @Dependency(\.helperClient) var helper
  @Dependency(\.keyRecorder) var recorder
  @Dependency(\.continuousClock) var clock
  @Dependency(\.keyLabels) var keyLabels
  @Dependency(\.textKeystrokes) var textKeystrokes

  private enum CancelID { case task, recording }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        state.labels = keyLabels.labels()
        refreshUntypeable(&state)
        let macroID = state.macroID
        let configuration = state.$configuration
        return .merge(
          .run { [keyLabels, textKeystrokes] send in
            for await _ in keyLabels.changes() {
              // The text table first, so that the untypeable characters follow the new input source.
              await textKeystrokes.refresh()
              await send(.labelsChanged(keyLabels.labels()))
            }
          },
          // The value travels in the action: the publisher emits before the shared reference returns it.
          // Awaited rather than a `.publisher` effect: a change made while another action is reduced
          // (the list deleting this macro) would otherwise be delivered synchronously, after the parent
          // already closed the editor. Through `send`, a cancelled watcher never delivers.
          .run { send in
            let changes = configuration.publisher
              .map { $0.macros[id: macroID] }
              .removeDuplicates()
              .dropFirst()
              // Holds the latest change while `send` is awaited.
              .buffer(size: 1, prefetch: .keepFull, whenFull: .dropOldest)
            for await macro in changes.values {
              await send(.macroChanged(macroID, macro))
            }
          }
        )
        // A new `.task` replaces the old watchers. The parent's `ifLet` cancels them when it closes the
        // editor or switches it to another macro.
        .cancellable(id: CancelID.task, cancelInFlight: true)

      case let .labelsChanged(labels):
        state.labels = labels
        refreshUntypeable(&state)
        return .none

      case let .macroChanged(id, macro):
        guard id == state.macroID else { return .none }
        refreshUntypeable(&state)
        guard let macro else {
          return .merge(.cancel(id: CancelID.recording), .send(.delegate(.macroRemoved)))
        }
        // A non-empty draft that isn't the saved name was renamed elsewhere; an empty one is being typed.
        let draft = state.name.trimmingCharacters(in: .whitespaces)
        if !draft.isEmpty, draft != macro.name {
          state.name = macro.name
        }
        return .none

      case let .nameChanged(name):
        guard !state.isReadOnly, let macro = state.macro else {
          state.name = state.macro?.name ?? ""
          return .none
        }
        state.name = name
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != macro.name {
          let id = state.macroID
          state.$configuration.withLock { $0.macros[id: id]?.name = trimmed }
        }
        return .none

      case .nameSubmitted:
        state.name = state.macro?.name ?? ""
        return .none

      case let .addStep(kind):
        state.editSteps { $0.append(kind.newStep) }
        refreshUntypeable(&state)
        return .none

      case let .deleteStep(index):
        guard !state.isReadOnly, state.macro?.steps.indices.contains(index) == true else { return .none }
        state.editSteps { $0.remove(at: index) }
        refreshUntypeable(&state)
        return stopRecording(&state)

      case let .moveSteps(source, destination):
        guard !state.isReadOnly, let count = state.macro?.steps.count,
              source.allSatisfy({ $0 < count }), (0 ... count).contains(destination)
        else { return .none }
        state.editSteps { $0.moveElements(at: source, to: destination) }
        refreshUntypeable(&state)
        return stopRecording(&state)

      case let .stepChanged(index, step):
        guard let steps = state.macro?.steps, steps.indices.contains(index) else { return .none }
        // Steps of an unknown type are never replaced, and nothing becomes one.
        if case .unsupported = steps[index] {
          return .none
        }
        if case .unsupported = step {
          return .none
        }
        state.editSteps { $0[index] = step.normalized }
        refreshUntypeable(&state)
        return .none

      case let .recordTapped(index):
        guard !state.isReadOnly, state.recordingStep == nil, let steps = state.macro?.steps,
              steps.indices.contains(index), case .key = steps[index]
        else { return .none }
        state.recordingStep = index
        return .run { [helper, recorder, clock] send in
          let key = await KeyActionEditorFeature.recordKey(helper: helper, recorder: recorder, clock: clock)
          await send(.recorded(index, key))
        }
        .cancellable(id: CancelID.recording, cancelInFlight: true)

      case let .recorded(index, key):
        state.recordingStep = nil
        guard let key, let steps = state.macro?.steps, steps.indices.contains(index),
              case var .key(step) = steps[index]
        else { return .none }
        step.key = key
        state.editSteps { $0[index] = .key(step) }
        return .none

      case .delegate:
        return .none
      }
    }
  }

  /// Stops a recording whose step index may no longer point at the same step.
  private func stopRecording(_ state: inout State) -> Effect<Action> {
    guard state.recordingStep != nil else { return .none }
    state.recordingStep = nil
    return .cancel(id: CancelID.recording)
  }

  /// Recomputes `untypeable` from the macro's steps and the current input source.
  private func refreshUntypeable(_ state: inout State) {
    var result: [Int: [Character]] = [:]
    for (index, step) in (state.macro?.steps ?? []).enumerated() {
      if case let .text(text) = step {
        let characters = untypeable(text)
        if !characters.isEmpty {
          result[index] = characters
        }
      }
    }
    state.untypeable = result
  }

  /// The characters of `text` the current input source can't type, each once, in order of appearance.
  public func untypeable(_ text: String) -> [Character] {
    var seen = Set<Character>()
    return Array(text).filter { character in
      textKeystrokes.strokes(character) == nil && seen.insert(character).inserted
    }
  }
}

extension MacroStepKind {
  /// The step the add menu appends.
  var newStep: MacroStep {
    switch self {
    case .key: .key(KeyStep(key: nil, modifiers: [], kind: .tap))
    case .text: .text("")
    case .delay: .delay(milliseconds: 100)
    }
  }
}

private extension MacroStep {
  /// A delay never waits a negative time.
  var normalized: MacroStep {
    if case let .delay(milliseconds) = self, milliseconds < 0 {
      return .delay(milliseconds: 0)
    }
    return self
  }
}

private extension Array {
  /// Moves the elements at `source` so that they end up before the element that was at
  /// `destination`, as `List`'s `onMove` reports it.
  mutating func moveElements(at source: IndexSet, to destination: Int) {
    let moving = source.map { self[$0] }
    let insertion = destination - source.count(in: 0 ..< destination)
    for index in source.reversed() {
      remove(at: index)
    }
    insert(contentsOf: moving, at: insertion)
  }
}
