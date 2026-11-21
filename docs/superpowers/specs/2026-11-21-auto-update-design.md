# Auto update (Sparkle) — design

## Why

KeyLayers will ship as notarized binaries on GitHub Releases (the repository is going public).
Users should get new versions without watching the repository: the app checks for updates, offers
them, and installs them, and every part of KeyLayers (configurator, helper, root daemon) ends up on
the new version.

## Goals

- The configurator checks GitHub for a newer release automatically (Sparkle's default schedule,
  once a day while it runs) and on demand ("Check for Updates…" in the app menu).
- Installing an update leaves no old code running: the configurator relaunches (Sparkle), the
  helper restarts itself, the daemon replaces itself (already does).
- Pushing a version tag (`v1.2.3`) builds, notarizes and publishes a GitHub Release with the zip
  and the appcast. The version comes from the tag; nothing is committed back.

## Non-goals

- Updating from the helper or its menu bar menu (approach B/C below, not taken).
- Delta updates, beta/pre-release channels, a Settings UI for update preferences (Sparkle's own
  prompt and menu item are the UI).
- Hosting outside GitHub. A private repository can't serve updates (assets need a token); the
  repository is assumed public.

## Anti-goals

- A helper left running old code after an update, or a helper that restarts while the user quit it
  on purpose.
- An update that loses Accessibility or Input Monitoring grants (would happen if signing identity
  or bundle IDs changed; they must not).
- Local `mise run release` breaking or needing new secrets for a plain test build.

## Approaches

- **A. Sparkle in the configurator only.** Picked. Sparkle's standard setup in the app it is built
  for; least code. Cost: someone who never opens the configurator is not offered updates; C can be
  added later without undoing A.
- B. Sparkle in the helper, updating the outer app. Always running, but the helper replaces the
  bundle it runs from and must relaunch itself and the configurator: unusual, the riskiest part.
- C. Helper probes and announces, configurator installs. Sparkle in two processes; more wiring.

## Design

### Versioning

- `Project.swift`: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the base settings, from
  `TUIST_MARKETING_VERSION` / `TUIST_BUILD_NUMBER` (defaults `0.0.0` and `1` for dev builds).
- The Configurator, KeyLayersHelper and KeyLayersInputDaemon Info.plists set
  `CFBundleShortVersionString = $(MARKETING_VERSION)` and `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`
  (Tuist's defaults hard-code "1.0" / "1").
- Release workflow: marketing version = tag without the `v`; build number = `github.run_number` of the
  release workflow (monotonic, which is what Sparkle compares). `release:archive` reads both from the
  environment through the `TUIST_` variables.

### Sparkle in the configurator

- Dependency: `https://github.com/sparkle-project/Sparkle` from `2.10.1` in `Tuist/Package.swift`,
  linked to the Configurator target only (dynamic framework, as Sparkle ships it).
- Info.plist: `SUFeedURL = $(SPARKLE_FEED_URL)`, `SUPublicEDKey = $(SPARKLE_PUBLIC_KEY)`,
  `SUEnableAutomaticChecks = true` (no "check automatically?" prompt on second launch).
  `Project.swift` fills both settings from `TUIST_SPARKLE_FEED_URL` / `TUIST_SPARKLE_PUBLIC_KEY`,
  empty by default. Nothing about the feed is committed as a constant.
- The updater starts only when both values are non-empty, and only tag builds set them: the tag
  workflow passes the feed URL built from `github.repository`
  (`https://github.com/<repo>/releases/latest/download/appcast.xml`) and the public key from fnox
  (`SPARKLE_PUBLIC_KEY`). So dev builds, local `mise run release` builds and `workflow_dispatch`
  artifacts never update themselves (they would be offered the latest release and overwrite the
  build under test), and a fork never checks plu's feed (its own tag workflow points at its own
  repository and needs its own key). *Builder's call, recorded here.*
- Without the updater the "Check for Updates…" item is hidden.
- `SPUStandardUpdaterController` started at launch; a "Check for Updates…" item after "About
  KeyLayers" in the app menu (`CommandGroup(after: .appInfo)`), disabled while a check runs
  (`canCheckForUpdates`).

### Helper restarts itself after an update

- The helper records its executable's identity at launch (`ExecutableIdentity`, moved from
  `InputDaemonCore` to a module both can use) and compares it on its existing 2 s poll.
- Changed → it shuts down exactly like Quit (releases held keys, hands keyboards back) but exits
  with a non-zero status, so launchd (`KeepAlive.SuccessfulExit = false`) starts the new binary.
  A user Quit still exits 0 and stays stopped.
- The new helper connects to the daemon, which sees its own binary changed and exits; launchd
  starts the new daemon on the helper's next attempt (existing behaviour).
- Also covers a manual update (new app dragged over the old one).

### Release workflow

- `.github/workflows/release.yml` additionally triggers on `push: tags: ['v*']`; `workflow_dispatch`
  stays (artifact only, no GitHub Release; version `0.0.0-dev`, build number = run number).
- After `mise run release`, a new task `release:appcast` writes `build/release/appcast.xml`: one
  item for this version, enclosure URL
  `https://github.com/plu/KeyLayers/releases/download/<tag>/KeyLayers.zip`, length, EdDSA signature
  from Sparkle's `sign_update` (from the Sparkle SPM artifact's `bin/`), `sparkle:version` = build
  number, `sparkle:shortVersionString` = marketing version, `sparkle:minimumSystemVersion` = 26.0,
  release notes link to the GitHub Release page.
- On a tag: `gh release create <tag> KeyLayers.zip appcast.xml --generate-notes` (permissions:
  `contents: write`). The feed URL's `latest/download` then serves this appcast.
- New fnox secrets `SPARKLE_ED_PRIVATE_KEY` and `SPARKLE_PUBLIC_KEY` (from Sparkle's
  `generate_keys`). `release:appcast` is not part of the local `mise run release` chain, so a local
  release needs neither.
- If the private key is lost, no installed copy can be updated again: key creation and backup is a
  manual step before the first tag (see "Key").

### Key

- A KeyLayers-only Ed25519 key pair, created with Sparkle 2.10.1's `generate_keys --account KeyLayers`
  (not shared with other Sparkle apps). Public key: `zuh9sXp3zdrSHs7Hc+gxeRhfqkjCyOAhVjWHSyoLnAs=`.
- Copies of the private key: the author's login keychain (account `KeyLayers`) and fnox
  (`SPARKLE_ED_PRIVATE_KEY`, age-encrypted for the author and CI). The fnox copy is only as safe as
  the author's age key; the author keeps a backup of that.
- `release:appcast` signs with `sign_update --ed-key-file` from the fnox value, never the keychain
  (CI has none).

## Left to the builder

- Where exactly `ExecutableIdentity` moves (new tiny module vs. an existing shared one).
- Exact non-zero exit status for the helper's self-restart.
- Appcast template details beyond the fields listed.
