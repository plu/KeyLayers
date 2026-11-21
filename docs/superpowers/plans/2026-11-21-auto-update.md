# Auto Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tag-built KeyLayers releases update themselves with Sparkle from GitHub Releases, and an update leaves no old helper or daemon running.

**Architecture:** Versions and the Sparkle feed/key are build settings fed from `TUIST_*` environment variables, set only by the tag workflow. Sparkle lives in the Configurator app target (not `ConfiguratorFeature`). The helper notices its replaced executable on its existing 2 s poll and exits non-zero so launchd relaunches it. A new `release:appcast` task writes a one-item signed appcast; the workflow publishes it with the zip as a GitHub Release.

**Tech Stack:** Swift 6, TCA, Tuist, Sparkle 2.10.1 (SPM), mise, fnox, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-21-auto-update-design.md`

## Global Constraints

- Sparkle `from: "2.10.1"`, linked to the `Configurator` target only.
- Env → build setting: `TUIST_MARKETING_VERSION` → `MARKETING_VERSION` (default `0.0.0`), `TUIST_BUILD_NUMBER` → `CURRENT_PROJECT_VERSION` (default `1`), `TUIST_SPARKLE_FEED_URL` → `SPARKLE_FEED_URL` (default empty), `TUIST_SPARKLE_PUBLIC_KEY` → `SPARKLE_PUBLIC_KEY` (default empty).
- Feed URL: `https://github.com/<github.repository>/releases/latest/download/appcast.xml`.
- fnox: `SPARKLE_ED_PRIVATE_KEY`, `SPARKLE_PUBLIC_KEY` (exist already).
- Tags: `v<major>.<minor>.<patch>`; build number = `github.run_number`.
- `sparkle:minimumSystemVersion` = `26.0`.
- A local `mise run release` needs no new secrets and never starts the updater.
- No README changes.

## Review Focus

- Helper quit by the user (menu or SIGTERM) must still exit 0 and stay stopped; only a replaced executable exits non-zero.
- Executable missing mid-replace counts as changed (existing `hasChanged` semantics) — the helper must not exit in a loop when it has no launch identity.
- Build with only one of feed URL / public key set: updater stays off (both required).
- Tag that isn't `vX.Y.Z` (e.g. `v1.2`, `test`): workflow fails before building.
- `gh release create` failing after a successful build: the zip is still uploaded as an artifact.

---

### Task 1: Version numbers from the environment

**Files:**
- Modify: `Project.swift` (base settings; `infoPlist` of `Configurator`, `KeyLayersHelper`, `KeyLayersInputDaemon`)

- [ ] **Step 1:** Base settings gain `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` from `Environment.marketingVersion` / `Environment.buildNumber` with the defaults above. Each of the three `infoPlist: .extendingDefault(with:)` gets `"CFBundleShortVersionString": "$(MARKETING_VERSION)"`, `"CFBundleVersion": "$(CURRENT_PROJECT_VERSION)"`.
- [ ] **Step 2: Verify** `TUIST_MARKETING_VERSION=1.2.3 TUIST_BUILD_NUMBER=42 mise run generate && mise run build`, then `plutil -p` on the built `KeyLayers.app`, its embedded helper, and `otool -s __TEXT __info_plist` / `launchctl plist` on the daemon: all show `1.2.3` / `42`. Without the variables: `0.0.0` / `1`.
- [ ] **Step 3: Commit** `feat(release): version and build number come from the environment`.

### Task 2: Helper restarts itself when its executable is replaced

**Files:**
- Move: `Sources/InputDaemonCore/ExecutableIdentity.swift` → `Sources/InputDaemonIPC/ExecutableIdentity.swift`; `Tests/InputDaemonCoreTests/ExecutableIdentityTests.swift` → `Tests/InputDaemonIPCTests/` (fix imports; daemon `main.swift` imports `InputDaemonIPC`)
- Modify: `Sources/HelperFeature/HelperAppClient.swift`, `Sources/HelperFeature/HelperFeature.swift`, `Apps/KeyLayersHelper/Sources/KeyLayersHelperApp.swift`
- Test: `Tests/HelperFeatureTests/HelperFeatureTests.swift`

