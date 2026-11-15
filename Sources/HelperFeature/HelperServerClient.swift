import Dependencies
import DependenciesMacros
import HelperIPC

/// The helper's side of the XPC status channel.
@DependencyClient
public struct HelperServerClient: Sendable {
  /// Pushes `status` to every connected configurator and answers later status requests with it.
  public var publish: @Sendable (_ status: HelperStatus) -> Void
  /// Requests from configurators. Single consumer.
  public var requests: @Sendable () -> AsyncStream<HelperRequest> = { .finished }
}

public extension HelperServerClient {
  /// A client backed by `server`. Retains `server`, which keeps its listener's (weak) delegate alive.
  static func live(_ server: HelperXPCServer) -> Self {
    HelperServerClient(
      publish: { server.publish($0) },
      requests: { server.requests }
    )
  }
}

extension HelperServerClient: TestDependencyKey {
  public static let testValue = HelperServerClient()
  /// The app injects `live(_:)` with its server; without one, statuses go nowhere.
  public static let previewValue = HelperServerClient(publish: { _ in }, requests: { .finished })
}

public extension DependencyValues {
  var helperServer: HelperServerClient {
    get { self[HelperServerClient.self] }
    set { self[HelperServerClient.self] = newValue }
  }
}
