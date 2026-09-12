# Template sections and style packs (#139 / #141)

`scs init` scaffolds a **vertically sliced** documentation tree: each content
domain is a top-level folder. You may nest feature/system folders inside a
section (e.g. `technical-specifications/login-screen/`).

## Style packs (`scs init --style`)

A **style pack** is a vertical skeleton + default assembly layout + recommended
config. Built-in packs:

| Id | What you get |
|----|----------------|
| `default` | Full Path A tree (current `scs init` without `--style`) |
| `minimal` | Stub: metadata, overview, requirements, diagrams, ADRs |

```bash
scs init MySpecs                  # same as --style default
scs init MyNotes --style minimal
scs init --help                   # lists built-in ids
```

The chosen id is stored as `doc.style` in `.specticus/config.yml`. If that key
is missing, specticus uses **`default`**. `scs lint` / `scs build` **warn** on
an unknown id (they do not fail the build).

**On disk (engine repo):** `default` stays at `Sources/scs/Resources/Skeleton/`.
Additional packs live at `Sources/scs/Resources/Styles/<id>/`. A new built-in
style is: that directory + a `StylePackRegistry` entry + a pack `layout.yml`.

`minimal` is an extensibility stub, not a product paradigm. Full alternate
styles are separate epics (#110–#114).

## Section folders (default pack)

| Folder | Role |
|--------|------|
| `document-metadata/` | Title/authors; nested `document-revisions/` for spec history |
| `system-overview/` | Context / overview |
| `stakeholders-and-scope/` | Stakeholders, in/out of scope |
| `business-notes/` / `technical-notes/` | Working notes |
| `assumptions-and-open-questions/` | Unknowns |
| `business-constraints/` / `technical-constraints/` | Constraints |
| `business-requirements/` | BRs |
| `technical-specifications/` | TSs |
| `quality-attributes/` | System qualities (aka NFRs / “ilities”) |
| `external-interfaces/` | APIs, UIs, third parties |
| `data-and-privacy/` | Data / privacy |
| `security-and-access/` | Authn/z, roles |
| `use-cases/` | UCs |
| `test-plan/` | Test intent |
| `operational-concerns/` | Ops / SRE intent |
| `risks-and-tradeoffs/` | Risks |
| `compliance-and-controls/` | Lightweight controls narrative |
| `business-glossary/` / `technical-glossary/` | Split glossaries |
| `references/` | External links |
| `diagrams/` | Mermaid `.mmd` (+ overview markdown) |
| `ADRs/` / `BDRs/` | Decision records |
| `appendices/` | Includes `tech-specs-to-business-reqs/` (TS→BR tables) |

## ADRs / BDRs

```text
ADRs/
  000-adrs.md
  proposed/ | accepted/ | deprecated/ | superseded/ | rejected/
```

Same shape for `BDRs/`. Prefer `000-adrs.md` / `000-bdrs.md` (not `README.md`) so
assembly includes the header (`README*` is skipped as content).

## Assembly order (#140)

Defaults ship in `.specticus/layout.yml` (copied by `scs init`). That file is
the pack’s **complete** section map (so `minimal` is not padded with unused
Path A verticals). Overlay individual ids under `assembly.sections` in
`config.yml` if you need to.

- **Section order:** `order` integers (lower first). Pack default follows the
  table above.
- **Per-section file sort** (`sort`) on paths relative to that section folder:
  - `lexical` — string sort
  - `reverse_lexical` — reverse string sort
  - `alphanumeric` — natural sort (`9-…` before `10-…`) — **default**

Override in `layout.yml` or under `assembly.sections` in `config.yml`:

```yaml
assembly:
  sections:
    - id: appendices
      order: 900
      sort: alphanumeric
    - id: technical-specifications
      order: 5
      sort: reverse_lexical
```

**Legacy:** projects with only flat root `00N-*.md` files still assemble (no
section folders detected).

## See also

- Epic #109 (style profiles)
- #140 assembly layout config
- #141 multi-template / `init --style`