**Interfaces:**
- `HelperAppClient.executableReplaced: @Sendable () -> Bool = { false }` — live: compares the helper executable (`Bundle.main.executablePath`, symlinks resolved) with the identity recorded at launch via `ExecutableIdentity.hasChanged`.
- `HelperAppClient.restartForUpdate: @Sendable () async -> Void` — live: `exit(75)` (EX_TEMPFAIL; non-zero → launchd `KeepAlive.SuccessfulExit = false` relaunches).
- `HelperFeature.Action.executableReplaced`.
- The live launch identity is captured when the helper app starts (touch it in the app's `init`), not lazily on the first poll.

- [ ] **Step 1: Write failing tests**
  - `executableReplacedRestartsAfterStoppingRuntime`: start `.task`, set fake `executableReplaced` to true, advance clock by `permissionPollInterval` → receive `.executableReplaced` (`isQuitting = true`); `calls == ["stop", "restartForUpdate"]`; no further polls.
  - `userQuitNeverRestartsForUpdate`: `.quitTapped` with `executableReplaced` true → `calls == ["stop", "terminate"]`.
- [ ] **Step 2:** Run `mise run test:unit`; both fail (no such action/endpoint).
- [ ] **Step 3:** In the poll loop, check `app.executableReplaced()` before each `permissionsChecked` send; when true send `.executableReplaced` and end the loop. The reducer handles it like `.quitTapped` (guard `!isQuitting`, cancel poll and grace, `runtime.stop()`) but ends with `app.restartForUpdate()`.
- [ ] **Step 4:** `mise run test:unit` passes (including the moved `ExecutableIdentityTests`).
- [ ] **Step 5: Commit** `feat(helper): restart when an update replaced the helper`.

### Task 3: Sparkle in the configurator

**Files:**
- Modify: `Tuist/Package.swift` (Sparkle dependency), `Project.swift` (Configurator dependency `.external(name: "Sparkle")`; Info.plist `SUFeedURL = $(SPARKLE_FEED_URL)`, `SUPublicEDKey = $(SPARKLE_PUBLIC_KEY)`, `SUEnableAutomaticChecks = true`; base settings for both from env)
- Create: `Apps/Configurator/Sources/Updater.swift`
- Modify: `Apps/Configurator/Sources/ConfiguratorApp.swift`

**Interfaces:**
- `@MainActor final class Updater: ObservableObject` — `init()` creates `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)` only when `Bundle.main` has non-empty `SUFeedURL` and `SUPublicEDKey`; `var isAvailable: Bool`; `@Published var canCheckForUpdates: Bool` (KVO on `updater.canCheckForUpdates`); `func checkForUpdates()`.
- `struct UpdateCommands: Commands` — `CommandGroup(after: .appInfo) { Button("Check for Updates…") }` disabled by `!canCheckForUpdates`; emits nothing when `!isAvailable`.

- [ ] **Step 1:** Dependency + settings + plist keys; `mise run generate` resolves Sparkle; note where SPM put `sign_update` (expected `Tuist/.build/artifacts/sparkle/Sparkle/bin/sign_update`) for Task 4.
- [ ] **Step 2:** `Updater` + `UpdateCommands`; `ConfiguratorApp` owns one `Updater` (`@StateObject`) and adds the commands.
- [ ] **Step 3: Verify** `mise run build` and `mise run test` pass. Run the built app without the env variables: no "Check for Updates…" item. Build with `TUIST_SPARKLE_FEED_URL=https://github.com/plu/KeyLayers/releases/latest/download/appcast.xml` and `TUIST_SPARKLE_PUBLIC_KEY=$(fnox get SPARKLE_PUBLIC_KEY)`: item present after "About KeyLayers"; clicking it shows Sparkle's check (an error about the missing feed is expected until the first release). Built with only one of the two: no item.
- [ ] **Step 4: Commit** `feat(configurator): check for updates with Sparkle in tag builds`.

### Task 4: Appcast and tag releases

**Files:**
- Create: `mise/tasks/release/appcast`
- Modify: `mise/tasks/release/archive` (feed switch + verification), `.github/workflows/release.yml`

**Interfaces:**
- `release:appcast` (not in the `release` depends chain). Env: `RELEASE_TAG`, `GITHUB_REPOSITORY`, `SPARKLE_ED_PRIVATE_KEY`. Reads version/build from `build/release/export/KeyLayers.app/Contents/Info.plist`; signs `build/release/KeyLayers.zip` with `sign_update --ed-key-file` (key written to a temp file, removed on exit); writes `build/release/appcast.xml` (one `<item>`: title, `sparkle:version` = build, `sparkle:shortVersionString` = version, `sparkle:minimumSystemVersion` 26.0, `sparkle:releaseNotesLink` = `https://github.com/<repo>/releases/tag/<tag>`, enclosure url `https://github.com/<repo>/releases/download/<tag>/KeyLayers.zip`, `length`, `sparkle:edSignature`, `type="application/octet-stream"`, `pubDate`). Fails if the tag isn't `v` + the app's version.

- [ ] **Step 1:** `release:archive`: when `TUIST_SPARKLE_FEED_URL` is set, require `SPARKLE_PUBLIC_KEY` and export `TUIST_SPARKLE_PUBLIC_KEY` from it; after export, verify the app's `SUFeedURL` / `SUPublicEDKey` equal the inputs. Unset: verify both are empty.
- [ ] **Step 2:** `release:appcast` as above. **Verify** against the local release from Task 3's settings (or a stub `build/release` with a real zip): `xmllint --noout` passes; `sign_update --verify build/release/KeyLayers.zip <sig> --ed-key-file <tmp key>` succeeds; wrong tag fails with a message.
- [ ] **Step 3:** Workflow: add `push: tags: ['v*']`, `permissions: contents: write`. A first step validates the tag (`^v[0-9]+\.[0-9]+\.[0-9]+$`) and exports `TUIST_MARKETING_VERSION`, `TUIST_SPARKLE_FEED_URL`, `RELEASE_TAG`; every run exports `TUIST_BUILD_NUMBER=${{ github.run_number }}`. After `mise run release`: upload artifact (always), then on tags only `fnox exec -- mise run release:appcast` and `gh release create "$RELEASE_TAG" build/release/KeyLayers.zip build/release/appcast.xml --generate-notes --verify-tag` with `GH_TOKEN`. `actionlint` clean.
- [ ] **Step 4: Commit** `ci: tag pushes publish a GitHub Release with the Sparkle appcast`.

### Task 5: Documentation

**Files:**
- Modify: `docs/ARCHITECTURE.md` (Updates section; helper self-restart next to the daemon's; "Known limitations": only tag builds update), `docs/MANUAL-CHECKLIST.md` (release by tag; update test: install vN, release vN+1, accept update, verify helper and daemon run vN+1 via `launchctl print` and remapping still works without new permission prompts)

- [ ] **Step 1:** Write both. **Step 2: Commit** `docs: auto update and tag releases`.
