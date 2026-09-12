# {{PROJECT_NAME}}

A specification project managed with [specticus](https://github.com/jacobmbarnard/specticus),
initialized with the **minimal** style pack (`scs init --style minimal`).

## Quick start

```bash
scs lint
scs build
scs open
```

## Layout

Sparse verticals only:

- `document-metadata/`
- `system-overview/`
- `business-requirements/` — nest feature folders here as needed
- `diagrams/`
- `ADRs/` (`proposed` / `accepted` / `deprecated` / `superseded` / `rejected`)

For the full Path A tree, start a project with `scs init` (style `default`).

## Traceability IDs

```bash
scs ids assign --dry-run
scs ids assign --yes
```
