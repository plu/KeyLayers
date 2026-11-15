import AppKit
import ComposableArchitecture
@testable import ConfiguratorFeature
import HelperIPC
import KeyboardLayout
import KeymapModel
import SharedConfig
@_spi(Internals) import Sharing
import SnapshotTesting
import SwiftUI

/// Hosts `view` at a fixed size in the given appearance, with animations off.
@MainActor
func host(_ view: some View, size: CGSize, dark: Bool) -> NSView {
  let scheme: ColorScheme = dark ? .dark : .light
  let root = view
    .frame(width: size.width, height: size.height)
    .background(Color(nsColor: .windowBackgroundColor))
    .environment(\.colorScheme, scheme)
    .transaction { $0.disablesAnimations = true }
  let hostingView = NSHostingView(rootView: root)
  hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
  hostingView.frame = CGRect(origin: .zero, size: size)
  hostingView.layoutSubtreeIfNeeded()
  return hostingView
}

@MainActor
func assertBothAppearances(
  _ view: some View,
  size: CGSize,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) {
  for dark in [false, true] {
    assertSnapshot(
      of: host(view, size: size, dark: dark),
      as: .image(precision: 0.995, perceptualPrecision: 0.98),
      named: dark ? "dark" : "light",
      fileID: fileID,
      file: filePath,
      testName: testName,
      line: line,
      column: column
    )
  }
}

let codingID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
let granted = PermissionStatus(accessibility: true)

/// Fixed, inert dependencies: a configuration file with two keymaps (or `fileData`), an enabled
/// registration and a helper that never reports.
func fixedDependencies(fileData: Data? = nil, starterOnly: Bool = false) throws -> (inout DependencyValues) -> Void {
  var configuration = Configuration.starter
  if !starterOnly {
    configuration.keymaps.append(Keymap(id: codingID, name: "Coding", abbreviation: "COD"))
  }
  let data = try fileData ?? Configuration.encoder.encode(configuration)
  let files = LockIsolated([AppIdentifiers.configurationURL: data])
  let defaults = UncheckedSendable(UserDefaults(suiteName: "ConfiguratorSnapshotTests-\(UUID().uuidString)")!)
  return {
    $0.defaultFileStorage = .inMemory(fileSystem: files)
    $0.defaultAppStorage = defaults.value
    $0.helperRegistration = HelperRegistrationClient(status: { .enabled }, register: {}, unregister: {},
                                                     daemonStatus: { .enabled }, registerDaemon: {}, unregisterDaemon: {})
    $0.helperClient = HelperClient(states: { AsyncStream { _ in } }, setPaused: { _ in }, start: {})
    $0.systemSettings = SystemSettingsClient(open: { _ in })
    $0.keyboardDetection = KeyboardDetectionClient(keyboards: { [] })
    $0.keyLabels = KeyLabelClient(labels: { StaticKeyLabels.usANSI }, changes: { .finished })
  }
}

@MainActor
func makeStore<R: Reducer>(
  _ reducer: R,
  dependencies: @escaping (inout DependencyValues) -> Void,
  state: () -> R.State
) -> Store<R.State, R.Action> {
  let initialState = withDependencies(dependencies, operation: state)
  return Store(initialState: initialState) { reducer } withDependencies: { dependencies(&$0) }
}
