import ComposableArchitecture
import Foundation
@testable import HelperFeature
import HelperIPC
import InputDaemonIPC
import KeyIO
import KeymapModel
import RemapEngine
import SharedConfig
@_spi(Internals) import Sharing
import Testing

private let granted = PermissionStatus(accessibility: true)
private let denied = PermissionStatus(accessibility: false)

private struct StartFailure: LocalizedError {
  var errorDescription: String? {
    "Something failed"
  }
}

private func device(_ id: UInt64, _ name: String, seizeError: UInt32? = nil) -> InputDevice {
  InputDevice(
    id: id, name: name, vendorID: 0x05AC, productID: 0x0342, countryCode: 0,
    seizeError: seizeError.map { Int32(bitPattern: $0) }
  )
}

/// Fake dependencies that record every call.
private final class Fakes: Sendable {
  let fileSystem = LockIsolated<[URL: Data]>([:])
  let clock = TestClock()
  let permissionStatus = LockIsolated(denied)
  let permissionRequests = LockIsolated(0)
  let starts = LockIsolated<[Configuration]>([])
  let startError = LockIsolated<(any Error)?>(nil)
  let updates = LockIsolated<[Configuration]>([])
  let paused = LockIsolated<[Bool]>([])
  let selected = LockIsolated<[Keymap.ID]>([])
  let eventsCalls = LockIsolated(0)
  let hud = LockIsolated<[String]>([])
  let published = LockIsolated<[HelperStatus]>([])
  /// Order of the quit sequence and configurator opens.
  let calls = LockIsolated<[String]>([])
  let events: AsyncStream<RuntimeEvent>
  let eventsContinuation: AsyncStream<RuntimeEvent>.Continuation
  let requests: AsyncStream<HelperRequest>
  let requestsContinuation: AsyncStream<HelperRequest>.Continuation
  let terminationRequests: AsyncStream<Void>
  let terminationRequestsContinuation: AsyncStream<Void>.Continuation

  init() {
    (events, eventsContinuation) = AsyncStream.makeStream()
    (requests, requestsContinuation) = AsyncStream.makeStream()
    (terminationRequests, terminationRequestsContinuation) = AsyncStream.makeStream()
  }

  var fileStorage: FileStorage {
    .inMemory(fileSystem: fileSystem)
  }

  func writeFile(_ data: Data) {
    fileSystem.withValue { $0[AppIdentifiers.configurationURL] = data }
  }

  func writeFile(_ configuration: Configuration) throws {
    try writeFile(Configuration.encoder.encode(configuration))
  }

  func apply(to dependencies: inout DependencyValues) {
    dependencies.defaultFileStorage = fileStorage
    dependencies.continuousClock = clock
    dependencies.permissions = PermissionsClient(
      status: { self.permissionStatus.value },
      request: { self.permissionRequests.withValue { $0 += 1 } }
    )
    dependencies.remapperRuntime = RemapperRuntimeClient(
      start: { configuration in
        self.starts.withValue { $0.append(configuration) }
        if let error = self.startError.value {
          throw error
        }
      },
      update: { configuration in self.updates.withValue { $0.append(configuration) } },
      setPaused: { paused in self.paused.withValue { $0.append(paused) } },
      selectKeymap: { id in self.selected.withValue { $0.append(id) } },
      stop: { self.calls.withValue { $0.append("stop") } },
      events: {
        self.eventsCalls.withValue { $0 += 1 }
        return self.events
      }
    )
    dependencies.hud = HUDClient(show: { text in self.hud.withValue { $0.append(text) } })
    dependencies.helperServer = HelperServerClient(
      publish: { status in self.published.withValue { $0.append(status) } },
      requests: { self.requests }
    )
    dependencies.helperApp = HelperAppClient(
      openConfigurator: { self.calls.withValue { $0.append("openConfigurator") } },
      terminate: { self.calls.withValue { $0.append("terminate") } },
      terminationRequests: { self.terminationRequests }
    )
  }
}

