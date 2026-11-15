import AppKit
import ComposableArchitecture
@testable import ConfiguratorFeature
import HelperIPC
import KeyboardLayout
import KeymapModel
import SharedConfig
import SnapshotTesting
import SwiftUI
import Testing

/// The editor's labels as its `.task` would load them (it doesn't run in a snapshot).
private func withUSLabels(_ state: AppFeature.State) -> AppFeature.State {
  var state = state
  state.editor?.labels = StaticKeyLabels.usANSI
  return state
}

@MainActor
struct ShellSnapshotTests {
  @Test func appWindow() throws {
    let store = try makeStore(AppFeature(), dependencies: fixedDependencies()) {
      withUSLabels(AppFeature.State(status: StatusFeature.State(
        helper: .running(HelperStatus(activeKeymapID: Keymap.starterID, permissions: granted)),
        registration: .enabled,
        daemonRegistration: .enabled
      )))
    }
    assertBothAppearances(AppView(store: store), size: CGSize(width: 1000, height: 700))
  }

  @Test func appWindowWithMacroSelected() throws {
    let store = try makeStore(AppFeature(), dependencies: fixedDependencies(macros: [coffeeMacro])) {
      var state = AppFeature.State(
        macroList: MacroListFeature.State(selection: coffeeMacroID),
        status: StatusFeature.State(
          helper: .running(HelperStatus(activeKeymapID: Keymap.starterID, permissions: granted)),
          registration: .enabled,
          daemonRegistration: .enabled
        )
      )
      // Like selecting the macro in the sidebar: the keymap is deselected.
      state.keymapList.selection = nil
      state.editor = nil
      state.macroEditor?.labels = StaticKeyLabels.usANSI
      state.macroEditor?.untypeable = coffeeUntypeable
      return state
    }
    assertBothAppearances(AppView(store: store), size: CGSize(width: 1000, height: 700))
  }

  @Test func appWindowReadOnly() throws {
    let store = try makeStore(AppFeature(), dependencies: fixedDependencies(fileData: Data("{".utf8))) {
      withUSLabels(AppFeature.State(status: StatusFeature.State(helper: .notRunning, registration: .enabled, daemonRegistration: .enabled)))
    }
    assertBothAppearances(AppView(store: store), size: CGSize(width: 1000, height: 700))
  }

  @MainActor private static let statuses: [String: StatusFeature.State] = [
    "notRunning": StatusFeature.State(helper: .notRunning, registration: .enabled, daemonRegistration: .enabled),
    "needsApproval": StatusFeature.State(helper: .notRunning, registration: .requiresApproval),
    "permissionsMissing": StatusFeature.State(
      helper: .running(HelperStatus(permissions: PermissionStatus(accessibility: false))),
      registration: .enabled,
      daemonRegistration: .enabled
    ),
    "running": StatusFeature.State(helper: .running(HelperStatus(permissions: granted)), registration: .enabled, daemonRegistration: .enabled),
    "inputServiceNeedsInputMonitoring": StatusFeature.State(
      helper: .running(HelperStatus(permissions: granted, inputServiceNeedsInputMonitoring: true)),
      registration: .enabled,
      daemonRegistration: .enabled,
      remappedKeyboards: ["Apple Internal Keyboard / Trackpad"]
    ),
    "paused": StatusFeature.State(
      helper: .running(HelperStatus(
        isPaused: true,
        permissions: granted,
        configError: "The configuration file is damaged and can't be read."
      )),
      registration: .enabled,
      daemonRegistration: .enabled
    ),
  ]

  @Test(arguments: ["notRunning", "needsApproval", "permissionsMissing", "running", "paused", "inputServiceNeedsInputMonitoring"])
  func status(_ name: String) throws {
    let state = try #require(Self.statuses[name])
    let store = try makeStore(StatusFeature(), dependencies: fixedDependencies()) { state }
    assertBothAppearances(
      StatusView(store: store).frame(maxHeight: .infinity, alignment: .top),
      size: CGSize(width: 770, height: 150),
      testName: "status_\(name)"
    )
  }

  @Test func settings() throws {
    let store = try makeStore(SettingsFeature(), dependencies: fixedDependencies()) { SettingsFeature.State() }
    assertBothAppearances(SettingsView(store: store), size: CGSize(width: 460, height: 430))
  }

  @Test func settingsReadOnly() throws {
    let store = try makeStore(SettingsFeature(), dependencies: fixedDependencies(fileData: Data("{".utf8))) {
      SettingsFeature.State()
    }
    assertBothAppearances(SettingsView(store: store), size: CGSize(width: 460, height: 430))
  }
}
