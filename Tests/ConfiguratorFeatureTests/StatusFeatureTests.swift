import ComposableArchitecture
@testable import ConfiguratorFeature
import Foundation
import HelperIPC
import KeymapModel
import Sharing
import Testing

@MainActor
private func makeStore(
  _ fakes: Fakes,
  state: StatusFeature.State = StatusFeature.State()
) -> TestStoreOf<StatusFeature> {
  TestStore(initialState: state) {
    StatusFeature()
  } withDependencies: {
    fakes.apply(to: &$0)
  }
}

private let granted = PermissionStatus(accessibility: true)

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct StatusFeatureTests {
  @Test func statusFollowsHelperStates() async throws {
    let fakes = try Fakes()
    fakes.registrationStatus.setValue(.enabled)
    let store = makeStore(fakes)

    let task = await store.send(.task)
    await store.receive(\.refreshed) { $0.registration = .enabled }

    let status = HelperStatus(activeKeymapID: Keymap.starterID, activeLayer: .mod, permissions: granted)
    fakes.statesContinuation.yield(.running(status))
    await store.receive(\.stateChanged) { $0.helper = .running(status) }
    // Every helper state change refreshes the registration (it may just have been approved).
    await store.receive(\.refreshed)

    fakes.statesContinuation.yield(.notRunning)
    await store.receive(\.stateChanged) { $0.helper = .notRunning }
    await store.receive(\.refreshed)
    await task.cancel()
  }

  @Test func pauseSendsRequest() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes, state: StatusFeature.State(helper: .running(HelperStatus(permissions: granted))))

    await store.send(.pauseToggled)
    await store.finish()
    #expect(fakes.pauseRequests.value == [true])

    await store.send(.stateChanged(.running(HelperStatus(isPaused: true, permissions: granted)))) {
      $0.helper = .running(HelperStatus(isPaused: true, permissions: granted))
    }
    await store.receive(\.refreshed) { $0.registration = .notRegistered }
    await store.send(.pauseToggled)
    await store.finish()
    #expect(fakes.pauseRequests.value == [true, false])
  }

  @Test func hangingPauseRequestBlocksNothing() async throws {
    let fakes = try Fakes()
    // A wedged helper: the requests don't return until the end of the test.
    let pending = LockIsolated<[CheckedContinuation<Void, Never>]>([])
    let store = TestStore(initialState: StatusFeature.State(helper: .running(HelperStatus(permissions: granted)))) {
      StatusFeature()
    } withDependencies: {
      fakes.apply(to: &$0)
      $0.helperClient.setPaused = { _ in
        await withCheckedContinuation { continuation in pending.withValue { $0.append(continuation) } }
      }
    }

    // No "pausing" state: nothing is disabled while the requests are in flight, and other
    // actions and helper updates are still handled.
    await store.send(.pauseToggled)
    await store.send(.pauseToggled)
    await store.send(.stateChanged(.notRunning)) { $0.helper = .notRunning }
    await store.receive(\.refreshed) { $0.registration = .notRegistered }
    await store.send(.enableHelperTapped)
    await store.receive(\.refreshed) { $0.registration = .enabled; $0.daemonRegistration = .enabled }
    #expect(fakes.registrationCalls.value == ["register"])

    while pending.value.count < 2 {
      await Task.yield()
    }
    for continuation in pending.value {
      continuation.resume()
    }
    await store.finish()
  }

  @Test func pauseWhileNotRunningDoesNothing() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.pauseToggled)
    await store.finish()
    #expect(fakes.pauseRequests.value.isEmpty)
  }

  @Test func openSettingsOpensPane() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.openSettingsTapped(.accessibility))
    await store.send(.openSettingsTapped(.inputMonitoring))
    await store.finish()
    #expect(fakes.openedPanes.value == [.accessibility, .inputMonitoring])
  }

  @Test func enableHelperRegisters() async throws {
    let fakes = try Fakes()
    let launchAtLogin = fakes.makeState { Shared(.launchHelperAtLogin) }
    launchAtLogin.withLock { $0 = false }
    let store = makeStore(fakes)

    await store.send(.enableHelperTapped)
    await store.receive(\.refreshed) { $0.registration = .enabled; $0.daemonRegistration = .enabled }
    #expect(fakes.registrationCalls.value == ["register"])
    // Enabling by hand also turns "launch at login" back on.
    #expect(launchAtLogin.wrappedValue)
  }

  @Test func enableHelperOpensLoginItemsWhenApprovalIsRequired() async throws {
    let fakes = try Fakes()
    fakes.registrationStatus.setValue(.requiresApproval)
    let store = makeStore(fakes, state: StatusFeature.State(registration: .requiresApproval))

    await store.send(.enableHelperTapped)
    await store.finish()
    #expect(fakes.openedPanes.value == [.loginItems])
    #expect(fakes.registrationCalls.value.isEmpty)
  }

  @Test func registrationFailureIsShown() async throws {
    let fakes = try Fakes()
    fakes.registrationError.setValue(RegistrationFailure())
    let store = makeStore(fakes)

    await store.send(.enableHelperTapped)
    await store.receive(\.registrationFailed) {
      $0.registrationError = "The helper couldn't be enabled: Operation not permitted"
    }
    await store.receive(\.refreshed) { $0.registration = .notRegistered; $0.daemonRegistration = .enabled }

    fakes.registrationError.setValue(nil)
    await store.send(.enableHelperTapped)
    await store.receive(\.refreshed) {
      $0.registration = .enabled
      $0.registrationError = nil
    }
  }

  @Test func startHelperLaunchesHelper() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes, state: StatusFeature.State(helper: .notRunning, registration: .enabled))

    await store.send(.startHelperTapped)
    await store.finish()
    #expect(fakes.startRequests.value == 1)
  }

  @Test func startHelperOfferedOnlyWhileRegisteredAndNotRunning() {
    // E.g. after the user chose Quit in the helper's menu: it stays quit until started here.
    #expect(StatusFeature.State(helper: .notRunning, registration: .enabled).showsStartHelper)
    #expect(!StatusFeature.State(helper: .notRunning, registration: .enabled).showsEnableHelper)
    #expect(!StatusFeature.State(helper: .running(HelperStatus()), registration: .enabled).showsStartHelper)
    #expect(!StatusFeature.State(helper: .notRunning, registration: .notRegistered).showsStartHelper)
    #expect(!StatusFeature.State(helper: .notRunning, registration: .requiresApproval).showsStartHelper)
  }

  @Test func headlines() {
    #expect(StatusFeature.State(helper: .notRunning, registration: .enabled).headline == "Remapper not running")
    #expect(
      StatusFeature.State(helper: .notRunning, registration: .requiresApproval).headline
        == "Remapper not running: the helper needs approval in System Settings"
    )
    #expect(StatusFeature.State(helper: .running(HelperStatus())).headline == "Remapper waiting for permissions")
    #expect(StatusFeature.State(helper: .running(HelperStatus(permissions: granted))).headline == "Remapping active")
    #expect(
      StatusFeature.State(helper: .running(HelperStatus(isPaused: true, permissions: granted))).headline
        == "Remapping paused"
    )
  }

  @Test func daemonNeedsApprovalHeadline() async throws {
    let fakes = try Fakes()
    let state = StatusFeature.State(
      helper: .running(HelperStatus(permissions: granted)),
      registration: .enabled,
      daemonRegistration: .requiresApproval
    )
    #expect(state.headline == "Remapper waiting: approve “KeyLayers” in Login Items")
    #expect(state.showsEnableHelper)
    #expect(state.enableHelperTitle == "Open Login Items…")

    let store = makeStore(fakes, state: state)
    await store.send(.enableHelperTapped)
    await store.finish()
    #expect(fakes.openedPanes.value == [.loginItems])
    #expect(fakes.registrationCalls.value.isEmpty)
  }

  @Test func headlinePrecedence() {
    let needsIM = HelperStatus(permissions: granted, inputServiceNeedsInputMonitoring: true)
    // Daemon approval beats Accessibility, which beats the input service's Input Monitoring.
    #expect(
      StatusFeature.State(
        helper: .running(HelperStatus(inputServiceNeedsInputMonitoring: true)),
        registration: .enabled, daemonRegistration: .requiresApproval
      ).headline == "Remapper waiting: approve “KeyLayers” in Login Items"
    )
    #expect(
      StatusFeature.State(helper: .running(HelperStatus(inputServiceNeedsInputMonitoring: true)))
        .headline == "Remapper waiting for permissions"
    )
    #expect(
      StatusFeature.State(helper: .running(needsIM)).headline
        == "Remapper waiting: the input service needs Input Monitoring"
    )
    // A helper that isn't running wins over everything.
    #expect(
      StatusFeature.State(helper: .notRunning, registration: .enabled, daemonRegistration: .requiresApproval).headline
        == "Remapper not running"
    )
  }

  @Test func inputServiceNotConnectedHeadline() {
    let notCapturing = HelperStatus(permissions: granted, isCapturing: false)
    #expect(StatusFeature.State(helper: .running(notCapturing)).headline == "Input service not connected")
    // Login Items approval, permissions and Input Monitoring explain it better.
    #expect(
      StatusFeature.State(helper: .running(notCapturing), registration: .enabled, daemonRegistration: .requiresApproval)
        .headline == "Remapper waiting: approve “KeyLayers” in Login Items"
    )
    #expect(
      StatusFeature.State(helper: .running(HelperStatus(isCapturing: false))).headline
        == "Remapper waiting for permissions"
    )
    #expect(
      StatusFeature.State(
        helper: .running(HelperStatus(permissions: granted, inputServiceNeedsInputMonitoring: true, isCapturing: false))
      ).headline == "Remapper waiting: the input service needs Input Monitoring"
    )
  }

  @Test func inputServiceNeedsInputMonitoringShowsStep() {
    let state = StatusFeature.State(
      helper: .running(HelperStatus(permissions: granted, inputServiceNeedsInputMonitoring: true)),
      registration: .enabled
    )
    #expect(state.showsInputServiceInputMonitoringStep)
    #expect(state.headline == "Remapper waiting: the input service needs Input Monitoring")
    let runningState = StatusFeature.State(helper: .running(HelperStatus(permissions: granted)))
    #expect(!runningState.showsInputServiceInputMonitoringStep)
    #expect(!StatusFeature.State(helper: .notRunning).showsInputServiceInputMonitoringStep)
  }

  @Test func showInFinderRevealsDaemon() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.showInputServiceInFinderTapped)
    await store.finish()
    let url = try #require(fakes.revealedURLs.value.first)
    #expect(fakes.revealedURLs.value.count == 1)
    #expect(url.path.hasSuffix("Contents/Library/HelperTools/KeyLayersInputDaemon"))
  }

  @Test func openInputMonitoringOpensPane() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.openSettingsTapped(.inputMonitoring))
    await store.finish()
    #expect(fakes.openedPanes.value == [.inputMonitoring])
  }

  @Test func daemonRegistrationFailureHasItsOwnMessage() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.registrationFailed("The helper couldn't be enabled: A")) {
      $0.registrationError = "The helper couldn't be enabled: A"
    }
    await store.send(.daemonRegistrationFailed("The input service couldn't be enabled: B")) {
      $0.daemonRegistrationError = "The input service couldn't be enabled: B"
    }
    #expect(
      store.state.registrationMessage
        == "The helper couldn't be enabled: A\nThe input service couldn't be enabled: B"
    )
    #expect(HelperRegistrationClient.describeDaemon(RegistrationFailure())
      == "The input service couldn't be enabled: Operation not permitted")
  }

  @Test func modifierKeysNote() async throws {
    let fakes = try Fakes()
    fakes.remappedKeyboards.setValue(["Apple Internal Keyboard / Trackpad"])
    let store = makeStore(fakes)

    await store.send(.task)
    await store.receive(\.refreshed) {
      $0.registration = .notRegistered
      $0.remappedKeyboards = ["Apple Internal Keyboard / Trackpad"]
    }
    #expect(
      store.state.modifierKeysNote
        == "macOS Modifier Keys settings don't apply while KeyLayers remaps a keyboard. "
        + "Set those remaps in your keymap instead."
    )
    await store.skipInFlightEffects()
    #expect(StatusFeature.State().modifierKeysNote == nil)
  }

  @Test func enableRegistersDaemonWhileHelperRuns() async throws {
    let fakes = try Fakes()
    fakes.registrationStatus.setValue(.enabled)
    let state = StatusFeature.State(
      helper: .running(HelperStatus(permissions: granted)), registration: .enabled, daemonRegistration: .notRegistered
    )
    #expect(state.showsEnableHelper)
    #expect(state.enableHelperTitle == "Enable Input Service")
    #expect(!StatusFeature.State(
      helper: .running(HelperStatus(permissions: granted)), registration: .enabled, daemonRegistration: .enabled
    ).showsEnableHelper)

    let store = makeStore(fakes, state: state)
    await store.send(.enableHelperTapped)
    await store.receive(\.refreshed) { $0.daemonRegistration = .enabled }
    #expect(fakes.daemonCalls.value == ["register"])
    #expect(fakes.registrationCalls.value.isEmpty)
  }

  @Test func daemonRegistrationFailureOnEnableIsShown() async throws {
    let fakes = try Fakes()
    fakes.registrationStatus.setValue(.enabled)
    fakes.daemonRegistrationError.setValue(RegistrationFailure())
    let store = makeStore(fakes, state: StatusFeature.State(
      helper: .running(HelperStatus(permissions: granted)), registration: .enabled
    ))
    await store.send(.enableHelperTapped)
    await store.receive(\.daemonRegistrationFailed) {
      $0.daemonRegistrationError = "The input service couldn't be enabled: Operation not permitted"
    }
    await store.receive(\.refreshed)
  }
}
