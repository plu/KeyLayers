import ApplicationServices
import Dependencies
import DependenciesMacros
import HelperIPC

/// The helper's Accessibility permission (needed to create the virtual keyboards). Input
/// Monitoring belongs to the input daemon, which reads the keyboards.
@DependencyClient
public struct PermissionsClient: Sendable {
  public var status: @Sendable () -> PermissionStatus = { .init(accessibility: false) }
  /// Shows the system prompt if Accessibility isn't granted yet.
  public var request: @Sendable () -> Void
}

extension PermissionsClient: DependencyKey {
  public static let liveValue = PermissionsClient(
    status: {
      PermissionStatus(accessibility: AXIsProcessTrusted())
    },
    request: {
      // The value of `kAXTrustedCheckOptionPrompt`, which Swift 6 rejects as a mutable global.
      let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(options)
    }
  )

  public static let testValue = PermissionsClient()
}

public extension DependencyValues {
  var permissions: PermissionsClient {
    get { self[PermissionsClient.self] }
    set { self[PermissionsClient.self] = newValue }
  }
}
