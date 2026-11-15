import AppKit
import Dependencies
import DependenciesMacros
import UniformTypeIdentifiers

/// Asks the user where to export to and what to import, with the system save and open panels.
@DependencyClient
public struct FilePanelClient: Sendable {
  /// The chosen file, or `nil` when the user cancels. `defaultName` prefills the name field.
  public var chooseExportURL: @Sendable (_ defaultName: String) async -> URL? = { _ in nil }
  /// The chosen .json file, or `nil` when the user cancels.
  public var chooseImportURL: @Sendable () async -> URL? = { nil }
}

extension FilePanelClient: DependencyKey {
  public static let liveValue = FilePanelClient(
    chooseExportURL: { defaultName in await runSavePanel(defaultName: defaultName) },
    chooseImportURL: { await runOpenPanel() }
  )

  public static let testValue = FilePanelClient()

  public static let previewValue = FilePanelClient(chooseExportURL: { _ in nil }, chooseImportURL: { nil })
}

@MainActor
private func runSavePanel(defaultName: String) async -> URL? {
  let panel = NSSavePanel()
  panel.nameFieldStringValue = defaultName
  panel.allowedContentTypes = [.json]
  panel.canCreateDirectories = true
  return await present(panel)
}

@MainActor
private func runOpenPanel() async -> URL? {
  let panel = NSOpenPanel()
  panel.allowedContentTypes = [.json]
  panel.allowsMultipleSelection = false
  panel.canChooseDirectories = false
  panel.canChooseFiles = true
  return await present(panel)
}

/// As a sheet on the configurator window, or app-modal when no window is open.
@MainActor
private func present(_ panel: NSSavePanel) async -> URL? {
  let response: NSApplication.ModalResponse = if let window = NSApp.keyWindow ?? NSApp.mainWindow {
    await panel.beginSheetModal(for: window)
  } else {
    panel.runModal()
  }
  return response == .OK ? panel.url : nil
}

public extension DependencyValues {
  var filePanel: FilePanelClient {
    get { self[FilePanelClient.self] }
    set { self[FilePanelClient.self] = newValue }
  }
}
