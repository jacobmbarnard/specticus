# {{PROJECT_NAME}}

A specification and documentation project managed with [specticus](https://github.com/jacobmbarnard/specticus).

## Quick Start

```bash
scs lint          # validate your project layout first
scs build
# → output/index.html plus css/, img/, svg/ assets

# or force a single file:
scs build --input welcome-template.md

# Traceability IDs (assign rewrites Markdown — preview first):
# scs ids assign --dry-run
# scs ids assign --yes
# ids.auto_assign in .specticus/config.yml only reports during build;
# mutation requires: scs build --assign-ids  (avoid in CI unless intentional)
#
# Full workflow + pitfalls:
# https://github.com/jacobmbarnard/specticus/blob/develop/docs/traceability-ids.md
```

## Contents

- Numbered section Markdown files (00N-*.md) covering metadata, overview, elicitation notes, constraints (business + technical), requirements, specifications, use cases, test plan, diagrams, glossary, references, BDRs, and document revisions appendix.
- Architecture Decision Records in `ADRs/`
- Business Decision Records in `BDRs/`
- Diagrams in `diagrams/` (Mermaid .mmd files — embed using ```mermaid blocks)
- Project config in `.specticus/config.yml` (output path, CSS, asset copy, diagrams, ID settings)
- Metadata in `title.yml` (used for the HTML document title)

Edit the Markdown files and config, then run `scs build`. Open `output/index.html` in a browser (CSS and images are copied beside it).

## Philosophy

> Simple tools that get out of your way.
