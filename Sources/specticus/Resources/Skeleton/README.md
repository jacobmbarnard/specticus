# {{PROJECT_NAME}}

A specification and documentation project managed with [specticus](https://github.com/jacobmbarnard/specticus).

## Quick Start

```bash
specticus lint          # validate your project layout first
specticus build
# (assembles 00N-*.md files in order)

# or force a single file:
specticus build --input welcome-template.md
```

## Contents

- Numbered section Markdown files (00N-*.md) covering metadata, overview, elicitation notes, constraints (business + technical), requirements, specifications, use cases, test plan, diagrams, glossary, references, BDRs, and document revisions appendix.
- Architecture Decision Records in `ADRs/`
- Business Decision Records in `BDRs/`
- Diagrams in `diagrams/` (Mermaid .mmd files — embed using ```mermaid blocks)
- Project config in `.specticus/config.yml` (output path, CSS, diagrams, ID settings)
- Metadata in `title.yml` (used for the HTML document title)

Edit the Markdown files and config, then run `specticus build` to generate HTML.

## Philosophy

> Simple tools that get out of your way.
