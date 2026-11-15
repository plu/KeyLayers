import AppKit
import Dependencies
import DependenciesMacros

/// App-level actions of the helper process.
@DependencyClient
public struct HelperAppClient: Sendable {
  /// Opens the configurator app the helper is embedded in.
  public var openConfigurator: @Sendable () async -> Void
  /// Quits the helper.
  public var terminate: @Sendable () async -> Void
  /// Yields when the process is asked to terminate (SIGTERM). Single consumer.
  public var terminationRequests: @Sendable () -> AsyncStream<Void> = { .finished }
}

extension HelperAppClient: DependencyKey {
  public static let liveValue = HelperAppClient(
    openConfigurator: {
      // The helper lives at KeyLayers.app/Contents/Library/LoginItems/KeyLayersHelper.app.
      var url = Bundle.main.bundleURL
      for _ in 0 ..< 4 {
        url.deleteLastPathComponent()
      }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    },
    terminate: {
      await MainActor.run { NSApplication.shared.terminate(nil) }
    },
    terminationRequests: {
      AsyncStream { continuation in
        // Handle SIGTERM on the main queue instead of dying with virtual keys still held.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { continuation.yield() }
        source.resume()
        continuation.onTermination = { _ in
          source.cancel()
          signal(SIGTERM, SIG_DFL)
        }
      }
    }
  )

  public static let testValue = HelperAppClient()
}

public extension DependencyValues {
  var helperApp: HelperAppClient {
    get { self[HelperAppClient.self] }
    set { self[HelperAppClient.self] = newValue }
  }
}
