import Foundation
import SharedConfig
import Sharing

/// Writes the configuration's pending edits to disk; the app calls it before quitting.
///
/// `FileStorageKey` writes the first save at once and debounces later ones by a second, so the
/// last edits before quitting would otherwise be lost. Never writes while the file couldn't be
/// loaded: the in-memory value is then the default, and writing it would overwrite the user's file.
public struct ConfigurationFlusher: Sendable {
  public init() {}

  public func flush() async {
    @Shared(.configuration) var configuration
    guard $configuration.loadError == nil else { return }
    // Nothing can be shown while quitting; a failed write leaves the file as it was.
    try? await $configuration.save()
  }
}
