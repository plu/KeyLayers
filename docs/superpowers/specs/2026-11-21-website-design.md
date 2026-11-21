# KeyLayers Website — Design

## Intent

KeyLayers now ships as notarized GitHub Releases that update themselves (v0.0.1, v0.0.2). An end user
downloads `KeyLayers.zip` from the latest release and then has to get through three macOS approvals, one
of which (Input Monitoring for the root input service) macOS can't prompt for and that needs a trip into a
hidden folder of the app bundle. Today the only guidance is the README and the status strip in the app.

The site gives end users one place that explains what KeyLayers is and why it exists, gets them from
download to working layers with a screenshot for every step, and documents everyday use. A smaller
section serves contributors. The README shrinks to a pointer.

Why it exists, in the author's words: KeyLayers is inspired by the UHK (Ultimate Hacking Keyboard). Using
the MacBook on the road without the UHK, the author got lost without their layers, so they built KeyLayers
to bring layers to any Mac keyboard, the built-in one included.

## Goals

- Home page: what KeyLayers does, the personal story (UHK, MacBook on the road), the starter layer with the
  keyboard images, a prominent download link to the latest release's zip.
- Setup guide that a non-developer can follow from download to working remapping, with a screenshot of
  every step, including the Gatekeeper first-open dialog, Login Items, Accessibility and the manual Input
  Monitoring "+" step.
- Usage docs moved out of the README: layers and key editing, macros, pause and emergency stop, updates,
  troubleshooting by status line.
- Contributors section: building from source, architecture, testing, releasing.
- Screenshots reproducible: app screenshots from the snapshot tests, System Settings screenshots from a
  scripted capture in a throwaway VM.
- README slimmed down, linking to the site; the "HID Virtual Device entitlement pending" note removed
  (the entitlement is approved and releases are published).

## Non-goals

- No custom domain configuration in this repo: `plu.github.io` already serves `johannes.plunien.com`, so
  this repo's Pages site appears at `https://johannes.plunien.com/KeyLayers/`.
- No blog, changelog page, analytics, search service, comments or i18n. (VitePress' built-in local search
  is fine.)
- No redesign of the app's own onboarding; this is documentation only.
- `docs/superpowers/` (plans and specs) and `AGENTS.md` are not published.

## Anti-goals

- Two copies of the developer docs that drift apart.
- Screenshots that can only be recreated by hand.
- A README that still duplicates the site after the move.
- Screenshots that silently show a state other than a fresh install (KeyLayers already listed in Login
  Items or Privacy & Security).

## Constraints

- Tools come from mise (pinned in `mise.toml`): `node`, `aube`. Node packages are installed with aube
  (`aube-lock.yaml` committed; CI uses `aube install --frozen-lockfile` or `aube ci`).
