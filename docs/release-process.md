# Release process, versioning, and changelog policy

This document defines how specticus is versioned, how the changelog is
maintained, how releases are cut, and how maintenance and backports are
handled. It supports Path A Phase 0 readiness and feeds later distribution work
(binary releases, packaging) without requiring those artifacts on day one.

Release authority rests with the **original creator** (and any collaborator
explicitly delegated for a given release). There is no community release train
or shared ownership of the release checklist unless that duty is assigned.

## Goals

- Users can tell **what changed** between versions.
- Tags, GitHub Releases, the CLI `--version` string, and the changelog stay
  **consistent**.
- Cutting a release is **boring and repeatable**.
- Expectations for **pre-1.0** and for **backports** are explicit and modest.

## Versioning (Semantic Versioning)

specticus follows [Semantic Versioning 2.0.0](https://semver.org/) with the
public surface defined as:

- The **CLI** (commands, flags, and documented behavior users rely on)
- Documented **project layout and config** contracts (for example
  `.specticus/config.yml`, `ids.json` semantics, and documented ID syntax)
- Behavior described as stable in user-facing docs (README and `docs/`)

Internal code structure, private helpers, and undocumented flags may change
without a version bump when they do not affect that surface.

### Pre-1.0 (`0.y.z`)

While the major version is **0**:

| Component | Meaning for specticus |
|-----------|------------------------|
| **MAJOR** (`0`) | Pre-stable public product. **1.0.0** is declared when the original creator considers the core CLI and ID workflow stable enough for a compatibility promise. |
| **MINOR** (`y`) | New features, notable behavior changes, or **breaking** changes to the public surface. Prefer calling out breaks clearly in the changelog. |
| **PATCH** (`z`) | Backward-compatible bug fixes, docs-only releases that still warrant a tag, and small safe corrections. |

Breaking changes **before 1.0.0** are allowed in minor bumps. After **1.0.0**,
breaking changes require a major bump.

### Post-1.0 (when declared)

After 1.0.0, apply SemVer strictly:

- **MAJOR** — incompatible CLI, config, or documented contract changes
- **MINOR** — backward-compatible features
- **PATCH** — backward-compatible fixes

### Version string sources of truth

For any released version `X.Y.Z`:

1. **Git tag:** `vX.Y.Z` (leading `v`, no other suffix unless pre-release)
2. **CLI version:** `Specticus.configuration.version` in
   `Sources/specticus/specticus.swift` (shown by `specticus --version`)
3. **Changelog:** a matching section in [`CHANGELOG.md`](../CHANGELOG.md)
4. **GitHub Release:** named/tagged `vX.Y.Z` with notes derived from the
   changelog

These four must agree for a published release. Do not tag a release without
updating the CLI version string and changelog first (same PR or immediately
preceding commit on the release branch).

### Pre-releases (optional)

When needed, use SemVer pre-release labels on tags, for example:

- `v1.0.0-rc.1`
- `v0.2.0-beta.1`

Pre-releases may be published as GitHub pre-releases. They are not “supported
versions” for long-term maintenance unless the original creator says otherwise.
The CLI version string should match the pre-release identifier when a
pre-release binary or tag is published.

## Changelog policy

### Location and format

- File: [`CHANGELOG.md`](../CHANGELOG.md) at the repository root
- Style: [Keep a Changelog](https://keepachangelog.com/) (human-readable,
  grouped change types)
- Versions: newest first under the file’s version headings
- Dates: ISO-8601 (`YYYY-MM-DD`) on released sections

### Sections

Use these headings when they apply (omit empty ones for a release):

- **Added** — new capabilities
- **Changed** — changes in existing behavior
- **Deprecated** — soon-to-be removed
- **Removed** — removed features
- **Fixed** — bug fixes
- **Security** — vulnerability fixes (coordinate with
  [`SECURITY.md`](../SECURITY.md); avoid unnecessary exploit detail)

### `[Unreleased]`

- Keep an **`[Unreleased]`** section at the top of `CHANGELOG.md`.
- During development on `develop`, append notable user-facing changes there
  (or in the PR that introduces them).
- When cutting a release, rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD` and
  open a fresh empty `[Unreleased]` section above it.

### What belongs in the changelog

**Include:** user-visible CLI behavior, config/ID contract changes, important
fixes, security fixes, deprecations, and install/distribution changes once
those exist.

**Usually skip:** pure refactors, internal renames, test-only changes, and
chore commits with no user impact—unless they matter for operators (for example
minimum Swift version).

### Comparison links (optional)

Keep a Changelog comparison links at the bottom of `CHANGELOG.md` are
encouraged once there are at least two tags. They are optional for the first
tagged release.

## Branching model (release-relevant)

| Branch / ref | Role |
|--------------|------|
| **`develop`** | Primary integration branch. Day-to-day work and CI target. |
| **`main`** (if used) | Optional stable pointer; only if the original creator maintains it. Do not assume `main` exists or is the release source. |
| **`vX.Y.Z` tags** | Immutable release markers. |
| **`release/X.Y.Z`** (optional) | Short-lived branch for release prep if needed; merge back to `develop` after tag. |
| **`hotfix/*`** (optional) | Rare emergency fixes; see maintenance policy below. |

Default path: **release from a commit on `develop`** (or a release branch
fast-forwarded from it) that already contains version + changelog updates.

## Cutting a release (checklist)

Perform releases as the original creator (or a delegated collaborator). Adjust
artifact steps when binary or package publishing lands (#99, #61, #62).

### 1. Preconditions

- [ ] `develop` is in a known-good state for the intended scope
- [ ] CI is green on the commit to be released (`swift build`, `swift test`)
- [ ] No open critical defects intended to block this version
- [ ] Security reports that must ship in this version are addressed or
      explicitly deferred

### 2. Version and changelog PR

- [ ] Choose the next version per the SemVer rules above
- [ ] Move `[Unreleased]` notes into `[X.Y.Z] - YYYY-MM-DD`
- [ ] Recreate an empty `[Unreleased]` section
- [ ] Set CLI `version:` to `"X.Y.Z"` in `Sources/specticus/specticus.swift`
- [ ] Open/merge a focused PR (or commit) with **only** release metadata plus
      any last-minute release-critical fixes

### 3. Tag

From the release commit (after merge to the release line):

```bash
git checkout develop
git pull
git tag -a vX.Y.Z -m "specticus vX.Y.Z"
git push origin vX.Y.Z
```

Prefer **annotated** tags. Do not move or delete published tags except in
extraordinary circumstances (and document why if it ever happens).

### 4. GitHub Release

- [ ] Create a **GitHub Release** for tag `vX.Y.Z`
- [ ] Title: `vX.Y.Z` (or `specticus vX.Y.Z`)
- [ ] Body: paste or summarize the matching `CHANGELOG.md` section
- [ ] Mark as **pre-release** only when using a pre-release version
- [ ] Attach build artifacts **when** the project publishes them (optional
      until binary release automation exists). Until then, document that
      install is from source per the README.

### 5. Post-release

- [ ] Verify `specticus --version` on a release build of that commit prints
      `X.Y.Z`
- [ ] Confirm the GitHub Release page renders correctly
- [ ] Note any follow-ups (Homebrew, packages, announce) without blocking the
      tag on unfinished distribution work

## Maintenance and backport policy

specticus is **maintainer-driven** and does **not** promise long-term support
(LTS) branches by default.

| Policy | Default |
|--------|---------|
| **Supported for fixes** | Latest tagged release and current `develop` (see also [`SECURITY.md`](../SECURITY.md)) |
| **Older minor lines** | No commitment. Fixes land on `develop` and ship in the next release unless the original creator explicitly maintains a branch. |
| **Backports** | Exceptional. Security or critical regressions *may* be backported to a previous tag line at the original creator’s discretion (for example `v0.1.x` patch tags). |
| **Hotfixes** | Prefer fix on `develop` and a new patch release. Use a hotfix branch from a tag only when a faster patch on an older line is truly needed. |
| **Abandoned lines** | Untagged historical commits and unmaintained forks are out of scope. |

When a backport does occur:

1. Cherry-pick or re-implement the fix on the maintenance branch or from the
   target tag.
2. Bump **patch** version, update changelog and CLI version, tag `vX.Y.Z`.
3. Publish a GitHub Release as usual.

## Automation (current and future)

| Item | Status |
|------|--------|
| CI build/test on `develop` and PRs | In use (`.github/workflows/ci.yml`) |
| Automated version bump | Not required; manual is fine |
| Automated GitHub Release on tag | Optional future improvement |
| Multi-platform binary artifacts | Planned with install/distribution work (#99 and related issues) |
| Linux/Windows packages | Separate issues (#61, #62); not blockers for defining this process |

This policy remains valid when automation is added: automation should implement
the same version, changelog, and tag rules—not invent a second scheme.

## Relationship to other docs

| Doc | Role |
|-----|------|
| [`CHANGELOG.md`](../CHANGELOG.md) | User-facing history of releases |
| [`SECURITY.md`](../SECURITY.md) | Vulnerability reporting and supported versions for security fixes |
| [`CONTRIBUTING.md`](../CONTRIBUTING.md) | Who may contribute code; not a shared release ownership guide |
| README installation | How users obtain builds (source today; binaries later) |

## Summary

1. Use **SemVer**; treat `0.y.z` as pre-stable with breaks allowed in minor bumps.
2. Keep **`CHANGELOG.md`** current via `[Unreleased]`, then freeze into versioned
   sections at release.
3. Align **tag `vX.Y.Z`**, **CLI version**, **changelog**, and **GitHub Release**.
4. **Do not** promise LTS; backports are rare and discretionary.
5. Ship **source-based** releases cleanly first; attach binaries and packages
   when those pipelines exist.
