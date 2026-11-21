import ConfiguratorFeature
import Foundation
import Observation
import Sparkle
import SwiftUI

/// Sparkle's updater, started only in builds that carry a feed URL and a public key (tag releases).
/// It checks on Sparkle's schedule (`SUEnableAutomaticChecks`) and on "Check for Updates…".
@MainActor
@Observable
final class Updater {
  /// Whether this build updates itself at all; without it there is no menu item.
  let isAvailable: Bool
  /// False while a check or an update is already running.
  private(set) var canCheckForUpdates = false

  @ObservationIgnored private let controller: SPUStandardUpdaterController?
  @ObservationIgnored private var observation: NSKeyValueObservation?

  init() {
    guard UpdateFeed.isConfigured(infoDictionary: Bundle.main.infoDictionary) else {
      isAvailable = false
      controller = nil
      return
    }
    isAvailable = true
    let controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    self.controller = controller
    // SPUUpdater is main-actor bound and changes this property on the main thread.
    let options: NSKeyValueObservingOptions = [.initial, .new]
    observation = controller.updater.observe(\.canCheckForUpdates, options: options) { [weak self] updater, _ in
      MainActor.assumeIsolated {
        self?.canCheckForUpdates = updater.canCheckForUpdates
      }
    }
  }

  func checkForUpdates() {
    controller?.checkForUpdates(nil)
  }
}

/// KeyLayers → Check for Updates… (after "About KeyLayers"); absent in builds that don't update.
struct UpdateCommands: Commands {
  let updater: Updater

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      if updater.isAvailable {
        Button("Check for Updates…") {
          updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
      }
    }
  }
}