- Every entry point is a mise task (one executable file per task under `mise/tasks/`, the repo's pattern).
- VitePress 1.x (latest stable 1.6.4), `base: '/KeyLayers/'`.
- Deployed by a GitHub Actions workflow (`actions/upload-pages-artifact` + `actions/deploy-pages`), not a
  `gh-pages` branch. The repo's Pages source must be set to "GitHub Actions" (one-time setting).
- PNGs are in Git LFS (`.gitattributes`); `docs/images/*.png` are excluded so the README renders anywhere.
- Conventional commits and PR titles (AGENTS.md); `mise run lint` and `mise run test:unit` before pushing.
- macOS Tahoe (26) is the minimum system; screenshots come from Tahoe.

## Approaches

**Where the site lives**

- **A. `docs/` is the VitePress source (chosen).** `ARCHITECTURE.md`, `TESTING.md` and
  `MANUAL-CHECKLIST.md` become contributor pages in place; new end-user pages go under `docs/guide/`;
  `docs/superpowers/**` is excluded with `srcExclude`. `package.json` at the repo root. One copy of every
  doc, and existing paths (AGENTS.md links `docs/TESTING.md`) keep working.
- B. Separate `site/` folder with its own pages and copies of the developer docs. Rejected: two copies drift.

**Capturing System Settings screenshots**

- **A. Guided capture task in a throwaway VM (chosen).** A mise task clones a prepared base VM (made once
  from the vanilla Tahoe image), installs the latest release in the clone, walks the user through a shot list and captures only the System Settings
  (or dialog) window from inside the VM, then deletes the clone.
- B. Manual screenshots named from a list, a task only validates and copies. Rejected: every macOS update
  means redoing them by hand.

## Design

### Layout

```
package.json                 # vitepress devDependency, scripts docs:dev/build/preview
aube-lock.yaml
docs/
├─ .vitepress/config.mts     # base '/KeyLayers/', srcExclude ['superpowers/**'], nav, sidebar, local search
├─ index.md                  # home (VitePress home layout + story section)
├─ guide/
│  ├─ install.md             # download, unzip, move to Applications, first open (Gatekeeper)
│  ├─ setup.md               # Login Items → Accessibility → Input Monitoring, screenshot per step
│  ├─ layers.md              # starter keymap, layers, editing keys (from README "Editing")
│  ├─ macros.md              # from README "Macros"
│  ├─ pause.md               # pause button, emergency combo ⌃⌥⌘⎋, fn caveats
│  ├─ updates.md             # Check for Updates…, automatic checks, what restarts
│  └─ troubleshooting.md     # one entry per status headline: meaning, fix, screenshot
├─ contributing/
│  ├─ index.md               # building from source (README "Developing")
│  └─ (ARCHITECTURE.md, TESTING.md, MANUAL-CHECKLIST.md linked from the sidebar where they are)
├─ public/screenshots/
│  ├─ app/                   # copied from snapshot references, light + dark
│  └─ system-settings/       # captured in the VM, light + dark
└─ images/                   # unchanged, README keyboard images (not LFS)
```

The three existing docs stay at `docs/*.md` so their paths don't change; the sidebar lists them under
"Contributing". Their relative links to repo files outside `docs/` (source paths, `AGENTS.md`) are rewritten
to absolute GitHub URLs on `main` where VitePress would otherwise report dead links.

### Home page

VitePress `layout: home`: hero with name, tagline ("Layers for every Mac keyboard"), actions "Download"
(→ `https://github.com/plu/KeyLayers/releases/latest/download/KeyLayers.zip`) and "Set it up" (→ install
guide). Below: a short first-person story section (UHK layers; on the road with only the MacBook, lost
without them; so KeyLayers), the starter layer with the two keyboard images, three feature blurbs (layers on
any keyboard, macros, updates itself). The author reviews the story text before merge.

### Screenshots

Light and dark variants of every screenshot; pages show the matching one via VitePress' `.dark`
class (`<img class="light-only">` / `dark-only` with a few lines of CSS in a theme extension).

**App screenshots** — `mise run site:images`: re-records the needed snapshot tests (same approach as
`readme:images`) and copies light and dark references into `docs/public/screenshots/app/`: the app window,
settings, the starter keyboard layers (base and Mod; the README only has light variants, the site gets
light and dark), and every status strip state (`status_notRunning`, `status_needsApproval`,
`status_permissionsMissing`, `status_inputServiceNeedsInputMonitoring`, `status_running`, `status_paused`).
Snapshot names that don't exist yet (if a status state needed by the guide is missing) are added as
snapshot tests.

**System Settings screenshots** — `mise run site:screenshots`:

0. **Base VM, once.** If `keylayers-screenshots-base` doesn't exist, the task clones it from the vanilla
   image `ghcr.io/cirruslabs/macos-tahoe-xcode:27` (already pulled; never had KeyLayers, so no TCC or
   Login Items reset is needed), sets a larger display (e.g. 1920×1200), boots it, and asks the user to
   grant Screen Recording to the capture process inside it (System Settings → Privacy & Security → Screen
   & System Audio Recording), then shuts it down. The base is kept between runs; it never gets KeyLayers.
   `claude-dev` is not used. A `--reset-base` flag deletes and recreates it (e.g. after a macOS update of
   the image).
1. `tart clone keylayers-screenshots-base keylayers-screenshots` (the clone is deleted on exit, also on
   failure, via trap; the base is never modified).
2. Start it, wait for the guest agent, download the latest release's zip inside the VM, add the
   `com.apple.quarantine` attribute a browser download would set (so the Gatekeeper first-open dialog
   appears), and unzip it to `/Applications`.
3. For each shot in a list (name, instruction), print the instruction ("Open KeyLayers and click Open in
   the dialog, then press Enter"), wait for Enter on the host, capture inside the VM with `screencapture`
   restricted to the frontmost window (`-l <window id>`, `-o` for no shadow), and copy the PNG back to
   `docs/public/screenshots/system-settings/<name>.<light|dark>.png`. Each shot is captured in light and
   dark by switching the appearance in the VM between the two captures.
4. If a capture comes back empty or desktop-only (Screen Recording missing in the base), the task stops and
   says to rerun with `--reset-base`.

Shot list (names are final, pages reference them):

| Name | What it shows |
| --- | --- |
| `gatekeeper-open` | First-open dialog for the downloaded app |
| `login-items-approve` | Login Items & Extensions with KeyLayers' two background items awaiting approval |
| `accessibility` | Privacy & Security → Accessibility with KeyLayersHelper, switch on |
| `input-monitoring-add` | Input Monitoring with the "+" button |
| `input-monitoring-goto` | The file picker with ⌘⇧G and the daemon path pasted |
| `input-monitoring-enabled` | Input Monitoring with KeyLayersInputDaemon, switch on |

### Setup guide content

Each step: what to do in one or two sentences, the screenshot, and how KeyLayers' status strip confirms it
(status screenshot). The Input Monitoring step gives the exact path to paste after ⌘⇧G
(`/Applications/KeyLayers.app/Contents/Library/HelperTools/KeyLayersInputDaemon`) and mentions the app's
"Show in Finder" button, and that the service restarts on its own within about 10 seconds.

### mise tasks

| Task | Does |
| --- | --- |
| `site:dev` | `aube install`, then the VitePress dev server |
| `site:build` | `aube install --frozen-lockfile`, `vitepress build docs` (fails on dead links) |
| `site:preview` | builds, then serves the build |
| `site:images` | app screenshots from snapshot tests (above) |
| `site:screenshots` | System Settings screenshots from the VM (above) |

`mise.toml` gains `node` and `aube`.

### Deployment

`.github/workflows/site.yml`: on push to `main` (paths `docs/**`, `package.json`, `aube-lock.yaml`,
`mise.toml`, the workflow) and `workflow_dispatch`; on pull requests that touch the same paths it runs
`site:build` only (catches dead links), no deploy. Checkout with `lfs: true` (screenshots are LFS),
`jdx/mise-action`, `mise run site:build`, upload `docs/.vitepress/dist`, deploy with
`actions/deploy-pages`. Permissions `pages: write`, `id-token: write`; concurrency group `pages`. Runs on
`ubuntu-latest` (no Xcode needed); mise installs only `node` and `aube` there (`mise install node aube`
or `install_args`), not the Xcode tools `mise.toml` also pins. LFS fetches only `docs/public/**` and
`docs/images/**` (the latter are plain files anyway), not the snapshot references. Pages source set to "GitHub Actions" once with
`gh api -X POST repos/plu/KeyLayers/pages -f build_type=workflow`.

### README

Slimmed to: one-paragraph description, link to the site, download link, the two keyboard images, the
emergency combo, and one line for contributors pointing to the site's Contributing section. The entitlement
pending note is removed. `mise run readme:images` stays (it feeds `docs/images/`).
`docs/TESTING.md` mentions the site build in CI.

### Repository settings

Set the repo's homepage to `https://johannes.plunien.com/KeyLayers/` (`gh repo edit --homepage`).

## Calls made without the author (check these)

- `docs/` is the VitePress source in place; developer docs stay at their paths.
- Light and dark variants of every screenshot.
- Site deploys on push to `main`; pull requests only build it (dead-link check).
- Setup page includes the Gatekeeper first-open dialog.
- Repo homepage set to the site URL.
- `site:screenshots --reset-base` to rebuild the base VM.

## Left to the builder

- Exact page wording (the home story gets the author's review).
- VitePress theme details beyond the light/dark image switch; default theme otherwise.
- How the capture task finds the frontmost window's ID inside the VM.
- Which existing doc links need rewriting for the dead-link check.
