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
- **Powerful CLI** — `init`, `build`, `lint`, `clean`, and `ids` subcommands
- **Fast** — Written in Swift with minimal dependencies

## Installation

### From source (current)

```bash
git clone https://github.com/jacobmbarnard/specticus.git
cd specticus
swift build -c release
cp .build/release/specticus ~/.local/bin/specticus
```

> **Planned:** Binary releases, Windows installer (#61), Linux packages via apt/yum (#62), and Homebrew support.

## Quick Start

```bash
# Create a new documentation project
specticus init MySpecs

cd MySpecs

# Build HTML documentation
specticus build

# Check for issues
specticus lint

# Manage traceability IDs (preview first — assign rewrites Markdown in place)
specticus ids assign --dry-run
specticus ids assign --dry-run --diff
specticus ids assign --yes

# Inspect store vs Markdown (orphans, drift, recovery hints)
specticus ids status

# After review: rebind one drifted ID to its new heading text (same ID)
specticus ids accept-drift BR1

# After review: drop orphan bindings for deleted headings (numbers stay reserved)
specticus ids prune-orphans
```

### `ids.auto_assign` and build safety

`ids.auto_assign` in `.specticus/config.yml` is **report-only during build**. With it enabled, `specticus build` prints a dry-run of pending ID assignments but **does not rewrite Markdown**.

To mutate sources as part of a build you must pass an **explicit** flag:

```bash
specticus build --assign-ids   # ⚠️ rewrites Markdown in place
```

Avoid `--assign-ids` in CI or shared checkouts unless that is intentional. Prefer the dedicated `ids assign` workflow above. Default config leaves `auto_assign: false` so build stays purely generative (HTML/assets only).

## Commands

| Command              | Description                                                      |
|----------------------|------------------------------------------------------------------|
| `init`               | Initialize a new specticus project                               |
| `build`              | Generate HTML documentation                                      |
| `build --assign-ids` | Build **and** run `ids assign` (rewrites Markdown; opt-in, #38)  |
| `lint`               | Validate structure and IDs                                       |
| `clean`              | Remove generated output                                          |
| `ids assign`         | Assign missing IDs (rewrites Markdown; use `--dry-run` / `--yes`) |
| `ids status`         | Report ids.json lifecycle (live IDs, orphans, drift)             |
| `ids accept-drift`   | Accept content drift for one ID (same-identity reword + audit)   |
| `ids prune-orphans`  | Remove orphan bindings (counters never decrease)                 |
| `ids`                | Manage traceability IDs (group command)                          |

Run `specticus --help` or `specticus <command> --help` for details.

## How It Works

specticus reads a directory of Markdown files (plus optional configuration) and produces a single, cohesive HTML document with:

- Hierarchical heading numbering
- Stable traceability IDs
- Automatic table of contents
- Consistent styling

All IDs and numbering are designed to remain stable across edits and merges.

## Contributing

Contributions are welcome! Please open an issue first to discuss larger changes.

See the [issues labeled "good first issue"](https://github.com/jacobmbarnard/specticus/labels/good%20first%20issue) for smaller tasks.

## License

specticus is released under the [Apache 2.0 License](LICENSE).

---

> Simple tools that get out of your way.