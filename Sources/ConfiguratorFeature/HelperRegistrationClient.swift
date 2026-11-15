import Dependencies
import DependenciesMacros
import Foundation
import ServiceManagement
import SharedConfig
import Sharing

/// Registers the embedded helper with launchd as a login-item agent (`SMAppService`).
@DependencyClient
public struct HelperRegistrationClient: Sendable {
  public enum Status: Equatable, Sendable {
    case enabled, notRegistered, requiresApproval, notFound
  }

  public var status: @Sendable () -> Status = { .notFound }
  public var register: @Sendable () throws -> Void
  public var unregister: @Sendable () throws -> Void

  /// The root input daemon (`SMAppService.daemon`), registered alongside the helper.
  public var daemonStatus: @Sendable () -> Status = { .notFound }
  public var registerDaemon: @Sendable () throws -> Void
  public var unregisterDaemon: @Sendable () throws -> Void
}

extension HelperRegistrationClient: DependencyKey {
  public static let liveValue = HelperRegistrationClient(
    status: {
      map(service.status)
    },
    register: { try service.register() },
    unregister: { try service.unregister() },
    daemonStatus: { map(daemonService.status) },
    registerDaemon: { try daemonService.register() },
    unregisterDaemon: { try daemonService.unregister() }
  )

  public static let testValue = HelperRegistrationClient()

  public static let previewValue = HelperRegistrationClient(
    status: { .enabled },
    register: {},
    unregister: {},
    daemonStatus: { .enabled },
    registerDaemon: {},
    unregisterDaemon: {}
  )

  /// The agent described by `Contents/Library/LaunchAgents/<plist>` (written by `embed-helper.sh`).
  private static var service: SMAppService {
    SMAppService.agent(plistName: AppIdentifiers.helperLaunchdPlist)
  }

  /// The daemon described by `Contents/Library/LaunchDaemons/<plist>` (written by `embed-helper.sh`).
  private static var daemonService: SMAppService {
    SMAppService.daemon(plistName: AppIdentifiers.inputDaemonPlist)
  }

  private static func map(_ status: SMAppService.Status) -> Status {
    switch status {
    case .enabled: .enabled
    case .notRegistered: .notRegistered
    case .requiresApproval: .requiresApproval
    case .notFound: .notFound
    @unknown default: .notFound
    }
  }

  /// "The helper couldn't be enabled: …"
  static func describe(_ error: any Error) -> String {
    "The helper couldn't be enabled: \(error.localizedDescription)"
  }

  /// "The input service couldn't be enabled: …"
  static func describeDaemon(_ error: any Error) -> String {
    "The input service couldn't be enabled: \(error.localizedDescription)"
  }
}

public extension DependencyValues {
  var helperRegistration: HelperRegistrationClient {
    get { self[HelperRegistrationClient.self] }
    set { self[HelperRegistrationClient.self] = newValue }
  }
}

public extension SharedKey where Self == AppStorageKey<Bool>.Default {
  /// The user's "launch helper at login" choice. While it is on, the configurator registers the
  /// helper on launch if it isn't registered; turning it off unregisters the helper.
  static var launchHelperAtLogin: Self {
    Self[.appStorage("launchHelperAtLogin"), default: true]
  }
}