@MainActor
private func makeStore(
  _ fakes: Fakes,
  modify: (inout HelperFeature.State) -> Void = { _ in }
) -> TestStoreOf<HelperFeature> {
  var state = withDependencies {
    $0.defaultFileStorage = fakes.fileStorage
  } operation: {
    HelperFeature.State()
  }
  modify(&state)
  return TestStore(initialState: state) {
    HelperFeature()
  } withDependencies: {
    fakes.apply(to: &$0)
  }
}

private let otherKeymapID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

private func configuration(doubleTap: Int = 250, showLayerHUD: Bool = true) -> Configuration {
  var configuration = Configuration.starter
  configuration.settings.doubleTapTimeoutMilliseconds = doubleTap
  configuration.settings.showLayerHUD = showLayerHUD
  configuration.keymaps.append(Keymap(id: otherKeymapID, name: "Coding", abbreviation: "COD"))
  return configuration
}

/// The menu bar title and accessibility label for the given settings and runtime state.
@MainActor
private func menuBar(
  keymap: Bool = false,
  layer: Bool = false,
  status: EngineStatus? = nil,
  paused: Bool = false
) throws -> (title: String, accessibilityLabel: String) {
  let fakes = Fakes()
  var configuration = configuration()
  configuration.settings.menuBarShowsKeymap = keymap
  configuration.settings.menuBarShowsLayer = layer
  try fakes.writeFile(configuration)
  let store = makeStore(fakes) {
    $0.engineStatus = status
    $0.isPaused = paused
  }
  return (store.state.menuBarTitle, store.state.menuBarAccessibilityLabel)
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HelperFeatureTests {
  @Test func startsRuntimeOnlyAfterPermissionsGranted() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    let task = await store.send(.task) { $0.hasStartedTask = true }
    await store.receive(\.permissionsChecked)
    #expect(fakes.permissionRequests.value == 1)
    #expect(fakes.starts.value.isEmpty)

    fakes.permissionStatus.setValue(granted)
    await fakes.clock.advance(by: .seconds(1))
    #expect(fakes.starts.value.isEmpty)
    await fakes.clock.advance(by: .seconds(1))
    await store.receive(\.permissionsChecked) {
      $0.permissions = granted
      $0.runtimePhase = .starting
    }
    await store.receive(\.runtimeStarted) { $0.runtimePhase = .running }
    #expect(fakes.starts.value == [.starter])

    await fakes.clock.advance(by: .seconds(2))
    await store.receive(\.permissionsChecked)
    #expect(fakes.starts.value.count == 1)
    await task.cancel()
  }

  @Test func publishesStatusImmediatelyOnTask() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    let task = await store.send(.task) { $0.hasStartedTask = true }
    await store.receive(\.permissionsChecked)
    #expect(fakes.published.value.first == HelperStatus())
    await task.cancel()
  }

  @Test func taskSubscribesOnceAndForwardsRequests() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    let task = await store.send(.task) { $0.hasStartedTask = true }
    await store.receive(\.permissionsChecked)
    await store.send(.task)
    #expect(fakes.eventsCalls.value == 1)

    fakes.requestsContinuation.yield(.setPaused(true))
    await store.receive(\.request) { $0.isPaused = true }
    fakes.eventsContinuation.yield(.status(EngineStatus(activeKeymapID: Keymap.starterID, activeLayer: .fn)))
    await store.receive(\.runtime) {
      $0.engineStatus = EngineStatus(activeKeymapID: Keymap.starterID, activeLayer: .fn)
    }
    #expect(fakes.paused.value == [true])
    await task.cancel()
  }

  @Test func startFailureIsReportedAndRetriedOnNextPoll() async {
    let fakes = Fakes()
    fakes.permissionStatus.setValue(granted)
    fakes.startError.setValue(StartFailure())
    let store = makeStore(fakes)

    let task = await store.send(.task) { $0.hasStartedTask = true }
    await store.receive(\.permissionsChecked) {
      $0.permissions = granted
      $0.runtimePhase = .starting
    }
    await store.receive(\.runtimeStartFailed) {
      $0.runtimePhase = .notStarted
      $0.startError = "Something failed"
    }
    #expect(fakes.permissionRequests.value == 0)
    #expect(fakes.published.value.last?.configError == "Remapping couldn't start: Something failed")

    fakes.startError.setValue(nil)
    await fakes.clock.advance(by: .seconds(2))
    await store.receive(\.permissionsChecked) { $0.runtimePhase = .starting }
    await store.receive(\.runtimeStarted) {
      $0.runtimePhase = .running
      $0.startError = nil
    }
    #expect(fakes.starts.value.count == 2)
    #expect(fakes.published.value.last?.configError == nil)
    await task.cancel()
  }

  @Test func describesBackendStartErrors() {
    #expect(HelperFeature.describe(startError: KeyIOError.daemonUnavailable)
      == "The KeyLayers input service isn't running or needs approval in Login Items.")
    #expect(HelperFeature.describe(startError: KeyIOError.virtualKeyboardUnavailable)
      == "The virtual keyboard couldn't be created. Check Accessibility for KeyLayersHelper.")
  }

  @Test func statusLineWaitsOnlyForAccessibility() {
    var state = withDependencies {
      $0.defaultFileStorage = .inMemory(fileSystem: LockIsolated([:]))
    } operation: {
      HelperFeature.State()
    }
    #expect(state.statusLine == "Waiting for Accessibility")
    state.permissions = granted
    #expect(state.statusLine == "Starting…")
  }

  @Test func statusLineReportsInputServiceNotCapturing() {
    var state = withDependencies {
      $0.defaultFileStorage = .inMemory(fileSystem: LockIsolated([:]))
    } operation: {
      HelperFeature.State()
    }
    state.permissions = granted
    state.runtimePhase = .running
    #expect(state.statusLine == "Remapping active", "within the grace period after the start")
    #expect(state.helperStatus.isCapturing)
    state.captureGraceElapsed = true
    #expect(state.statusLine == "Input service not connected")
    #expect(!state.helperStatus.isCapturing)
    state.isPaused = true
    #expect(state.statusLine == "Remapping paused")
    #expect(state.helperStatus.isCapturing, "paused: nothing to capture")
    state.isPaused = false
    state.isCapturing = true
    #expect(state.statusLine == "Remapping active")
    #expect(state.helperStatus.isCapturing)
  }

  @Test func inputServiceNotConnectedOnlyAfterGracePeriod() async {
    let fakes = Fakes()
    let store = makeStore(fakes) {
      $0.permissions = granted
      $0.runtimePhase = .starting
    }

    await store.send(.runtimeStarted) { $0.runtimePhase = .running }
    await fakes.clock.advance(by: .milliseconds(2900))
    #expect(store.state.statusLine == "Remapping active", "no flash on every launch")
    await fakes.clock.advance(by: .milliseconds(100))
    await store.receive(\.captureGraceElapsed) { $0.captureGraceElapsed = true }
    #expect(store.state.statusLine == "Input service not connected")
    #expect(fakes.published.value.last?.isCapturing == false)

    // The daemon captures (e.g. relaunched, or approved in Login Items).
    await store.send(.runtime(.captureChanged(true))) { $0.isCapturing = true }
    #expect(store.state.statusLine == "Remapping active")
    #expect(fakes.published.value.last?.isCapturing == true)

    // Lost again (daemon timeout, connection lost): reported at once, the start is long past.
    await store.send(.runtime(.captureChanged(false))) { $0.isCapturing = false }
    #expect(store.state.statusLine == "Input service not connected")

    // Pause and resume: capture restarts, so the grace period does too.
    await store.send(.pauseToggled) { $0.isPaused = true }
    await store.send(.pauseToggled) {
      $0.isPaused = false
      $0.captureGraceElapsed = false
    }
    #expect(store.state.statusLine == "Remapping active")
    await fakes.clock.advance(by: .seconds(3))
    await store.receive(\.captureGraceElapsed) { $0.captureGraceElapsed = true }
    await store.finish()
  }

  @Test func daemonWithoutInputMonitoringIsReported() async {
    let fakes = Fakes()
    let store = makeStore(fakes) {
      $0.permissions = granted
      $0.runtimePhase = .running
    }
    let devices = [device(1, "Apple Internal Keyboard / Trackpad", seizeError: 0xE000_02E2)]

    await store.send(.runtime(.devices(devices))) { $0.devices = devices }
    await store.finish()
    #expect(store.state.statusLine == "Input service needs Input Monitoring")
    #expect(fakes.published.value.last?.inputServiceNeedsInputMonitoring == true)
    #expect(fakes.published.value.last?.configError == nil)

    // Granted: the relaunched daemon seizes the keyboard.
    let seized = [device(1, "Apple Internal Keyboard / Trackpad")]
    await store.send(.runtime(.devices(seized))) { $0.devices = seized }
    await store.finish()
    #expect(store.state.statusLine == "Remapping active")
    #expect(fakes.published.value.last?.inputServiceNeedsInputMonitoring == false)
  }

  @Test func otherSeizeErrorsGoIntoConfigError() async {
    let fakes = Fakes()
    let store = makeStore(fakes) {
      $0.permissions = granted
      $0.runtimePhase = .running
    }
    let devices = [
      device(1, "Apple Internal Keyboard / Trackpad"),
      device(2, "Keychron K2", seizeError: 0xE000_02C5),
    ]

    await store.send(.runtime(.devices(devices))) { $0.devices = devices }
    await store.finish()
    #expect(store.state.statusLine == "Remapping active")
    let status = fakes.published.value.last
    #expect(status?.inputServiceNeedsInputMonitoring == false)
    #expect(status?.configError == "Couldn't take over Keychron K2 (error 0xe00002c5).")
  }

  @Test func revokedPermissionStopsRuntimeAndRegrantRestartsIt() async {
    let fakes = Fakes()
    fakes.permissionStatus.setValue(granted)
    let store = makeStore(fakes)

    let task = await store.send(.task) { $0.hasStartedTask = true }
    await store.receive(\.permissionsChecked) {
      $0.permissions = granted
      $0.runtimePhase = .starting
    }
    await store.receive(\.runtimeStarted) { $0.runtimePhase = .running }

    // Revoked: the runtime stops (held keys released, keyboards handed back).
    fakes.permissionStatus.setValue(denied)
    await fakes.clock.advance(by: .seconds(2))
    await store.receive(\.permissionsChecked) {
      $0.permissions = denied
      $0.runtimePhase = .notStarted
    }
    // The stop runs in an effect; the permission poll keeps the store from finishing.
    for _ in 0 ..< 1000 where fakes.calls.value.isEmpty {
      await Task.yield()
    }
    #expect(fakes.calls.value == ["stop"])

    // Granted again: the poll restarts it.
    fakes.permissionStatus.setValue(granted)
    await fakes.clock.advance(by: .seconds(2))
    await store.receive(\.permissionsChecked) {
      $0.permissions = granted
      $0.runtimePhase = .starting
    }
    await store.receive(\.runtimeStarted) { $0.runtimePhase = .running }
    #expect(fakes.starts.value.count == 2)
    await task.cancel()
  }

  @Test func startFinishingAfterRevocationStopsAgain() async {
    let fakes = Fakes()
    let store = makeStore(fakes) {
      $0.permissions = granted
      $0.runtimePhase = .starting
    }

    await store.send(.permissionsChecked(denied)) {
      $0.permissions = denied
      $0.runtimePhase = .notStarted
    }
    // The start that was already under way completes after the revocation: stopped again.
    await store.send(.runtimeStarted)
    await store.finish()
    #expect(fakes.calls.value == ["stop", "stop"])
  }

  @Test func latchedLayerShowsHUD() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    await store.send(.runtime(.notification(.layerLatched(.mod))))
    await store.finish()
    #expect(fakes.hud.value == ["Mod"])
  }

  @Test func keymapSwitchShowsKeymapName() async throws {
    let fakes = Fakes()
    try fakes.writeFile(configuration())
    let store = makeStore(fakes)

    await store.send(.runtime(.notification(.keymapSwitched(otherKeymapID))))
    await store.send(.runtime(.notification(.layerUnlatched(.mod))))
    await store.finish()
    #expect(fakes.hud.value == ["Coding"])
  }

  @Test func hudDisabledShowsNothing() async throws {
    let fakes = Fakes()
    try fakes.writeFile(configuration(showLayerHUD: false))
    let store = makeStore(fakes)

    await store.send(.runtime(.notification(.layerLatched(.mod))))
    await store.send(.runtime(.notification(.keymapSwitched(otherKeymapID))))
    await store.finish()
    #expect(fakes.hud.value.isEmpty)
  }

  @Test func emergencyStopMarksPaused() async {
    let fakes = Fakes()
    let store = makeStore(fakes) {
      $0.engineStatus = EngineStatus(activeKeymapID: Keymap.starterID, activeLayer: .mod)
    }

    await store.send(.runtime(.notification(.emergencyStop))) { $0.isPaused = true }
    await store.finish()
    #expect(store.state.isPaused)
    #expect(fakes.hud.value == ["Remapping paused"])
    #expect(store.state.menuBarTitle == "")
    #expect(store.state.menuBarAccessibilityLabel == "KeyLayers, DEF, Paused")
    #expect(fakes.paused.value == [true])
  }

  @Test func menuBarTitleShowsWhatIsEnabled() throws {
    let mod = EngineStatus(activeKeymapID: Keymap.starterID, activeLayer: .mod)
    #expect(try menuBar(status: mod).title == "")
    #expect(try menuBar(keymap: true, status: mod).title == "DEF")
    #expect(try menuBar(layer: true, status: mod).title == "Mod")
    #expect(try menuBar(keymap: true, layer: true, status: mod).title == "DEF · Mod")
  }

  @Test func menuBarTitleNeverSaysPaused() throws {
    let mod = EngineStatus(activeKeymapID: Keymap.starterID, activeLayer: .mod)
    #expect(try menuBar(keymap: true, layer: true, status: mod, paused: true).title == "DEF")
    #expect(try menuBar(layer: true, status: mod, paused: true).title == "")
  }

  @Test func menuBarTitleBeforeStatus() throws {
    #expect(try menuBar().title == "")
    #expect(try menuBar(layer: true).title == "—")
    #expect(try menuBar(keymap: true).title == "—")
  }

  @Test func menuBarAccessibilityLabelIsAlwaysComplete() throws {
    let mod = EngineStatus(activeKeymapID: Keymap.starterID, activeLayer: .mod)
    #expect(try menuBar().accessibilityLabel == "KeyLayers")
    #expect(try menuBar(status: mod).accessibilityLabel == "KeyLayers, DEF, Mod")
    #expect(try menuBar(status: mod, paused: true).accessibilityLabel == "KeyLayers, DEF, Paused")
  }

  @Test func pauseToggledPausesAndResumes() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    await store.send(.pauseToggled) { $0.isPaused = true }
    await store.send(.pauseToggled) { $0.isPaused = false }
    #expect(fakes.paused.value == [true, false])
  }

  @Test func requestFromConfiguratorPauses() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    await store.send(.request(.setPaused(true))) { $0.isPaused = true }
    await store.finish()
    #expect(fakes.paused.value == [true])
  }

  @Test func keymapSelectedSwitchesRuntime() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    await store.send(.keymapSelected(otherKeymapID))
    await store.finish()
    #expect(fakes.selected.value == [otherKeymapID])
  }

  @Test func publishesStatusOnChange() async {
    let fakes = Fakes()
    let store = makeStore(fakes) { $0.permissions = granted }

    await store.send(.runtime(.status(EngineStatus(activeKeymapID: Keymap.starterID, activeLayer: .mod)))) {
      $0.engineStatus = EngineStatus(activeKeymapID: Keymap.starterID, activeLayer: .mod)
    }
    await store.finish()
    #expect(fakes.published.value.last == HelperStatus(
      activeKeymapID: Keymap.starterID,
      activeLayer: .mod,
      isPaused: false,
      permissions: granted,
      configError: nil
    ))
  }

  @Test func configurationChangeUpdatesRuntime() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    await store.send(.configurationChanged(configuration(doubleTap: 400)))
    await store.finish()
    #expect(fakes.updates.value == [configuration(doubleTap: 400)])
  }

  @Test func invalidFileAtLaunchReportsErrorAndNeverWrites() async {
    let fakes = Fakes()
    fakes.writeFile(Data("{".utf8))
    fakes.permissionStatus.setValue(granted)
    let store = makeStore(fakes)

    let task = await store.send(.task) {
      $0.hasStartedTask = true
      $0.configError = "The configuration file is damaged and can't be read."
    }
    await store.receive(\.permissionsChecked) {
      $0.permissions = granted
      $0.runtimePhase = .starting
    }
    await store.receive(\.runtimeStarted) { $0.runtimePhase = .running }
    #expect(fakes.updates.value.isEmpty)
    #expect(fakes.published.value.last?.configError != nil)
    await task.cancel()
    // The helper never saves: the user's (invalid) file is untouched.
    #expect(fakes.fileSystem.value[AppIdentifiers.configurationURL] == Data("{".utf8))
  }

  @Test func invalidFileKeepsLastGoodConfiguration() async throws {
    let fakes = Fakes()
    let good = configuration(doubleTap: 300)
    try fakes.writeFile(good)
    fakes.permissionStatus.setValue(granted)
    let store = makeStore(fakes)

    let task = await store.send(.task) { $0.hasStartedTask = true }
    await store.receive(\.permissionsChecked) {
      $0.permissions = granted
      $0.runtimePhase = .starting
    }
    await store.receive(\.runtimeStarted) { $0.runtimePhase = .running }
    #expect(fakes.starts.value == [good])

    // The file becomes invalid (e.g. written by a newer version): the load fails.
    fakes.writeFile(Data(#"{"formatVersion": 99, "keymaps": []}"#.utf8))
    await #expect(throws: (any Error).self) { try await store.state.$configuration.load() }
    await store.receive(\.configurationLoadErrorChanged) {
      $0.configError = "The configuration file was written by a newer version of KeyLayers (format version 99)."
    }
    #expect(fakes.updates.value.isEmpty)
    #expect(store.state.configuration == good)
    #expect(fakes.published.value.last?.configError == store.state.configError)

    // A valid file again: applied, and the error clears.
    let fixed = configuration(doubleTap: 350)
    try fakes.writeFile(fixed)
    try await store.state.$configuration.load()
    await store.receive(\.configurationChanged)
    await store.receive(\.configurationLoadErrorChanged) { $0.configError = nil }
    #expect(fakes.updates.value == [fixed])
    await task.cancel()
    #expect(try fakes.fileSystem.value[AppIdentifiers.configurationURL] == Configuration.encoder.encode(fixed))
  }

  @Test func quitStopsRuntimeBeforeTerminating() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    await store.send(.quitTapped) { $0.isQuitting = true }
    await store.finish()
    #expect(fakes.calls.value == ["stop", "terminate"])
  }

  @Test func terminationRequestStopsRuntimeBeforeTerminating() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    let task = await store.send(.task) { $0.hasStartedTask = true }
    await store.receive(\.permissionsChecked)
    // SIGTERM from launchd (SMAppService unregister, launchctl bootout).
    fakes.terminationRequestsContinuation.yield()
    await store.receive(\.quitTapped) { $0.isQuitting = true }
    await task.cancel()
    await store.finish()
    #expect(fakes.calls.value == ["stop", "terminate"])
  }

  @Test func quittingNeverStartsRuntime() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    let task = await store.send(.task) { $0.hasStartedTask = true }
    await store.receive(\.permissionsChecked)
    await store.send(.quitTapped) { $0.isQuitting = true }
    // A poll result already on its way when quitting: no start.
    await store.send(.permissionsChecked(granted)) { $0.permissions = granted }
    // Polling stopped: nothing more arrives.
    fakes.permissionStatus.setValue(granted)
    await fakes.clock.advance(by: .seconds(10))
    await task.cancel()
    await store.finish()
    #expect(fakes.starts.value.isEmpty)
    #expect(fakes.calls.value == ["stop", "terminate"])
  }

  @Test func openConfiguratorTappedOpensConfigurator() async {
    let fakes = Fakes()
    let store = makeStore(fakes)

    await store.send(.openConfiguratorTapped)
    await store.finish()
    #expect(fakes.calls.value == ["openConfigurator"])
  }
}
