import AppKit
import ConfiguratorFeature

/// Flushes the configuration's debounced save before the app quits.
@MainActor
final class ConfiguratorAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task {
      await ConfigurationFlusher().flush()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
