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
Until then, build from source (see below).

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

## Building from source

Requires [mise](https://mise.jdx.dev), which installs Tuist and the other tools.

```sh
mise run build
mise run test
```

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) explains how the three parts work together,
[`docs/TESTING.md`](docs/TESTING.md) covers the tests, and
[`docs/MANUAL-CHECKLIST.md`](docs/MANUAL-CHECKLIST.md) lists the steps for a release.

The screenshots above are rendered by the snapshot tests. After changing the UI, run
`mise run readme:images` to re-record them and copy the light variants to `docs/images/`.
