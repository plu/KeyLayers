import Foundation

/// Identifiers injected into each app's Info.plist by the Tuist manifest.
/// Outside an app bundle (unit tests) the keys are absent and the fallbacks apply.
public enum AppIdentifiers {
  public static var appGroup: String {
    infoString("AppGroupIdentifier") ?? "com.plunien.keylayers.tests"
  }

  public static var helperMachService: String {
    infoString("HelperMachServiceName") ?? "com.plunien.keylayers.tests.helper"
  }

  /// The helper app's bundle identifier, to find its running process.
  public static var helperBundleID: String {
    infoString("HelperBundleIdentifier") ?? "com.plunien.keylayers.helper"
  }

  /// The configurator's bundle identifier, which the helper admits as its XPC peer.
  public static var configuratorBundleID: String {
    infoString("ConfiguratorBundleIdentifier") ?? "com.plunien.keylayers.configurator"
  }

  /// The signing team, or `nil` for ad-hoc signed builds.
  public static var teamID: String? {
    infoString("SigningTeamIdentifier")
  }

  public static var helperLaunchdPlist: String {
    infoString("HelperLaunchdPlistName") ?? "com.plunien.keylayers.helper.plist"
  }

  /// The root input daemon's Mach service, which the helper connects to.
  public static var inputDaemonMachService: String {
    infoString("InputDaemonMachServiceName") ?? "com.plunien.keylayers.tests.inputservice"
  }

  /// The input daemon's signing identifier, which the helper requires of the daemon it connects to.
  public static var inputDaemonBundleID: String {
    infoString("InputDaemonBundleIdentifier") ?? "com.plunien.keylayers.inputservice"
  }

  public static var inputDaemonPlist: String {
    infoString("InputDaemonPlistName") ?? "com.plunien.keylayers.inputservice.plist"
  }

  /// `<group container>/configuration.json`. Falls back to
  /// `Application Support/<appGroup>/` when the group container is unavailable
  /// (for example ad-hoc signed builds). The directory is created lazily by the
  /// file storage on first write, so this never touches the disk.
  public static var configurationURL: URL {
    let directory =
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appending(component: appGroup, directoryHint: .isDirectory)
        ?? FileManager.default.temporaryDirectory.appending(component: appGroup, directoryHint: .isDirectory)
    return directory.appending(component: "configuration.json")
  }

  private static func infoString(_ key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty
    else { return nil }
    return value
  }
}
