import ComposableArchitecture
import Foundation
import KeymapModel
import SharedConfig

/// File → Export Configuration… and File → Import Configuration….
///
/// Export writes the whole configuration in its on-disk format. Import either adds the file's
/// keymaps (new IDs, unique abbreviations and names) or, after a confirmation, replaces the whole
/// configuration. While the configuration file couldn't be loaded, export is off (the in-memory
/// value is only the default) and import can only replace, which repairs the file.
@Reducer
public struct ImportExportFeature: Sendable {
  public static let defaultExportName = "KeyLayers Configuration.json"
  /// Larger files are rejected before they're read; real configurations are a few kilobytes.
  static let maximumImportSize = 5 * 1024 * 1024

  @ObservableState
  public struct State: Equatable {
    @Shared(.configuration) public var configuration: Configuration
    @Presents public var alert: AlertState<Action.Alert>?
    /// A panel is up or a file is being read or written; a second import or export is ignored.
    public var isBusy = false

    public init() {}

    public var isReadOnly: Bool {
      $configuration.loadError != nil
    }

    public var canExport: Bool {
      !isReadOnly
    }
  }

  public enum Action: Sendable {
    case exportTapped
    case importTapped
    /// The export panel closed and the file was written; `failure` says why not.
    case exportFinished(failure: String?)
    case importCancelled
    case importLoaded(fileName: String, Configuration)
    case importFailed(fileName: String, message: String)
    case alert(PresentationAction<Alert>)
    case delegate(Delegate)

    // The interface nests these here (`ImportExportFeature.Action.Alert`), as TCA examples do.
    // swiftlint:disable nesting
    public enum Alert: Equatable, Sendable {
      case addKeymaps(Configuration)
      /// Asks for confirmation first.
      case replaceEverything(Configuration)
      case confirmReplace(Configuration)
    }

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      /// After an import: the keymap to show.
      case selectKeymap(Keymap.ID)
    }
    // swiftlint:enable nesting
  }

  @Dependency(\.filePanel) var filePanel
  @Dependency(\.fileIO) var fileIO
  @Dependency(\.uuid) var uuid

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .exportTapped:
        guard state.canExport, !state.isBusy, state.alert == nil else { return .none }
        state.isBusy = true
        let configuration = state.configuration
        return .run { [filePanel, fileIO] send in
          guard let url = await filePanel.chooseExportURL(Self.defaultExportName) else {
            await send(.exportFinished(failure: nil))
            return
          }
          do {
            try fileIO.write(Configuration.encoder.encode(configuration), url)
            await send(.exportFinished(failure: nil))
          } catch {
            await send(.exportFinished(failure: error.localizedDescription))
          }
        }

      case let .exportFinished(failure):
        state.isBusy = false
        if let failure {
          state.alert = .exportFailed(message: failure)
        }
        return .none

      case .importTapped:
        guard !state.isBusy, state.alert == nil else { return .none }
        state.isBusy = true
        return .run { [filePanel, fileIO] send in
          guard let url = await filePanel.chooseImportURL() else {
            await send(.importCancelled)
            return
          }
          let fileName = url.lastPathComponent
          do {
            guard try fileIO.size(url) <= Self.maximumImportSize else { throw ImportError.tooLarge }
            let configuration = try Configuration.decoder.decode(Configuration.self, from: fileIO.read(url))
            await send(.importLoaded(fileName: fileName, configuration))
          } catch {
            await send(.importFailed(fileName: fileName, message: ImportError.message(for: error)))
          }
        }

      case .importCancelled:
        state.isBusy = false
        return .none

      case let .importLoaded(fileName, configuration):
        state.isBusy = false
        state.alert = .importChoice(fileName: fileName, configuration: configuration, isReadOnly: state.isReadOnly)
        return .none

      case let .importFailed(fileName, message):
        state.isBusy = false
        state.alert = .importFailed(fileName: fileName, message: message)
        return .none

      case let .alert(.presented(.addKeymaps(imported))):
        // Merging into swift-sharing's in-memory default would overwrite the user's file.
        guard !state.isReadOnly else { return .none }
        let newIDs = state.$configuration.withLock { configuration in
          let result = configuration.importingKeymaps(from: imported, newID: { uuid() })
          configuration = result.configuration
          return result.newIDs
        }
        guard let first = imported.keymaps.first.flatMap({ newIDs[$0.id] }) else { return .none }
        return .send(.delegate(.selectKeymap(first)))

      case let .alert(.presented(.replaceEverything(imported))):
        state.alert = .confirmReplace(imported)
        return .none

      case let .alert(.presented(.confirmReplace(imported))):
        // Allowed while read-only: the file replaces the one that couldn't be read.
        state.$configuration.withLock { $0 = imported }
        return .send(.delegate(.selectKeymap(imported.defaultKeymap.id)))

      case .alert, .delegate:
        return .none
      }
    }
    .ifLet(\.$alert, action: \.alert)
  }
}

/// Why a file couldn't be imported, worded about the chosen file (not the user's configuration).
enum ImportError: Error {
  case tooLarge

  static func message(for error: any Error) -> String {
    switch error {
    case ImportError.tooLarge:
      "The file is too large to be a KeyLayers configuration."
    case let ConfigurationError.newerFormat(version):
      "This file can't be imported: it was written by a newer version of KeyLayers (format version \(version))."
    case is DecodingError:
      "This file can't be imported: it is damaged or isn't a KeyLayers configuration."
    default:
      "This file can't be imported: \(error.localizedDescription)"
    }
  }
}

extension AlertState where Action == ImportExportFeature.Action.Alert {
  /// Add or replace; while read-only only replace, which then needs no second confirmation.
  static func importChoice(fileName: String, configuration: Configuration, isReadOnly: Bool) -> Self {
    let count = configuration.keymaps.count
    let keymaps = count == 1 ? "1 keymap" : "\(count) keymaps"
    if isReadOnly {
      return AlertState {
        TextState("Import “\(fileName)”?")
      } actions: {
        ButtonState(role: .destructive, action: .confirmReplace(configuration)) {
          TextState("Replace Everything")
        }
        ButtonState(role: .cancel) {
          TextState("Cancel")
        }
      } message: {
        TextState(
          "The current configuration can't be read. Replace it with the file's settings and \(keymaps)?"
        )
      }
    }
    return AlertState {
      TextState("Import “\(fileName)”?")
    } actions: {
      ButtonState(action: .addKeymaps(configuration)) {
        TextState("Add Keymaps")
      }
      ButtonState(role: .destructive, action: .replaceEverything(configuration)) {
        TextState("Replace Everything…")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState(
        "Add the file's \(keymaps) to your keymaps, or replace your whole configuration (settings and keymaps) "
          + "with the file."
      )
    }
  }

  static func confirmReplace(_ configuration: Configuration) -> Self {
    AlertState {
      TextState("Replace Everything?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmReplace(configuration)) {
        TextState("Replace")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState("Your settings and keymaps are replaced by the imported ones. This can't be undone.")
    }
  }

  static func importFailed(fileName: String, message: String) -> Self {
    AlertState {
      TextState("“\(fileName)” Couldn't Be Imported")
    } message: {
      TextState(message)
    }
  }

  static func exportFailed(message: String) -> Self {
    AlertState {
      TextState("The Configuration Couldn't Be Exported")
    } message: {
      TextState(message)
    }
  }
}
