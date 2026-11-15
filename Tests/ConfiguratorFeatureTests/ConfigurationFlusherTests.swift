import ConfiguratorFeature
import Dependencies
import Foundation
import KeymapModel
import SharedConfig
@_spi(Internals) import Sharing
import Testing

/// An in-memory configuration file whose debounced saves never fire, like the app's
/// saves still waiting out FileStorageKey's 1 s debounce when the user quits.
private final class DebouncedFile: Sendable {
  let files = LockIsolated<[URL: Data]>([:])
  var storage: FileStorage {
    .inMemory(fileSystem: files, asyncAfter: { _, _ in })
  }

  var data: Data? {
    files.value[AppIdentifiers.configurationURL]
  }

  func write(_ data: Data) {
    files.withValue { $0[AppIdentifiers.configurationURL] = data }
  }

  /// The first keymap's name in the file, or `nil` when the file is missing or invalid.
  var savedKeymapName: String? {
    data.flatMap { try? Configuration.decoder.decode(Configuration.self, from: $0) }?.keymaps.first?.name
  }
}

@MainActor
struct ConfigurationFlusherTests {
  @Test func flushWritesTheLatestEdit() async throws {
    let file = DebouncedFile()
    try file.write(Configuration.encoder.encode(Configuration.starter))
    await withDependencies {
      $0.defaultFileStorage = file.storage
    } operation: {
      @Shared(.configuration) var configuration
      // Rapid edits (the name field commits per keystroke): the first is written at once, the
      // rest wait for the debounce.
      $configuration.withLock { $0.keymaps[0].name = "W" }
      $configuration.withLock { $0.keymaps[0].name = "Wo" }
      $configuration.withLock { $0.keymaps[0].name = "Work" }
      #expect(file.savedKeymapName == "W")

      await ConfigurationFlusher().flush()
      #expect(file.savedKeymapName == "Work")
    }
  }

  @Test func flushNeverWritesWhileTheFileCantBeLoaded() async {
    let file = DebouncedFile()
    file.write(Data("{".utf8))
    await withDependencies {
      $0.defaultFileStorage = file.storage
    } operation: {
      @Shared(.configuration) var configuration
      #expect($configuration.loadError != nil)

      await ConfigurationFlusher().flush()
      #expect(file.data == Data("{".utf8))
    }
  }
}
