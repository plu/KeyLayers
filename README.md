# KeyLayers

KeyLayers is a keyboard remapper for macOS. It adds layers to your keyboard: hold a key and
the layer it points to replaces the keys underneath until you let go.

The starter keymap holds **fn** for the Mod layer:

- **H J K L** are the arrow keys (left, down, up, right).
- **Y U I O** are Home, Page Down, Page Up and End.
- **F1 to F12** are the Mac top-row functions: brightness, Mission Control, Spotlight, dictation,
  Do Not Disturb, previous/play/next track, mute and volume.
- **Delete** is Forward Delete, and **← → ↑ ↓** are Home, End, Page Up and Page Down, as with fn on a Mac.

Caps Lock is left alone.

Because fn is the Mod key, a fn tap, Globe shortcuts (Globe+E for emoji, Globe+F for full screen,
Globe+arrow for window tiling) and fn combos the Mod layer doesn't map don't reach macOS. The
starter maps the common ones above. To keep fn, pick another Mod key in the configurator.

| Base layer | Mod layer (hold fn) |
| --- | --- |
| ![Base layer](docs/images/keylayers-base.png) | ![Mod layer](docs/images/keylayers-mod.png) |

## Setup

Release builds need Apple's approval of the HID Virtual Device entitlement, which is still pending.
Until then, build from source (see "Developing" below, which needs a paid Apple Developer account).

KeyLayers has three parts: the configurator (`KeyLayers.app`), a login item (`KeyLayersHelper`) and
a root input service (`KeyLayersInputDaemon`). The status area at the bottom of the window shows
what is still missing. In short:

1. Open `KeyLayers.app` and approve KeyLayers (the helper and the input service) in System Settings, General, Login Items.
2. Allow **Accessibility** for `KeyLayersHelper`. It uses it to post the remapped keys through a
   virtual keyboard.
3. Allow **Input Monitoring** for the input service. macOS can't prompt for this one. In System
   Settings, Privacy & Security, Input Monitoring, click "+" and add
   `KeyLayers.app/Contents/Library/HelperTools/KeyLayersInputDaemon`. The service restarts itself
   shortly afterwards (launchd may take up to about 10 seconds).

If remapping gets in your way, press **Left Control + Left Option + Left Command + Escape** to pause
it. The Pause button in the window does the same.

## Editing

Click a key on the layer you want to change and pick an action: a key press with optional
modifiers (including media keys), a layer switch, a keymap switch, or None. To remove a mapping, click the key, choose the None tab and
leave "Block the key" off. The key then behaves as it normally does.

## Developing

Requires [mise](https://mise.jdx.dev), which installs Tuist and the other tools.

**Without an Apple Developer account** the project builds ad hoc: you can build and run the
configurator and run the unit and snapshot tests. Remapping does not work.

**Remapping requires a paid Apple Developer Program membership.** The helper creates its virtual
keyboard with the restricted `com.apple.developer.hid.virtual.device` entitlement, which needs a
provisioning profile. The root input service exits at startup without a team ID, because it can only
verify its XPC peer with a team signature and it streams keystrokes as root. As far as we know, a free
Personal Team can't add the HID Virtual Device capability. The bundle IDs under `com.plunien.keylayers`
belong to the author's team, so use your own prefix.

Setup (Xcode 27.2; `Tuist.swift` pins it):

1. `mise install`, then `git lfs install && git lfs pull` (snapshot references are in Git LFS).
2. `cp mise.local.toml.example mise.local.toml` and set `TUIST_TEAM_ID` and `TUIST_BUNDLE_ID_PREFIX`
   (mise loads it for every task; the file is git-ignored).
3. In the developer portal, register the App IDs `<prefix>.configurator` (no capabilities) and
   `<prefix>.helper` with the "HID Virtual Device (development)" capability. `<prefix>.inputd` needs
   no App ID.
4. Sign in to that team in Xcode (Settings, Accounts).
5. `mise run build`. It passes `-allowProvisioningUpdates`, so Xcode creates the development profile.
   After each Debug build the helper restarts and the input service replaces itself on the helper's
   next connection (a gap of about 2 s).
6. Launch the app and grant the permissions from "Setup" above.
7. `mise run test` runs the unit and snapshot tests.

| Variable | Needed for | Default |
| --- | --- | --- |
| `TUIST_TEAM_ID` | Remapping, signed builds, release | none (ad hoc build) |
| `TUIST_BUNDLE_ID_PREFIX` | Using your own App IDs | `com.plunien.keylayers` |
| `HELPER_PROVISIONING_PROFILE` | Release only: Developer ID profile name for the helper | none |
| `ASC_API_KEY`, `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID` | Release only: notarization | none |
| `DEVELOPER_ID_CERTIFICATE` | Release only, optional: base64 .p12 instead of a login keychain identity | none |

`fnox.toml` holds the maintainer's age-encrypted secrets, which only the author and CI can decrypt.
Everyone else uses `mise.local.toml` or plain environment variables.

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) explains how the three parts work together,
[`docs/TESTING.md`](docs/TESTING.md) covers the tests, and
[`docs/MANUAL-CHECKLIST.md`](docs/MANUAL-CHECKLIST.md) lists the steps for a release.

The screenshots above are rendered by the snapshot tests. After changing the UI, run
`mise run readme:images` to re-record them and copy the light variants to `docs/images/`.
