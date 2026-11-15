import ComposableArchitecture
@testable import ConfiguratorFeature
import Foundation
import KeymapModel
import SharedConfig
import Testing

private let exportURL = URL(fileURLWithPath: "/Exports/KeyLayers Configuration.json")
private let importURL = URL(fileURLWithPath: "/Imports/Backup.json")
private let writingID = UUID(uuidString: "00000000-0000-0000-0000-0000000057A1")!

/// 00…A1, 00…A2, … (never the starter's 00…01).
private func importedID(_ n: Int) -> UUID {
  UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", 0xA0 + n))!
}

@MainActor
private func makeStore(_ fakes: Fakes) -> TestStoreOf<AppFeature> {
  TestStore(initialState: fakes.makeState { AppFeature.State() }) {
    AppFeature()
  } withDependencies: {
    fakes.apply(to: &$0)
    let next = LockIsolated(1)
    $0.uuid = UUIDGenerator {
      next.withValue { n in
        defer { n += 1 }
        return importedID(n)
      }
    }
  }
}

/// A file to import: "Writing" (WRI, default), and "Coding" (COD) with a key that switches to Writing.
private func backup() -> Configuration {
  var coding = Keymap(id: codingID, name: "Coding", abbreviation: "COD")
  coding.setAction(.switchKeymap(writingID), for: .a, on: .base)
  return Configuration(
    settings: Settings(doubleTapTimeoutMilliseconds: 400, showLayerHUD: false),
    keymaps: [Keymap(id: writingID, name: "Writing", abbreviation: "WRI"), coding],
    defaultKeymapID: writingID
  )
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ImportExportFeatureTests {
  // MARK: Export

  @Test func exportWritesTheEncodedConfiguration() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    fakes.exportURL.setValue(exportURL)
    let store = makeStore(fakes)
    #expect(store.state.importExport.canExport)

    await store.send(.importExport(.exportTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.exportFinished) { $0.importExport.isBusy = false }
    #expect(fakes.exportPanelNames.value == ["KeyLayers Configuration.json"])
    #expect(try fakes.externalFiles.value[exportURL] == Configuration.encoder.encode(twoKeymaps()))
    // Identical to what the configurator itself saves.
    #expect(fakes.externalFiles.value[exportURL] == fakes.fileData)
  }

  @Test func cancelledExportWritesNothing() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.importExport(.exportTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.exportFinished) { $0.importExport.isBusy = false }
    #expect(fakes.exportPanelNames.value.count == 1)
    #expect(fakes.externalFiles.value.isEmpty)
  }

  @Test func failedExportShowsAnAlert() async throws {
    let fakes = try Fakes()
    fakes.exportURL.setValue(exportURL)
    fakes.writeError.setValue(RegistrationFailure())
    let store = makeStore(fakes)

    await store.send(.importExport(.exportTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.exportFinished) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .exportFailed(message: "Operation not permitted")
    }
    await store.send(.importExport(.alert(.dismiss))) {
      $0.importExport.alert = nil
    }
  }

  @Test func exportIsDisabledWhileReadOnly() async {
    let fakes = Fakes(fileData: Data("{".utf8))
    fakes.exportURL.setValue(exportURL)
    let store = makeStore(fakes)
    #expect(!store.state.importExport.canExport)

    await store.send(.importExport(.exportTapped))
    #expect(fakes.exportPanelNames.value.isEmpty)
    #expect(fakes.externalFiles.value.isEmpty)
  }

  // MARK: Import

  @Test func importAddsKeymaps() async throws {
    let fakes = try Fakes()
    fakes.importURL.setValue(importURL)
    fakes.externalFiles.withValue { $0[importURL] = try? Configuration.encoder.encode(backup()) }
    let store = makeStore(fakes)

    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importLoaded) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .importChoice(fileName: "Backup.json", configuration: backup(), isReadOnly: false)
    }
    await store.send(.importExport(.alert(.presented(.addKeymaps(backup()))))) {
      $0.importExport.alert = nil
      $0.$configuration.withLock {
        $0 = Configuration.starter.addingKeymaps(from: backup(), newID: sequence(importedID(1), importedID(2)))
      }
    }
    // The first imported keymap is selected.
    await store.receive(\.importExport.delegate.selectKeymap)
    await store.receive(\.keymapList.binding) {
      $0.keymapList.selection = importedID(1)
      $0.editor = fakes.makeState { KeymapEditorFeature.State(keymapID: importedID(1)) }
    }

    let saved = try #require(try fakes.savedConfiguration())
    #expect(saved.keymaps.map(\.name) == ["Default", "Writing", "Coding"])
    #expect(saved.keymaps.map(\.id) == [Keymap.starterID, importedID(1), importedID(2)])
    // Re-pointed to the imported Writing.
    #expect(saved.keymaps[2].action(for: .a, on: .base) == .switchKeymap(importedID(1)))
    // Settings and default keymap are kept.
    #expect(saved.settings == Configuration.starter.settings)
    #expect(saved.defaultKeymapID == Keymap.starterID)
  }

  @Test func importingTheOwnExportDuplicatesWithUniqueAbbreviations() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    fakes.exportURL.setValue(exportURL)
    fakes.importURL.setValue(exportURL)
    let store = makeStore(fakes)
    store.exhaustivity = .off

    await store.send(.importExport(.exportTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.exportFinished)
    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importLoaded)
    await store.send(.importExport(.alert(.presented(.addKeymaps(twoKeymaps())))))
    await store.skipReceivedActions()

    let saved = try #require(try fakes.savedConfiguration())
    #expect(saved.keymaps.map(\.abbreviation) == ["DEF", "COD", "DE2", "CO2"])
    #expect(saved.keymaps.map(\.name) == ["Default", "Coding", "Default (imported)", "Coding (imported)"])
  }

  @Test func importReplacesEverythingAfterConfirmation() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    fakes.importURL.setValue(importURL)
    fakes.externalFiles.withValue { $0[importURL] = try? Configuration.encoder.encode(backup()) }
    let store = makeStore(fakes)

    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importLoaded) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .importChoice(fileName: "Backup.json", configuration: backup(), isReadOnly: false)
    }
    await store.send(.importExport(.alert(.presented(.replaceEverything(backup()))))) {
      $0.importExport.alert = .confirmReplace(backup())
    }
    #expect(try fakes.savedConfiguration() == twoKeymaps())

    await store.send(.importExport(.alert(.presented(.confirmReplace(backup()))))) {
      $0.importExport.alert = nil
      $0.$configuration.withLock { $0 = backup() }
    }
    await store.receive(\.importExport.delegate.selectKeymap)
    await store.receive(\.keymapList.binding) {
      $0.keymapList.selection = writingID
      $0.editor = fakes.makeState { KeymapEditorFeature.State(keymapID: writingID) }
    }
    #expect(try fakes.savedConfiguration() == backup())
  }

  @Test func cancellingTheReplaceConfirmationChangesNothing() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    fakes.importURL.setValue(importURL)
    fakes.externalFiles.withValue { $0[importURL] = try? Configuration.encoder.encode(backup()) }
    let store = makeStore(fakes)

    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importLoaded) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .importChoice(fileName: "Backup.json", configuration: backup(), isReadOnly: false)
    }
    await store.send(.importExport(.alert(.presented(.replaceEverything(backup()))))) {
      $0.importExport.alert = .confirmReplace(backup())
    }
    await store.send(.importExport(.alert(.dismiss))) {
      $0.importExport.alert = nil
    }
    #expect(store.state.configuration == twoKeymaps())
    #expect(try fakes.savedConfiguration() == twoKeymaps())
  }

  @Test func cancellingTheImportChangesNothing() async throws {
    let fakes = try Fakes(file: twoKeymaps())
    fakes.importURL.setValue(importURL)
    fakes.externalFiles.withValue { $0[importURL] = try? Configuration.encoder.encode(backup()) }
    let store = makeStore(fakes)

    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importLoaded) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .importChoice(fileName: "Backup.json", configuration: backup(), isReadOnly: false)
    }
    await store.send(.importExport(.alert(.dismiss))) {
      $0.importExport.alert = nil
    }
    #expect(try fakes.savedConfiguration() == twoKeymaps())
  }

  @Test func cancelledOpenPanelDoesNothing() async throws {
    let fakes = try Fakes()
    let store = makeStore(fakes)

    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importCancelled) { $0.importExport.isBusy = false }
    #expect(fakes.importPanelShown.value == 1)
  }

  @Test func importOfANewerFormatShowsAnError() async throws {
    let fakes = try Fakes()
    fakes.importURL.setValue(importURL)
    fakes.externalFiles.withValue { $0[importURL] = Data(#"{"formatVersion": 2, "keymaps": []}"#.utf8) }
    let store = makeStore(fakes)

    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importFailed) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .importFailed(
        fileName: "Backup.json",
        message: "This file can't be imported: it was written by a newer version of KeyLayers (format version 2)."
      )
    }
    #expect(store.state.configuration == .starter)
  }

  @Test func importOfADamagedFileShowsAnError() async throws {
    let fakes = try Fakes()
    fakes.importURL.setValue(importURL)
    fakes.externalFiles.withValue { $0[importURL] = Data("{".utf8) }
    let store = makeStore(fakes)

    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importFailed) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .importFailed(
        fileName: "Backup.json",
        message: "This file can't be imported: it is damaged or isn't a KeyLayers configuration."
      )
    }
  }

  @Test func importOfAnUnreadableFileShowsAnError() async throws {
    let fakes = try Fakes()
    fakes.importURL.setValue(importURL)
    let store = makeStore(fakes)

    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importFailed) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .importFailed(
        fileName: "Backup.json",
        message: "This file can't be imported: \(CocoaError(.fileReadNoSuchFile).localizedDescription)"
      )
    }
  }

  @Test func tooLargeFileIsRejectedWithoutReadingIt() async throws {
    let fakes = try Fakes()
    fakes.importURL.setValue(importURL)
    fakes.externalFiles.withValue { $0[importURL] = try? Configuration.encoder.encode(backup()) }
    fakes.fileSizes.withValue { $0[importURL] = 5 * 1024 * 1024 + 1 }
    let store = makeStore(fakes)

    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importFailed) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .importFailed(
        fileName: "Backup.json",
        message: "The file is too large to be a KeyLayers configuration."
      )
    }
    #expect(fakes.readURLs.value.isEmpty)
  }

  @Test func secondImportOrExportWhileBusyOrAlertingIsIgnored() async throws {
    let fakes = try Fakes()
    let (choices, choose) = AsyncStream.makeStream(of: URL?.self)
    let store = TestStore(initialState: fakes.makeState { AppFeature.State() }) {
      AppFeature()
    } withDependencies: {
      fakes.apply(to: &$0)
      let panelShown = fakes.importPanelShown
      $0.filePanel.chooseImportURL = {
        panelShown.withValue { $0 += 1 }
        for await choice in choices {
          return choice
        }
        return nil
      }
    }
    fakes.externalFiles.withValue { $0[importURL] = try? Configuration.encoder.encode(backup()) }
    fakes.exportURL.setValue(exportURL)

    // While the open panel is up.
    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.send(.importExport(.importTapped))
    await store.send(.importExport(.exportTapped))
    choose.yield(importURL)
    await store.receive(\.importExport.importLoaded) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .importChoice(fileName: "Backup.json", configuration: backup(), isReadOnly: false)
    }
    // While the choice is up.
    await store.send(.importExport(.importTapped))
    await store.send(.importExport(.exportTapped))
    #expect(fakes.importPanelShown.value == 1)
    #expect(fakes.exportPanelNames.value.isEmpty)
    await store.send(.importExport(.alert(.dismiss))) { $0.importExport.alert = nil }
  }

  // MARK: Read-only

  @Test func readOnlyImportOffersOnlyReplaceAndRepairsTheFile() async throws {
    let corrupt = Data("{".utf8)
    let fakes = Fakes(fileData: corrupt)
    fakes.importURL.setValue(importURL)
    fakes.externalFiles.withValue { $0[importURL] = try? Configuration.encoder.encode(backup()) }
    let store = makeStore(fakes)
    #expect(store.state.isReadOnly)

    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importLoaded) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .importChoice(fileName: "Backup.json", configuration: backup(), isReadOnly: true)
    }
    let alert = try #require(store.state.importExport.alert)
    #expect(alert.buttons.compactMap(\.action.action) == [.confirmReplace(backup())])

    // Adding would write swift-sharing's in-memory default over the user's file: a no-op.
    await store.send(.importExport(.alert(.presented(.addKeymaps(backup()))))) {
      $0.importExport.alert = nil
    }
    #expect(fakes.fileData == corrupt)

    await store.send(.importExport(.importTapped)) { $0.importExport.isBusy = true }
    await store.receive(\.importExport.importLoaded) {
      $0.importExport.isBusy = false
      $0.importExport.alert = .importChoice(fileName: "Backup.json", configuration: backup(), isReadOnly: true)
    }
    await store.send(.importExport(.alert(.presented(.confirmReplace(backup()))))) {
      $0.importExport.alert = nil
      $0.$configuration.withLock { $0 = backup() }
    }
    await store.receive(\.importExport.delegate.selectKeymap)
    await store.receive(\.keymapList.binding) {
      $0.keymapList.selection = writingID
      $0.editor = fakes.makeState { KeymapEditorFeature.State(keymapID: writingID) }
    }
    #expect(try fakes.savedConfiguration() == backup())
    #expect(!store.state.isReadOnly)
  }
}

/// A generator that hands out `ids` in order.
private func sequence(_ ids: UUID...) -> () -> UUID {
  var remaining = ids[...]
  return { remaining.popFirst()! }
}
