# Release CI

## Intent

Build the notarized release (`KeyLayers.zip`) on GitHub-hosted macOS runners instead of the
maintainer's Mac. First step: a manually dispatched workflow that leaves the zip as a downloadable
build artifact. Later it will run on tag pushes and may publish a GitHub Release; neither is part
of this change.

## Goals, non-goals

- Goal: `workflow_dispatch` runs archive → notarize → package and uploads `KeyLayers.zip`.
- Goal: CI runs the same `mise run release` chain as a local release, nothing CI-only beyond setup.
- Non-goal: tag triggers, GitHub Releases, version bumps, README changes.
- Anti-goal: local releases behaving differently than today.

## Approaches

1. **Thin workflow over the existing mise tasks** (picked). `release:archive` already imports the
   Developer ID certificate into a throwaway keychain, and `fnox.toml` already encrypts every
   secret for the `ci` age recipient.
2. Workflow-level signing setup with marketplace actions (certificate import, profile install).
   Rejected: duplicates the task's keychain handling and makes CI diverge from local releases.

## Design

- `.github/workflows/release.yml`: `workflow_dispatch` only, `runs-on: xcode-27` (the GitHub image
  with Xcode 27.2; `Tuist.swift` pins exactly 27.2 and the image defaults to 27.1, so the job selects
  `/Applications/Xcode_27.2.app`). Steps: checkout (no LFS), `jdx/mise-action`,
  `fnox exec -- mise run release` with `FNOX_AGE_KEY` from the repository secret of the same name,
  upload `build/release/KeyLayers.zip`. `concurrency: release`, never cancelled; 60 minute timeout.
- New fnox secret `HELPER_PROVISIONING_PROFILE_DATA`: base64 of the helper's Developer ID
  `.provisionprofile`. When set, `release:archive` installs it into
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile` before its
  existing profile check. Unset (the local default) changes nothing.
- `docs/MANUAL-CHECKLIST.md` release section mentions the workflow and the new secret.

## Left to the builder

Action versions, artifact name and retention.
