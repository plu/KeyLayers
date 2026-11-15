import AppKit
import Dependencies
import DependenciesMacros

/// Reveals files in Finder.
@DependencyClient
public struct FinderClient: Sendable {
  public var reveal: @Sendable (URL) -> Void
}

extension FinderClient: DependencyKey {
  public static let liveValue = FinderClient(reveal: { url in
    NSWorkspace.shared.activateFileViewerSelecting([url])
  })

  public static let testValue = FinderClient()

  public static let previewValue = FinderClient(reveal: { _ in })
}

public extension DependencyValues {
  var finder: FinderClient {
    get { self[FinderClient.self] }
    set { self[FinderClient.self] = newValue }
  }
}
