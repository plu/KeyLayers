# Troubleshooting

The status area at the bottom of the KeyLayers window says what KeyLayers is doing. Here is what each
message means and what to do.

## Remapping active

Everything works. Nothing to do.

<Shot name="app/status-running" alt="Status: Remapping active" />

## Remapper not running

The helper is approved but isn't running, for example because you quit it from its menu. Click
**Start Helper**. It also starts at your next login.

<Shot name="app/status-not-running" alt="Status: Remapper not running, with a Start Helper button" />

## Remapper not running: the helper isn't enabled

KeyLayers hasn't asked macOS to run the helper yet, or the request was undone. Click **Enable Helper**,
then follow [Login Items](./setup#_1-login-items).

## Remapper not running: the helper needs approval in System Settings

macOS is waiting for your approval. Click **Open Login Items…** and turn on KeyLayers, as in
[Login Items](./setup#_1-login-items).

<Shot name="app/status-needs-approval" alt="Status: the helper needs approval in System Settings" />

## Remapper not running: the helper is missing from the app

The app is incomplete. Download it again and replace the copy in Applications.

## Remapper waiting: approve “KeyLayers” in Login Items

The helper runs, but the input service still waits for approval. Click **Open Login Items…** and check that
KeyLayers' switch is on.

<Shot name="app/status-daemon-needs-approval" alt="Status: Remapper waiting, approve KeyLayers in Login Items" />

## Remapper waiting for permissions

The helper doesn't have Accessibility. Click **Open System Settings…** next to Accessibility and turn on
KeyLayersHelper, as in [Accessibility](./setup#_2-accessibility). If KeyLayersHelper is on and the message
stays, turn it off and on again.

<Shot name="app/status-permissions-missing" alt="Status: Accessibility not allowed" />

## Remapper waiting: the input service needs Input Monitoring

Add the input service to Input Monitoring by hand, as in [Input Monitoring](./setup#_3-input-monitoring).
**Show in Finder** shows the file you need.

<Shot name="app/status-input-monitoring" alt="Status: the input service needs Input Monitoring" />

## Input service not connected

The helper runs but can't reach the input service. Right after setup or an update, wait about 10 seconds.
If it stays, check KeyLayers' switch in Login Items; if the status area offers **Enable Input Service**,
click it.

## Remapping paused

You (or the emergency stop) paused remapping. Click **Resume Remapping**. See
[Pause and emergency stop](./pause).

<Shot name="app/status-paused" alt="Status: Remapping paused" />

## “The configuration file is damaged and can't be read.”

KeyLayers can't read your keymaps. The helper keeps running with what it last had. Recreate your keymaps in
the app, or bring back an exported copy with **File → Import Configuration…**.

## A macOS Modifier Keys remap doesn't work

macOS' per-keyboard Modifier Keys settings don't apply while KeyLayers remaps that keyboard. Set those remaps
in your keymap instead.
