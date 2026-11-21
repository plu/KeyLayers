# Manual checklist (real Mac)

Automated tests cannot cover real keyboards, TCC prompts, sleep or login. Run this on a physical
Mac with the notarized build (`build/release/KeyLayers.zip`, see "Release" below). Mark each item.

## Release

One-time setup: install a "Developer ID Application" certificate in the login keychain, and store the
secrets declared in `fnox.toml` (age-encrypted, committed): `fnox set TUIST_TEAM_ID`, and an App Store
Connect API key for notarization with `base64 -i AuthKey_<KEY_ID>.p8 | fnox set ASC_API_KEY`,
`fnox set ASC_API_KEY_ID` and `fnox set ASC_API_ISSUER_ID`. `TUIST_BUNDLE_ID_PREFIX` defaults to
`com.plunien.keylayers`; set it (e.g. in `mise.local.toml`) to override, and `<prefix>` below means its value.
The helper needs a Developer ID provisioning profile for `<prefix>.helper` (it carries the restricted
`com.apple.developer.hid.virtual.device` entitlement, which requires Apple's approval): create it in the developer
portal, install it, and `fnox set HELPER_PROVISIONING_PROFILE` with its name. `release:archive` fails before
archiving without it. It also verifies the app, helper and `KeyLayersInputDaemon` are Developer ID signed with
hardened runtime and that the helper carries the entitlement.
Then `mise run release` (with `fnox activate` in your shell, or `fnox exec -- mise run release`), and check `spctl -a -vvv -t exec build/release/export/KeyLayers.app`
prints `accepted` and `source=Notarized Developer ID`.
`release:notarize` and `release:package` re-run the earlier steps through their mise `depends` chain, so each
run archives, notarizes and packages from scratch.

On GitHub: Actions → Release → Run workflow runs the same `mise run release` on a hosted runner (`xcode-27`)
and keeps `KeyLayers.zip` as the run's artifact. It needs the repository secret `FNOX_AGE_KEY` (the private
key of the `ci` age recipient in `fnox.toml`). A fresh runner has no provisioning profile, so the helper's profile
is also stored in fnox: `fnox set HELPER_PROVISIONING_PROFILE_DATA "$(base64 -i <file>.provisionprofile)"`,
which `release:archive` installs when set. After regenerating the profile in the portal, update both.

## Core behaviour

1. [ ] Install (unzip, move to /Applications) and launch. Complete "Permissions setup" below.
2. [ ] With the starter keymap, fn+HJKL give arrows; arrows auto-repeat when held.
3. [ ] fn+Shift+J selects text (Shift carries through to the output).
4. [ ] Double-tapping a Layer key locks the layer, the HUD shows, and the menu bar shows the layer.
5. [ ] The emergency combo (Left Control + Left Option + Left Command + Escape) pauses remapping.
6. [ ] Editing a key in the configurator applies immediately, without a restart.
7. [ ] Logging out and in starts the helper.
8. [ ] ISO/JIS drawing on a matching keyboard, if available.

## Permissions setup

KeyLayers needs three approvals, none of which is requested by a system prompt for the daemon.

- [ ] Login Items: System Settings > General > Login Items & Extensions lists KeyLayers twice, for the helper
  and for the input service (the root daemon). Approve both (the configurator offers to register them).
- [ ] Accessibility: add/enable KeyLayersHelper (needed to post the remapped events).
- [ ] Input Monitoring for the daemon: System Settings > Privacy & Security > Input Monitoring > "+", then pick
  `KeyLayers.app/Contents/Library/HelperTools/KeyLayersInputDaemon` (inside the app bundle; press Cmd+Shift+G in the
  file picker and paste the path). The daemon does not get a prompt, so it must be added by hand.
