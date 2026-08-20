#!/usr/bin/env bash
# Build a release tarball for specticus (binary + SPM resource bundle).
#
# Usage:
#   scripts/package-release.sh <platform-arch>
#   VERSION=0.1.0 scripts/package-release.sh linux-x86_64
#
# platform-arch examples: macos-arm64, macos-x86_64, linux-x86_64, linux-arm64
#
# Output (under dist/):
#   specticus-<version>-<platform-arch>/
#   specticus-<version>-<platform-arch>.tar.gz
#   specticus-<version>-<platform-arch>.tar.gz.sha256
#
# Layout inside the archive (matches the Homebrew libexec model):
#   bin/scs              # thin wrapper
#   libexec/scs          # real binary
#   libexec/scs_*.bundle # or *.resources (Bundle.module)

set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PLATFORM_ID="${1:-}"
if [[ -z "${PLATFORM_ID}" ]]; then
  echo "usage: $0 <platform-arch>" >&2
  echo "  e.g. macos-arm64 | macos-x86_64 | linux-x86_64 | linux-arm64" >&2
  exit 2
fi

if [[ ! "${PLATFORM_ID}" =~ ^(macos|linux)-(arm64|x86_64)$ ]]; then
  echo "error: platform-arch must look like macos-arm64 or linux-x86_64 (got: ${PLATFORM_ID})" >&2
  exit 2
fi

