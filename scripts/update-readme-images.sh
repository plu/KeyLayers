#!/usr/bin/env bash
# Copy the light README snapshot references to docs/images/.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/Tests/ConfiguratorSnapshotTests/__Snapshots__/ReadmeSnapshotTests"
mkdir -p "$root/docs/images"
cp "$src/readmeBase.light.png" "$root/docs/images/keylayers-base.png"
cp "$src/readmeMod.light.png" "$root/docs/images/keylayers-mod.png"
