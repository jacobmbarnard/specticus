# Prebuilt release binaries

specticus publishes **prebuilt CLI archives** on [GitHub Releases](https://github.com/jacobmbarnard/specticus/releases)
for tagged versions (`vX.Y.Z`). This is issue **#120** (epic **#99**).

Homebrew remains the **preferred** install on macOS when you already have Xcode /
Swift. Binaries are for users who want a downloadable build without compiling.

## Supported targets (current CI matrix)

| Archive suffix | Runner / toolchain | Notes |
|----------------|--------------------|--------|
| `macos-arm64` | `macos-15` + Xcode (Swift 6.2+) | Apple Silicon (**required** on tag) |
| `linux-x86_64` | `ubuntu-24.04` + `swift:6.2` container | glibc (**required** on tag); **static Swift stdlib** |
| `linux-arm64` | `ubuntu-24.04-arm` + `swift:6.2` container | glibc (**best-effort**); static Swift stdlib |

### Runtime requirements

| Platform | Needs Swift toolchain at runtime? | Needs |
|----------|-------------------------------------|--------|
| **macOS** | No (binary is self-contained enough for CLI use) | macOS on matching arch; Gatekeeper may quarantine downloads |
| **Linux** | **No** — packages use `swift build --static-swift-stdlib` | **glibc** + usual `libstdc++` / `libgcc` (Ubuntu 24.04-class). **Not** Alpine/musl |

If you see `error while loading shared libraries: libswiftCore.so`, the archive was
built **without** static stdlib (old package) or you are not using the release
tarball layout. Rebuild with current `scripts/package-release.sh` or re-download
a newer artifact.

Not automated yet (use source / Homebrew / local `scripts/package-release.sh`):

- **macOS Intel (x86_64)** — no dedicated CI runner in this pipeline
- **Windows** — tracked under [#62](https://github.com/jacobmbarnard/specticus/issues/62)
- **musl / Alpine** — not supported by this glibc matrix
- **Linux packages** (`.deb` / `.rpm`) — [#61](https://github.com/jacobmbarnard/specticus/issues/61)

Artifact names:

```text
specticus-<version>-<platform>-<arch>.tar.gz
specticus-<version>-<platform>-<arch>.tar.gz.sha256
```

Example: `specticus-0.1.0-linux-x86_64.tar.gz`

## Archive layout

Each tarball expands to a relocatable tree:

```text
specticus-<version>-<platform>-<arch>/
  bin/specticus                 # thin wrapper (add this dir to PATH)
  libexec/specticus             # real executable
  libexec/specticus_*.bundle    # macOS SPM resources (Bundle.module)
  # or libexec/specticus_*.resources on Linux
  INSTALL.txt
```

The resource bundle **must** stay next to the real binary under `libexec/`.
Shipping only `bin/specticus` breaks `specticus init` (same class of bug as the
Homebrew “binary-only” install).

## Install from a GitHub Release

1. Download the archive for your OS/arch from the release page.
2. Verify checksum (optional but recommended):

   ```bash
   sha256sum -c specticus-*-*.tar.gz.sha256
   # macOS:
   shasum -a 256 -c specticus-*-*.tar.gz.sha256
   ```

3. Extract and install into `~/.local` (or another prefix):

   ```bash
   tar -xzf specticus-VERSION-PLATFORM.tar.gz
   mkdir -p "$HOME/.local"
   cp -R specticus-VERSION-PLATFORM/bin specticus-VERSION-PLATFORM/libexec "$HOME/.local/"
   export PATH="$HOME/.local/bin:$PATH"
   specticus --version
   specticus init MySpecs
   ```

## macOS Gatekeeper / quarantine

Release binaries are **not** Developer ID–signed or notarized. Downloads from
the browser may get the quarantine attribute.

If macOS blocks the binary:

```bash
xattr -dr com.apple.quarantine path/to/extracted/specticus-VERSION-macos-arm64
```

Or right-click → Open once in Finder for the executable. Prefer **Homebrew** if
you want a source build under your own toolchain without quarantine on random
tarballs.

## How maintainers produce binaries

Automation: [`.github/workflows/release.yml`](../.github/workflows/release.yml)

- On push of tag `vX.Y.Z`, the workflow builds each matrix target, packages with
  [`scripts/package-release.sh`](../scripts/package-release.sh), and attaches
  `.tar.gz` + `.sha256` files to the GitHub Release for that tag.
- Manual dry-run: **Actions → Release binaries → Run workflow** (`dry_run: true`)
  uploads workflow artifacts only.

Local package (e.g. on a Mac):

```bash
scripts/package-release.sh macos-arm64
# → dist/specticus-<version>-macos-arm64.tar.gz
```

## Release checklist touchpoints

See [release-process.md](release-process.md): after tagging `vX.Y.Z`, confirm the
Release page lists the expected archives and that `--version` matches the tag
(without the leading `v`).

Homebrew bottles from these assets are **optional follow-up** (not required for
#120). Source-based `brew install` remains valid.
