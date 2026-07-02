# {{PROJECT_NAME}}

A specification and documentation project managed with [specticus](https://github.com/jacobmbarnard/specticus).

## Quick Start

```bash
specticus build
# (assembles 00N-*.md files in order)

# or force a single file:
specticus build --input welcome-template.md
```

## Contents

- See numbered section files (001-*.md) 
- Architecture Decision Records in `ADRs/`
- Diagrams in `diagrams/` (Mermaid .mmd files - embed with ```mermaid blocks)
- Project config in `.specticus/config.yml`
- Metadata in `title.yml`

Edit the Markdown files, then run `specticus build` to generate HTML.

## Philosophy

> Simple tools that get out of your way.
