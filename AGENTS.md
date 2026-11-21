# Agent guidelines

## Commits and pull requests

**Always use [Conventional Commits](https://www.conventionalcommits.org/)**, for every commit message and
every pull request title: `type(scope): summary`, e.g. `fix(helper): release held keys on sleep`.

- Types in use: `feat`, `fix`, `perf`, `refactor`, `style`, `test`, `docs`, `build`, `ci`, `chore`.
- Common scopes: `configurator`, `helper`, `daemon`, `engine`, `model`, `keyio`, `layout`, `ipc`, `build`,
  `release`; omit the scope when a change has none.
- The summary is lowercase, imperative or descriptive, without a trailing period.

Pull requests are **squash merged**, so the PR title becomes the commit message on `main`. A PR title
without a conventional prefix ends up in `git log` as is. Give the title the same type and voice as the
commits inside it, and fix it before merging if the PR's scope changed.

## Checks

Before pushing, run `mise run lint` (SwiftLint strict and SwiftFormat; `mise run format` fixes the
formatting) and `mise run test:unit`. CI runs both on every pull request; see `docs/TESTING.md`.
