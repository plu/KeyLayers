import AppKit
import ComposableArchitecture
@testable import HelperFeature
import HelperIPC
import KeymapModel
import RemapEngine
import SharedConfig
@_spi(Internals) import Sharing
import SnapshotTesting
import SwiftUI
import Testing

/// Hosts `view` at a fixed size in the given appearance, with animations off.
@MainActor
private func host(_ view: some View, size: CGSize, dark: Bool) -> NSView {
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
private func assertBothAppearances(
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

@MainActor
struct HelperSnapshotTests {
  @Test func layerHUD() {
    assertBothAppearances(LayerHUDView(text: "Mod"), size: CGSize(width: 240, height: 110))
  }

  @Test func menuBarLabel() {
    assertBothAppearances(
      MenuBarLabel(title: "DEF · Mod", isPaused: false),
      size: CGSize(width: 140, height: 24)
    )
  }

  @Test func menuBarLabelPaused() {
    assertBothAppearances(
      MenuBarLabel(title: "DEF · Paused", isPaused: true),
      size: CGSize(width: 140, height: 24)
    )
  }

  @Test func helperMenu() throws {
    var configuration = Configuration.starter
    let codingID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    configuration.keymaps.append(Keymap(id: codingID, name: "Coding", abbreviation: "COD"))
    let data = try Configuration.encoder.encode(configuration)
    let files = LockIsolated([AppIdentifiers.configurationURL: data])
    let store = withDependencies {
      $0.defaultFileStorage = .inMemory(fileSystem: files)
    } operation: {
      var state = HelperFeature.State()
      state.permissions = PermissionStatus(accessibility: true)
      state.runtimePhase = .running
      state.engineStatus = EngineStatus(activeKeymapID: Keymap.starterID, activeLayer: .mod)
      return Store(initialState: state) { HelperFeature() }
    }
    assertBothAppearances(
      VStack(alignment: .leading, spacing: 6) {
        HelperMenuView(store: store)
      }
      .padding(10)
      .frame(width: 260, alignment: .leading),
      size: CGSize(width: 260, height: 270)
    )
  }
}
