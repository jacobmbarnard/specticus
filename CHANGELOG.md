# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
as described in [docs/release-process.md](docs/release-process.md).

## [Unreleased]

### Added

- Assembly layout config (#140): `.specticus/layout.yml` + optional
  `assembly.sections` in config.yml for section order and per-folder sort
  (`lexical`, `reverse_lexical`, `alphanumeric`)

### Changed

### Fixed

## [0.2.1] - 2026-08-19

Vertical default template layout, grayscale HTML theme, and README release badges.

### Added

- README badges for CI, Release binaries workflow, per-platform release matrix
  (macOS arm64 / Linux x86_64 / Linux arm64), Windows planned, and latest release (#137)

### Changed

- Default HTML theme: grayscale (no accent color), Helvetica/Arial stack, left
  sidebar TOC in the browser and linear print layout without the menu (#143)
- Default `scs init` skeleton uses **vertical section folders** (requirements,
  specs, glossaries, notes, …) with nested feature folders supported; ADR/BDR
  gain `rejected/`; appendices include TS→BR mapping; flat `00N-*.md` projects
  remain supported (#139)

## [0.2.0] - 2026-08-13

Public command rename and terminal brand chrome. Pre-1.0: scripts that call
`specticus` as a binary name should switch to **`scs`**.

### Changed

- **CLI command renamed** from `specticus` to **`scs`** (#133). Install via
  Homebrew remains `brew install specticus` (formula/tap name); the binary on
  `PATH` is `scs`.

### Added

- ASCII **specticus** wordmark at the top of `scs --help` and `scs --version`
  when stdout is a TTY (#135)

## [0.1.0] - 2026-08-06

First tagged public release of specticus (Path A foundation): Markdown specs as
code, stable traceability IDs, HTML output, and install paths for macOS and Linux.

### Added

- CLI: `init`, `build`, `open`, `lint`, `clean`, and `ids` (assign, status,
  accept-drift, prune-orphans) for Git-native specifications
- Stable human-readable traceability IDs (`BR1`, `TS2`, …) with drift detection,
  lifecycle tooling, and workflow docs (`docs/traceability-ids.md`)
- Hierarchical heading numbering, TOC, structured HTML assets, build stamps
- Homebrew formula and tap install path for macOS (`Formula/specticus.rb`,
  `docs/homebrew.md`) (#119)
- Prebuilt GitHub Release binaries for **macOS arm64** and **Linux** (x86_64,
  arm64), with packaging script and release workflow (#120)
- `scs open` to launch built HTML in the default browser (#122)
- Release process, versioning, and changelog policy (`docs/release-process.md`)
  (#52)
- Maintainer-driven contribution guide (`CONTRIBUTING.md`)
- Security policy and private vulnerability reporting (`SECURITY.md`)
- Code of conduct (`CODE_OF_CONDUCT.md`)
- Apache 2.0 license

### Fixed

- Homebrew and manual installs ship the SPM resource bundle with the binary so
  `scs init` can load embedded Skeleton templates (`Bundle.module`)
- Linux prebuilt archives link the Swift standard library statically so the
  binary runs without `libswiftCore.so` / a local Swift toolchain

### Changed

- README installation prefers Homebrew on macOS; prebuilt binaries and source
  build are documented alternatives
- README contributing section aligned with maintainer-driven posture

<!--
When cutting a release:
1. Rename [Unreleased] notes into ## [X.Y.Z] - YYYY-MM-DD
2. Set Sources/scs version (Brand.version) to "X.Y.Z"
3. Tag vX.Y.Z and create a GitHub Release
4. Keep an empty ## [Unreleased] section above
See docs/release-process.md.
-->
