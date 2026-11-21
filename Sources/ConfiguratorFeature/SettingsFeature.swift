import ComposableArchitecture
import Foundation
import KeymapModel
import SharedConfig

/// Settings: double-tap timeout, layer HUD, menu bar text, launch helper at login.
///
/// Configuration fields change through explicit actions (not bindings) so the read-only guard
/// runs before anything is written.
@Reducer
public struct SettingsFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    @Shared(.configuration) public var configuration: Configuration
    @Shared(.launchHelperAtLogin) public var launchAtLogin: Bool
    /// Why the last registration change failed, if it did.
    public var registrationError: String?

    public init() {}

    public var isReadOnly: Bool {
      $configuration.loadError != nil
    }
  }

  public enum Action: Sendable {
    case doubleTapTimeoutChanged(Int)
    case showLayerHUDChanged(Bool)
    case menuBarShowsKeymapChanged(Bool)
    case menuBarShowsLayerChanged(Bool)
    case launchAtLoginChanged(Bool)
    case registrationFailed(String)
    case doneTapped
  }

  public static let doubleTapTimeoutRange = 100 ... 1000
  public static let doubleTapTimeoutStep = 50

  /// Rounds to the nearest step and clamps to the range: 40 → 100, 333 → 350, 1210 → 1000.
  public static func clampedDoubleTapTimeout(_ milliseconds: Int) -> Int {
    let step = Double(doubleTapTimeoutStep)
    let rounded = Int((Double(milliseconds) / step).rounded()) * doubleTapTimeoutStep
    return min(max(rounded, doubleTapTimeoutRange.lowerBound), doubleTapTimeoutRange.upperBound)
  }

  @Dependency(\.helperRegistration) var registration
  @Dependency(\.dismiss) var dismiss

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .doubleTapTimeoutChanged(milliseconds):
        guard !state.isReadOnly else { return .none }
        let clamped = Self.clampedDoubleTapTimeout(milliseconds)
        guard clamped != state.configuration.settings.doubleTapTimeoutMilliseconds else { return .none }
        state.$configuration.withLock { $0.settings.doubleTapTimeoutMilliseconds = clamped }
        return .none

      case let .showLayerHUDChanged(isOn):
        guard !state.isReadOnly, isOn != state.configuration.settings.showLayerHUD else { return .none }
        state.$configuration.withLock { $0.settings.showLayerHUD = isOn }
        return .none

      case let .menuBarShowsKeymapChanged(isOn):
        guard !state.isReadOnly, isOn != state.configuration.settings.menuBarShowsKeymap else { return .none }
        state.$configuration.withLock { $0.settings.menuBarShowsKeymap = isOn }
        return .none

      case let .menuBarShowsLayerChanged(isOn):
        guard !state.isReadOnly, isOn != state.configuration.settings.menuBarShowsLayer else { return .none }
        state.$configuration.withLock { $0.settings.menuBarShowsLayer = isOn }
        return .none

      case let .launchAtLoginChanged(isOn):
        // Not part of the configuration file, so allowed while it's read-only.
        state.$launchAtLogin.withLock { $0 = isOn }
        state.registrationError = nil
        return .run { send in
          // SMAppService rejects registering twice and unregistering what isn't registered.
          let status = registration.status()
          do {
            if isOn, status != .enabled, status != .requiresApproval {
              try registration.register()
            } else if !isOn, status != .notRegistered, status != .notFound {
              try registration.unregister()
            }
          } catch {
            await send(.registrationFailed(HelperRegistrationClient.describe(error)))
          }
          // The input daemon follows the helper. Unregistering it on "off" makes off and on again
          // replace a daemon registration launchd can no longer start (one made by another build
          // of KeyLayers, whose signature it still expects) with one made by this app.
          let daemonStatus = registration.daemonStatus()
          do {
            if isOn, daemonStatus == .notRegistered || daemonStatus == .notFound {
              try registration.registerDaemon()
            } else if !isOn, daemonStatus != .notRegistered, daemonStatus != .notFound {
              try registration.unregisterDaemon()
            }
          } catch {
            await send(.registrationFailed(HelperRegistrationClient.describeDaemon(error)))
          }
        }

      case let .registrationFailed(message):
        state.registrationError = message
        return .none

      case .doneTapped:
        return .run { _ in await dismiss() }
      }
    }
  }
}
