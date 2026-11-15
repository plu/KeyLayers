import ComposableArchitecture
@testable import ConfiguratorFeature
import Foundation
import HelperIPC
import KeyboardLayout
import KeymapModel
import SharedConfig
@_spi(Internals) import Sharing

let codingID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
let newID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

/// The starter configuration plus a second, empty keymap "Coding" (COD).
func twoKeymaps() -> Configuration {
  var configuration = Configuration.starter
  configuration.keymaps.append(Keymap(id: codingID, name: "Coding", abbreviation: "COD"))
  return configuration
}

/// Fake dependencies that record every call. The configuration lives in an in-memory file system.
final class Fakes: Sendable {
  let files = LockIsolated<[URL: Data]>([:])
  /// A fresh `UserDefaults` suite per test, for `@Shared(.launchHelperAtLogin)`.
  let defaults = UncheckedSendable(UserDefaults(suiteName: "ConfiguratorFeatureTests-\(UUID().uuidString)")!)
  let registrationStatus = LockIsolated(HelperRegistrationClient.Status.notRegistered)
  let daemonStatus = LockIsolated(HelperRegistrationClient.Status.notRegistered)
  /// "register" / "unregister" of the input daemon in call order.
  let daemonCalls = LockIsolated<[String]>([])
  let daemonRegistrationError = LockIsolated<(any Error)?>(nil)
  let revealedURLs = LockIsolated<[URL]>([])
  let remappedKeyboards = LockIsolated<[String]>([])
  let registrationError = LockIsolated<(any Error)?>(nil)
  /// "register" / "unregister" in call order.
  let registrationCalls = LockIsolated<[String]>([])
  let openedPanes = LockIsolated<[SystemSettingsClient.Pane]>([])
  let pauseRequests = LockIsolated<[Bool]>([])
  let startRequests = LockIsolated(0)
  let states: AsyncStream<HelperConnectionState>
  let statesContinuation: AsyncStream<HelperConnectionState>.Continuation
  let detectedKeyboards = LockIsolated<[DetectedKeyboard]>([])
  let labels = LockIsolated(StaticKeyLabels.usANSI)
  let labelChanges: AsyncStream<Void>
  /// The characters the current input source types; ASCII unless a test changes it.
  let typeable = LockIsolated<@Sendable (Character) -> Bool>({ $0.isASCII })
  /// How often the text table was brought up to date.
  let textRefreshes = LockIsolated(0)
  let labelChangesContinuation: AsyncStream<Void>.Continuation
  /// What the save panel returns; `nil` is Cancel.
  let exportURL = LockIsolated<URL?>(nil)
  /// The default file names the save panel was shown with.
  let exportPanelNames = LockIsolated<[String]>([])
  /// What the open panel returns; `nil` is Cancel.
  let importURL = LockIsolated<URL?>(nil)
  let importPanelShown = LockIsolated(0)
  /// Files outside the configuration, read and written by the file IO client.
  let externalFiles = LockIsolated<[URL: Data]>([:])
  let writeError = LockIsolated<(any Error)?>(nil)
  /// Sizes that override the size of `externalFiles`' data.
  let fileSizes = LockIsolated<[URL: Int]>([:])
  let readURLs = LockIsolated<[URL]>([])

  init(file configuration: Configuration? = .starter) throws {
    (states, statesContinuation) = AsyncStream.makeStream()
    (labelChanges, labelChangesContinuation) = AsyncStream.makeStream()
    if let configuration {
      try writeFile(Configuration.encoder.encode(configuration))
    }
  }

  init(fileData: Data) {
    (states, statesContinuation) = AsyncStream.makeStream()
    (labelChanges, labelChangesContinuation) = AsyncStream.makeStream()
    writeFile(fileData)
  }

  var fileStorage: FileStorage {
    .inMemory(fileSystem: files)
  }

  var fileData: Data? {
    files.value[AppIdentifiers.configurationURL]
  }

