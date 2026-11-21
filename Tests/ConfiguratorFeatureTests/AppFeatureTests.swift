import ComposableArchitecture
@testable import ConfiguratorFeature
import Foundation
import HelperIPC
import KeymapModel
import SharedConfig
import Sharing
import Testing

@MainActor
private func makeStore(_ fakes: Fakes) -> TestStoreOf<AppFeature> {
  TestStore(initialState: fakes.makeState { AppFeature.State() }) {
    AppFeature()
  } withDependencies: {
    fakes.apply(to: &$0)
  }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppFeatureTests {
  @Test func registersHelperOnFirstLaunch() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    let task = await store.send(.task)
    await store.receive(\.status.task)
    await store.receive(\.status.refreshed) {
      $0.status.registration = .enabled
      $0.status.daemonRegistration = .enabled
    }
    #expect(fakes.registrationCalls.value == ["register"])
    await task.cancel()
  }

  @Test func registersDaemonOnFirstLaunch() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    let task = await store.send(.task)
    await store.receive(\.status.task)
    await store.receive(\.status.refreshed) {
      $0.status.registration = .enabled
      $0.status.daemonRegistration = .enabled
    }
    #expect(fakes.daemonCalls.value == ["register"])
    #expect(fakes.registrationCalls.value == ["register"])
    await task.cancel()
  }

  @Test func registersHelperAndDaemonWhenNotFound() async throws {
    let fakes = try Fakes()
    fakes.registrationStatus.setValue(.notFound)
    fakes.daemonStatus.setValue(.notFound)
    let store = makeStore(fakes)

    let task = await store.send(.task)
    await store.receive(\.status.task)
    await store.receive(\.status.refreshed) {
      $0.status.registration = .enabled
      $0.status.daemonRegistration = .enabled
    }
    #expect(fakes.registrationCalls.value == ["register"])
    #expect(fakes.daemonCalls.value == ["register"])
    await task.cancel()
  }

  @Test func doesNotRegisterDaemonWhenAlreadyEnabled() async throws {
    let fakes = try Fakes()
    fakes.daemonStatus.setValue(.enabled)
    let store = makeStore(fakes)

    let task = await store.send(.task)
    await store.receive(\.status.task)
    await store.receive(\.status.refreshed) {
      $0.status.registration = .enabled
      $0.status.daemonRegistration = .enabled
    }
    #expect(fakes.daemonCalls.value.isEmpty)
    await task.cancel()
  }

  @Test func doesNotRegisterAgainWhenAlreadyRegistered() async throws {
    let fakes = try Fakes()
    fakes.registrationStatus.setValue(.requiresApproval)
    let store = makeStore(fakes)

    let task = await store.send(.task)
    await store.receive(\.status.task)
    await store.receive(\.status.refreshed) {
      $0.status.registration = .requiresApproval
      $0.status.daemonRegistration = .enabled
    }
    #expect(fakes.registrationCalls.value.isEmpty)
    await task.cancel()
  }

  @Test func doesNotRegisterWhenLaunchAtLoginIsOff() async throws {
    let fakes = try Fakes()
    fakes.makeState { Shared(.launchHelperAtLogin) }.withLock { $0 = false }
    let store = makeStore(fakes)

    let task = await store.send(.task)
    await store.receive(\.status.task)
    await store.receive(\.status.refreshed) { $0.status.registration = .notRegistered }
    #expect(fakes.registrationCalls.value.isEmpty)
    await task.cancel()
  }

  @Test func settingsArePresentedAndDismissed() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.settingsButtonTapped) {
      $0.settings = fakes.makeState { SettingsFeature.State() }
    }
    await store.send(\.settings.doneTapped)
    await store.receive(\.settings.dismiss) { $0.settings = nil }
  }

  @Test func loadErrorMakesEditorReadOnly() async {
    let corrupt = Data("{".utf8)
    let fakes = Fakes(fileData: corrupt)
    fakes.registrationStatus.setValue(.enabled)
    let store = makeStore(fakes)
    #expect(store.state.isReadOnly)
    #expect(store.state.loadErrorMessage == "The configuration file is damaged and can't be read.")
    #expect(store.state.keymapList.isReadOnly)
    #expect(!store.state.keymapList.canDelete)

    // Every mutation is a no-op: swift-sharing's in-memory value is the default, and saving it
    // would overwrite the user's file.
    await store.send(.keymapList(.addTapped))
    await store.send(.keymapList(.duplicateTapped(Keymap.starterID)))
    await store.send(.keymapList(.setDefaultTapped(Keymap.starterID)))
    await store.send(.keymapList(.deleteTapped(Keymap.starterID)))
    #expect(store.state.editor?.isReadOnly == true)
    await store.send(.editor(.binding(.set(\.name, "Work"))))
    await store.send(.editor(.binding(.set(\.abbreviation, "WRK"))))
    await store.send(.editor(.abbreviationSubmitted))

    await store.send(.settingsButtonTapped) {
      $0.settings = fakes.makeState { SettingsFeature.State() }
    }
    #expect(store.state.settings?.isReadOnly == true)
    await store.send(\.settings.doubleTapTimeoutChanged, 500)
    await store.send(\.settings.showLayerHUDChanged, false)
    await store.send(\.settings.menuBarShowsKeymapChanged, true)
    await store.send(\.settings.menuBarShowsLayerChanged, true)

    // The rest of the app still works.
    let task = await store.send(.task)
    await store.receive(\.status.task)
    await store.receive(\.status.refreshed) {
      $0.status.registration = .enabled
      $0.status.daemonRegistration = .enabled
    }
    await task.cancel()

    #expect(store.state.configuration == .starter)
    #expect(fakes.fileData == corrupt)
  }

  @Test func editorFollowsSelection() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = makeStore(fakes)
    #expect(store.state.editor?.keymap.id == Keymap.starterID)

    await store.send(.keymapList(.binding(.set(\.selection, codingID)))) {
      $0.keymapList.selection = codingID
      $0.editor = fakes.makeState { KeymapEditorFeature.State(keymapID: codingID) }
    }
    await store.send(.keymapList(.binding(.set(\.selection, nil)))) {
      $0.keymapList.selection = nil
      $0.editor = nil
    }
    await store.send(.keymapList(.addTapped)) {
      $0.keymapList.$configuration.withLock {
        _ = $0.keymaps.append(Keymap(id: newID, name: "New Keymap", abbreviation: "NEW"))
      }
      $0.keymapList.selection = newID
      $0.editor = fakes.makeState { KeymapEditorFeature.State(keymapID: newID) }
    }
  }

  @Test func selectingMacroClearsKeymapSelection() async throws {
    var file = Configuration.starter
    let macro = Macro(id: newID, name: "Greet", steps: [])
    file.macros = [macro]
    let fakes = try Fakes(file: file)
    let store = makeStore(fakes)
    #expect(store.state.keymapList.selection == Keymap.starterID)

    await store.send(.macroList(.binding(.set(\.selection, macro.id)))) {
      $0.macroList.selection = macro.id
      $0.keymapList.selection = nil
      $0.editor = nil
      $0.macroEditor = fakes.makeState { MacroEditorFeature.State(macroID: macro.id) }
    }
  }

  @Test func selectingAMissingMacroClearsTheSelection() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)
    let missing = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000B9"))

    await store.send(.macroList(.binding(.set(\.selection, missing)))) {
      $0.keymapList.selection = nil
      $0.editor = nil
    }
  }

  @Test func macroRemovedElsewhereClosesTheEditor() async throws {
    var file = Configuration.starter
    let macro = Macro(id: newID, name: "Greet", steps: [])
    file.macros = [macro]
    let fakes = try Fakes(file: file)
    let store = makeStore(fakes)
    await store.send(.macroList(.binding(.set(\.selection, macro.id)))) {
      $0.macroList.selection = macro.id
      $0.keymapList.selection = nil
      $0.editor = nil
      $0.macroEditor = fakes.makeState { MacroEditorFeature.State(macroID: macro.id) }
    }

    let task = await store.send(.macroEditor(.task)) { $0.macroEditor?.labels = fakes.labels.value }
    // Another process saved the file without the macro.
    store.state.$configuration.withLock { $0.macros = [] }
    await store.receive(\.macroEditor.macroChanged)
    await store.receive(\.macroEditor.delegate.macroRemoved) {
      $0.macroList.selection = nil
      $0.macroEditor = nil
    }
    await task.cancel()
  }

  /// Regression: the editor's configuration watcher must not reach the editor once the list's delete
  /// has closed it (TCA reported an `ifLet` child action with nil state).
  @Test func deletingTheSelectedMacroClosesTheEditorQuietly() async throws {
    var file = Configuration.starter
    let macro = Macro(id: newID, name: "Greet", steps: [])
    file.macros = [macro]
    let fakes = try Fakes(file: file)
    let store = makeStore(fakes)
    await store.send(.macroList(.binding(.set(\.selection, macro.id)))) {
      $0.macroList.selection = macro.id
      $0.keymapList.selection = nil
      $0.editor = nil
      $0.macroEditor = fakes.makeState { MacroEditorFeature.State(macroID: macro.id) }
    }
    let task = await store.send(.macroEditor(.task)) { $0.macroEditor?.labels = fakes.labels.value }

    await store.send(.macroList(.deleteTapped(macro.id))) {
      $0.macroList.alert = .confirmDelete(macro, keyCount: 0)
    }
    await store.send(.macroList(.alert(.presented(.confirmDelete(macro.id))))) {
      $0.macroList.alert = nil
      $0.$configuration.withLock { $0.removeMacro(macro.id) }
      $0.macroList.selection = nil
      $0.macroEditor = nil
    }
    await task.cancel()
    await store.finish()
    #expect(store.state.macroEditor == nil)
    #expect(store.state.macroList.selection == nil)
  }

  @Test func switchingMacrosEditsTheNewOne() async throws {
    var file = Configuration.starter
    let first = Macro(id: newID, name: "Greet", steps: [])
    let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000B2"))
    let second = Macro(id: secondID, name: "Sign", steps: [])
    file.macros = [first, second]
    let fakes = try Fakes(file: file)
    let store = makeStore(fakes)
    await store.send(.macroList(.binding(.set(\.selection, first.id)))) {
      $0.macroList.selection = first.id
      $0.keymapList.selection = nil
      $0.editor = nil
      $0.macroEditor = fakes.makeState { MacroEditorFeature.State(macroID: first.id) }
    }
    let firstTask = await store.send(.macroEditor(.task)) { $0.macroEditor?.labels = fakes.labels.value }

    await store.send(.macroList(.binding(.set(\.selection, second.id)))) {
      $0.macroList.selection = second.id
      $0.macroEditor = fakes.makeState { MacroEditorFeature.State(macroID: second.id) }
    }
    let secondTask = await store.send(.macroEditor(.task)) { $0.macroEditor?.labels = fakes.labels.value }
    #expect(store.state.macroEditor?.name == "Sign")

    // The second editor's task replaced the first macro's watcher: its removal reports nothing and
    // doesn't close the second's editor.
    store.state.$configuration.withLock { _ = $0.macros.remove(id: first.id) }
    await firstTask.cancel()
    await secondTask.cancel()
    #expect(store.state.macroList.selection == second.id)
  }

  @Test func initialMacroSelectionWithoutMacroIsCleared() throws {
    let fakes = try Fakes()
    let state = fakes.makeState {
      AppFeature.State(macroList: MacroListFeature.State(selection: newID))
    }
    #expect(state.macroList.selection == nil)
    #expect(state.macroEditor == nil)
  }

  @Test func selectingKeymapClearsMacroSelection() async throws {
    var file = twoKeymaps()
    let macro = Macro(id: newID, name: "Greet", steps: [])
    file.macros = [macro]
    let fakes = try Fakes(file: file)
    let store = makeStore(fakes)
    await store.send(.macroList(.binding(.set(\.selection, macro.id)))) {
      $0.macroList.selection = macro.id
      $0.keymapList.selection = nil
      $0.editor = nil
      $0.macroEditor = fakes.makeState { MacroEditorFeature.State(macroID: macro.id) }
    }

    await store.send(.keymapList(.binding(.set(\.selection, codingID)))) {
      $0.keymapList.selection = codingID
      $0.editor = fakes.makeState { KeymapEditorFeature.State(keymapID: codingID) }
      $0.macroList.selection = nil
      $0.macroEditor = nil
    }
  }

  @Test func renamingInTheEditorUpdatesTheSidebar() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    let store = makeStore(fakes)

    await store.send(.editor(.binding(.set(\.name, "Work")))) {
      $0.editor?.name = "Work"
      $0.editor?.syncedName = "Work"
      $0.$configuration.withLock { $0.keymaps[id: Keymap.starterID]?.name = "Work" }
    }
    #expect(store.state.keymapList.configuration.keymaps[id: Keymap.starterID]?.name == "Work")
  }

  @Test func newerFormatFileIsReadOnly() async {
    let newer = Data(#"{"formatVersion": 99, "keymaps": []}"#.utf8)
    let fakes = Fakes(fileData: newer)
    let store = makeStore(fakes)
    #expect(store.state.isReadOnly)
    #expect(
      store.state.loadErrorMessage
        == "The configuration file was written by a newer version of KeyLayers (format version 99)."
    )
    await store.send(.keymapList(.addTapped))
    #expect(fakes.fileData == newer)
  }

  @Test func validFileIsEditable() throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)
    #expect(!store.state.isReadOnly)
    #expect(store.state.loadErrorMessage == nil)
  }

  @Test func helperAndDaemonFailuresAreBothShown() async throws {
    let fakes = try Fakes()
    fakes.registrationError.setValue(RegistrationFailure())
    fakes.daemonRegistrationError.setValue(RegistrationFailure())
    let store = makeStore(fakes)

    let task = await store.send(.task)
    await store.receive(\.status.registrationFailed) {
      $0.status.registrationError = "The helper couldn't be enabled: Operation not permitted"
    }
    await store.receive(\.status.daemonRegistrationFailed) {
      $0.status.daemonRegistrationError = "The input service couldn't be enabled: Operation not permitted"
    }
    await store.receive(\.status.task)
    await store.receive(\.status.refreshed) { $0.status.registration = .notRegistered }
    #expect(
      store.state.status.registrationMessage
        == "The helper couldn't be enabled: Operation not permitted\n"
        + "The input service couldn't be enabled: Operation not permitted"
    )
    await task.cancel()
  }
}
