import XCTest

/// The helper state the app fakes in UI-test mode (`UITEST_HELPER_STATE`).
enum FakeHelperState: String {
  case running, notRunning, needsPermissions, paused
}

extension XCUIApplication {
  /// Launches the configurator in UI-test mode: in-memory configuration and app storage, a fake
  /// helper in `helper` state, and a key recorder that returns `recordedKey` ("<page>:<usage>").
  static func launchConfigurator(helper: FakeHelperState = .running, recordedKey: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-UITestMode"]
    app.launchEnvironment["UITEST_HELPER_STATE"] = helper.rawValue
    if let recordedKey {
      app.launchEnvironment["UITEST_RECORDED_KEY"] = recordedKey
    }
    app.launch()
    return app
  }
}
