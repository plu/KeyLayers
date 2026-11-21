import ConcurrencyExtras
import Dependencies
import Foundation
import KeymapModel
@testable import SharedConfig
@_spi(Internals) import Sharing
import Testing

@Suite(.serialized)
struct SharedConfigurationTests {
  @Test func defaultsToStarterWhenFileMissing() {
    withDependencies {
      $0.defaultFileStorage = .inMemory
    } operation: {
      @Shared(.configuration) var configuration
      #expect(configuration == .starter)
    }
  }

  @Test func writesPrettySortedJSON() throws {
    let files = LockIsolated<[URL: Data]>([:])
    try withDependencies {
      $0.defaultFileStorage = .inMemory(fileSystem: files)
    } operation: {
      @Shared(.configuration) var configuration
      $configuration.withLock { $0.settings.doubleTapTimeoutMilliseconds = 321 }
      var expected = Configuration.starter
      expected.settings.doubleTapTimeoutMilliseconds = 321
      let data = try #require(files.value[AppIdentifiers.configurationURL])
      #expect(try data == (Configuration.encoder.encode(expected)))
    }
  }

  @Test func externalWriteIsObserved() async throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(component: "configuration.json")

    try await withDependencies {
      $0.defaultFileStorage = .fileSystem
    } operation: {
      @Shared(.configuration(at: url)) var configuration
      #expect(configuration == .starter)

      var changed = Configuration.starter
      changed.settings.doubleTapTimeoutMilliseconds = 777
      // Another process: plain atomic replacement.
      try Configuration.encoder.encode(changed).write(to: url, options: .atomic)

      let shared = $configuration
      try await waitUntil { shared.wrappedValue.settings.doubleTapTimeoutMilliseconds == 777 }
      #expect(configuration == changed)
    }
  }

  @Test func corruptFileReportsLoadError() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(component: "configuration.json")
    try Data("{".utf8).write(to: url)

    withDependencies {
      $0.defaultFileStorage = .fileSystem
    } operation: {
      @Shared(.configuration(at: url)) var configuration
      #expect($configuration.loadError != nil)
      #expect(configuration == .starter)
    }
  }

  @Test func daemonIdentifierFallbacks() {
    #expect(AppIdentifiers.inputDaemonMachService == "com.plunien.keylayers.tests.inputservice")
    #expect(AppIdentifiers.inputDaemonPlist == "com.plunien.keylayers.inputservice.plist")
    #expect(AppIdentifiers.inputDaemonBundleID == "com.plunien.keylayers.inputservice")
  }

  @Test func identifiersFallBackOutsideAnApp() {
    #expect(AppIdentifiers.appGroup == "com.plunien.keylayers.tests")
    #expect(AppIdentifiers.configurationURL.lastPathComponent == "configuration.json")
  }
}

private func makeTempDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appending(component: "SharedConfigTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

/// Polls (main-queue file events need the run loop to turn) until `condition` holds, up to 2 s.
private func waitUntil(_ condition: @Sendable () -> Bool) async throws {
  let deadline = ContinuousClock.now + .seconds(2)
  while !condition(), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
}
