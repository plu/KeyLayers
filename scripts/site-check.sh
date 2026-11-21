#!/usr/bin/env bash
# Checks the website sources and its build (docs/.vitepress/dist) for what VitePress doesn't catch:
# - every <Shot name="X"> has both docs/public/screenshots/X.light.png and X.dark.png
# - every PNG in the build is a PNG (not a Git LFS pointer from a checkout without LFS)
# - the internal plans and specs (docs/superpowers) are not published
# - no page references a screenshot without the site's base path (/KeyLayers/)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
docs="$root/docs"
dist="$docs/.vitepress/dist"
errors=0
fail() { echo "error: $*" >&2; errors=$((errors + 1)); }

while IFS= read -r name; do
  for appearance in light dark; do
    file="$docs/public/screenshots/$name.$appearance.png"
    [[ -f "$file" ]] || fail "<Shot name=\"$name\"> has no ${file#"$root"/}"
  done
done < <(grep -rhoE '<Shot[^>]*name="[^"]+"' "$docs" --include='*.md' --exclude-dir=superpowers --exclude-dir=node_modules \
  | sed -E 's/.*name="([^"]+)".*/\1/' | sort -u)

if [[ -d "$dist" ]]; then
  png_signature="89504e470d0a1a0a"
  while IFS= read -r -d '' png; do
    [[ "$(head -c 8 "$png" | xxd -p)" == "$png_signature" ]] ||
      fail "${png#"$root"/} is not a PNG (a Git LFS pointer? run git lfs pull)"
  done < <(find "$dist" -name '*.png' -print0)

  published="$(find "$dist" -path '*superpowers*' | head -1)"
  [[ -z "$published" ]] || fail "internal docs were published: ${published#"$root"/}"

  unprefixed="$(grep -rlE '(src|href)="/screenshots/|url\((&quot;|")?/screenshots/' "$dist" --include='*.html' || true)"
  [[ -z "$unprefixed" ]] || fail "screenshots referenced without the base path in: ${unprefixed//$root\//}"

  # Every screenshot the built pages reference, however it got there (<Shot> in a page or a component,
  # a FeatureCard's background), must be in the build.
  while IFS= read -r path; do
    [[ -f "$dist/${path#/KeyLayers/}" ]] || fail "a page references $path, which is not in the build"
  done < <(grep -rhoE '/KeyLayers/screenshots/[A-Za-z0-9/_.-]+\.png' "$dist" --include='*.html' | sort -u)
else
  fail "no build at ${dist#"$root"/} (run mise run site:build)"
fi

if ((errors > 0)); then
  echo "site check failed: $errors error(s)" >&2
  exit 1
fi
echo "site check passed"
