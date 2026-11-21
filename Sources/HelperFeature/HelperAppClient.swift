import AppKit
import Dependencies
import DependenciesMacros
import InputDaemonIPC

/// App-level actions of the helper process.
@DependencyClient
public struct HelperAppClient: Sendable {
  /// Opens the configurator app the helper is embedded in.
  public var openConfigurator: @Sendable () async -> Void
  /// Quits the helper.
  public var terminate: @Sendable () async -> Void
  /// Yields when the process is asked to terminate (SIGTERM). Single consumer.
  public var terminationRequests: @Sendable () -> AsyncStream<Void> = { .finished }
  /// Whether an update (or a rebuild) replaced the helper's executable since launch.
  public var executableReplaced: @Sendable () -> Bool = { false }
  /// Exits so launchd starts the replaced executable. Call after stopping the runtime.
  public var restartForUpdate: @Sendable () async -> Void
}

/// The helper's executable as it was at launch. Read it once at app start
/// (`HelperAppClient.recordLaunchIdentity()`), so the comparison starts from the launched file.
private let executablePath = Bundle.main.executablePath.map {
  URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
}

private let launchIdentity = executablePath.flatMap { ExecutableIdentity.current(path: $0) }

public extension HelperAppClient {
  /// Records the launched executable's identity; call at app start.
  static func recordLaunchIdentity() {
    _ = launchIdentity
  }
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
    },
    executableReplaced: {
      // Without a launch identity nothing counts as changed (no exit loop).
      ExecutableIdentity.hasChanged(path: executablePath, since: launchIdentity)
    },
    restartForUpdate: {
      // Non-zero: the launchd job restarts only unsuccessful exits (KeepAlive.SuccessfulExit =
      // false), while a Quit (status 0) stays stopped. 75 is EX_TEMPFAIL.
      exit(75)
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
