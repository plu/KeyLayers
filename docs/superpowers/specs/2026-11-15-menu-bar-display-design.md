# Menu bar display setting — design

## Why

The helper's menu bar item always reads "DEF · Mod" next to the keyboard icon. That takes too much
menu bar space, and the user should choose what appears there.

## Goals

- The user picks what's next to the icon: nothing, the keymap, the layer, or both.
- Default: icon only.

## Non-goals

- Hiding the layer while on Base, per-layer icons, full keymap names. (Offered, not taken.)
- Changing the setting from the helper's menu.

## Approaches

- **A. Two toggles in the configurator's Settings sheet** ("Show keymap", "Show layer"), stored in
  the configuration file next to `showLayerHUD`. **Picked**: plain, matches the HUD setting, the
  helper already observes the file.
- B. One four-way picker in Settings. Same behavior, more wordy; only pays off with more modes later.
- C. A submenu in the helper's menu. Settings would live in two places, and the helper would have to
  start writing the configuration file.

## Design

- `Settings` (KeymapModel) gains `menuBarShowsKeymap: Bool` and `menuBarShowsLayer: Bool`, both
  default `false`. `Settings` gets a custom `init(from:)` using `decodeIfPresent` so existing files
  load; files without the keys get icon only (intended, even for existing users).
- `SettingsFeature`: actions `menuBarShowsKeymapChanged(Bool)` / `menuBarShowsLayerChanged(Bool)`,
  guarded by `isReadOnly` like the HUD toggle.
- `SettingsView`: a new "Menu Bar" section with the two toggles (accessibility IDs
  `settings.menuBarKeymap`, `settings.menuBarLayer`). Sheet height grows to fit.
- `HelperFeature.menuBarTitle` builds the text from the enabled parts, joined by " · ":
  - keymap → abbreviation; layer → layer name.
  - Paused never appears as text; the icon alone signals it. While paused the layer is left out
    (no layer is active); the keymap still shows if enabled.
  - **Builder's call:** pick a paused symbol more distinct than today's `keyboard.badge.ellipsis`,
    checked in SF Symbols at menu bar size; keep the current one if nothing reads better.
  - Nothing enabled → empty string.
  - Before the runtime reports a status: "—" only if some text is enabled, else empty.
- `MenuBarLabel` omits the `Text` when the title is empty, and keeps an accessibility label
  ("KeyLayers" plus keymap and layer) so VoiceOver still says the full state in icon-only mode.
  **My call.**

## Tests

- KeymapModel: decoding a file without the new keys → both `false`; round-trip.
- SettingsFeature: each toggle writes the file; ignored while read-only.
- HelperFeature: `menuBarTitle` for all four combinations, paused, and before status.
