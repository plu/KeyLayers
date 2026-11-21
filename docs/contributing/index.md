# Building from source

KeyLayers is a Swift 6 app built with [Tuist](https://tuist.dev) and The Composable Architecture. The source
is on [GitHub](https://github.com/plu/KeyLayers), MIT licensed.

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
3. In the developer portal, register the App IDs `<prefix>.dev.configurator` (no capabilities) and
   `<prefix>.dev.helper` with the "HID Virtual Device (development)" capability. `<prefix>.dev.inputservice`
   needs no App ID. Debug builds use `<prefix>.dev` for every identifier (App Group
   `<TEAMID>.<prefix>.dev`, so their own configuration file) and show as "KeyLayers Dev", so they never
   collide with an installed release; release builds use `<prefix>` itself.
4. Sign in to that team in Xcode (Settings, Accounts).
5. `mise run build`. It passes `-allowProvisioningUpdates`, so Xcode creates the development profile.
   After each Debug build the helper restarts and the input service replaces itself on the helper's
   next connection (a gap of about 2 s).
6. Launch the app and grant the permissions as in the [setup guide](../guide/setup.md).
7. `mise run test` runs the unit and snapshot tests.

| Variable | Needed for | Default |
| --- | --- | --- |
| `TUIST_TEAM_ID` | Remapping, signed builds, release | none (ad hoc build) |
| `TUIST_BUNDLE_ID_PREFIX` | Using your own App IDs | `com.plunien.keylayers` |
| `HELPER_PROVISIONING_PROFILE` | Release only: Developer ID profile name for the helper | none |
| `ASC_API_KEY`, `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID` | Release only: notarization | none |
| `DEVELOPER_ID_CERTIFICATE` | Release only, optional: base64 .p12 instead of a login keychain identity | none |

`fnox.toml` holds the maintainer's age-encrypted secrets, which only the author and CI can decrypt.

No Tuist account is needed. The project is connected to the [Tuist server](https://tuist.dev/plu/keylayers)
for a shared binary cache of the external packages (TCA and its dependencies); without a login Tuist simply
builds them from source. Maintainers get the cache locally with `tuist auth login`.
Everyone else uses `mise.local.toml` or plain environment variables.

## The website

This site is built with [VitePress](https://vitepress.dev) from `docs/`. Node and the package manager
[aube](https://github.com/aubepkg/aube) come from mise.

| Task | Does |
| --- | --- |
| `mise run site:dev` | Serves the site with live reload at `http://localhost:5173/KeyLayers/` |
| `mise run site:build` | Builds it into `docs/.vitepress/dist` and checks it (screenshots, base paths) |
| `mise run site:preview` | Builds and serves the build |
| `mise run site:images` | Copies the app screenshots from the snapshot test references, and the app icon from an installed KeyLayers |
| `mise run site:screenshots` | Captures the System Settings screenshots in a throwaway tart VM, guided |

`site:screenshots` needs [tart](https://tart.run). The first run prepares a base VM,
`keylayers-screenshots-base`, from `ghcr.io/cirruslabs/macos-tahoe-xcode:27`, and asks you once to allow
the guest agent to control System Events (to switch between light and dark). Each run clones the base,
installs the latest release, opens the clone in Screen Sharing and walks you through the shots; the clone
is deleted afterwards. `--only <name>` redoes one shot, `--reset-base` rebuilds the base.

A pull request that touches the site builds it; a push to `main` deploys it to GitHub Pages.

## More

- [Architecture](../ARCHITECTURE.md): how the configurator, the helper and the input service work together.
- [Testing](../TESTING.md): commands, UI-test mode, snapshot recording.
- [Releasing & manual checks](../MANUAL-CHECKLIST.md): release steps and the checks on a real Mac.