  func writeFile(_ data: Data) {
    files.withValue { $0[AppIdentifiers.configurationURL] = data }
  }

  func savedConfiguration() throws -> Configuration? {
    try fileData.map { try Configuration.decoder.decode(Configuration.self, from: $0) }
  }

  func apply(to dependencies: inout DependencyValues) {
    dependencies.defaultFileStorage = fileStorage
    dependencies.defaultAppStorage = defaults.value
    dependencies.uuid = .constant(newID)
    dependencies.helperRegistration = HelperRegistrationClient(
      status: { self.registrationStatus.value },
      register: {
        self.registrationCalls.withValue { $0.append("register") }
        if let error = self.registrationError.value {
          throw error
        }
        self.registrationStatus.setValue(.enabled)
      },
      unregister: {
        self.registrationCalls.withValue { $0.append("unregister") }
        self.registrationStatus.setValue(.notRegistered)
      },
      daemonStatus: { self.daemonStatus.value },
      registerDaemon: {
        self.daemonCalls.withValue { $0.append("register") }
        if let error = self.daemonRegistrationError.value {
          throw error
        }
        self.daemonStatus.setValue(.enabled)
      },
      unregisterDaemon: {
        self.daemonCalls.withValue { $0.append("unregister") }
        self.daemonStatus.setValue(.notRegistered)
      }
    )
    dependencies.systemSettings = SystemSettingsClient(open: { pane in
      self.openedPanes.withValue { $0.append(pane) }
    })
    dependencies.finder = FinderClient(reveal: { url in self.revealedURLs.withValue { $0.append(url) } })
    dependencies.modifierKeysSettings = ModifierKeysSettingsClient(remappedKeyboards: { self.remappedKeyboards.value })
    dependencies.helperClient = HelperClient(
      states: { self.states },
      setPaused: { paused in self.pauseRequests.withValue { $0.append(paused) } },
      start: { self.startRequests.withValue { $0 += 1 } }
    )
    dependencies.keyboardDetection = KeyboardDetectionClient(keyboards: { self.detectedKeyboards.value })
    dependencies.keyLabels = KeyLabelClient(labels: { self.labels.value }, changes: { self.labelChanges })
    dependencies.textKeystrokes = TextKeystrokeClient(
      strokes: { self.typeable.value($0) ? [TextStroke(key: .a, modifiers: [])] : nil },
      capsLockIsOn: { false },
      refresh: { self.textRefreshes.withValue { $0 += 1 } }
    )
    applyFileClients(to: &dependencies)
  }

  /// The save and open panels and the file IO of import and export.
  private func applyFileClients(to dependencies: inout DependencyValues) {
    dependencies.filePanel = FilePanelClient(
      chooseExportURL: { name in
        self.exportPanelNames.withValue { $0.append(name) }
        return self.exportURL.value
      },
      chooseImportURL: {
        self.importPanelShown.withValue { $0 += 1 }
        return self.importURL.value
      }
    )
    dependencies.fileIO = FileIOClient(
      size: { url in
        guard let data = self.externalFiles.value[url] else { throw CocoaError(.fileReadNoSuchFile) }
        return self.fileSizes.value[url] ?? data.count
      },
      read: { url in
        self.readURLs.withValue { $0.append(url) }
        guard let data = self.externalFiles.value[url] else { throw CocoaError(.fileReadNoSuchFile) }
        return data
      },
      write: { data, url in
        if let error = self.writeError.value {
          throw error
        }
        self.externalFiles.withValue { $0[url] = data }
      }
    )
  }

  /// Builds state under the fake file system, so its `@Shared(.configuration)` reads the fake file.
  func makeState<State>(_ make: () -> State) -> State {
    withDependencies { apply(to: &$0) } operation: { make() }
  }
}

struct RegistrationFailure: LocalizedError {
  var errorDescription: String? {
    "Operation not permitted"
  }
}
