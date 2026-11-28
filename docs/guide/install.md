# Install

KeyLayers needs macOS 26 (Tahoe) or later.

::: warning Installing is only half of it
After you open KeyLayers, macOS needs three approvals before it can remap anything: Login Items,
Accessibility, and Input Monitoring, which you add by hand for `KeyLayersInputDaemon`. The
[setup guide](./setup) shows every step.
:::

1. Download [KeyLayers.zip](https://github.com/plu/KeyLayers/releases/latest/download/KeyLayers.zip) from
   the latest release. Safari unzips it for you; otherwise double-click the zip.
2. Move **KeyLayers** into your **Applications** folder. It has to be there: one of the setup steps points
   System Settings at a file inside the app, at `/Applications/KeyLayers.app`.
3. Open KeyLayers. Because it comes from the internet, macOS asks first. Click **Open**.

<Shot name="system-settings/gatekeeper-open" alt="macOS asking whether to open KeyLayers, an app downloaded from the internet, with Cancel and Open" />

KeyLayers opens its window. It can't remap anything yet: macOS needs three approvals first.
[Set it up →](./setup)
