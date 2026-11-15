import Dependencies
import DependenciesMacros
import Foundation

/// Reads and writes files the user chose (import and export); the configuration file itself goes
/// through `@Shared(.configuration)`.
@DependencyClient
public struct FileIOClient: Sendable {
  /// The file's size in bytes, checked before `read`.
  public var size: @Sendable (_ url: URL) throws -> Int
  public var read: @Sendable (_ url: URL) throws -> Data
  public var write: @Sendable (_ data: Data, _ url: URL) throws -> Void
}

extension FileIOClient: DependencyKey {
  public static let liveValue = FileIOClient(
    size: { url in try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 },
    read: { url in try Data(contentsOf: url) },
    write: { data, url in try data.write(to: url, options: .atomic) }
  )

  public static let testValue = FileIOClient()
}

public extension DependencyValues {
  var fileIO: FileIOClient {
    get { self[FileIOClient.self] }
    set { self[FileIOClient.self] = newValue }
  }
}