- [ ] After adding it, the input service restarts on its own within about 10 s (it exits on a not-permitted
  seize and the helper's reconnect relaunches it); the configurator's input daemon state turns to running. No
  logout is needed.

## Input daemon and virtual keyboards

Record what is observed where marked "Result:".

1. [ ] Daemon approval flow: first launch shows the input service as not approved, approving it in Login Items
   and adding Input Monitoring (see "Permissions setup") ends with remapping active.
2. [ ] Caps Lock with a macOS Modifier Keys remap (System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys,
   Caps Lock set to another key, e.g. Escape or No Action): the keymap's Caps Lock mapping still works, and the
   configurator shows its note about Modifier Keys settings.
3. [ ] Password fields: remapping keeps working in a password field and `sudo` in Terminal, and again after leaving
   it (secure input doesn't stop remapping).
4. [ ] Hot-plugging an external keyboard: plugged in while running it is remapped without restarting; unplugging
   it leaves the built-in keyboard working.
5. [ ] `kill -9 $(pgrep KeyLayersHelper)` while holding a key: the key is released and the keyboard is usable
   again within 2 s (macOS gets the physical keyboard back, no stuck key).
6. [ ] Emergency combo (Left Control + Left Option + Left Command + Escape) pauses remapping; keys behave
   normally afterwards and after resuming.
7. [ ] Top row / fn / media keys (brightness, volume, play/pause, Globe/fn): record behaviour. Result: media keys
   verified 2026-11-15 (see "Media keys and self-update" below); fn tap / Globe behaviour not yet recorded.
   - [ ] fn tap and Globe shortcuts (Globe+E, Globe+F, Globe+arrow tiling) with fn as the Mod key: they don't
     reach macOS (expected); record what is observed. Result: ________
8. [ ] Caps Lock LED. Result: ________ The LED is not forwarded: macOS sends the Caps Lock LED output report to the
   virtual keyboard, and KeyLayers doesn't pass it on to the seized physical keyboard, so the physical LED stays off
   even while Caps Lock is on. Forwarding it would need output reports to the physical keyboard through the daemon.
9. [x] ISO keyboard: the keys land where the configurator draws them (top-left `§`/`±` key = non-US backslash,
   key next to left Shift = grave/`<`). Verified on the built-in German ISO keyboard 2026-11-15.
   - [ ] External Apple ISO keyboard: same check.
   - [ ] JIS keyboard: keys land where the configurator draws them.
10. [ ] Mixed ISO + ANSI keyboards attached at once: each works, remapping applies to both.
11. [ ] The configurator's note about Modifier Keys settings shows and is accurate.
12. [ ] The configurator's keyboard drawing still detects the right layout (ANSI/ISO/JIS) while the helper's virtual
   keyboards are attached (they must not confuse layout detection). Result: ________ If wrong, record it as an
   open item.
13. [ ] After sleep and wake, remapping still works (the daemon reconnects the keyboards).
14. [ ] Output modifier flags: fn+Shift+J, Cmd held with a remapped arrow (Cmd+Left Arrow moves to line start) and
   Option held with a remapped arrow (word jump) all carry the held modifiers.
15. [ ] Quitting the helper from its menu leaves the keyboard fully normal (physical keys, Caps Lock) and the helper
   stays quit while the configurator is open (wait 10 s); "Start Helper" starts it again.

## Media keys and self-update

Verified on the built-in keyboard 2026-11-15 with the starter keymap (fn holds Mod); the user ran their manual
tests and "everything works as expected".

- [x] All twelve media keys on fn+F1–F12 work (brightness, Mission Control, Spotlight, Dictation, Do Not Disturb,
  previous/play-pause/next, mute, volume down/up).
- [x] Normal typing and password fields work with the report-ID keyboard reports (report 1).
- [x] Do Not Disturb works via Generic Desktop 0x9B (system control, report 3).
- [x] After a rebuild the input daemon replaces itself without sudo: on the helper's next connection it logs
  "executable changed on disk; exiting…" and launchd starts the new version.
- [ ] Media keys on an external ISO keyboard and a JIS keyboard: not verified.

## Security

16. [ ] A process other than the signed KeyLayersHelper cannot receive key events from the input daemon: its connect
   attempt is rejected (the daemon pins the helper's signing identity and team). Not practical to test manually
   without building a differently signed client; verify by code review of the daemon's connection check.

## Permissions and helper runtime

17. [ ] The configurator shows which permission is missing (Accessibility, input daemon / Input Monitoring).
18. [ ] Granting a permission in System Settings is noticed without restarting the helper. Revoking Accessibility
   while remapping stops remapping within about 2 s and releases every held key; the menu shows the waiting
   state and the configurator shows the missing permission. Granting it again restarts remapping.
19. [ ] Turning off "Launch the helper at login" also stops the running helper (it disappears from the menu bar
   and Activity Monitor) and unregisters the input service (gone from Login Items). Turning it on starts the
   helper again and registers the input service, which may need approval in Login Items again.

## Configurator and helper UI

20. [ ] Key recorder: click Record and press one key; it records the first key pressed: letters, arrows, F-keys
    and modifier keys alike (Shift, Control, Option, Command, Fn, Caps Lock; left and right are told apart).
    A modifier pressed first is recorded as that modifier key, so Shift+A records Left Shift, not A. Modifiers
    for the output are chosen with the modifier toggles, not recorded. A running helper is paused while
    recording, so Caps Lock records as Caps Lock.
21. [ ] Menu bar label shows the active layer/keymap and updates on layer change and keymap switch; the HUD
    appears on layer lock and disappears afterwards.
22. [ ] Double-tap timeout (default 250 ms) feels right: a deliberate double tap locks the layer, a normal
    tap-then-type does not. Try changing the timeout and check the new value applies.
