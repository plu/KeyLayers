# Verify your copy

KeyLayers reads every key you press, so you shouldn't have to take anyone's word for what it does. The
source is [on GitHub](https://github.com/plu/KeyLayers). This page shows how to check that the app on your
Mac was built from that source by GitHub Actions, and not on someone's laptop, including mine.

There are two checks:

1. **Signature:** Apple confirms who signed the app and that it was notarized.
2. **Build provenance:** GitHub confirms which workflow built each file, and from which commit.

## 1. Signature and notarization

In Terminal:

```sh
codesign -dv --verbose=2 /Applications/KeyLayers.app 2>&1 | grep -E 'Authority=Developer ID Application|TeamIdentifier'
spctl -a -vv /Applications/KeyLayers.app
```

The team must be **HZ7YVCSB89**, and `spctl` must say `accepted` and `source=Notarized Developer ID`.

This tells you who signed the app. It doesn't tell you which code it was built from: whoever holds the
signing key could sign anything. The next check closes that gap.

## 2. Build provenance

Every release is built by the [release workflow](https://github.com/plu/KeyLayers/blob/main/.github/workflows/release.yml)
on GitHub's runners. When the build is done, the workflow records the SHA-256 of the zip and of every
executable in the app, and signs a statement with its GitHub identity: *this file was built by this
workflow, in this run, from this commit.* That statement is a
[build provenance attestation](https://docs.github.com/en/actions/concepts/security/artifact-attestations).
A file built anywhere else, or changed afterwards, has none.

The check needs the [GitHub CLI](https://cli.github.com), signed in with `gh auth login`.

Check the input service, the part that reads your keyboard:

```sh
gh attestation verify /Applications/KeyLayers.app/Contents/Library/HelperTools/KeyLayersInputDaemon \
  --repo plu/KeyLayers --signer-workflow plu/KeyLayers/.github/workflows/release.yml
```

Check every executable in the app (the app, the helper, the input service and the updater):

```sh
cd /Applications/KeyLayers.app
find . -type f -perm +111 | while IFS= read -r file; do
  if gh attestation verify "$file" --repo plu/KeyLayers \
      --signer-workflow plu/KeyLayers/.github/workflows/release.yml >/dev/null 2>&1; then
    echo "ok      $file"
  else
    echo "FAILED  $file"
  fi
done
```

Every line must start with `ok`.

### Which commit it came from

```sh
gh attestation verify /Applications/KeyLayers.app/Contents/MacOS/KeyLayers \
  --repo plu/KeyLayers --signer-workflow plu/KeyLayers/.github/workflows/release.yml \
  --format json --jq '.[0].verificationResult.signature.certificate
    | {sourceRepositoryRef, sourceRepositoryDigest, runInvocationURI}'
```

- `sourceRepositoryRef` is the release tag, like `refs/tags/v1.2.3`.
- `sourceRepositoryDigest` is the commit. Its code is at
  `https://github.com/plu/KeyLayers/tree/<commit>`.
- `runInvocationURI` is the workflow run that built it, with its full log.

### Before you install

The same check works on the download itself:

```sh
gh attestation verify ~/Downloads/KeyLayers.zip \
  --repo plu/KeyLayers --signer-workflow plu/KeyLayers/.github/workflows/release.yml
```

Each release also lists these hashes in `SHA256SUMS` on its
[release page](https://github.com/plu/KeyLayers/releases), so you can compare files with `shasum -a 256`.

[Updates](./updates) install from the same zip, so an updated copy passes the same checks.

## What this proves, and what it doesn't

**It proves** that each file is exactly what the release workflow built from the commit shown, in the
public repository, and that nothing changed it since.

**It doesn't prove the code is harmless.** It moves the question to code you can read. The parts that see
your keys are `Sources/InputDaemonCore` (the input service, reading the keyboard), `Sources/RemapEngine`
(deciding what each key does) and `Sources/KeyIO` with `Sources/HelperFeature` (the helper, sending the
result through a virtual keyboard). [Architecture](../ARCHITECTURE) explains how they fit together. None
of KeyLayers' own code opens a network
connection; the only connection is the update check, made by [Sparkle](https://sparkle-project.org).

**It still trusts the build environment:** GitHub's runner, Apple's Xcode, the Swift packages pinned in the
repository, and the actions the workflow uses.

**It isn't a reproducible build.** Building the same commit yourself won't give byte-identical files: Xcode
builds and code signatures aren't reproducible. The attestation is how you connect the binary to the source
instead.

::: info Older releases
v0.0.1 and v0.0.2 were built by the same workflow, but before it attested its builds. For them only the
signature check works. Install the current version to use both.
:::
