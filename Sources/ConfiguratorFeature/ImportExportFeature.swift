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

  @ObservableState
  public struct State: Equatable {
    @Shared(.configuration) public var configuration: Configuration
    @Presents public var alert: AlertState<Action.Alert>?

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
    case exportFailed(String)
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
        guard state.canExport else { return .none }
        let configuration = state.configuration
        return .run { [filePanel, fileIO] send in
          guard let url = await filePanel.chooseExportURL(Self.defaultExportName) else { return }
          do {
            try fileIO.write(Configuration.encoder.encode(configuration), url)
          } catch {
            await send(.exportFailed(error.localizedDescription))
          }
        }

      case let .exportFailed(message):
        state.alert = .exportFailed(message: message)
        return .none

      case .importTapped:
        return .run { [filePanel, fileIO] send in
          guard let url = await filePanel.chooseImportURL() else { return }
          let fileName = url.lastPathComponent
          do {
            let configuration = try Configuration.decoder.decode(Configuration.self, from: fileIO.read(url))
            await send(.importLoaded(fileName: fileName, configuration))
          } catch {
            await send(.importFailed(fileName: fileName, message: ConfigurationLoadError.message(for: error) ?? ""))
          }
        }

      case let .importLoaded(fileName, configuration):
        state.alert = .importChoice(fileName: fileName, configuration: configuration, isReadOnly: state.isReadOnly)
        return .none

      case let .importFailed(fileName, message):
        state.alert = .importFailed(fileName: fileName, message: message)
        return .none

      case let .alert(.presented(.addKeymaps(imported))):
        // Merging into swift-sharing's in-memory default would overwrite the user's file.
        guard !state.isReadOnly else { return .none }
        let firstNew = state.configuration.keymaps.count
        state.$configuration.withLock { $0 = $0.addingKeymaps(from: imported, newID: { uuid() }) }
        return .send(.delegate(.selectKeymap(state.configuration.keymaps[firstNew].id)))

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
