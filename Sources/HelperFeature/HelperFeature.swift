import ComposableArchitecture
import Foundation
import HelperIPC
import InputDaemonIPC
import KeyIO
import KeymapModel
import Observation
import RemapEngine
import SharedConfig

/// The helper app: hosts the remapper, shows its state in the menu bar, flashes the HUD and
/// publishes status to the configurator.
///
/// The helper only ever reads the configuration. After a failed load the in-memory value is the
/// last good configuration (or the default), and saving it would overwrite the user's file.
@Reducer
public struct HelperFeature: Sendable {
  public enum RuntimePhase: Equatable, Sendable {
    case notStarted, starting, running
  }

  @ObservableState
  public struct State: Equatable {
    @Shared(.configuration) public var configuration: Configuration
    public var engineStatus: EngineStatus?
    public var isPaused = false
    public var permissions = PermissionStatus(accessibility: false)
    /// Why the configuration file couldn't be loaded, if it couldn't.
    public var configError: String?
    /// Why the runtime couldn't start, if the last attempt failed. Retried on the next poll.
    public var startError: String?
    /// The keyboards the input daemon reported last (seized, or with the seize's error).
    public var devices: [InputDevice] = []
    public var runtimePhase = RuntimePhase.notStarted
    /// Whether the input daemon captures the keyboards (`RuntimeEvent.captureChanged`).
    public var isCapturing = false
    /// Capture takes a moment after a start or resume; until then not capturing isn't reported.
    public var captureGraceElapsed = false
    var hasStartedTask = false
    /// Set on quit: no more polls or starts, so nothing takes the keyboards over again before exit.
    public var isQuitting = false

    public init() {}

    /// The text next to the menu bar icon, as the settings choose: "", "DEF", "Mod" or "DEF · Mod".
    /// Paused isn't spelled out (the icon shows it) and drops the layer, since none is active.
    /// Before the runtime reports a status: "—", or "" when nothing is shown.
    public var menuBarTitle: String {
      let settings = configuration.settings
      guard settings.menuBarShowsKeymap || settings.menuBarShowsLayer else { return "" }
      guard let engineStatus else { return "—" }
      var parts: [String] = []
      if settings.menuBarShowsKeymap {
        parts.append(activeKeymapAbbreviation(engineStatus))
      }
      if settings.menuBarShowsLayer, !isPaused {
        parts.append(engineStatus.activeLayer.displayName)
      }
      return parts.joined(separator: " · ")
    }

    /// The full state for VoiceOver, whatever the menu bar shows: "KeyLayers, DEF, Mod".
    public var menuBarAccessibilityLabel: String {
      guard let engineStatus else { return "KeyLayers" }
      let layer = isPaused ? "Paused" : engineStatus.activeLayer.displayName
      return "KeyLayers, \(activeKeymapAbbreviation(engineStatus)), \(layer)"
    }

    private func activeKeymapAbbreviation(_ engineStatus: EngineStatus) -> String {
      configuration.keymaps[id: engineStatus.activeKeymapID]?.abbreviation ?? "—"
    }

    /// One line describing what the helper is doing, for the top of the menu.
    public var statusLine: String {
      if !permissions.allGranted {
        return "Waiting for Accessibility"
      }
      if startError != nil {
        return "Remapping couldn't start"
      }
      if inputServiceNeedsInputMonitoring {
        return "Input service needs Input Monitoring"
      }
      if inputServiceNotConnected {
        return "Input service not connected"
      }
      switch runtimePhase {
      case .notStarted, .starting: return "Starting…"
      case .running: return isPaused ? "Remapping paused" : "Remapping active"
      }
    }

    /// Remapping should be running, but the input daemon hasn't captured the keyboards (unreachable,
    /// released them, or no virtual keyboard) since the grace period after the start or resume.
    public var inputServiceNotConnected: Bool {
      runtimePhase == .running && !isPaused && !isCapturing && captureGraceElapsed
    }

    /// The daemon may not seize a keyboard: it lacks Input Monitoring (`kIOReturnNotPermitted`).
    public var inputServiceNeedsInputMonitoring: Bool {
      devices.contains { $0.seizeError == HelperFeature.seizeNotPermitted }
    }

    /// One line per keyboard the daemon couldn't seize for another reason than Input Monitoring.
    var seizeErrors: [String] {
      devices.compactMap { device in
        guard let error = device.seizeError, error != HelperFeature.seizeNotPermitted else { return nil }
        return "Couldn't take over \(device.name) (error 0x\(String(UInt32(bitPattern: error), radix: 16)))."
      }
    }

