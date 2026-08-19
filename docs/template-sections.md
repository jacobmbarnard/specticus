# Default template: vertical section folders (#139)

`scs init` scaffolds a **vertically sliced** documentation tree: each content
domain is a top-level folder. You may nest feature/system folders inside a
section (e.g. `technical-specifications/login-screen/`).

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

## Assembly today

Until layout config (#140): sections follow the pack order above; within a
section, files are ordered lexicographically by **relative path**.

**Legacy:** projects with only flat root `00N-*.md` files still assemble (no
section folders detected).

## See also

- Epic #109 (style profiles)
- #140 assembly layout config
- #141 multi-template / `init --style`
