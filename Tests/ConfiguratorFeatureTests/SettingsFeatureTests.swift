import ComposableArchitecture
@testable import ConfiguratorFeature
import Foundation
import KeymapModel
import Sharing
import Testing

@MainActor
private func makeStore(_ fakes: Fakes) -> TestStoreOf<SettingsFeature> {
  TestStore(initialState: fakes.makeState { SettingsFeature.State() }) {
    SettingsFeature()
  } withDependencies: {
    fakes.apply(to: &$0)
  }
}

@MainActor
struct SettingsFeatureTests {
  @Test func doubleTapTimeoutIsClamped() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.doubleTapTimeoutChanged(40)) {
      $0.$configuration.withLock { $0.settings.doubleTapTimeoutMilliseconds = 100 }
    }
    await store.send(.doubleTapTimeoutChanged(1210)) {
      $0.$configuration.withLock { $0.settings.doubleTapTimeoutMilliseconds = 1000 }
    }
    await store.send(.doubleTapTimeoutChanged(333)) {
      $0.$configuration.withLock { $0.settings.doubleTapTimeoutMilliseconds = 350 }
    }
    #expect(try fakes.savedConfiguration()?.settings.doubleTapTimeoutMilliseconds == 350)
  }

  @Test func layerHUDToggleIsSaved() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.showLayerHUDChanged(false)) {
      $0.$configuration.withLock { $0.settings.showLayerHUD = false }
    }
    #expect(try fakes.savedConfiguration()?.settings.showLayerHUD == false)
  }

  @Test func menuBarTogglesAreSaved() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.menuBarShowsKeymapChanged(true)) {
      $0.$configuration.withLock { $0.settings.menuBarShowsKeymap = true }
    }
    await store.send(.menuBarShowsLayerChanged(true)) {
      $0.$configuration.withLock { $0.settings.menuBarShowsLayer = true }
    }
    let saved = try fakes.savedConfiguration()?.settings
    #expect(saved?.menuBarShowsKeymap == true && saved?.menuBarShowsLayer == true)
  }

  @Test func turningOffLaunchAtLoginUnregistersHelper() async throws {
    let fakes = try Fakes()
    fakes.registrationStatus.setValue(.enabled)
    let store = makeStore(fakes)
    #expect(store.state.launchAtLogin)

    await store.send(.launchAtLoginChanged(false)) {
      $0.$launchAtLogin.withLock { $0 = false }
    }
    await store.finish()
    #expect(fakes.registrationCalls.value == ["unregister"])

    await store.send(.launchAtLoginChanged(true)) {
      $0.$launchAtLogin.withLock { $0 = true }
    }
    await store.finish()
    #expect(fakes.registrationCalls.value == ["unregister", "register"])
  }

  @Test func registrationFailureIsShown() async throws {
    let fakes = try Fakes()
    fakes.registrationError.setValue(RegistrationFailure())
    let store = makeStore(fakes)

    await store.send(.launchAtLoginChanged(true))
    await store.receive(\.registrationFailed) {
      $0.registrationError = "The helper couldn't be enabled: Operation not permitted"
    }
  }

  @Test func launchAtLoginOnRegistersDaemonAndOffLeavesIt() async throws {
    let fakes = try Fakes()
    fakes.registrationStatus.setValue(.enabled)
    fakes.daemonStatus.setValue(.notFound)
    let store = makeStore(fakes)

    await store.send(.launchAtLoginChanged(true)) { $0.$launchAtLogin.withLock { $0 = true } }
    await store.finish()
    #expect(fakes.daemonCalls.value == ["register"])
    #expect(fakes.registrationCalls.value.isEmpty)

    await store.send(.launchAtLoginChanged(false)) { $0.$launchAtLogin.withLock { $0 = false } }
    await store.finish()
    #expect(fakes.daemonCalls.value == ["register"])
    #expect(fakes.registrationCalls.value == ["unregister"])
  }

  @Test func daemonRegistrationFailureInSettingsIsShown() async throws {
    let fakes = try Fakes()
    fakes.registrationStatus.setValue(.enabled)
    fakes.daemonRegistrationError.setValue(RegistrationFailure())
    let store = makeStore(fakes)

    await store.send(.launchAtLoginChanged(true))
    await store.receive(\.registrationFailed) {
      $0.registrationError = "The input service couldn't be enabled: Operation not permitted"
    }
  }
}
