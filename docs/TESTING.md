# Testing

Every check runs from the command line through mise; nothing needs Xcode's UI.

| Command | What it runs |
| --- | --- |
| `mise run test:unit` | `UnitTests` scheme: one Swift Testing target per module |
| `mise run test:snapshot` | `SnapshotTests` scheme: helper and configurator views against the PNGs in `__Snapshots__` |
| `mise run test:ui` | `UITests` scheme: `ConfiguratorUITests`, XCUITest flows through the configurator |
| `mise run test` | all three, in that order |
| `mise run snapshot:record` | re-records every snapshot (see below) |
| `mise run lint` | SwiftLint (strict) and SwiftFormat in lint mode (`lint:swiftlint` and `lint:swiftformat` run one) |

On GitHub, every pull request and push to `main` runs `lint:swiftlint`, `lint:swiftformat` (workflow `Lint`)
and `test:unit` (workflow `Unit Tests`). The unit tests need no secrets: without `TUIST_TEAM_ID` they build
signed ad hoc.

To run one test while iterating:

```sh
mise exec -- tuist test UITests --no-selective-testing \
  --test-targets ConfiguratorUITests/ConfiguratorUITests/testRecordKey
```

## One-time VM setup for UI tests

1. Allow the developer tools to debug and control other processes:

   ```sh
   sudo DevToolsSecurity -enable
   ```

   `DevToolsSecurity -status` should then print "Developer mode is currently enabled." On the
   development VM it was already enabled.

2. Run `mise run test:ui` once. On a fresh Mac, macOS can ask to let the UI test runner
   (`ConfiguratorUITests-Runner`) control the computer (an Accessibility or Automation prompt).
   Approve it over VNC in System Settings → Privacy & Security → Accessibility (or Automation),
   then run `mise run test:ui` again. Later runs need no attention.

### Prompts actually seen on the development VM (2026-11-14, macOS 26.6, Xcode 27.1)

- **None from the UI tests.** The first `mise run test:ui`, run over SSH, launched the runner,
  connected to the app ("Setting up automation session") and ran the tests without any
  Accessibility, Automation or Developer Tools prompt.
- One unrelated prompt appeared once, caused by running `screencapture` from the SSH session (not
  by the tests): *"“com.apple.sshd-session” is requesting to bypass the system private window
  picker and directly access your screen and audio."* with the buttons **Allow** and **Open
  System Settings**. While it was on screen it covered the middle of the configurator window, and
  XCUITest's click on a key went to the dialog (`testAssignKeymapAction` failed with "No
  popover"). Once it was gone the test passed. Don't run `screencapture` over SSH while UI tests
  run; if the dialog shows up, dismiss it over VNC before running the tests.
- Because the SSH session has no Screen Recording permission, the screen recordings that XCTest
  attaches to the result bundle show only the desktop, not the app's window. Use the "App UI
  hierarchy" and "Debug description" attachments in the `.xcresult` instead
  (`xcrun xcresulttool export attachments --path <result>.xcresult --output-path <dir>`).

## UI-test mode

The UI tests launch the configurator with the argument `-UITestMode` (see
`Sources/ConfiguratorFeature/UITestDependencies.swift`). In this mode the app:

- keeps the configuration in memory, so it starts from the starter keymap and never writes the
  real App Group configuration file;
- uses a fresh in-memory `UserDefaults` suite for app storage, so preferences such as "launch
  helper at login" and the selected keyboard reset on every launch;
- fakes the helper: `UITEST_HELPER_STATE` = `running` (default) | `notRunning` |
  `needsPermissions` | `paused`; pause requests change the fake's state;
- reports the helper registration as enabled and never registers or unregisters it;
- never opens System Settings;
- draws a compact ANSI "Test Keyboard" with US English labels, whatever the VM's keyboard;
- records the key named by `UITEST_RECORDED_KEY` (`"<page>:<usage>"`, e.g. `7:14` for K) when
  "Record" is clicked.

## Snapshot recording workflow

Snapshot tests compare against the PNGs committed under `Tests/*SnapshotTests/__Snapshots__/`.

1. Change the view.
2. `mise run snapshot:record` re-records every snapshot (the run itself reports failures, which is
   expected while recording; the task ignores them).
3. Look at every changed PNG (`git status`, then open each one), light and dark, and check for
   clipping or anything unintended.
4. `mise run test:snapshot` must then pass without recording.
5. Commit the PNGs with the view change.
