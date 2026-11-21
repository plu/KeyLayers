# Architecture

This document describes how KeyLayers is built: what it does, which processes take part, how a key
travels from the physical keyboard to the system, and what keeps that path safe. The code is the
reference; this document names the files to read for details.

## What KeyLayers is

KeyLayers makes a Mac keyboard (the built-in keyboard or an external Apple keyboard) behave like an
[Ultimate Hacking Keyboard](https://ultimatehackingkeyboard.com): several **keymaps**, each with
**layers**, keys with a secondary role on hold, and layer switching by hold, toggle or
double-tap lock.

- **Layers** per keymap: Base, Mod, Fn, Mouse, Fn2, Fn3, Fn4, Fn5 (`LayerName`). "Mouse" is only a
  name; there are no mouse keys.
- **Key actions** (`KeyAction`):
  - `keypress`: a key, optional modifiers (left and right distinguished), and an optional
    secondary role on hold (a layer or a modifier);
  - `switchLayer`: with mode `hold`, `toggle` or `holdAndDoubleTapToggle`;
  - `switchKeymap`;
  - `none` (transparent: falls through to Base) and `block` (does nothing).
  An action type the running version doesn't know decodes to `unsupported`, which the configurator
  shows as such and the engine treats as Block.
- **Secondary roles** follow UHK's Simple strategy: the key's tap action is held back; if another key
  goes down while it is held, the secondary role applies; released alone, it sends its tap action.
- One keymap is active at a time. A keymap switch resets to Base. The double-tap timeout for layer
  locking defaults to 250 ms.

### Starter keymap

New users start with one keymap, "Default" (`DEF`, `Configuration+Starter.swift`):

- **Base**: fn holds the Mod layer. Every other key, Caps Lock included, is unmapped and types what is
  printed on it.
- **Mod**:
  - H J K L are the arrows (left, down, up, right); Y U I O are Home, Page Down, Page Up and End.
  - F1–F12 are the Mac top-row functions (see the media-key table below).
  - Delete is Forward Delete, and the arrows are Home, End, Page Up and Page Down, the combos fn gives
    on a Mac.
- All other layers are empty.

## Processes

KeyLayers runs as three processes. Reading the keyboards and emitting keys have to be split: a root
process can seize a keyboard but cannot create a CoreHID virtual keyboard (that needs Accessibility,
which root can't be granted), and a user process can create the virtual keyboard but is refused the
seize.

| Process | Bundle ID | Runs as | Registered as |
| --- | --- | --- | --- |
| Configurator `KeyLayers.app` | `<prefix>.configurator` | user | — |
| Helper `KeyLayersHelper` | `<prefix>.helper` | user | login item, `SMAppService.agent` |
| Input daemon `KeyLayersInputDaemon` | `<prefix>.inputd` | root | `SMAppService.daemon` |

The `<prefix>` comes from `TUIST_BUNDLE_ID_PREFIX` (default `com.plunien.keylayers`). Debug builds
append `.dev` to it (see "Signing and builds"), so a dev build runs beside an installed release.

**Configurator** (`Apps/Configurator`, `ConfiguratorFeature`). The window where keymaps are edited on a
drawing of the user's own keyboard. It writes the configuration file, registers the helper and the
daemon, and shows their status: helper running or not, approval needed, missing permissions, the
input daemon needing Input Monitoring (with buttons that open System Settings and reveal the daemon in
Finder), configuration errors, and a pause toggle. It also reads macOS's per-keyboard Modifier Keys
remaps (`com.apple.keyboard.modifiermapping.*`) and shows a note that they don't apply to keyboards
KeyLayers seizes. The configurator works without a running helper.

**Helper** (`Apps/KeyLayersHelper`, `HelperFeature`). An `LSUIElement` agent embedded at
`Contents/Library/LoginItems/KeyLayersHelper.app`. It owns the remapping engine, the connection to the
input daemon, one CoreHID virtual keyboard per seized physical keyboard, the menu bar item (active
keymap abbreviation and layer, keymap list, pause/resume, open the configurator, quit) and the layer
HUD (shown for about 1 s when a layer is toggled or locked and on a keymap switch; can be turned off).
It watches the configuration file and applies changes without a restart, and polls permissions every
2 s so a grant or a revocation is noticed without restarting.

**Input daemon** (`Apps/KeyLayersInputDaemon`, `InputDaemonCore`). A small command-line tool embedded
at `Contents/Library/HelperTools/KeyLayersInputDaemon`, started on demand by launchd when the helper
connects to its Mach service (no `RunAtLoad`). It matches keyboards and keypads with `IOHIDManager`,
seizes them (`kIOHIDOptionsTypeSeizeDevice`) while capture is on, and forwards their raw key events to
the helper. It never seizes KeyLayers' own virtual keyboards, which it recognises by the reserved
vendor ID `0x4B4C` ("KL") and the unique-ID/name prefix `com.plunien.keylayers.virtual.`.

`scripts/embed-helper.sh` (a post-build phase of the Configurator target) copies the helper and the
daemon into the app bundle and writes both launchd plists (`Contents/Library/LaunchAgents/` and
`Contents/Library/LaunchDaemons/`). In Debug builds it also restarts a running helper so the new build
takes over.

## Modules

| Module | Purpose |
| --- | --- |
| `KeymapModel` | Value types and the Codable file format: `Configuration`, `Keymap`, `Layer`, `KeyAction`, `KeyID`, the starter keymap. |
| `RemapEngine` | Pure, deterministic state machine: `KeyEvent` in, output events, status and notifications out. Time is passed in; no OS APIs. |
| `KeyIO` | The `KeyInputOutput` seam and its live conformance `HIDBackend`: daemon connection, virtual keyboards and their reports, output routing, macOS keycode table for the key recorder and labels. |
| `SharedConfig` | App identifiers from Info.plist, the configuration file location in the App Group, the `@Shared` file-storage key. |
| `HelperIPC` | XPC between configurator and helper: `HelperStatus`, the protocols, server and client. |
| `InputDaemonIPC` | XPC between helper and daemon: protocols, `RawKeyEvent` and `InputDevice` wire formats, the peer requirement. |
| `InputDaemonCore` | The daemon's logic: `CaptureController` (seize/release rules), `InputDaemonServer` (connection policy), `LiveHIDSeizer`, `ExecutableIdentity`. |
| `HelperFeature` | The helper's TCA feature: `RemapperRuntime` hosting the engine on a backend, permissions, menu bar, HUD. |
| `ConfiguratorFeature` | The configurator's TCA features and SwiftUI views: keymap list, keymap editor, key action popover, key recorder, status area, settings. |
| `KeyboardLayout` | Geometry of the supported Apple keyboards (MacBook built-in and Magic Keyboard; ANSI, ISO, JIS), keyboard detection, key labels from the current input source. |

## From a physical key to the system

1. **Seize.** The daemon seizes every matched keyboard when the helper starts capture, and newly
   plugged-in keyboards while capture is on. With the device seized, macOS no longer sees its events.
2. **Raw HID usage.** The daemon reads input values and forwards only the Keyboard/Keypad page (`0x07`,
   usages `0x04`–`0xE7`) and the Apple top-case `fn` (`0xFF`/`0x03`). These are the keys' raw usages,
   before any macOS remapping, so a Modifier Keys remap of Caps Lock doesn't change what KeyLayers sees.
3. **XPC.** Events go to the helper as `RawKeyEvent`s (device ID, page, usage, down/up, timestamp)
   from one serial queue, in arrival order across all keyboards. Device changes and seize results
   travel as `InputDevice` lists.
4. **Engine.** `HIDBackend` turns each event into a `KeyEvent` and calls `RemapperRuntime`'s handler
   synchronously on one input queue. The handler takes a lock, runs `RemapEngine`, and posts the output
   before returning. `KeyID` is a HID page/usage pair, so no keycode translation happens on this path.
   Raw seized usages need no ISO swap: on an ISO keyboard `0x64` is the key top-left and `0x35` the key
   next to left Shift, which is the convention the configurator draws (`PhysicalKeyFixup`).
5. **Virtual keyboard.** Nothing reaches the system unless the helper sends it. A pass-through emits
   the original key; otherwise only the engine's output is sent. Output goes to the virtual keyboard
   of the physical keyboard whose key caused it, and a key-up follows its key-down's keyboard
   (`OutputRouter`). Each virtual keyboard mirrors its physical keyboard's HID country code so macOS
   picks the same layout type. `VirtualKeyboardState` turns output events into full reports:

   | Report ID | Collection | Size | Content |
   | --- | --- | --- | --- |
   | 1 | Keyboard | 10 bytes | ID, modifier byte, reserved, 6 key slots, Apple `fn` vendor byte |
   | 2 | Consumer Control | 3 bytes | ID, one 16-bit usage (little-endian) |
   | 3 | Generic Desktop System Control | 2 bytes | ID, one 8-bit usage |

   Modifiers of a shortcut are pressed and released in the same report. Repeats are dropped (macOS
   repeats a held key itself). A seventh simultaneous key is dropped, and so is its key-up. Only one
   consumer and one system usage is held at a time; a new one replaces it.

### Media keys

The Mac top-row functions are standard HID usages, verified from a CoreHID virtual keyboard on
macOS 26:

| Starter Mod key | Function | Page / usage |
| --- | --- | --- |
| F1 | Brightness Down | Consumer `0x0C` / `0x70` |
| F2 | Brightness Up | Consumer `0x0C` / `0x6F` |
| F3 | Mission Control | Consumer `0x0C` / `0x29F` (AC Desktop Show All Windows) |
| F4 | Spotlight | Consumer `0x0C` / `0x221` (AC Search) |
| F5 | Dictation | Consumer `0x0C` / `0xCF` (Voice Command) |
| F6 | Do Not Disturb | Generic Desktop `0x01` / `0x9B` (System Do Not Disturb) |
| F7 | Previous Track | Consumer `0x0C` / `0xB6` |
| F8 | Play/Pause | Consumer `0x0C` / `0xCD` |
| F9 | Next Track | Consumer `0x0C` / `0xB5` |
| F10 | Mute | Consumer `0x0C` / `0xE2` |
| F11 | Volume Down | Consumer `0x0C` / `0xEA` |
| F12 | Volume Up | Consumer `0x0C` / `0xE9` |

Do Not Disturb works only on the Generic Desktop page (Apple's own keyboard maps F6 to `0x0001009B`);
the Consumer-page `0x9B` does nothing. The twelve keys are `KeyID` constants (`KeyID.mediaKeys`) and
appear as a "Media" group in the key picker. They are output only: they can't be recorded or used as
input.

## Configuration file

The configurator and the helper share one JSON file, `configuration.json`, in the App Group
container `<TEAMID>.<prefix>` (`AppIdentifiers.configurationURL`; ad-hoc builds without a
team fall back to Application Support). Debug builds use their own group, `<TEAMID>.<prefix>.dev`.
Both use swift-sharing's `@Shared(.configuration)` file storage. The configurator writes; the helper
only reads and applies every change at once. A file that can't be read keeps the last good
configuration in the helper, and the error is shown in the configurator's status area.

The top level holds `formatVersion` (1), the settings (double-tap timeout, HUD on/off), the ordered
keymaps and the default keymap's ID. Each layer is a sparse map from `KeyID` to `KeyAction`; absent keys
are transparent. The active keymap and layer are runtime state in the helper, not persisted; the
helper starts on the default keymap.

## XPC channels and their security

### Configurator → helper

The helper vends the Mach service `<TEAMID>.<prefix>.helper` (`RemapperXPCProtocol`:
current status, pause/resume). The configurator exports an observer the helper pushes
`HelperStatus` changes to. When the build has a team, the helper admits only the configurator: its
bundle ID, anchored to Apple, signed by the team (`HelperXPCServer.configuratorRequirement`).

### Helper ↔ input daemon

The daemon vends `<TEAMID>.<prefix>.inputd` (`InputDaemonXPCProtocol`: `startCapture`,
`stopCapture`, `heartbeat`); the helper exports `InputDaemonClientXPCProtocol` (`devicesChanged`,
`keyEvents`). The helper always connects to the daemon, never the other way round.

- **Peer requirements in both directions.** The daemon admits only a peer with the helper's bundle ID,
  anchored to Apple and signed by the team; the helper connects with `.privileged` and requires the
  daemon's identifier and the same team (`PeerRequirement.helper`). Without a team ID the daemon exits
  at launch and the helper refuses to connect: there is no unauthenticated mode for root code.
- **Promotion only on `startCapture`.** `setCodeSigningRequirement` is enforced on incoming messages,
  so accepting a connection proves nothing. A connection becomes the daemon's one client only when its
  `startCapture` arrives. A heartbeat never promotes. A newer client replaces the old one, whose
  connection is invalidated; until a connection is promoted it can neither drive capture nor receive
  key events.
- **Console user.** `startCapture` is admitted only from a connection whose effective uid is the
  console user's. The same check runs on every heartbeat: if the client's user has left the console
  (fast user switching, login window), the daemon releases the keyboards and answers `false`.
- **Heartbeat with reply.** The helper sends a heartbeat every 500 ms from its input queue, so a stuck
  handler stops them. The daemon releases everything 2 s after the last one. The reply says whether
  the daemon still captures for this connection; on `false` the helper drops its virtual keyboards,
  releases held keys and sends `startCapture` again.
- **Release** happens on `stopCapture`, client disconnect or interruption, replacement by a newer
  client, a missed heartbeat, and SIGTERM. On SIGTERM the daemon releases, flushes its last messages to
  the helper and exits.
- **Not permitted.** A seize refused with `kIOReturnNotPermitted` (`0xE00002E2`) means the daemon lacks
  Input Monitoring. macOS caches that decision per process, so the daemon reports it to the helper,
  flushes, and exits; the helper's reconnect (every 2 s) relaunches it with a fresh check.
- **Self-replacement.** At launch the daemon records its executable's identity (device, inode,
  modification time, size). On every new connection it compares the file on disk; if it changed or
  can't be read, it rejects the connection, releases everything and exits with status 0, so launchd
  starts the new binary on the helper's next attempt. An update or a rebuild therefore never leaves a
  stale root daemon running, and no `sudo` is needed.

## Permissions and setup

1. **Login Items.** The configurator registers the helper (`SMAppService.agent`) and the daemon
   (`SMAppService.daemon`). The user approves both under System Settings → General → Login Items &
   Extensions; the daemon needs admin approval.
2. **Accessibility for the helper.** CoreHID refuses to create a virtual keyboard without it.
3. **Input Monitoring for the daemon**, added by hand with "+" under Privacy & Security → Input
   Monitoring (`KeyLayers.app/Contents/Library/HelperTools/KeyLayersInputDaemon`). A root process can't
   be prompted (TCC refuses to prompt for uid 0), but without the grant the seize fails with
   `kIOReturnNotPermitted`. The daemon calls `IOHIDRequestAccess` once so it is listed. After the grant
   it is relaunched as described above, within about 10 s.

The helper doesn't need Input Monitoring: it never reads input itself.

### Signing and builds

- Minimum macOS is 26.0 for every target. Swift 6 with complete strict concurrency, hardened runtime
  everywhere. The project is generated by Tuist (`Project.swift`); tools and tasks come from mise.
- The team ID is set in one place (`TUIST_TEAM_ID`); it prefixes the App Group and both Mach service
  names. With a team, the apps sign with Apple Development (automatic); without one, builds are ad
  hoc and the helper goes without its restricted entitlement (so remapping can't start).
- The helper carries `com.apple.developer.hid.virtual.device`, a restricted entitlement that needs a
  provisioning profile. Development builds get it from Xcode (`-allowProvisioningUpdates` in the mise
  tasks). Release builds need a Developer ID provisioning profile for `<prefix>.helper`
  (`HELPER_PROVISIONING_PROFILE`); `release:archive` fails early without it.
- The configurator and the daemon need no profile. The daemon is a command-line tool with its
  Info.plist embedded in the binary.
- **Dev and release identities.** Debug builds use the prefix `<prefix>.dev` for everything that
  identifies an installation: bundle IDs (`<prefix>.dev.configurator`, `.dev.helper`, `.dev.inputd`),
  launchd labels and plists, both Mach services and the App Group (`<TEAMID>.<prefix>.dev`). In
  System Settings they show as "KeyLayers Dev" and "KeyLayers Helper Dev". Release builds keep the
  plain prefix, unchanged since the first release. `Project.swift` derives both sets from one
  function (`identitySettings`) as per-configuration project settings; Info.plists, entitlements,
  `AppIdentifiers` and `scripts/embed-helper.sh` read only these build settings. The reason: with a
  shared identity, a dev build and an installed release clobber each other on one Mac. Background
  Task Management keeps one record per bundle ID and moves it between the two copies, regenerating
  the helper item's UUID, so launchd's job for the other copy fails with `EX_CONFIG`; and TCC pins
  the Accessibility and Input Monitoring grants to one signing certificate (Apple Development or
  Developer ID), so the other build is denied while System Settings shows it as allowed.
- The dev App Group is separate on purpose: a dev build reads and writes its own
  `configuration.json`, so experiments never touch the configuration of the installed release.
- Both builds share `VirtualKeyboardIdentity` (vendor ID `0x4B4C`, unique ID prefix
  `com.plunien.keylayers.virtual.`), so each daemon ignores the virtual keyboards of both builds. Only
  one build remaps a given keyboard at a time: the seize is exclusive, so if both run, the second
  build's seize of a keyboard the first holds fails and shows as a seize error. A helper creates
  virtual keyboards only for seized keyboards, so the two builds never mirror the same keyboard.
- `mise run release` archives, exports with Developer ID, notarizes and packages
  `build/release/KeyLayers.zip` (see `docs/MANUAL-CHECKLIST.md`, "Release").

## Safety

- **Emergency combo.** Physical Left Control + Left Option + Left Command + Escape, checked on raw
  keys before any mapping, pauses remapping and releases every key. Pausing stops capture, so the
  daemon hands the keyboards back to macOS.
- **No key contents in logs.** Neither the daemon nor the helper logs which keys are pressed. Only
  device-level events (seized, released, seize failed, connection changes) are logged.
- **No stuck keys.**
  - A key's release resolves through the action that handled its press, even if the layer changed in
    between.
  - Losing the daemon connection, a keyboard disappearing with keys down, or a heartbeat reply of
    `false` resets the engine and releases every virtual key.
  - Pausing, stopping or disabling capture releases every virtual key before `stopCapture`.
  - The helper calls `startCapture` only once its virtual keyboards can be created.
  - The daemon releases the keyboards whenever the helper can't vouch for them (see the release rules
    above); killing the helper hands the keyboard back within about 2 s.
- The helper quits on SIGTERM like the menu's Quit does, releasing keys and stopping capture first.

## Known limitations and open items

- **Distribution.** Release builds need Apple's approval of the HID Virtual Device entitlement for a
  Developer ID provisioning profile. The approval is pending, so KeyLayers is built from source.
- **External ISO and JIS keyboards** are untested. The ISO convention is verified on a German MacBook
  ISO built-in keyboard (country code 13); mixed ISO + ANSI setups are untested too.
- **Caps Lock LED.** The system's LED output reports go to the virtual keyboard and are not forwarded
  to the physical keyboard, so its Caps Lock light stays off.
- **macOS per-keyboard Modifier Keys settings** don't apply to seized keyboards. KeyLayers doesn't
  imitate them; the configurator shows a note and the remap belongs in the keymap.
- **fn tap and Globe shortcuts are not passed through** while fn is the Mod key (fn tap, Globe+E,
  Globe+F, Globe+arrow tiling). The starter maps fn's common combos; to keep fn, pick another Mod key.
  The "Use F1, F2… as standard function keys" setting isn't honoured: the top row sends F1–F12, and
  the media functions live on a layer.
- **VoiceOver on mapped caps.** A key cap's VoiceOver label names the physical key, but its value for a
  Keypress whose target is a non-printing key (an arrow, Home, Forward Delete, …) is the glyph shown on
  the cap rather than the key's name. Media-key targets are read by name.
- Layout detection in the configurator while the helper's virtual keyboards are attached has not been
  checked on hardware (see the manual checklist).

## Testing

All automated tests run headlessly through mise tasks. `RemapEngine` has scripted, timestamped
`KeyEvent` tests; `KeyIO` and `InputDaemonCore` test the backend, report bytes, descriptor and the
daemon's safety and connection rules against fake seizers, fake daemons and test clocks; the TCA
features use `TestStore`; views are covered by snapshot tests and XCUITest flows (the configurator has
a `-UITestMode` with in-memory storage and a fake helper). What needs real hardware (seizing, virtual
keyboards, TCC, `SMAppService`, typing feel) is in the manual checklist.

- [`docs/TESTING.md`](TESTING.md): commands, UI-test mode, snapshot recording.
- [`docs/MANUAL-CHECKLIST.md`](MANUAL-CHECKLIST.md): release steps and the checks on a real Mac.
