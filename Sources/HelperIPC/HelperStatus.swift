import Foundation
import KeymapModel

/// The helper's macOS privacy permissions. The helper only needs Accessibility (virtual
/// keyboards); Input Monitoring belongs to the input daemon (`inputServiceNeedsInputMonitoring`).
public struct PermissionStatus: Codable, Equatable, Sendable {
  public var accessibility: Bool

  public init(accessibility: Bool) {
    self.accessibility = accessibility
  }

  public var allGranted: Bool {
    accessibility
  }
}

/// What the helper reports to the configurator. Crosses XPC as JSON `Data`.
public struct HelperStatus: Codable, Equatable, Sendable {
  public var activeKeymapID: Keymap.ID?
  public var activeLayer: LayerName
  public var isPaused: Bool
  public var permissions: PermissionStatus
  public var configError: String?
  /// The input daemon reported a keyboard it may not seize because it lacks Input Monitoring.
  public var inputServiceNeedsInputMonitoring: Bool
  /// `false` when remapping should be running but the input daemon isn't capturing the keyboards
  /// (unreachable, released them, or no virtual keyboard), past a short grace period after a start
  /// or resume. `true` otherwise, including while paused or not started.
  public var isCapturing: Bool

  public init(
    activeKeymapID: Keymap.ID? = nil,
    activeLayer: LayerName = .base,
    isPaused: Bool = false,
    permissions: PermissionStatus = PermissionStatus(accessibility: false),
    configError: String? = nil,
    inputServiceNeedsInputMonitoring: Bool = false,
    isCapturing: Bool = true
  ) {
    self.activeKeymapID = activeKeymapID
    self.activeLayer = activeLayer
    self.isPaused = isPaused
    self.permissions = permissions
    self.configError = configError
    self.inputServiceNeedsInputMonitoring = inputServiceNeedsInputMonitoring
    self.isCapturing = isCapturing
  }

  func encoded() throws -> Data {
    try JSONEncoder().encode(self)
  }

  static func decode(_ data: Data) throws -> HelperStatus {
    try JSONDecoder().decode(HelperStatus.self, from: data)
  }
}

/// The configurator's view of the helper.
public enum HelperConnectionState: Equatable, Sendable {
  case notRunning
  case running(HelperStatus)
}

/// A request from the configurator to the helper.
public enum HelperRequest: Equatable, Sendable {
  case setPaused(Bool)
}
