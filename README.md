# specticus

A fast, beautiful documentation generator for specifications as code.

## Features

- Specifications as code
- Turns plain text (like Markdown) into styled, readable, printable HTML
- Respects light and dark system themes
- CLI with subcommands for init, build, lint, clean, and traceability IDs

## Installation

```bash
# Build from source
swift build -c release
cp .build/release/specticus ~/.local/bin/specticus
```

## Usage

```bash
specticus --help
specticus init MyDocs
specticus build
```

## Philosophy

> Simple tools that get out of your way.

Just getting started!

---

## Credits

Specticus draws inspiration from earlier tools for turning plain-text sources into structured documentation.[^1]

[^1]: [SRSGem](https://github.com/jacobmbarnard/srsgem)
