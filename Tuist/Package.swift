// swift-tools-version: 6.0
import PackageDescription

#if TUIST
  import ProjectDescription

  let packageSettings = PackageSettings(productTypes: [
    "ComposableArchitecture": .staticFramework,
    "Dependencies": .staticFramework,
    "Sharing": .staticFramework,
    "SnapshotTesting": .staticFramework,
    "IdentifiedCollections": .staticFramework,
    "CustomDump": .staticFramework,
    // swift-case-paths 1.9.0+ ships CasePathsMacrosSupport as a plain library that the CasePaths and
    // SwiftNavigation macros link against. Tuist refuses a macro depending on a dynamic framework,
    // and the cache build fails linking `MacroSupport` unless it is pinned static here.
    "CasePathsMacrosSupport": .staticFramework,
  ])
#endif

let package = Package(
  name: "KeyLayersDependencies",
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.26.2"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.2"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.10.1"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.1"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.7.3"),
  ]
)
