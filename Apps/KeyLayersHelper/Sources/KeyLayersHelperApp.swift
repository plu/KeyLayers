import ComposableArchitecture
import Foundation
import HelperFeature
import HelperIPC
import SharedConfig
import SwiftUI

/// The background agent (LSUIElement): hosts the remapper and shows its state in the menu bar.
@main
struct KeyLayersHelperApp: App {
  @NSApplicationDelegateAdaptor(HelperAppDelegate.self) private var appDelegate
  /// Retained for the app's lifetime: the listener's delegate is weak. Without a launchd
  /// registration for the Mach service (a dev build run directly), it never receives connections.
  private let server: HelperXPCServer
  private let store: StoreOf<HelperFeature>

  init() {
    // Before anything else can be replaced under us: the update check compares against this.
    HelperAppClient.recordLaunchIdentity()
    let server = HelperXPCServer(
      listener: NSXPCListener(machServiceName: AppIdentifiers.helperMachService),
      // Only the configurator may pause the helper or read its status.
      peerRequirement: HelperXPCServer.configuratorRequirement(
        bundleID: AppIdentifiers.configuratorBundleID,
        teamID: AppIdentifiers.teamID
      )
    )
    self.server = server
    store = Store(initialState: HelperFeature.State()) {
      HelperFeature()
    } withDependencies: {
      $0.helperServer = .live(server)
    }
    // Sent here, not from a view's `.task`: the menu's content only exists while it's open.
    store.send(.task)
    server.resume()
  }

  var body: some Scene {
    MenuBarExtra {
      HelperMenuView(store: store)
    } label: {
      MenuBarLabel(
        title: store.menuBarTitle,
        accessibilityLabel: store.menuBarAccessibilityLabel,
        isPaused: store.isPaused
      )
    }
    .menuBarExtraStyle(.menu)
  }
}

/// Covers terminations that bypass the menu's Quit (logout, restart, `NSApp.terminate` from
/// elsewhere): stops the runtime so held keys are released and the keyboards handed back before the
/// daemon notices the dropped connection. Stopping again after a menu quit is harmless.
@MainActor
final class HelperAppDelegate: NSObject, NSApplicationDelegate {
  func applicationWillTerminate(_: Notification) {
    @Dependency(\.remapperRuntime) var runtime
    runtime.stop()
  }
}
