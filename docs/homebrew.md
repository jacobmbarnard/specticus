# Homebrew distribution

specticus ships a Homebrew formula in-repo at [`Formula/specticus.rb`](../Formula/specticus.rb).
The **specticus GitHub repository itself** is the first-party tap (no separate
`homebrew-specticus` repo required for Path A).

## User install (macOS)

```bash
brew tap jacobmbarnard/specticus https://github.com/jacobmbarnard/specticus
brew install --HEAD specticus   # until a stable tag is in the formula
```

Then:

```bash
specticus --version
```

### Requirements

- [Homebrew](https://brew.sh)
- **Xcode** (or a **Swift 6.2+** toolchain) — the formula **builds from source**
  via Swift Package Manager
- Network access on first build (SPM dependency fetch)
- Access to the GitHub repository (required while the repo is private)

There is **no bottle** yet. Install compiles on the machine (can take several
minutes). Prebuilt binaries / bottles are tracked separately (#120).

### Resource bundle (required for `init`)

SwiftPM embeds init templates in `specticus_specticus.bundle` next to the release
binary (`Bundle.module`). The formula installs the binary **and** that bundle into
`libexec`, with a thin wrapper on `PATH`. Installing only the binary (e.g. a bare
`cp .build/release/specticus …`) causes:

```text
Fatal error: could not load resource bundle: …/specticus_specticus.bundle
```

Reinstall after formula updates with `brew reinstall --HEAD specticus` (or upgrade
once a stable version exists).

### Optional: formula from a local checkout

```bash
git clone https://github.com/jacobmbarnard/specticus.git
cd specticus
brew install --build-from-source --HEAD Formula/specticus.rb
```

## Why in-repo (not homebrew-core)

- Maintainer-driven project: one place to update formula + CLI
- Personal/org tap is enough before public popularity warrants homebrew-core
- Source formula works **before** multi-arch release assets exist

A dedicated `homebrew-specticus` tap or a homebrew-core submission can come later
without changing the preferred user command shape much (`brew install …`).

## Maintainer: after cutting a release

Follow [`docs/release-process.md`](release-process.md) for tags and changelog.
Then update the formula for a **stable** install (not only HEAD):

1. Note the release tag (`vX.Y.Z`) and the **full commit SHA** of that tag:
   ```bash
   git rev-parse vX.Y.Z
   ```
2. Edit `Formula/specticus.rb` to add (or bump) the stable block, for example:
   ```ruby
   url "https://github.com/jacobmbarnard/specticus.git",
       tag:      "v0.1.0",
       revision: "abc123…full-sha…"
   version "0.1.0"

   head "https://github.com/jacobmbarnard/specticus.git", branch: "develop"
   ```
3. Keep `head` pointed at `develop` for unreleased installs (`brew install --HEAD specticus` when both stable and head exist).
4. Open a PR that only (or primarily) bumps the formula when the release metadata is already on the release line.
5. Users who already tapped update with:
   ```bash
   brew update
   brew upgrade specticus
   ```

Do **not** invent a second version scheme: formula `version` must match the CLI
`specticus --version` string and the git tag without the `v` prefix.

## Maintainer: smoke-check on a Mac

```bash
brew tap-new jacobmbarnard/specticus-dev 2>/dev/null || true
# Or use the real tap URL against your fork / this repo:
brew tap jacobmbarnard/specticus https://github.com/jacobmbarnard/specticus
brew install --verbose specticus
specticus --version
specticus --help
brew test specticus
brew uninstall specticus
```

## Relationship to other install work

| Work | Ticket / doc |
|------|----------------|
| This formula + README brew path | #119 |
| Prebuilt GitHub Release binaries / bottles | #120 (later) |
| Linux packages | #61 |
| Windows | #62 |
| SemVer, tags, changelog | #52 / `docs/release-process.md` |
