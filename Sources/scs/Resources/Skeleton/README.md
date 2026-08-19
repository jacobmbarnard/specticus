# {{PROJECT_NAME}}

A specification and documentation project managed with [specticus](https://github.com/jacobmbarnard/specticus).

## Quick Start

```bash
scs lint
scs build
scs open
```

## Layout (vertical slices)

Content lives in **section folders** (business requirements, technical specifications, glossaries, etc.). You may add nested folders under a section (e.g. `technical-specifications/login-screen/`).

Decision records: `ADRs/` and `BDRs/` with status subfolders (`proposed`, `accepted`, `deprecated`, `superseded`, `rejected`).

Appendices include `appendices/tech-specs-to-business-reqs/` for TS→BR ID mapping tables.

Document revision history: `document-metadata/document-revisions/`.

## Traceability IDs

```bash
scs ids assign --dry-run
scs ids assign --yes
```

See https://github.com/jacobmbarnard/specticus/blob/develop/docs/traceability-ids.md
