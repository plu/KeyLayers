# Setup

KeyLayers has three parts: the app you edit your keymaps in, a **helper** that remaps your keys, and an
**input service** that reads the keyboard. macOS wants your approval for each of them, in three steps.

The status area at the bottom of the KeyLayers window always shows what's missing and offers a button for
the next step. When everything is approved, it says **Remapping active**.

## 1. Login Items

KeyLayers asks macOS to run the helper and the input service in the background. macOS holds both until
you approve them.

In KeyLayers, click **Open Login Items…** in the status area.

<Shot name="app/status-needs-approval" alt="KeyLayers' status area: the helper needs approval in System Settings, with an Open Login Items button" />

System Settings opens **Login Items & Extensions**. Under **App Background Activity**, KeyLayers is listed
once, as "2 items": the helper and the input service. Turn on its switch and enter your password.

<Shot name="system-settings/login-items-approve" alt="Login Items & Extensions with KeyLayers listed under App Background Activity, its switch off" />

If the status area then says **approve “KeyLayers” in Login Items**, the input service is still waiting:
check that the switch is on.

<Shot name="app/status-daemon-needs-approval" alt="KeyLayers' status area: Remapper waiting, approve KeyLayers in Login Items" />

## 2. Accessibility

The helper types your remapped keys, which macOS allows only with Accessibility.

When the helper starts, the status area shows **Accessibility: not allowed**. Click
**Open System Settings…** next to it.

<Shot name="app/status-permissions-missing" alt="KeyLayers' status area: Accessibility not allowed, with an Open System Settings button" />

In **Privacy & Security → Accessibility**, turn on **KeyLayersHelper**.

<Shot name="system-settings/accessibility" alt="Privacy & Security, Accessibility, with KeyLayersHelper switched on" />

## 3. Input Monitoring

The input service reads your keyboard, which needs Input Monitoring. It runs as part of macOS, not in
your login, so macOS can't ask you for this one. You add it by hand.

When the status area says **the input service needs Input Monitoring**, click **Open Input Monitoring…**.
(You can also open System Settings → Privacy & Security → Input Monitoring yourself.)

<Shot name="app/status-input-monitoring" alt="KeyLayers' status area: the input service needs Input Monitoring, with Open Input Monitoring and Show in Finder buttons" />

Click **+** below the list.

<Shot name="system-settings/input-monitoring-add" alt="Privacy & Security, Input Monitoring, with no items yet and the + button below the list" />

The file picker can't see inside apps by itself. Press **⌘⇧G** (Command-Shift-G), paste this path and
press Return:

```
/Applications/KeyLayers.app/Contents/Library/HelperTools/KeyLayersInputDaemon
```

<Shot name="system-settings/input-monitoring-goto" alt="The file picker's Go to field with the path to KeyLayersInputDaemon" />

Click **Open**, then turn on **KeyLayersInputDaemon**.

<Shot name="system-settings/input-monitoring-enabled" alt="Input Monitoring with KeyLayersInputDaemon switched on" />

The input service restarts by itself to pick up the permission. That takes up to about 10 seconds.

## Done

The status area says **Remapping active**.

<Shot name="app/status-running" alt="KeyLayers' status area: Remapping active, Accessibility allowed" />

Hold **fn** and press **H J K L**: the cursor moves. Next: [layers and keys](./layers).

If the status area shows something else, [Troubleshooting](./troubleshooting) explains each message.
