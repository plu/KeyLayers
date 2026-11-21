import ProjectDescription

let tuist = Tuist(
  // Connects the project to the Tuist server (https://tuist.dev/plu/keylayers): the shared binary
  // cache, and build and test insights. Without authentication those simply aren't used.
  fullHandle: "plu/keylayers",
  project: .tuist(
    compatibleXcodeVersions: .exact("27.2"),
    // Without this a handle makes every command, `tuist generate` included, require a Tuist login.
    // A fresh clone has to build without an account; an authenticated run (`tuist auth login`
    // locally, TUIST_TOKEN in CI) still gets the cache.
    generationOptions: .options(optionalAuthentication: true),
    // Only the external packages (TCA and its dependencies) come from the cache; KeyLayers' own
    // modules always build from source. Set here rather than on the command line, so the
    // `tuist cache warm` that fills the cache and the `tuist generate`/`tuist test` that read it
    // agree on which targets are binaries.
    cacheOptions: .options(profiles: .profiles(default: .onlyExternal))
  )
)
