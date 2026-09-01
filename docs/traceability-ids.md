# Traceability IDs: recommended workflow and common pitfalls

This guide is the practical companion to specticus’s ID commands. It covers **syntax**, **when to run which command**, **drift and orphans**, **team patterns**, and **mistakes that waste time**.

For CLI details, also run `scs ids --help` and `scs help ids <subcommand>`.

---

## What a traceability ID is

A **traceability ID** is a stable, human-readable label on a Markdown heading, for example:

```markdown
## BR1: User Login
```

specticus binds each ID to the **descriptive text** of that heading (here, `User Login`) in `.specticus/ids.json`. The point of the system is:

- The **same ID keeps meaning the same requirement** across renames of files, outline numbering, and document reshuffles.
- Changing *what* an ID means is a **deliberate, visible act** (content drift), not a silent side effect of editing.

IDs are **not** outline numbers (`1.2.3`). Outline numbering is presentation in HTML; IDs are ownership and audit handles.

---

## Recommended syntax

### Preferred form

```markdown
## BR7: The system shall authenticate users with corporate SSO.
```

Rules (see also issue #31):

| Rule | Detail |
|------|--------|
| Position | Owning ID is the **first** token of the heading title (after any outline prefix if one was pasted in by mistake) |
| Shape | `PREFIX` + digits: `BR1`, `TS10`, `ADR3` — **no** dash, **no** zero-padding (`BR-001` / `BR01` are not owning IDs) |
| Digits | Start at 1; no leading zeros |
| Delimiter | Immediately after the ID: **`:`** (preferred), `.`, or whitespace |
| Prefixes | Known set only: `BR`, `TS`, `UC`, `ADR`, `BDR`, `TC`, `BC`, `REF`, `DIAG`, `REV` |
| Heading levels | By default only **H1 and H2** may own IDs (`ids.heading_max_level: 2`) |
| Title text | **Plain text only** — no `**bold**`, links, or other Markdown in the heading title |

### Owning vs merely mentioning

Only a **leading** ID owns the heading:

| Heading | Owns? |
|---------|--------|
| `## BR7: Support for SSO` | Yes — `BR7` |
| `## Support for the BR42 protocol` | **No** — `BR42` is content |
| `## BR7: Implement TS10 and BR99 formats` | Owns `BR7`; `TS10` / `BR99` are mentions (may be noted) |

### Prefix by section (skeleton)

`scs init` scaffolds section files. When you leave headings without IDs, `ids assign` infers a prefix from heading wording, filename, or siblings. Typical mapping:

| Prefix | Typical use |
|--------|-------------|
| `BR` | Business requirements |
| `TS` | Technical specifications |
| `UC` | Use cases |
| `TC` | Test cases / test plan items |
| `BC` | Business constraints |
| `ADR` / `BDR` | Architecture / business decision records |
| `REF`, `DIAG`, `REV` | References, diagrams, revisions (when you choose to ID them) |

You can always write the ID yourself (`## TS4: …`) before running assign.

**Section / vertical titles are not owners.** Headings that are document chrome — e.g. `# Business Requirements`, `# Technical Specifications`, or a title that only restates the section folder name — are **skipped** by `ids assign`. Put owning IDs on the child headings under them (`## User Login` → `## BR1: User Login`). Skips show up in assign feedback as “structural section / vertical title.”

---

## Happy-path workflow (solo or small team)

```text
write / edit Markdown headings
        │
        ▼
scs ids assign --dry-run          # optional: --diff
        │
        ▼
scs ids assign --yes              # rewrites Markdown + updates ids.json
        │
        ▼
scs lint                          # structure + ID problems
        │
        ▼
scs build                         # HTML only (default)
        │
        ▼
commit Markdown + .specticus/ids.json together
```

1. **Author in plain language** — add or edit H1/H2 headings; IDs optional at first.
2. **Preview assignment** — `scs ids assign --dry-run` (add `--diff` to see line-level rewrites).
3. **Assign** — `scs ids assign --yes` when the preview looks right. Non-interactive shells require `--yes` to rewrite.
4. **Lint** — `scs lint` should pass (duplicates and drift are not “ignore forever” problems).
5. **Build** — `scs build` generates HTML. Prefer **not** mutating sources during build.
6. **Commit store + sources** — treat `.specticus/ids.json` (and audit log if present) as part of the same change set as the Markdown.

### Reading `ids assign` skip feedback (#43)

Every `ids assign` (including `--dry-run`) prints a **heading scan** summary:

- How many headings were **considered** for ownership (eligible levels, not in code fences / quotes / tables)
- How many already have IDs, will be assigned, or were **skipped**
- Counts of headings **not eligible** (too deep for `ids.heading_max_level`, or inside exclusion zones)
- Per skipped heading: **reason** + **syntax tip**
- Near-miss forms (`BR-001`, `br1`, `[BR1]`, zero-padding) are called out instead of silently getting a second ID injected

```bash
scs ids assign --dry-run
scs ids assign --dry-run --verbose   # list every eligible heading considered
```

### When you only reword an existing requirement

Keep the **same ID**, change the descriptive text, then:

```bash
scs lint                 # reports content drift
scs ids status           # see old vs new binding context
scs ids accept-drift BR1 --note "editorial rename"
scs lint
```

Do **not** invent a new ID for a pure reword of the same requirement. Do **not** reuse an old ID for a *different* requirement — mint a new one with `ids assign` instead.

### When you delete a requirement

Delete or un-ID the heading. The binding becomes an **orphan** in `ids.json` (number stays reserved). Inspect, then prune after review:

```bash
scs ids status
scs ids prune-orphans --dry-run
scs ids prune-orphans --id BR2 --note "retired"
```

Pruning **never** frees the number for reuse. New IDs always use per-prefix **max + 1** (gaps are intentional).

---

## When to run `ids assign` vs lint vs build

| Goal | Command | Writes Markdown? | Writes `ids.json`? |
|------|---------|------------------|--------------------|
| Preview new IDs | `ids assign --dry-run` | No | No |
| Mint / inject missing IDs | `ids assign --yes` | **Yes** | Yes |
| Validate project + IDs | `lint` | No | No |
| Generate HTML | `build` | No (default) | No (default) |
| Report pending assigns at build | `build` with `ids.auto_assign: true` | No | No |
| Assign **during** build | `build --assign-ids` | **Yes** | Yes |
| Inspect orphans / drift | `ids status` | No | No |
| Accept one reword | `ids accept-drift <ID>` | No | Yes (+ audit log) |
| Drop orphan bindings | `ids prune-orphans` | No | Yes (+ audit log) |
| Remove HTML output | `clean` | No | No |

### Practical rules of thumb

- **After adding new requirement headings without IDs** → `ids assign` (preview, then `--yes`).
- **Before a PR / integrate** → `lint` (and often `ids status` if people deleted or reworded headings).
- **Day-to-day HTML preview** → `build` only; leave assign as a separate, intentional step.
- **CI** → run `lint` and `build`; do **not** enable source mutation (`--assign-ids`) unless the pipeline is explicitly designed to commit rewritten Markdown.
- **`clean`** only deletes generated output under the configured output tree. It does **not** touch IDs, `ids.json`, or source Markdown.

### `ids.auto_assign` and build safety

In `.specticus/config.yml`:

```yaml
ids:
  auto_assign: false   # recommended default
```

| Setting / flag | Effect |
|----------------|--------|
| `auto_assign: false` (default) | Build never talks about pending assigns unless you pass `--assign-ids` |
| `auto_assign: true` | Build **reports** a dry-run of pending assignments only — **does not** rewrite sources |
| `scs build --assign-ids` | Explicit opt-in: run assign and **rewrite Markdown** during build |

Prefer:

```bash
scs ids assign --dry-run
scs ids assign --yes
scs build
```

---

## Content drift (in depth)

**Drift** means: the heading still claims the same ID, but the descriptive text no longer matches the binding in `ids.json`.

Example:

```text
ids.json:   BR1 → "User Login"
Markdown:   ## BR1: User Logout     ← drift
```

| Command | Behavior on drift |
|---------|-------------------|
| `ids assign` | Reports drift; does **not** silently rebind; does not overwrite the existing ID token |
| `lint` | Surfaces drift as a problem to fix |
| `build` | Warns (build may still succeed) so HTML generation is not blocked by editorial work |

### Accepting drift (same identity)

```bash
scs ids accept-drift BR1
scs ids accept-drift BR1 --note "renamed under CR-42"
```

- Updates **only** that ID’s binding in `ids.json`
- Never changes the ID token in Markdown
- Never bulk-accepts other IDs
- Appends an audit line to `.specticus/ids-audit.jsonl` (fail closed if the log cannot be written)

### Drift sensitivity (`ids.drift_sensitivity`)

| Value | Behavior |
|-------|----------|
| `strict` (default) | Any character difference is drift |
| `contentStrict` | Allow letter-case changes; whitespace may grow/shrink (not vanish entirely) |
| `contentStrictPlus` | Like `contentStrict`, plus ignore punctuation differences |

Markdown formatting in titles is never “normalized away” into a clean binding — keep titles plain text.

**Do not** lower sensitivity just to hide real meaning changes. Use `accept-drift` when the identity is still the same requirement.

---

## Orphans, counters, and the store

`.specticus/ids.json` is the **source of truth** for which IDs exist and what text they were bound to.

| Term | Meaning |
|------|---------|
| **Live ID** | Claimed by an eligible heading in Markdown |
| **Orphan** | In `ids.json`, not claimed by any eligible heading |
| **Unbound live ID** | In Markdown, not yet (or no longer) in the store — usually fixed by `ids assign` |
| **Counter / high-water** | Per prefix, next ID is always **max + 1**; numbers are **never reused** |

```bash
scs ids status          # full lifecycle snapshot
scs ids prune-orphans   # after review only
```

Missing `ids.json` is treated as an empty store; `ids assign` can bootstrap bindings from IDs already present in Markdown.

---

## Team usage patterns

specticus is **SCM-agnostic**: it does not call Git (or any VCS) for safety. Collaboration depends on **ID hygiene** and a coherent store. See also the short section in the [README](../README.md#team-workflow-for-traceability-ids-39).

### Recommended practices

1. **Integrate latest docs before minting IDs** — reduce concurrent `ids assign` collisions.
2. **One assign pass per integrate cycle** — teammates land plain-language headings; one person (or a deliberate job) runs assign.
3. **Commit Markdown and `ids.json` together** — never land one without the other when assign ran.
4. **Preview before rewrite** — `--dry-run` / `--diff`, then `--yes`.
5. **No source mutation in shared CI by default** — no `--assign-ids` unless you mean it.
6. **Fix duplicates in Markdown** — two live `BR5`s is an authoring error; lint will fail until each ID is unique.

```bash
# After integrating teammates' doc changes:
scs lint
scs ids status
scs ids assign --dry-run
scs ids assign --yes
```

Optional: if `git` is on `PATH`, `ids assign` may print a soft dirty-path hint for files it is about to rewrite. Silence with `--skip-git-check`. Guarantees still come from uniqueness and store coherence, not from Git.

---

## Common mistakes and how to recover

| Mistake | Why it hurts | Recovery |
|---------|--------------|----------|
| Copy-paste a heading and leave the same ID (`BR1` twice) | Duplicate live IDs; broken uniqueness | Edit one heading to remove/change the ID, then `lint` / `ids assign` |
| Rewrite the title but keep the old ID for a **different** requirement | Silent semantic theft of the ID | Prefer a **new** heading + new ID; if you already drifted, treat carefully — often better to give the new meaning a new ID and retire the old |
| Change title text and ignore drift warnings | Store and docs disagree | `ids accept-drift <ID>` after review, or restore the old title |
| Manually invent `BR-001` / `br1` / `[BR1]` | Not recognized as an owning ID | Use `BR1:` form; re-run assign |
| Put IDs only on H3+ with default config | Assign/lint ignore those levels | Raise `ids.heading_max_level` or promote headings to H2 |
| Put IDs inside fenced code / blockquotes expecting ownership | Non-content is ignored (#30) | Put real requirements in normal headings |
| Run `ids assign` on two long-lived branches, then merge | Duplicate numbers minted independently | Integrate first next time; on conflict, make each live ID unique, reconcile `ids.json`, `lint` |
| Enable `build --assign-ids` in CI “for convenience” | Surprise Markdown rewrites / dirty trees | Use dedicated `ids assign` and commit explicitly |
| Delete a requirement and expect its number to come back | Counters never reuse | Accept the gap; next ID is max+1 |
| Hand-edit `ids.json` without updating Markdown | Store/Markdown diverge | Prefer CLI (`assign`, `accept-drift`, `prune-orphans`); advanced edits are possible but easy to get wrong |
| Expect `clean` to reset IDs | `clean` only removes build output | Manage IDs with `ids` subcommands |
| Markdown in heading titles (`## BR1: **Login**`) | Rejected / problematic for bindings | Use plain text titles |

---

## Config reference (IDs)

From `.specticus/config.yml` (see skeleton after `scs init`):

```yaml
ids:
  auto_assign: false           # report-only on build when true; mutation needs --assign-ids
  heading_max_level: 2         # ATX levels 1…N may own IDs (1…6)
  drift_sensitivity: strict    # strict | contentStrict | contentStrictPlus
```

Independent of:

- `build.heading_number_max_level` — outline numbers in HTML  
- `build.toc_max_level` — table of contents depth  

---

## Command cheat sheet

```bash
# Assign
scs ids assign --dry-run
scs ids assign --dry-run --diff
scs ids assign --dry-run --verbose   # list every eligible heading (#43)
scs ids assign --yes

# Inspect
scs ids status
scs lint

# Drift (one ID at a time)
scs ids accept-drift BR1
scs ids accept-drift BR1 --note "same requirement, clearer title"

# Orphans
scs ids prune-orphans --dry-run
scs ids prune-orphans
scs ids prune-orphans --id BR2 --note "retired"

# Build / clean (IDs unchanged by default)
scs build
scs build --assign-ids    # ⚠️ rewrites Markdown
scs clean                 # output only
```

---

## Related issues

Implementation and policy history (for maintainers and curious authors):

| Topic | Issues |
|-------|--------|
| Core IDs + assign | #6 |
| Syntax rules | #31 |
| Heading levels | #32 |
| Counter / no reuse | #33 |
| Outline vs IDs | #34 |
| Assign UX / safety | #35 |
| Drift sensitivity | #36 |
| Store lifecycle | #37 |
| `auto_assign` / `--assign-ids` | #38 |
| Collaboration hygiene | #39 |
| Accept drift | #66 |
| This guide | #41 |

---

> **Success looks like:** you can add a requirement, assign an ID once, reword it with `accept-drift` when needed, and trust that `BR1` still means the same thing six months later — without discovering the rules the hard way.
