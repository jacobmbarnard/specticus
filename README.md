# specticus

**Documentation as code.** A fast, beautiful CLI tool that turns plain-text specifications into clean, styled, printable HTML — with built-in support for traceability IDs.

[![CI](https://github.com/jacobmbarnard/specticus/actions/workflows/ci.yml/badge.svg)](https://github.com/jacobmbarnard/specticus/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache_2.0-blue.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)

## Why specticus?

Writing specifications in Markdown keeps them close to the code and under version control. specticus turns those files into professional, readable documentation while preserving stable traceability IDs (e.g. `BR1`, `TS2`, `ADR3`) that survive refactoring and content changes.

## Features

- **Specifications as code** — Author in plain Markdown, generate beautiful HTML
- **Traceability IDs** — Stable, human-readable identifiers (`BR1`, `TS2`, etc.) with drift detection
- **Clean output** — Light/dark theme support, printable, well-structured HTML
- **Powerful CLI** — `scs` with `init`, `build`, `open`, `lint`, `clean`, and `ids` subcommands
- **Fast** — Written in Swift with minimal dependencies

**Using IDs for the first time?** Read **[Traceability IDs: recommended workflow and common pitfalls](docs/traceability-ids.md)** — syntax, when to assign vs lint vs build, drift, orphans, team patterns, and recovery recipes (#41).

## Happy path

```bash
# macOS (Homebrew) — installs the `scs` command (or use a GitHub Release binary)
brew tap jacobmbarnard/specticus https://github.com/jacobmbarnard/specticus
brew install specticus

scs init MySpecs
cd MySpecs
# edit Markdown… then:
scs ids assign --dry-run
scs build
scs open
```

**Pre-1.0:** the public CLI surface may still change in minor releases. specticus
is **maintainer-driven** (see [CONTRIBUTING.md](CONTRIBUTING.md)). It is a
lightweight **specs-as-code** tool — not a DOORS/Jama-class requirements platform.

## Installation

### macOS (Homebrew) — preferred

```bash
brew tap jacobmbarnard/specticus https://github.com/jacobmbarnard/specticus
brew install specticus
```

This **builds from source** with Swift Package Manager (no bottle yet). You need
Homebrew plus **Xcode / Swift 6.2+**. The first install may take several minutes
while dependencies compile. For unreleased `develop`, use `brew install --HEAD specticus`.

```bash
scs --version   # 0.2.0 on the v0.2.0 release
```

Maintainer notes: **[docs/homebrew.md](docs/homebrew.md)**.

### Prebuilt binaries (GitHub Releases)

[GitHub Releases](https://github.com/jacobmbarnard/specticus/releases) attach
archives for **macOS arm64**, **Linux x86_64**, and **Linux arm64** (no Swift
toolchain required). See **[docs/binaries.md](docs/binaries.md)** for the arch
matrix, checksums, and **macOS Gatekeeper** notes (unsigned builds may need
`xattr -dr com.apple.quarantine` once).

```bash
# Example — pick the asset matching your OS/arch from the release page:
tar -xzf specticus-0.2.0-linux-x86_64.tar.gz
mkdir -p "$HOME/.local"
cp -R specticus-0.2.0-linux-x86_64/bin specticus-0.2.0-linux-x86_64/libexec "$HOME/.local/"
export PATH="$HOME/.local/bin:$PATH"
scs --version
```

### From source

```bash
git clone https://github.com/jacobmbarnard/specticus.git
cd specticus
swift build -c release
# Install the binary *and* its SPM resources side-by-side (required for `init`).
# macOS: scs_*.bundle · Linux: scs_*.resources
mkdir -p ~/.local/libexec/scs
cp .build/release/scs ~/.local/libexec/scs/
cp -R .build/release/scs_*.bundle .build/release/scs_*.resources \
  ~/.local/libexec/scs/ 2>/dev/null || true
printf '%s\n' '#!/bin/sh' 'exec "$HOME/.local/libexec/scs/scs" "$@"' > ~/.local/bin/scs
chmod +x ~/.local/bin/scs
```

Copying only the binary (without the SPM resource bundle/dir) breaks `scs init`
with a “could not load resource bundle” fatal error.

> **Also planned:** Linux distro packages (#61), Windows installer (#62).

## Quick Start

```bash
# Create a new documentation project
scs init MySpecs

cd MySpecs

# Build HTML documentation
scs build

# Open the built HTML in your default browser
scs open

# Check for issues
scs lint

# Manage traceability IDs (preview first — assign rewrites Markdown in place)
scs ids assign --dry-run
scs ids assign --dry-run --diff
scs ids assign --yes

# Inspect store vs Markdown (orphans, drift, recovery hints)
scs ids status

# After review: rebind one drifted ID to its new heading text (same ID)
scs ids accept-drift BR1

# After review: drop orphan bindings for deleted headings (numbers stay reserved)
scs ids prune-orphans
```

### `ids.auto_assign` and build safety

`ids.auto_assign` in `.specticus/config.yml` is **report-only during build**. With it enabled, `scs build` prints a dry-run of pending ID assignments but **does not rewrite Markdown**.

To mutate sources as part of a build you must pass an **explicit** flag:

```bash
scs build --assign-ids   # ⚠️ rewrites Markdown in place
```

Avoid `--assign-ids` in CI or shared checkouts unless that is intentional. Prefer the dedicated `ids assign` workflow above. Default config leaves `auto_assign: false` so build stays purely generative (HTML/assets only).

## Commands

| Command              | Description                                                      |
|----------------------|------------------------------------------------------------------|
| `init`               | Initialize a new specticus project                               |
| `build`              | Generate HTML documentation                                      |
| `build --assign-ids` | Build **and** run `ids assign` (rewrites Markdown; opt-in, #38)  |
| `open`               | Open built HTML in the default browser (`build.output` / `--output`) |
| `lint`               | Validate structure and IDs                                       |
| `clean`              | Remove generated output                                          |
| `ids assign`         | Assign missing IDs (rewrites Markdown; use `--dry-run` / `--yes`) |
| `ids status`         | Report ids.json lifecycle (live IDs, orphans, drift)             |
| `ids accept-drift`   | Accept content drift for one ID (same-identity reword + audit)   |
| `ids prune-orphans`  | Remove orphan bindings (counters never decrease)                 |
| `ids`                | Manage traceability IDs (group command)                          |

Run `scs --help` or `scs <command> --help` for details.

## How It Works

specticus reads a directory of Markdown files (plus optional configuration) and produces a single, cohesive HTML document with:

- Hierarchical heading numbering
- Stable traceability IDs
- Automatic table of contents
- Consistent styling

All IDs and numbering are designed to remain stable across edits and merges.

### Traceability ID workflow (#41)

Day-to-day ID usage is documented in full here:

**[docs/traceability-ids.md](docs/traceability-ids.md)**

That guide covers:

- Recommended heading syntax (`## BR1: …`)
- When to run `ids assign` vs `lint` vs `build`
- Content drift and `ids accept-drift`
- Orphans, counters, and `ids prune-orphans`
- Config (`auto_assign`, `heading_max_level`, `drift_sensitivity`)
- Common mistakes (copy-paste duplicates, wrong ID forms, CI mutation, …)

### Team workflow for traceability IDs (#39)

specticus is **SCM-agnostic by design**: it never calls Git, Fossil, SVN, or any other version-control tool, and it does not model SCM-specific artifacts. Collaboration safety is **ID hygiene** — unique live IDs and a coherent `ids.json` store.

**Hazards teams hit:**

| Situation | What goes wrong | What specticus does |
|-----------|-----------------|---------------------|
| Two people run `ids assign` on divergent checkouts | Both mint the same next ID (e.g. two `BR5`s) | Duplicate IDs fail `lint` / block `ids assign`; `build` warns |
| `ids.json` and Markdown diverge after a messy integrate | Drift, orphans, or unbound live IDs | `ids status`, `lint`, and `build` surface lifecycle problems |

**Recommended practices:**

1. **Integrate first** — bring in the latest documentation before running `ids assign`.
2. **One assign pass per integrate cycle** — prefer a single person (or CI job) to mint new IDs after teammates have landed plain-language headings.
3. **Commit Markdown and `ids.json` together** — treat them as one unit so the store stays coherent with sources.
4. **Preview before rewrite** — `scs ids assign --dry-run` (add `--diff`), then `--yes` when ready.
5. **Never enable source mutation in shared CI by default** — `ids.auto_assign` is report-only on build; `--assign-ids` is opt-in (#38).
6. **Keep each live ID unique** — if concurrent assigns produce duplicates, edit Markdown so each ID appears once, then re-run `scs lint`.

```bash
# After integrating teammates' doc changes:
scs lint                 # fails on duplicate IDs
scs ids status           # lifecycle + collaboration snapshot
scs ids assign --dry-run
scs ids assign --yes     # only when clean
```

Optional: if git is present, `ids assign` may print a soft dirty-path hint for files it is about to rewrite. That hint is convenience-only and can be skipped with `--skip-git-check`. Collaboration guarantees come from ID uniqueness and store coherence, not from any SCM.

## Contributing

specticus is **maintainer-driven**. See **[CONTRIBUTING.md](CONTRIBUTING.md)** for
project posture, invited collaboration, and how to report ordinary bugs.

## Code of conduct

Project spaces should stay professional and on-topic. See
**[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)**.

## Security

To report a vulnerability privately, see **[SECURITY.md](SECURITY.md)**. Do not
open public issues for exploitable security problems.

## Versioning and releases

specticus uses Semantic Versioning. Current release: **0.2.0** (`v0.2.0`).
See **[CHANGELOG.md](CHANGELOG.md)** for user-facing history and
**[docs/release-process.md](docs/release-process.md)** for how versions, tags, and
GitHub Releases are cut. The CLI reports its version via `scs --version`
(should match the installed release; **0.2.0** after this tag).

## License

specticus is released under the [Apache 2.0 License](LICENSE).

---

> Simple tools that get out of your way.