# Prefer explicit VERSION; else parse CLI version string from source.
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(
    # Brand.version is the source of truth (see Sources/scs/Brand.swift)
    if [[ -f Sources/scs/Brand.swift ]]; then
      sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/scs/Brand.swift | head -1
    fi
  )"
  if [[ -z "${VERSION}" ]]; then
    # Legacy: version: "X.Y.Z" on the root command
    for f in Sources/scs/scs.swift Sources/scs/specticus.swift; do
      if [[ -f "$f" ]]; then
        VERSION="$(sed -n 's/.*version: "\([^"]*\)".*/\1/p' "$f" | head -1)"
        break
      fi
    done
  fi
fi
if [[ -z "${VERSION}" ]]; then
  echo "error: could not determine VERSION (set VERSION= or check Brand.version)" >&2
  exit 1
fi

DIST="${ROOT}/dist"
NAME="specticus-${VERSION}-${PLATFORM_ID}"
STAGE="${DIST}/${NAME}"
TARBALL="${DIST}/${NAME}.tar.gz"

echo "==> Packaging ${NAME}"
echo "    version=${VERSION}  platform=${PLATFORM_ID}"

rm -rf "${STAGE}"
mkdir -p "${STAGE}/bin" "${STAGE}/libexec" "${DIST}"

# Linux: default SPM builds dynamically link libswiftCore.so etc. from the
# toolchain. Users without Swift installed then fail with:
#   error while loading shared libraries: libswiftCore.so
# --static-swift-stdlib embeds the Swift runtime so only common system libs
# (glibc, libstdc++, libm, libgcc) are needed. macOS ships differently; leave default.
BUILD_ARGS=(
  --disable-sandbox
  --configuration release
  --product scs
)
if [[ "${PLATFORM_ID}" == linux-* ]]; then
  BUILD_ARGS+=(--static-swift-stdlib)
  echo "==> swift build -c release --static-swift-stdlib (Linux portable binary)"
else
  echo "==> swift build -c release"
fi

swift build "${BUILD_ARGS[@]}"

RELEASE_DIR="${ROOT}/.build/release"
if [[ ! -x "${RELEASE_DIR}/scs" ]]; then
  # Some toolchains use a triple subdirectory; resolve via swift build --show-bin-path
  RELEASE_DIR="$(swift build --configuration release --show-bin-path)"
fi
if [[ ! -x "${RELEASE_DIR}/scs" ]]; then
  echo "error: release binary not found under ${RELEASE_DIR}/scs" >&2
  exit 1
fi

# Guardrail: refuse to ship a Linux binary that still needs the Swift toolchain.
if [[ "${PLATFORM_ID}" == linux-* ]] && command -v ldd >/dev/null 2>&1; then
  if ldd "${RELEASE_DIR}/scs" 2>/dev/null | grep -E 'libswift|libFoundation|libdispatch' >/dev/null; then
    echo "error: Linux binary still dynamically links Swift runtime libraries:" >&2
    ldd "${RELEASE_DIR}/scs" 2>/dev/null | grep -E 'libswift|libFoundation|libdispatch' >&2 || true
    echo "       Expected --static-swift-stdlib to eliminate these." >&2
    exit 1
  fi
  echo "    Linux dynamic deps: no libswift* (static stdlib OK)"
fi

echo "==> Staging binary and SPM resources from ${RELEASE_DIR}"
cp "${RELEASE_DIR}/scs" "${STAGE}/libexec/scs"
chmod +x "${STAGE}/libexec/scs"

shopt -s nullglob
resource_artifacts=(
  "${RELEASE_DIR}"/scs_*.bundle
  "${RELEASE_DIR}"/scs_*.resources
)
shopt -u nullglob

if [[ ${#resource_artifacts[@]} -eq 0 ]]; then
  echo "error: no SPM resource bundle/dir found (scs_*.bundle or *.resources)" >&2
  echo "       Bundle.module is required for 'scs init'." >&2
  exit 1
fi

for artifact in "${resource_artifacts[@]}"; do
  echo "    + $(basename "${artifact}")"
  cp -R "${artifact}" "${STAGE}/libexec/"
done

# Relative wrapper so the archive is relocatable.
cat > "${STAGE}/bin/scs" << 'EOF'
#!/bin/sh
# scs (specticus) — relocatable launcher (binary + Bundle.module live in ../libexec)
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
exec "$ROOT/libexec/scs" "$@"
EOF
chmod +x "${STAGE}/bin/scs"

cat > "${STAGE}/INSTALL.txt" << EOF
specticus ${VERSION} (${PLATFORM_ID})
==============================

This archive contains a prebuilt specticus CLI and the SPM resource bundle
required for \`scs init\`.

Quick install (user-local)
--------------------------
  tar -xzf ${NAME}.tar.gz
  mkdir -p "\$HOME/.local"
  cp -R ${NAME}/bin ${NAME}/libexec "\$HOME/.local/"
  export PATH="\$HOME/.local/bin:\$PATH"   # add to your shell profile
  scs --version
  scs init MySpecs

System-wide (optional)
----------------------
  sudo cp -R ${NAME}/bin ${NAME}/libexec /usr/local/

Linux notes
-----------
  The binary is linked with --static-swift-stdlib (no full Swift install needed).
  You still need a normal glibc system (Ubuntu/Debian-class). Alpine/musl is not
  supported by these archives.

macOS notes
-----------
  Binaries are not notarized. If Gatekeeper blocks the download:
    xattr -dr com.apple.quarantine path/to/extracted/${NAME}
  Prefer Homebrew on Mac when you have Xcode/Swift:
    brew tap jacobmbarnard/specticus https://github.com/jacobmbarnard/specticus
    brew install --HEAD specticus

See https://github.com/jacobmbarnard/specticus/blob/develop/docs/binaries.md
EOF

echo "==> Smoke test"
"${STAGE}/bin/scs" --version
SMOKE="$(mktemp -d "${TMPDIR:-/tmp}/specticus-pkg.XXXXXX")"
"${STAGE}/bin/scs" init "${SMOKE}/demo"
test -f "${SMOKE}/demo/.specticus/config.yml"
test -f "${SMOKE}/demo/document-metadata/001-title-and-authors.md"
rm -rf "${SMOKE}"
echo "    init OK"

echo "==> Creating tarball"
tar -C "${DIST}" -czf "${TARBALL}" "${NAME}"

# Portable sha256
if command -v sha256sum >/dev/null 2>&1; then
  (cd "${DIST}" && sha256sum "$(basename "${TARBALL}")" > "$(basename "${TARBALL}").sha256")
elif command -v shasum >/dev/null 2>&1; then
  (cd "${DIST}" && shasum -a 256 "$(basename "${TARBALL}")" > "$(basename "${TARBALL}").sha256")
else
  echo "warning: no sha256 tool found; skipping checksum file" >&2
fi

ls -la "${TARBALL}" "${TARBALL}.sha256" 2>/dev/null || ls -la "${TARBALL}"
echo "==> Done: ${TARBALL}"
