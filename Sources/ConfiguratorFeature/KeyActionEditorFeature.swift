import ComposableArchitecture
import Foundation
import HelperIPC
import KeymapModel

/// The key action popover: chooses what one key does on one layer (Keypress, Layer, Keymap or
/// None), as in UHK Agent. The editor that presents it writes the result.
@Reducer
public struct KeyActionEditorFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    // swiftlint:disable:next nesting
    public enum Tab: String, CaseIterable, Sendable {
      case keypress, layer, keymap, none
    }

    public let key: KeyID
    public let layer: LayerName
    public var tab: Tab
    public var keypress: Keypress = .init(key: nil, modifiers: [])
    public var searchText = ""
    public var isRecording = false
    public var targetLayer: LayerName = .mod
    public var layerMode: LayerSwitchMode = .holdAndDoubleTapToggle
    public var targetKeymap: Keymap.ID?
    public var noneIsBlock = false
    /// For the Keymap tab's picker.
    public var keymaps: [Keymap]
    /// Key labels of the current input source, for the key picker.
    public var labels: [KeyID: String] = [:]
    /// The configuration couldn't be loaded: the popover shows the action but can't apply.
    public var isReadOnly = false

    /// Opens on the tab of `action`, prefilled with it; with no action (or one this version
    /// doesn't support) on the Keypress tab.
    public init(key: KeyID, layer: LayerName, action: KeyAction?, keymaps: [Keymap]) {
      self.key = key
      self.layer = layer
      self.keymaps = keymaps
      switch action {
      case let .keypress(keypress):
        tab = .keypress
        self.keypress = keypress
      case let .switchLayer(target, mode):
        tab = .layer
        targetLayer = target
        layerMode = mode
      case let .switchKeymap(id):
        tab = .keymap
        targetKeymap = id
      case .block:
        tab = .none
        noneIsBlock = true
      case .unsupported, nil:
        tab = .keypress
      }
      dropModifiersOfMediaKey()
    }

    /// False while the chosen key is a media key: those are sent without modifiers, so the
    /// toggles are disabled.
    public var modifiersEnabled: Bool {
      !(keypress.key.map(KeyID.mediaKeys.contains) ?? false)
    }

    /// Clears the modifiers of a media keypress, which would otherwise be dropped silently when sent.
    mutating func dropModifiersOfMediaKey() {
      if !modifiersEnabled {
        keypress.modifiers = []
      }
    }

    /// False while read-only, for a keypress with neither key nor modifiers, and for the Keymap
    /// tab without a target.
    public var canApply: Bool {
      guard !isReadOnly else { return false }
      switch tab {
      case .keypress: return keypress.key != nil || !keypress.modifiers.isEmpty
      case .keymap: return targetKeymap != nil
      case .layer, .none: return true
      }
    }

    /// The action Apply writes; `nil` removes the key's action (transparent).
    var action: KeyAction? {
      switch tab {
      case .keypress: .keypress(keypress)
      case .layer: .switchLayer(targetLayer, mode: layerMode)
      case .keymap: targetKeymap.map(KeyAction.switchKeymap)
      case .none: noneIsBlock ? .block : nil
      }
    }

    /// `KeyID.allKnown` whose label or name contains `searchText`; keys whose label is exactly
    /// the search text come first.
    public var searchResults: [KeySearchResult] {
      let all = KeyID.allKnown.map { key in
        KeySearchResult(
          key: key,
          label: KeyCapContent.label(for: key, labels: labels),
          name: KeyNames.name(for: key),
          group: KeyID.mediaKeys.contains(key) ? "Media" : nil
        )
      }
      let query = searchText.trimmingCharacters(in: .whitespaces)
      guard !query.isEmpty else { return all }
      let matches = all.filter {
        $0.label.localizedCaseInsensitiveContains(query) || $0.name?.localizedCaseInsensitiveContains(query) == true
      }
      let exact = matches.filter { $0.label.localizedCaseInsensitiveCompare(query) == .orderedSame }
      return exact + matches.filter { $0.label.localizedCaseInsensitiveCompare(query) != .orderedSame }
    }
  }

  public enum Action: BindableAction, Sendable {
    case binding(BindingAction<State>)
    case recordTapped
    case recorded(KeyID?)
    case applyTapped
    case cancelTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable, Sendable { // swiftlint:disable:this nesting
      case apply(KeyAction?)
    }
  }

  @Dependency(\.helperClient) var helper
  @Dependency(\.keyRecorder) var recorder
  @Dependency(\.continuousClock) var clock
  @Dependency(\.dismiss) var dismiss

  /// How long recording waits for the helper's state before it records without pausing it.
  static let helperStateTimeout: Duration = .seconds(1)
  /// How long the resume request waits for the pause request's reply before it's sent anyway.
  static let pauseReplyTimeout: Duration = .seconds(1)

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding(\.keypress):
        state.dropModifiersOfMediaKey()
        return .none

      case .binding:
        return .none

      case .recordTapped:
        guard !state.isRecording else { return .none }
        state.isRecording = true
        return .run { [helper, recorder, clock] send in
          // Pausing lets keys reach the recorder unmapped, not as whatever the keymap turns them into. Both requests
          // are fire-and-forget: a wedged helper may never reply, and recording must not wait.
          let pause = await Self.helperNeedsPause(helper, clock: clock)
          let pauseRequest: Task<Void, Never>? = pause ? Task { try? await helper.setPaused(true) } : nil
          if pauseRequest != nil {
            await Task.yield()
          }
          let key = await recorder.record()
          if let pauseRequest {
            // Resume after the pause request is answered (or given up on), so it can't overtake it.
            // Unstructured, so it's sent even when recording was cancelled.
            Task {
              await Self.waitForReply(to: pauseRequest, clock: clock)
              try? await helper.setPaused(false)
            }
            await Task.yield()
          }
          await send(.recorded(key))
        }

      case let .recorded(key):
        state.isRecording = false
        if let key {
          state.keypress.key = key
          state.dropModifiersOfMediaKey()
        }
        return .none

      case .applyTapped:
        guard state.canApply else { return .none }
        return .send(.delegate(.apply(state.action)))

      case .cancelTapped:
        return .run { _ in await dismiss() }

      case .delegate:
        return .none
      }
    }
  }

  /// Returns when `request` finishes or after `pauseReplyTimeout`, whichever comes first.
  private static func waitForReply(to request: Task<Void, Never>, clock: any Clock<Duration>) async {
    // Not a task group: it would wait for all its children, and `request.value` can't be
    // cancelled, so a wedged helper would hold it forever.
    let (done, finish) = AsyncStream.makeStream(of: Void.self)
    Task {
      await request.value
      finish.finish()
    }
    let timer = Task {
      try? await clock.sleep(for: pauseReplyTimeout)
      finish.finish()
    }
    for await _ in done {}
    timer.cancel()
  }

  /// Whether the helper is running and not paused, by its first reported state; `false` if it
  /// doesn't report one within `helperStateTimeout`.
  private static func helperNeedsPause(_ helper: HelperClient, clock: any Clock<Duration>) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        for await state in helper.states() {
          if case let .running(status) = state {
            return !status.isPaused
          }
          return false
        }
        return false
      }
      group.addTask {
        try? await clock.sleep(for: helperStateTimeout)
        return false
      }
      let needsPause = await group.next() ?? false
      group.cancelAll()
      return needsPause
    }
  }
}

/// A row of the key picker.
public struct KeySearchResult: Equatable, Identifiable, Sendable {
  public var key: KeyID
  /// The cap label: from the input source, else the static symbol, else the key ID.
  public var label: String
  /// The English name, for keys whose label alone is ambiguous.
  public var name: String?
  /// The picker section header this key sits under (`nil`: the ungrouped main list).
  public var group: String?

  public var id: KeyID {
    key
  }

  /// What VoiceOver reads: just the name for glyph-labelled media keys, else "label, name".
  var accessibilityLabel: String {
    if group != nil, let name { return name }
    return name.map { "\(label), \($0)" } ?? label
  }
}
