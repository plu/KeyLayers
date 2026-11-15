import AppKit
import Dependencies
import DependenciesMacros

/// Opens panes of System Settings.
@DependencyClient
public struct SystemSettingsClient: Sendable {
  public enum Pane: Sendable {
    case accessibility, inputMonitoring, loginItems

    public var url: URL {
      switch self {
      case .accessibility:
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
      case .inputMonitoring:
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
      case .loginItems:
        URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
      }
    }
  }

  public var open: @Sendable (Pane) -> Void
}

extension SystemSettingsClient: DependencyKey {
  public static let liveValue = SystemSettingsClient(open: { pane in
    NSWorkspace.shared.open(pane.url)
  })

  public static let testValue = SystemSettingsClient()

  public static let previewValue = SystemSettingsClient(open: { _ in })
}

public extension DependencyValues {
  var systemSettings: SystemSettingsClient {
    get { self[SystemSettingsClient.self] }
    set { self[SystemSettingsClient.self] = newValue }
  }
}