    public var helperStatus: HelperStatus {
      let errors = [configError] + seizeErrors + [startError.map { "Remapping couldn't start: \($0)" }]
      let messages = errors.compactMap(\.self)
      return HelperStatus(
        activeKeymapID: engineStatus?.activeKeymapID,
        activeLayer: engineStatus?.activeLayer ?? .base,
        isPaused: isPaused,
        permissions: permissions,
        configError: messages.isEmpty ? nil : messages.joined(separator: "\n"),
        inputServiceNeedsInputMonitoring: inputServiceNeedsInputMonitoring,
        isCapturing: !inputServiceNotConnected
      )
    }
  }

  public enum Action: Sendable {
    case task
    case permissionsChecked(PermissionStatus)
    case configurationChanged(Configuration)
    case configurationLoadErrorChanged
    case runtime(RuntimeEvent)
    case runtimeStarted
    case captureGraceElapsed
    case runtimeStartFailed(String)
    case pauseToggled
    case keymapSelected(Keymap.ID)
    case request(HelperRequest)
    case openConfiguratorTapped
    case quitTapped
    /// An update replaced the helper's executable: stop and exit so launchd starts the new one.
    case executableReplaced
  }

  static let permissionPollInterval: Duration = .seconds(2)
  /// How long after a start or resume the daemon may take to capture before the status says so.
  static let captureGracePeriod: Duration = .seconds(3)
  /// IOReturn `kIOReturnNotPermitted`: the input daemon lacks Input Monitoring.
  static let seizeNotPermitted = Int32(bitPattern: 0xE000_02E2)

  enum CancelID {
    case permissionPoll
    case captureGrace
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.permissions) var permissions
  @Dependency(\.remapperRuntime) var runtime
  @Dependency(\.hud) var hud
  @Dependency(\.helperServer) var server
  @Dependency(\.helperApp) var app

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        return task(&state)

      case let .permissionsChecked(status):
        state.permissions = status
        if !status.allGranted, state.runtimePhase != .notStarted {
          // Revoked while remapping: stop (releases held keys, hands the keyboards back).
          // The poll starts it again once it's granted.
          state.runtimePhase = .notStarted
          return .merge(.cancel(id: CancelID.captureGrace), .run { _ in runtime.stop() })
        }
        guard status.allGranted, state.runtimePhase == .notStarted, !state.isQuitting else { return .none }
        state.runtimePhase = .starting
        let configuration = state.$configuration
        return .run { send in
          do {
            // Read the shared value now, so a change that arrived since this action isn't lost.
            try runtime.start(configuration.wrappedValue)
            await send(.runtimeStarted)
          } catch {
            await send(.runtimeStartFailed(Self.describe(startError: error)))
          }
        }

      case .runtimeStarted:
        state.startError = nil
        guard state.permissions.allGranted else {
          // Permissions were revoked while it was starting.
          state.runtimePhase = .notStarted
          return .run { _ in runtime.stop() }
        }
        state.runtimePhase = .running
        return startCaptureGrace(&state)

      case .captureGraceElapsed:
        state.captureGraceElapsed = true
        return .none

      case let .runtimeStartFailed(message):
        state.runtimePhase = .notStarted
        state.startError = message
        return .none

      case let .configurationChanged(configuration):
        state.configError = Self.describe(loadError: state.$configuration.loadError)
        return .run { _ in runtime.update(configuration) }

      case .configurationLoadErrorChanged:
        state.configError = Self.describe(loadError: state.$configuration.loadError)
        return .none

      case let .runtime(.status(status)):
        state.engineStatus = status
        return .none

      case let .runtime(.notification(notification)):
        return handle(notification, &state)

      case let .runtime(.devices(devices)):
        state.devices = devices
        return .none

      case let .runtime(.captureChanged(capturing)):
        state.isCapturing = capturing
        return .none

      case .pauseToggled:
        return setPaused(!state.isPaused, &state)

      case let .request(.setPaused(paused)):
        return setPaused(paused, &state)

      case let .keymapSelected(id):
        return .run { _ in runtime.selectKeymap(id) }

      case .openConfiguratorTapped:
        return .run { _ in await app.openConfigurator() }

      case .quitTapped:
        return quit(&state) { await app.terminate() }

