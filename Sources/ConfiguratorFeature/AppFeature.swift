import ComposableArchitecture
import Foundation
import KeymapModel
import SharedConfig

/// The configurator window: keymap list, status area, settings.
///
/// When the configuration file can't be loaded the app is read-only: swift-sharing's in-memory
/// value is then the default, and any write would overwrite the user's file. Each child feature
/// checks the shared load error itself before it writes.
@Reducer
public struct AppFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    @Shared(.configuration) public var configuration: Configuration
    public var keymapList: KeymapListFeature.State
    public var macroList: MacroListFeature.State
    /// The selected keymap's editor; `nil` when nothing is selected.
    public var editor: KeymapEditorFeature.State?
    /// The selected macro's editor; `nil` when no macro is selected.
    public var macroEditor: MacroEditorFeature.State?
    public var status: StatusFeature.State
    @Presents public var settings: SettingsFeature.State?
    public var importExport: ImportExportFeature.State

    public init(
      keymapList: KeymapListFeature.State = KeymapListFeature.State(),
      macroList: MacroListFeature.State = MacroListFeature.State(),
      status: StatusFeature.State = StatusFeature.State(),
      settings: SettingsFeature.State? = nil,
      importExport: ImportExportFeature.State = ImportExportFeature.State()
    ) {
      self.keymapList = keymapList
      self.macroList = macroList
      editor = keymapList.selection.flatMap { KeymapEditorFeature.State(keymapID: $0) }
      macroEditor = macroList.selection.flatMap { id in
        macroList.configuration.macros[id: id] != nil ? MacroEditorFeature.State(macroID: id) : nil
      }
      self.status = status
      self.settings = settings
      self.importExport = importExport
      // A selected macro that doesn't exist isn't shown.
      if macroEditor == nil {
        self.macroList.selection = nil
      }
    }

    public var isReadOnly: Bool {
      $configuration.loadError != nil
    }

    public var loadErrorMessage: String? {
      ConfigurationLoadError.message(for: $configuration.loadError)
    }
  }

  public enum Action: Sendable {
    case task
    case keymapList(KeymapListFeature.Action)
    case macroList(MacroListFeature.Action)
    case editor(KeymapEditorFeature.Action)
    case macroEditor(MacroEditorFeature.Action)
    case status(StatusFeature.Action)
    case settingsButtonTapped
    case settings(PresentationAction<SettingsFeature.Action>)
    case importExport(ImportExportFeature.Action)
  }

  @Dependency(\.helperRegistration) var registration

  public init() {}

  public var body: some ReducerOf<Self> {
    // The editors' `ifLet`s wrap every reducer that can close them, so they run first and cancel an
    // editor's effects (e.g. the macro editor's configuration watcher) when its state goes away.
    CombineReducers {
      Scope(state: \.keymapList, action: \.keymapList) {
        KeymapListFeature()
      }
      .onChange(of: \.keymapList.selection) { _, selection in
        Reduce { state, _ in
          state.editor = selection.flatMap { KeymapEditorFeature.State(keymapID: $0) }
          // A keymap and a macro are never selected together.
          if selection != nil {
            state.macroList.selection = nil
            state.macroEditor = nil
          }
          return .none
        }
      }
      Scope(state: \.macroList, action: \.macroList) {
        MacroListFeature()
      }
      .onChange(of: \.macroList.selection) { _, selection in
        Reduce { state, _ in
          if selection != nil {
            state.keymapList.selection = nil
            state.editor = nil
          }
          // A selection whose macro is gone shows nothing rather than a stale editor.
          if let selection, state.configuration.macros[id: selection] != nil {
            state.macroEditor = MacroEditorFeature.State(macroID: selection)
          } else {
            state.macroList.selection = nil
            state.macroEditor = nil
          }
          return .none
        }
      }
      Scope(state: \.status, action: \.status) {
        StatusFeature()
      }
      Scope(state: \.importExport, action: \.importExport) {
        ImportExportFeature()
      }
      Reduce { state, action in
        switch action {
        case .task:
          return .run { send in
            // macOS reports a never-registered service as `.notFound`, so that counts too; a plist that
            // is really missing makes `register()` throw, which is reported below.
            // First launch (or "launch at login" back on): register the helper with launchd.
            @Shared(.launchHelperAtLogin) var launchAtLogin
            if launchAtLogin, needsRegistration(registration.status()) {
              do {
                try registration.register()
              } catch {
                await send(.status(.registrationFailed(HelperRegistrationClient.describe(error))))
              }
            }
            // The root input daemon follows the same rules.
            if launchAtLogin, needsRegistration(registration.daemonStatus()) {
              do {
                try registration.registerDaemon()
              } catch {
                await send(.status(.daemonRegistrationFailed(HelperRegistrationClient.describeDaemon(error))))
              }
            }
            await send(.status(.task))
          }

        case .settingsButtonTapped:
          state.settings = SettingsFeature.State()
          return .none

        case let .importExport(.delegate(.selectKeymap(id))):
          // Through the list, so the editor follows the selection.
          return .send(.keymapList(.binding(.set(\.selection, id))))

        case .macroEditor(.delegate(.macroRemoved)):
          state.macroList.selection = nil
          state.macroEditor = nil
          return .none

        case .keymapList, .macroList, .editor, .macroEditor, .status, .settings, .importExport:
          return .none
        }
      }
    }
    .ifLet(\.editor, action: \.editor) {
      KeymapEditorFeature()
    }
    .ifLet(\.macroEditor, action: \.macroEditor) {
      MacroEditorFeature()
    }
    .ifLet(\.$settings, action: \.settings) {
      SettingsFeature()
    }
  }
}

private func needsRegistration(_ status: HelperRegistrationClient.Status) -> Bool {
  status == .notRegistered || status == .notFound
}
