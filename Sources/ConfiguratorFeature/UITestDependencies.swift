import Dependencies
import Foundation
import HelperIPC
import KeyboardLayout
import KeymapModel
import Sharing

// Debug builds only (the UITests scheme tests the Debug configuration): a release build has no
// way to swap in fake dependencies.
#if DEBUG
  /// The configurator's UI-test mode, turned on by the launch argument `-UITestMode`.
  ///
  /// It never touches the real system: the configuration lives in memory, app storage is a fresh
  /// in-memory suite on every launch, the helper is a fake, its registration always reports
  /// `.enabled`, and System Settings is never opened.
  public enum UITestMode {
    public static let launchArgument = "-UITestMode"
    /// `running` | `notRunning` | `needsPermissions` | `paused`; `running` when absent.
    public static let helperStateVariable = "UITEST_HELPER_STATE"
    /// The key the recorder returns, as `"<page>:<usage>"`; without it recording yields nothing.
    public static let recordedKeyVariable = "UITEST_RECORDED_KEY"

    public static var isEnabled: Bool {
      ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Replaces every dependency that reaches outside the app.
    public static func prepare(
      _ dependencies: inout DependencyValues,
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
      dependencies.defaultFileStorage = .inMemory
      dependencies.defaultAppStorage = .inMemory
      dependencies.helperClient = FakeHelper(
        initial: helperState(named: environment[helperStateVariable])
      ).client
      dependencies.helperRegistration = HelperRegistrationClient(
        status: { .enabled },
        register: {},
        unregister: {},
        daemonStatus: { .enabled },
        registerDaemon: {},
        unregisterDaemon: {}
      )
      dependencies.keyboardDetection = KeyboardDetectionClient(keyboards: {
        [DetectedKeyboard(
          id: "uitest",
          name: "Test Keyboard",
          kind: KeyboardKind(model: .compact, layout: .ansi),
          isBuiltIn: true
        )]
      })
      dependencies.keyLabels = KeyLabelClient(labels: { StaticKeyLabels.usANSI }, changes: { .finished })
      let recordedKey = environment[recordedKeyVariable].flatMap(KeyID.init(string:))
      dependencies.keyRecorder = KeyRecorderClient(record: { recordedKey })
      dependencies.finder = FinderClient(reveal: { _ in })
      dependencies.modifierKeysSettings = ModifierKeysSettingsClient(remappedKeyboards: { [] })
      dependencies.systemSettings = SystemSettingsClient(open: { _ in })
    }

    static func helperState(named name: String?) -> HelperConnectionState {
      let granted = PermissionStatus(accessibility: true)
      switch name {
      case "notRunning":
        return .notRunning
      case "needsPermissions":
        return .running(HelperStatus(permissions: PermissionStatus(accessibility: false)))
      case "paused":
        return .running(HelperStatus(isPaused: true, permissions: granted))
      default:
        return .running(HelperStatus(permissions: granted))
      }
    }
  }

  /// A helper that stays in one state, except that pause requests change `isPaused` while it runs
  /// and are pushed to every observer, as the real helper's status pushes are.
  private final class FakeHelper: Sendable {
    private let state: LockIsolated<HelperConnectionState>
    private let observers = LockIsolated<[UUID: AsyncStream<HelperConnectionState>.Continuation]>([:])

    init(initial: HelperConnectionState) {
      state = LockIsolated(initial)
    }

    var client: HelperClient {
      HelperClient(
        states: { self.states() },
        setPaused: { self.setPaused($0) },
        start: {}
      )
    }

    private func states() -> AsyncStream<HelperConnectionState> {
      let id = UUID()
      let (stream, continuation) = AsyncStream.makeStream(of: HelperConnectionState.self)
      continuation.onTermination = { _ in self.observers.withValue { $0[id] = nil } }
      observers.withValue { $0[id] = continuation }
      continuation.yield(state.value)
      return stream
    }

    private func setPaused(_ paused: Bool) {
      let updated = state.withValue { state -> HelperConnectionState? in
        guard case var .running(status) = state else { return nil }
        status.isPaused = paused
        state = .running(status)
        return state
      }
      guard let updated else { return }
      for observer in observers.value.values {
        observer.yield(updated)
      }
    }
  }
#endif