      case .executableReplaced:
        return quit(&state) { await app.restartForUpdate() }
      }
    }
    .onChange(of: \.helperStatus) { _, status in
      Reduce { _, _ in publish(status) }
    }
  }

  /// Stops polling and the runtime (releasing held keys, handing the keyboards back), then `exit`s.
  private func quit(_ state: inout State, exit: @escaping @Sendable () async -> Void) -> Effect<Action> {
    guard !state.isQuitting else { return .none }
    state.isQuitting = true
    return .merge(
      .cancel(id: CancelID.permissionPoll),
      .cancel(id: CancelID.captureGrace),
      .run { _ in
        runtime.stop()
        await exit()
      }
    )
  }

  private func task(_ state: inout State) -> Effect<Action> {
    // `.task` subscribes to single-consumer streams: only the first one counts.
    guard !state.hasStartedTask else { return .none }
    state.hasStartedTask = true
    state.configError = Self.describe(loadError: state.$configuration.loadError)
    let configuration = state.$configuration
    return .merge(
      // Before any permission gating, so an early configurator sees the helper's state.
      publish(state.helperStatus),
      .run { send in
        let status = permissions.status()
        if !status.allGranted {
          permissions.request()
        }
        await send(.permissionsChecked(status))
        // Keeps polling after the start: a failed start is retried on the next poll, and the
        // configurator sees permission changes. Each poll also notices an update that replaced
        // the helper on disk.
        while true {
          try await clock.sleep(for: Self.permissionPollInterval)
          if app.executableReplaced() {
            await send(.executableReplaced)
            return
          }
          await send(.permissionsChecked(permissions.status()))
        }
      }
      .cancellable(id: CancelID.permissionPoll),
      // A publisher effect delivers every change in order (an async sequence would drop values
      // emitted while the consumer is busy). A failed load never emits.
      .publisher {
        configuration.publisher.dropFirst().map(Action.configurationChanged)
      },
      .run { send in
        for await _ in Self.loadErrorChanges(of: configuration) {
          await send(.configurationLoadErrorChanged)
        }
      },
      .run { send in
        for await event in runtime.events() {
          await send(.runtime(event))
        }
      },
      .run { send in
        for await request in server.requests() {
          await send(.request(request))
        }
      },
      // SIGTERM (launchd: SMAppService unregister, `launchctl bootout`) quits like the menu does.
      .run { send in
        for await _ in app.terminationRequests() {
          await send(.quitTapped)
        }
      }
    )
  }

  private func handle(_ notification: EngineNotification, _ state: inout State) -> Effect<Action> {
    let showHUD = state.configuration.settings.showLayerHUD
    switch notification {
    case let .layerLatched(layer):
      return showHUD ? show(layer.displayName) : .none
    case .layerUnlatched:
      return .none
    case let .keymapSwitched(id):
      guard showHUD, let keymap = state.configuration.keymaps[id: id] else { return .none }
      return show(keymap.name)
    case .emergencyStop:
      // The runtime has already paused itself; this keeps the reducer and the runtime client in sync.
      state.isPaused = true
      return .merge(
        .run { _ in runtime.setPaused(true) },
        show("Remapping paused")
      )
    }
  }

  private func setPaused(_ paused: Bool, _ state: inout State) -> Effect<Action> {
    let resumed = state.isPaused && !paused
    state.isPaused = paused
    let effect = Effect<Action>.run { _ in runtime.setPaused(paused) }
    // Resuming starts capture again.
    return resumed && state.runtimePhase == .running ? .merge(effect, startCaptureGrace(&state)) : effect
  }

  /// (Re)starts the grace period after which not capturing is reported.
  private func startCaptureGrace(_ state: inout State) -> Effect<Action> {
    state.captureGraceElapsed = false
    return .run { send in
      try await clock.sleep(for: Self.captureGracePeriod)
      await send(.captureGraceElapsed)
    }
    .cancellable(id: CancelID.captureGrace, cancelInFlight: true)
  }

  private func show(_ text: String) -> Effect<Action> {
    .run { _ in await hud.show(text) }
  }

  /// Main-actor effects start in the order they're created and run without hopping, so statuses
  /// reach the server in the order the state produced them.
  private func publish(_ status: HelperStatus) -> Effect<Action> {
    .run { @MainActor _ in server.publish(status) }
  }

  // MARK: - Helpers

  /// Fires whenever the shared configuration's load error is set or cleared.
  static func loadErrorChanges(of configuration: Shared<Configuration>) -> AsyncStream<Void> {
    AsyncStream { continuation in
      @Sendable func observe() {
        withObservationTracking {
          _ = configuration.loadError
        } onChange: {
          // Stop observing once the consumer is gone; otherwise re-register right away (from
          // `willSet`) so no later change is missed.
          if case .terminated = continuation.yield() {
            return
          }
          observe()
        }
      }
      observe()
    }
  }

  static func describe(loadError: (any Error)?) -> String? {
    ConfigurationLoadError.message(for: loadError)
  }

  static func describe(startError error: any Error) -> String {
    switch error {
    case KeyIOError.daemonUnavailable:
      "The KeyLayers input service isn't running or needs approval in Login Items."
    case KeyIOError.virtualKeyboardUnavailable:
      "The virtual keyboard couldn't be created. Check Accessibility for KeyLayersHelper."
    default:
      error.localizedDescription
    }
  }
}
