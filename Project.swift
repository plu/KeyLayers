import ProjectDescription

let teamId = Environment.teamId.getString(default: "")
let prefix = Environment.bundleIdPrefix.getString(default: "com.plunien.keylayers")
/// Name of the Developer ID provisioning profile for the helper (carries the HID virtual device
/// entitlement). Set only by `mise run release:archive` (as TUIST_HELPER_PROVISIONING_PROFILE);
/// empty in dev builds, which sign automatically and need no profile name.
let helperProfile = Environment.helperProvisioningProfile.getString(default: "")

/// Everything that identifies one installation of KeyLayers to macOS: bundle IDs, launchd labels and
/// plists, Mach services, the App Group (and with it the configuration file), and the names shown
/// in System Settings. Debug builds use `<prefix>.dev` and "… Dev" names, so a development build and
/// the installed release never share a Background Task Management record, TCC grant, Mach service or
/// configuration file. Release keeps the plain prefix: existing installs depend on it.
func identitySettings(prefix: String, displayNameSuffix: String) -> SettingsDictionary {
  let groupPrefix = teamId.isEmpty ? prefix : "\(teamId).\(prefix)"
  return [
    "APP_GROUP_ID": .string(groupPrefix),
    "HELPER_MACH_SERVICE_NAME": .string("\(groupPrefix).helper"),
    "HELPER_BUNDLE_ID": .string("\(prefix).helper"),
    "CONFIGURATOR_BUNDLE_ID": .string("\(prefix).configurator"),
    "HELPER_LAUNCHD_PLIST_NAME": .string("\(prefix).helper.plist"),
    // `inputservice`, not the earlier `inputd`: a registration of `<prefix>.inputd` made by a dev build
    // before dev builds had their own identity can stay stuck in Background Task Management, with a
    // code requirement launchd checks the Developer ID daemon against and that re-registering doesn't
    // replace. A new label gives every Mac a fresh record.
    "INPUT_DAEMON_LABEL": .string("\(prefix).inputservice"),
    "INPUT_DAEMON_MACH_SERVICE_NAME": .string("\(groupPrefix).inputservice"),
    "INPUT_DAEMON_PLIST_NAME": .string("\(prefix).inputservice.plist"),
    "CONFIGURATOR_DISPLAY_NAME": .string("KeyLayers\(displayNameSuffix)"),
    "HELPER_DISPLAY_NAME": .string("KeyLayers Helper\(displayNameSuffix)"),
  ]
}

var baseSettings: SettingsDictionary = [
  "SWIFT_VERSION": "6",
  "SWIFT_STRICT_CONCURRENCY": "complete",
  "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
  "MACOSX_DEPLOYMENT_TARGET": "26.0",
  "ENABLE_HARDENED_RUNTIME": "YES",
  "DEVELOPMENT_TEAM": .string(teamId),
]
if teamId.isEmpty {
  baseSettings["CODE_SIGN_IDENTITY"] = "-"
}

let projectSettings: Settings = .settings(
  base: baseSettings,
  configurations: [
    .debug(name: .debug, settings: identitySettings(prefix: "\(prefix).dev", displayNameSuffix: " Dev")),
    .release(name: .release, settings: identitySettings(prefix: prefix, displayNameSuffix: "")),
  ]
)

/// Tuist's default target settings sign macOS apps ad hoc (`CODE_SIGN_IDENTITY = "-"`), which
/// overrides the project-level team. Ad-hoc dev builds break the helper's XPC peer check (it pins
/// the team) and lose their TCC grants on every rebuild, so sign the apps with the team when set.
let appSigningSettings: SettingsDictionary = teamId.isEmpty
  ? ["CODE_SIGN_IDENTITY": "-"]
  : ["CODE_SIGN_IDENTITY": "Apple Development", "CODE_SIGN_STYLE": "Automatic"]

/// Tuist's app defaults name an `AccentColor` asset; the apps have no asset catalog (only `AppIcon.icon`).
let noAccentColor: SettingsDictionary = ["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": ""]

/// `com.apple.developer.hid.virtual.device` is restricted: it needs a provisioning profile, which an
/// ad-hoc build (no team) can't have, and AMFI kills a process claiming it without one. Ad-hoc
/// helpers go without it (no virtual keyboard, so remapping can't start; the status says so).
let helperEntitlements: Entitlements = teamId.isEmpty
  ? .dictionary(["com.apple.security.application-groups": ["$(APP_GROUP_ID)"]])
  : .file(path: "Apps/KeyLayersHelper/KeyLayersHelper.entitlements")

