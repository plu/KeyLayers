import ComposableArchitecture
import Foundation
import HelperIPC
import KeymapModel

/// The status area: whether the helper runs, its registration and permissions, pause.
@Reducer
public struct StatusFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    public var helper: HelperConnectionState
    public var registration: HelperRegistrationClient.Status
    /// Why the last attempt to enable the helper failed, if it did.
    public var registrationError: String?
    /// The root input daemon's registration.
    public var daemonRegistration: HelperRegistrationClient.Status
    /// Why the last attempt to enable the input daemon failed, if it did.
    public var daemonRegistrationError: String?
    /// Keyboards with a macOS Modifier Keys remap.
    public var remappedKeyboards: [String]

    public init(
      helper: HelperConnectionState = .notRunning,
      registration: HelperRegistrationClient.Status = .notFound,
      registrationError: String? = nil,
      daemonRegistration: HelperRegistrationClient.Status = .notRegistered,
      daemonRegistrationError: String? = nil,
      remappedKeyboards: [String] = []
    ) {
      self.helper = helper
      self.registration = registration
      self.registrationError = registrationError
      self.daemonRegistration = daemonRegistration
      self.daemonRegistrationError = daemonRegistrationError
      self.remappedKeyboards = remappedKeyboards
    }

    /// Both registration failures, one per line.
    public var registrationMessage: String? {
      let messages = [registrationError, daemonRegistrationError].compactMap(\.self)
      return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    public var modifierKeysNote: String? {
      remappedKeyboards.isEmpty
        ? nil
        : """
        macOS Modifier Keys settings don't apply while KeyLayers remaps a keyboard. \
        Set those remaps in your keymap instead.
        """
    }

    /// The running helper is waiting for the user to approve the input daemon in Login Items.
    /// Only meaningful once the helper runs.
    public var daemonNeedsApproval: Bool {
      runningStatus != nil && daemonRegistration == .requiresApproval
    }

    /// The helper runs but the input daemon isn't registered (a failed or undone registration).
    public var daemonNeedsRegistration: Bool {
      runningStatus != nil && (daemonRegistration == .notRegistered || daemonRegistration == .notFound)
    }

    /// The input daemon reported it lacks Input Monitoring (the user adds it by hand).
    public var showsInputServiceInputMonitoringStep: Bool {
      runningStatus?.inputServiceNeedsInputMonitoring == true
    }

    /// The helper's status while it's running.
    public var runningStatus: HelperStatus? {
      if case let .running(status) = helper {
        status
      } else {
        nil
      }
    }

    public var headline: String {
      guard let status = runningStatus else {
        switch registration {
        case .enabled: return "Remapper not running"
        case .notRegistered: return "Remapper not running: the helper isn't enabled"
        case .requiresApproval: return "Remapper not running: the helper needs approval in System Settings"
        case .notFound: return "Remapper not running: the helper is missing from the app"
        }
      }
      if daemonNeedsApproval {
        return "Remapper waiting: approve “KeyLayers” in Login Items"
      }
      if !status.permissions.allGranted {
        return "Remapper waiting for permissions"
      }
      if status.inputServiceNeedsInputMonitoring {
        return "Remapper waiting: the input service needs Input Monitoring"
      }
      if !status.isCapturing {
        return "Input service not connected"
      }
      return status.isPaused ? "Remapping paused" : "Remapping active"
    }

    /// Offered while the helper isn't running and isn't registered (or awaits approval).
    public var showsEnableHelper: Bool {
      (runningStatus == nil && registration != .enabled) || daemonNeedsApproval || daemonNeedsRegistration
    }

    /// Offered while the helper is registered but not running, e.g. after the user quit it from
    /// its menu: it stays quit until started here (or at the next login).
    public var showsStartHelper: Bool {
      runningStatus == nil && registration == .enabled
    }

    public var enableHelperTitle: String {
      if registration == .requiresApproval || daemonNeedsApproval {
        return "Open Login Items…"
      }
      return runningStatus != nil ? "Enable Input Service" : "Enable Helper"
    }
  }

  public enum Action: Sendable {
    case task
    case stateChanged(HelperConnectionState)
    /// The registrations and the Modifier Keys remaps, read together.
    case refreshed(
      registration: HelperRegistrationClient.Status,
      daemon: HelperRegistrationClient.Status,
      remappedKeyboards: [String]
    )
    case registrationFailed(String)
    case daemonRegistrationFailed(String)
    case showInputServiceInFinderTapped
    case enableHelperTapped
    case startHelperTapped
    case openSettingsTapped(SystemSettingsClient.Pane)
    case pauseToggled
  }

  @Dependency(\.helperClient) var helper
  @Dependency(\.helperRegistration) var registration
  @Dependency(\.systemSettings) var systemSettings
  @Dependency(\.finder) var finder
  @Dependency(\.modifierKeysSettings) var modifierKeys

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        return .merge(
          refreshRegistration(),
          .run { send in
            for await helperState in helper.states() {
              await send(.stateChanged(helperState))
            }
          }
        )

      case let .stateChanged(helperState):
        state.helper = helperState
        // The helper starting (or stopping) is the usual sign that its registration changed,
        // e.g. the user approved it in System Settings.
        return refreshRegistration()

      case let .refreshed(status, daemon, remappedKeyboards):
        state.registration = status
        if status == .enabled {
          state.registrationError = nil
        }
        state.daemonRegistration = daemon
        if daemon == .enabled {
          state.daemonRegistrationError = nil
        }
        state.remappedKeyboards = remappedKeyboards
        return .none

      case let .registrationFailed(message):
        state.registrationError = message
        return .none

      case let .daemonRegistrationFailed(message):
        state.daemonRegistrationError = message
        return .none

      case .showInputServiceInFinderTapped:
        let url = Bundle.main.bundleURL.appending(path: "Contents/Library/HelperTools/KeyLayersInputDaemon")
        return .run { _ in finder.reveal(url) }

      case .enableHelperTapped:
        @Shared(.launchHelperAtLogin) var launchAtLogin
        $launchAtLogin.withLock { $0 = true }
        if state.registration == .requiresApproval || state.daemonNeedsApproval {
          return .run { _ in systemSettings.open(.loginItems) }
        }
        return .run { send in
          // SMAppService rejects registering twice, so only what isn't registered.
          if needsRegistration(registration.status()) {
            do {
              try registration.register()
            } catch {
              await send(.registrationFailed(HelperRegistrationClient.describe(error)))
            }
          }
          if needsRegistration(registration.daemonStatus()) {
            do {
              try registration.registerDaemon()
            } catch {
              await send(.daemonRegistrationFailed(HelperRegistrationClient.describeDaemon(error)))
            }
          }
          await send(.refreshed(
            registration: registration.status(),
            daemon: registration.daemonStatus(),
            remappedKeyboards: modifierKeys.remappedKeyboards()
          ))
        }

      case .startHelperTapped:
        // The helper's next status push (over the connection that launched it) updates the state.
        return .run { _ in await helper.start() }

      case let .openSettingsTapped(pane):
        return .run { _ in systemSettings.open(pane) }

      case .pauseToggled:
        guard let status = state.runningStatus else { return .none }
        let paused = !status.isPaused
        // Fire and forget: a wedged helper may never reply, so nothing waits for it. The helper's
        // next status push updates the state.
        return .run { _ in try? await helper.setPaused(paused) }
      }
    }
  }

  private func refreshRegistration() -> Effect<Action> {
    .run { send in
      await send(.refreshed(
        registration: registration.status(),
        daemon: registration.daemonStatus(),
        remappedKeyboards: modifierKeys.remappedKeyboards()
      ))
    }
  }
}

private func needsRegistration(_ status: HelperRegistrationClient.Status) -> Bool {
  status == .notRegistered || status == .notFound
}
