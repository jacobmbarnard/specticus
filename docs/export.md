# Exporting derived artifacts

specticus treats **project Markdown as canonical**. Export commands write
**derived** copies for review — PRs, wikis, chat paste — without turning those
files into a second source of truth.

Tracked under [#5](https://github.com/jacobmbarnard/specticus/issues/5) (old #102).

## GFM monolith (`scs export markdown`)

```bash
scs export markdown
# → output/export.md (default; override with --output or build.markdown_export)

scs export markdown --output review/spec.md
scs export markdown --skip-toc --skip-heading-numbers
```

What it does:

1. Assembles the same sources as `scs build` (layout / `--input`).
2. Optionally applies hierarchical heading numbers (`build.heading_number_max_level`).
3. Injects a **Contents** list (same heading policy as the HTML TOC).
4. **Keeps owning IDs** in headings (`## BR1: Title`). HTML chips (#149) are HTML-only.
5. Copies media into the shared output tree when `build.copy_assets` is on, and
   rewrites Markdown image/link destinations to match.

Banner at the top marks the file as generated. Edit sources, then re-export.

### Config

In `.specticus/config.yml`:

```yaml
build:
  output: "output/index.html"
  markdown_export: "output/export.md"   # default sibling of the HTML
  toc: true
  toc_max_level: 3
  heading_number_max_level: 3
  copy_assets: true
```

`scs clean` removes the output directory (HTML, assets, and the GFM file when
it lives under that tree).

## Out of scope (for now)

- Agent skill-pack distillation ([#7](https://github.com/jacobmbarnard/specticus/issues/7))
- Bidirectional sync / round-trip editing of exports
- Additional formats (PDF, etc.) — add under `scs export …` when needed