func framework(_ name: String, deps: [TargetDependency] = []) -> Target {
  .target(
    name: name,
    destinations: .macOS,
    product: .staticFramework,
    bundleId: "\(prefix).\(name)",
    deploymentTargets: .macOS("26.0"),
    sources: ["Sources/\(name)/**"],
    dependencies: deps
  )
}

func unitTests(_ module: String, deps: [TargetDependency] = []) -> Target {
  .target(
    name: "\(module)Tests",
    destinations: .macOS,
    product: .unitTests,
    bundleId: "\(prefix).\(module)Tests",
    deploymentTargets: .macOS("26.0"),
    sources: ["Tests/\(module)Tests/**"],
    dependencies: [.target(name: module)] + deps
  )
}

let unitTestTargets: [TargetReference] = [
  "KeymapModelTests", "RemapEngineTests", "KeyIOTests", "SharedConfigTests", "HelperIPCTests",
  "KeyboardLayoutTests", "HelperFeatureTests", "ConfiguratorFeatureTests", "InputDaemonIPCTests",
  "InputDaemonCoreTests",
]

let snapshotTestTargets: [TargetReference] = ["HelperSnapshotTests", "ConfiguratorSnapshotTests"]

let project = Project(
  name: "KeyLayers",
  settings: projectSettings,
  targets: [
    framework("KeymapModel", deps: [.external(name: "IdentifiedCollections")]),
    unitTests("KeymapModel"),
    framework("RemapEngine", deps: [.target(name: "KeymapModel")]),
    unitTests("RemapEngine", deps: [.target(name: "KeymapModel"), .external(name: "IdentifiedCollections")]),
    framework("KeyIO", deps: [
      .target(name: "RemapEngine"),
      .target(name: "KeymapModel"),
      .target(name: "InputDaemonIPC"),
    ]),
    unitTests("KeyIO", deps: [
      .target(name: "RemapEngine"),
      .target(name: "KeymapModel"),
      .target(name: "InputDaemonIPC"),
      .external(name: "Clocks"),
    ]),
    framework("SharedConfig", deps: [.target(name: "KeymapModel"), .external(name: "Sharing")]),
    unitTests("SharedConfig", deps: [.target(name: "KeymapModel"), .external(name: "Sharing")]),
    framework("HelperIPC", deps: [
      .target(name: "KeymapModel"),
      .target(name: "SharedConfig"),
      .external(name: "Dependencies"),
      .external(name: "DependenciesMacros"),
    ]),
    unitTests("HelperIPC", deps: [.target(name: "KeymapModel"), .external(name: "Dependencies")]),
    framework("InputDaemonIPC"),
    unitTests("InputDaemonIPC"),
    framework("InputDaemonCore", deps: [.target(name: "InputDaemonIPC")]),
    unitTests("InputDaemonCore", deps: [.target(name: "InputDaemonIPC"), .external(name: "Clocks")]),
    framework("KeyboardLayout", deps: [
      .target(name: "KeymapModel"),
      .target(name: "KeyIO"),
      .external(name: "Dependencies"),
      .external(name: "DependenciesMacros"),
    ]),
    unitTests("KeyboardLayout", deps: [.target(name: "KeymapModel"), .target(name: "KeyIO")]),
    framework("HelperFeature", deps: [
      .target(name: "KeymapModel"),
      .target(name: "KeyboardLayout"),
      .target(name: "RemapEngine"),
      .target(name: "KeyIO"),
      .target(name: "InputDaemonIPC"),
      .target(name: "HelperIPC"),
      .target(name: "SharedConfig"),
      .external(name: "ComposableArchitecture"),
      .external(name: "Dependencies"),
      .external(name: "DependenciesMacros"),
    ]),
    unitTests("HelperFeature", deps: [
      .target(name: "KeymapModel"),
      .target(name: "KeyboardLayout"),
      .target(name: "RemapEngine"),
      .target(name: "KeyIO"),
      .target(name: "InputDaemonIPC"),
      .target(name: "HelperIPC"),
      .target(name: "SharedConfig"),
      .external(name: "ComposableArchitecture"),
      .external(name: "Clocks"),
      .external(name: "IdentifiedCollections"),
    ]),
    .target(
      name: "HelperSnapshotTests",
      destinations: .macOS,
      product: .unitTests,
      bundleId: "\(prefix).HelperSnapshotTests",
      deploymentTargets: .macOS("26.0"),
      sources: ["Tests/HelperSnapshotTests/**"],
      dependencies: [
        .target(name: "HelperFeature"),
        .target(name: "HelperIPC"),
        .target(name: "SharedConfig"),
        .target(name: "KeymapModel"),
        .target(name: "RemapEngine"),
        .external(name: "ComposableArchitecture"),
        .external(name: "SnapshotTesting"),
      ]
    ),
    framework("ConfiguratorFeature", deps: [
      .target(name: "KeymapModel"),
      .target(name: "SharedConfig"),
      .target(name: "HelperIPC"),
      .target(name: "KeyboardLayout"),
      .target(name: "KeyIO"),
      .external(name: "ComposableArchitecture"),
      .external(name: "Sharing"),
      .external(name: "Dependencies"),
      .external(name: "DependenciesMacros"),
    ]),
    unitTests("ConfiguratorFeature", deps: [
      .target(name: "KeymapModel"),
      .target(name: "SharedConfig"),
      .target(name: "HelperIPC"),
      .target(name: "KeyboardLayout"),
      .external(name: "ComposableArchitecture"),
      .external(name: "IdentifiedCollections"),
    ]),
    .target(
      name: "ConfiguratorSnapshotTests",
      destinations: .macOS,
      product: .unitTests,
      bundleId: "\(prefix).ConfiguratorSnapshotTests",
      deploymentTargets: .macOS("26.0"),
      sources: ["Tests/ConfiguratorSnapshotTests/**"],
      dependencies: [
        .target(name: "ConfiguratorFeature"),
        .target(name: "HelperIPC"),
        .target(name: "SharedConfig"),
        .target(name: "KeymapModel"),
        .target(name: "KeyboardLayout"),
        .external(name: "ComposableArchitecture"),
        .external(name: "SnapshotTesting"),
      ]
    ),
    .target(
      name: "ConfiguratorUITests",
      destinations: .macOS,
      product: .uiTests,
      bundleId: "\(prefix).ConfiguratorUITests",
      deploymentTargets: .macOS("26.0"),
      sources: ["Tests/ConfiguratorUITests/**"],
      dependencies: [.target(name: "Configurator")],
      // The UI test runner loads this bundle under library validation: both must carry the same
      // team signature (ad hoc has no team), and the hardened runtime is for shipped binaries only.
      settings: .settings(base: appSigningSettings.merging(["ENABLE_HARDENED_RUNTIME": "NO"]) { $1 })
    ),
    .target(
      name: "KeyLayersHelper",
      destinations: .macOS,
      product: .app,
      productName: "KeyLayersHelper",
      bundleId: "$(HELPER_BUNDLE_ID)",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "$(HELPER_DISPLAY_NAME)",
        "LSUIElement": true,
        "AppGroupIdentifier": "$(APP_GROUP_ID)",
        "HelperMachServiceName": "$(HELPER_MACH_SERVICE_NAME)",
        "ConfiguratorBundleIdentifier": "$(CONFIGURATOR_BUNDLE_ID)",
        "SigningTeamIdentifier": "$(DEVELOPMENT_TEAM)",
        "InputDaemonMachServiceName": "$(INPUT_DAEMON_MACH_SERVICE_NAME)",
        "InputDaemonBundleIdentifier": "$(INPUT_DAEMON_LABEL)",
      ]),
      sources: ["Apps/KeyLayersHelper/Sources/**"],
      resources: ["Apps/Configurator/Resources/AppIcon.icon"],
      entitlements: helperEntitlements,
      dependencies: [
        .target(name: "HelperFeature"),
        .target(name: "HelperIPC"),
        .target(name: "SharedConfig"),
        .external(name: "ComposableArchitecture"),
      ],
      // Only embedded in Configurator; a standalone copy must not land in the archive's Applications.
      settings: .settings(
        base: appSigningSettings.merging(["SKIP_INSTALL": "YES"]) { $1 }
          .merging(noAccentColor) { $1 }
          .merging(helperProfile.isEmpty ? [:] : ["PROVISIONING_PROFILE_SPECIFIER": .string(helperProfile)]) { $1 }
      )
    ),
    .target(
      name: "KeyLayersInputDaemon",
      destinations: .macOS,
      product: .commandLineTool,
      productName: "KeyLayersInputDaemon",
      bundleId: "$(INPUT_DAEMON_LABEL)",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .extendingDefault(with: [
        "InputDaemonMachServiceName": "$(INPUT_DAEMON_MACH_SERVICE_NAME)",
        "HelperBundleIdentifier": "$(HELPER_BUNDLE_ID)",
        "SigningTeamIdentifier": "$(DEVELOPMENT_TEAM)",
      ]),
      sources: ["Apps/KeyLayersInputDaemon/Sources/**"],
      dependencies: [
        .target(name: "InputDaemonCore"),
        .target(name: "InputDaemonIPC"),
        .target(name: "SharedConfig"),
      ],
      // Only embedded in Configurator (Contents/Library/HelperTools).
      settings: .settings(base: appSigningSettings.merging([
        "SKIP_INSTALL": "YES",
        "CREATE_INFOPLIST_SECTION_IN_BINARY": "YES",
      ]) { $1 })
    ),
    .target(
      name: "Configurator",
      destinations: .macOS,
      product: .app,
      productName: "KeyLayers",
      bundleId: "$(CONFIGURATOR_BUNDLE_ID)",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "$(CONFIGURATOR_DISPLAY_NAME)",
        "AppGroupIdentifier": "$(APP_GROUP_ID)",
        "HelperMachServiceName": "$(HELPER_MACH_SERVICE_NAME)",
        "HelperLaunchdPlistName": "$(HELPER_LAUNCHD_PLIST_NAME)",
        "HelperBundleIdentifier": "$(HELPER_BUNDLE_ID)",
        "InputDaemonPlistName": "$(INPUT_DAEMON_PLIST_NAME)",
      ]),
      sources: ["Apps/Configurator/Sources/**"],
      resources: ["Apps/Configurator/Resources/AppIcon.icon"],
      entitlements: .file(path: "Apps/Configurator/Configurator.entitlements"),
      scripts: [
        .post(
          path: "scripts/embed-helper.sh",
          name: "Embed Helper",
          inputPaths: [
            "$(BUILT_PRODUCTS_DIR)/KeyLayersHelper.app",
            "$(BUILT_PRODUCTS_DIR)/KeyLayersInputDaemon",
          ],
          outputPaths: [
            "$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LoginItems/KeyLayersHelper.app",
            "$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchAgents/$(HELPER_LAUNCHD_PLIST_NAME)",
            "$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/HelperTools/KeyLayersInputDaemon",
            "$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchDaemons/$(INPUT_DAEMON_PLIST_NAME)",
          ],
          basedOnDependencyAnalysis: false
        ),
      ],
      dependencies: [
        .target(name: "ConfiguratorFeature"),
        .target(name: "SharedConfig"),
        .target(name: "KeyLayersHelper"),
        .target(name: "KeyLayersInputDaemon"),
        .external(name: "ComposableArchitecture"),
      ],
      settings: .settings(base: appSigningSettings.merging([
        // The script copies a whole app bundle, which the user-script sandbox doesn't allow.
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
      ]) { $1 }.merging(noAccentColor) { $1 })
    ),
  ],
  schemes: [
    .scheme(
      name: "UnitTests",
      shared: true,
      buildAction: .buildAction(targets: unitTestTargets),
      testAction: .targets(unitTestTargets.map { .testableTarget(target: $0) })
    ),
    .scheme(
      name: "KeyLayersHelper",
      shared: true,
      buildAction: .buildAction(targets: ["KeyLayersHelper"]),
      runAction: .runAction(executable: "KeyLayersHelper")
    ),
    .scheme(
      name: "Configurator",
      shared: true,
      buildAction: .buildAction(targets: ["KeyLayersHelper", "KeyLayersInputDaemon", "Configurator"]),
      runAction: .runAction(executable: "Configurator")
    ),
    .scheme(
      name: "SnapshotTests",
      shared: true,
      buildAction: .buildAction(targets: snapshotTestTargets),
      testAction: .targets(snapshotTestTargets.map { .testableTarget(target: $0) })
    ),
    .scheme(
      name: "UITests",
      shared: true,
      buildAction: .buildAction(
        targets: ["KeyLayersHelper", "KeyLayersInputDaemon", "Configurator", "ConfiguratorUITests"]
      ),
      testAction: .targets([.testableTarget(target: "ConfiguratorUITests")])
    ),
  ]
)
