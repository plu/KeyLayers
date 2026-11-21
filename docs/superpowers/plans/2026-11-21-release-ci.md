# Release CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `workflow_dispatch` GitHub workflow that builds the notarized `KeyLayers.zip` on a hosted macOS runner and uploads it as a build artifact.

**Architecture:** The workflow only sets up the runner (Xcode, mise, fnox key) and runs the existing `mise run release` chain. The one CI-specific need, a provisioning profile on a fresh machine, is solved inside `release:archive` from an optional fnox secret.

**Tech Stack:** GitHub Actions (`xcode-27` image), mise, fnox (age), Tuist, xcodebuild.

**Spec:** `docs/superpowers/specs/2026-11-21-release-ci-design.md`

## Global Constraints

- Trigger: `workflow_dispatch` only.
- Runner: `xcode-27`; Xcode `/Applications/Xcode_27.2.app` (Tuist pins exactly 27.2).
- Repository secret: `FNOX_AGE_KEY` (the `ci` age identity, inline key content).
- fnox secret: `HELPER_PROVISIONING_PROFILE_DATA` = base64 of the helper's Developer ID `.provisionprofile`.
- Local releases without `HELPER_PROVISIONING_PROFILE_DATA` behave exactly as before.
- No README changes.

## Review Focus

- `HELPER_PROVISIONING_PROFILE_DATA` set but not a valid profile: fail with a clear error, before archiving.
- The profile in the data has a different name than `HELPER_PROVISIONING_PROFILE`: the existing check still fails with its message.
- Xcode 27.2 missing from the image: the job fails at the Xcode step, not deep in Tuist.
- A second dispatch while one runs: it queues, never cancels the running one (notarization half done).
- Release fails: no artifact is uploaded (upload only on success), the log says where.

---

### Task 1: `release:archive` installs the profile from fnox

**Files:**
- Modify: `mise/tasks/release/archive` (before the profile check, ~line 30)
- Modify: `fnox.toml` (new secret via `fnox set`)

- [ ] **Step 1:** Before the `PROFILE_ERROR` check, when `HELPER_PROVISIONING_PROFILE_DATA` is set: base64-decode it to a temp file, read `UUID` with `security cms -D` + `plutil`, fail with "HELPER_PROVISIONING_PROFILE_DATA is not a provisioning profile" if that fails, else copy to `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile`.
- [ ] **Step 2: Verify** with `HOME` pointed at a scratch dir: valid data → the existing lookup loop finds the profile by name; garbage data → the new error, exit 1; unset → no file written.
- [ ] **Step 3:** `fnox set HELPER_PROVISIONING_PROFILE_DATA "$(base64 -i <profile>)"` with a description; `fnox get` round-trips to the same bytes (compare `shasum`).
- [ ] **Step 4: Commit** `feat(release): install the helper's profile from fnox when given`.

### Task 2: Release workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Modify: `docs/MANUAL-CHECKLIST.md` (release section)

- [ ] **Step 1:** Workflow: `on: workflow_dispatch`; `concurrency: {group: release, cancel-in-progress: false}`; `permissions: contents: read`; job `runs-on: xcode-27`, `timeout-minutes: 60`. Steps: `actions/checkout` (no LFS), select Xcode 27.2 (`sudo xcode-select -s`, then `xcodebuild -version`), `jdx/mise-action`, `fnox exec -- mise run release` with `env: FNOX_AGE_KEY: ${{ secrets.FNOX_AGE_KEY }}`, `actions/upload-artifact` of `build/release/KeyLayers.zip` with `if-no-files-found: error`.
- [ ] **Step 2: Verify** with `actionlint` (via `mise x actionlint@latest --`); expect no findings.
- [ ] **Step 3:** MANUAL-CHECKLIST: one paragraph — Actions → Release → Run workflow; needs repo secret `FNOX_AGE_KEY`; the zip is the run's artifact.
- [ ] **Step 4: Commit** `ci: release workflow that builds the notarized zip on demand`.
