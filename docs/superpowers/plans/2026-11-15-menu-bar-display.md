# Menu Bar Display Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user choose whether the menu bar item shows the keymap, the layer, both, or only the icon (default).

**Architecture:** Two `Bool`s in the shared configuration's `Settings`, edited in the configurator's Settings sheet; the helper derives the menu bar text and accessibility label from them.

**Tech Stack:** Swift, SwiftUI, TCA, Swift Testing, swift-snapshot-testing, Tuist + mise.

**Spec:** `docs/superpowers/specs/2026-11-15-menu-bar-display-design.md`

## Global Constraints

- Default: icon only (`menuBarShowsKeymap = false`, `menuBarShowsLayer = false`), also for files missing the keys.
- "Paused" never appears as menu bar text. While paused the layer is omitted.
- Parts joined by `" · "`.
- Swift warnings are errors; `mise run lint` must pass.

## Review Focus

- Existing config file without the new keys → loads, icon only (Task 1 test).
- Config file without `showLayerHUD` too (custom decoder now covers every field) → defaults `true` (Task 1 test).
- Paused with only the layer enabled → empty title, not "Paused" (Task 3 test).
- Before the runtime reports a status with nothing enabled → empty, not "—" (Task 3 test).
- Toggling while the file is unreadable → no write (Task 2 test).

---

### Task 1: Settings fields

**Files:**
- Modify: `Sources/KeymapModel/Configuration.swift` (`Settings`)
- Test: `Tests/KeymapModelTests/ConfigurationCodingTests.swift`

**Interfaces:**
- Produces: `Settings.menuBarShowsKeymap: Bool`, `Settings.menuBarShowsLayer: Bool`;
  `Settings.init(doubleTapTimeoutMilliseconds: Int = 250, showLayerHUD: Bool = true, menuBarShowsKeymap: Bool = false, menuBarShowsLayer: Bool = false)`

- [ ] **Step 1: Failing test** `settingsWithoutNewKeysDecodeToDefaults`: decode `{"doubleTapTimeoutMilliseconds": 300}` as `Settings` → `== Settings(doubleTapTimeoutMilliseconds: 300)`, so `showLayerHUD == true`, both menu bar flags `false`. Extend `roundTripIsStable` (or add a test) with both flags `true`.
- [ ] **Step 2:** `mise run test:unit` → new test fails to compile/fails.
- [ ] **Step 3:** Add the fields and a custom `init(from:)` using `decodeIfPresent` with the init defaults for every field (encoding stays synthesized).
- [ ] **Step 4:** `mise run test:unit` → PASS.
- [ ] **Step 5:** Commit `feat(model): menu bar display settings`.

### Task 2: Settings sheet toggles

**Files:**
- Modify: `Sources/ConfiguratorFeature/SettingsFeature.swift`, `Sources/ConfiguratorFeature/SettingsView.swift`
- Test: `Tests/ConfiguratorFeatureTests/SettingsFeatureTests.swift`, snapshots in `Tests/ConfiguratorSnapshotTests/ShellSnapshotTests.swift`

**Interfaces:**
- Consumes: Task 1 fields.
- Produces: `SettingsFeature.Action.menuBarShowsKeymapChanged(Bool)`, `.menuBarShowsLayerChanged(Bool)`.

- [ ] **Step 1: Failing tests** `menuBarTogglesAreSaved` (send both `true`, assert state change and `fakes.savedConfiguration()?.settings` has both `true`) and `menuBarTogglesIgnoredWhileReadOnly` (unreadable file → no state change, nothing saved; mirror any existing read-only test setup).
- [ ] **Step 2:** `mise run test:unit` → FAIL.
- [ ] **Step 3:** Actions follow the `showLayerHUDChanged` pattern (read-only guard, no-op if unchanged). View: new `Section` header "Menu Bar" between "Remapping" and "Helper", toggles "Show keymap" (`settings.menuBarKeymap`) and "Show layer" (`settings.menuBarLayer`), `.disabled(store.isReadOnly)`. Increase the sheet's frame height so nothing scrolls; update the snapshot test size to match.
- [ ] **Step 4:** `mise run test:unit` → PASS; `mise run snapshot:record`, inspect the settings PNGs, then `mise run test:snapshot` → PASS.
- [ ] **Step 5:** Commit `feat(configurator): menu bar display toggles`.

### Task 3: Helper menu bar label

**Files:**
- Modify: `Sources/HelperFeature/HelperFeature.swift` (`menuBarTitle`, new `menuBarAccessibilityLabel`), `Sources/HelperFeature/MenuBarLabel.swift`, `Apps/KeyLayersHelper/Sources/KeyLayersHelperApp.swift`
- Test: `Tests/HelperFeatureTests/HelperFeatureTests.swift`, `Tests/HelperSnapshotTests/HelperSnapshotTests.swift`

**Interfaces:**
- Consumes: Task 1 fields via `state.configuration.settings`.
- Produces: `HelperFeature.State.menuBarTitle: String`, `HelperFeature.State.menuBarAccessibilityLabel: String`;
  `MenuBarLabel(title: String, accessibilityLabel: String, isPaused: Bool)`.

- [ ] **Step 1: Failing tests** (status = starter keymap "DEF", layer `.mod`):
  - icon only → `""`; keymap → `"DEF"`; layer → `"Mod"`; both → `"DEF · Mod"`.
  - paused: both → `"DEF"`; layer only → `""`. Update `emergencyStopMarksPaused` (default config) to expect `""`.
  - no status: nothing enabled → `""`; any enabled → `"—"`.
  - `menuBarAccessibilityLabel`: `"KeyLayers, DEF, Mod"` running; `"KeyLayers, DEF, Paused"` paused; `"KeyLayers"` before status — independent of the toggles.
- [ ] **Step 2:** `mise run test:unit` → FAIL.
- [ ] **Step 3:** Implement both properties. `MenuBarLabel` renders `Text` only when `title` is non-empty and sets `.accessibilityLabel(accessibilityLabel)`. Pick the paused symbol: compare `keyboard.badge.ellipsis` with alternatives (e.g. a pause-badged keyboard) in SF Symbols at menu bar size; keep the current one unless another is clearly more noticeable, and verify the name exists in the SDK. Pass the new label in `KeyLayersHelperApp`.
- [ ] **Step 4:** Snapshot tests: add `menuBarLabelIconOnly` (`title: ""`), make `menuBarLabelPaused` use `title: "DEF"`. Record, inspect, `mise run test:snapshot` → PASS; `mise run test:unit` → PASS.
- [ ] **Step 5:** `mise run lint` → clean. Commit `feat(helper): configurable menu bar text`.
