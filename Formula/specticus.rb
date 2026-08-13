# Homebrew formula for specticus (source build via SwiftPM).
#
# Install (from this repository used as a tap):
#   brew tap jacobmbarnard/specticus https://github.com/jacobmbarnard/specticus
#   brew install specticus
#   brew install --HEAD specticus   # unreleased develop
#
# See docs/homebrew.md for maintainer notes (stable tags, sha/revision bumps).

class Specticus < Formula
  desc "Documentation-as-code CLI: Markdown specs to HTML with stable traceability IDs"
  homepage "https://github.com/jacobmbarnard/specticus"
  license "Apache-2.0"

  url "https://github.com/jacobmbarnard/specticus.git",
      tag:      "v0.1.0",
      revision: "07f233141d53cd95b374d687b39bac7b00263945"
  version "0.1.0"

  head "https://github.com/jacobmbarnard/specticus.git", branch: "develop"

  depends_on xcode: :build
  uses_from_macos "swift" => :build

  def install
    system "swift", "build",
           "--disable-sandbox",
           "--configuration", "release",
           "--product", "scs"

    # SPM places the executable and its resource bundle (Bundle.module) next to each
    # other under .build/release/. The binary alone is not enough: `init` loads the
    # Skeleton templates from scs_scs.bundle. Install both into libexec
    # and expose a bin wrapper so the bundle remains adjacent to the real binary.
    release_dir = buildpath/".build/release"
    odie "Release build product missing: #{release_dir}/scs" unless (release_dir/"scs").exist?

    libexec.install release_dir/"scs"

    # macOS: scs_scs.bundle; Linux SPM: scs_scs.resources
    resource_artifacts =
      Dir[release_dir/"scs_*.bundle"] +
      Dir[release_dir/"scs_*.resources"]
    odie "SPM resource bundle missing after release build (expected scs_*.bundle or *.resources)" if resource_artifacts.empty?
    libexec.install resource_artifacts

    # Thin PATH wrapper so Bundle.main resolves next to the real binary in libexec
    # (not next to a lone copy in bin/, which breaks `scs init`).
    bin.write_exec_script libexec/"scs"
  end

  def caveats
    <<~EOS
      specticus is built from source with the Swift Package Manager.
      Requires Xcode (or another Swift 6.2+ toolchain). The first install
      fetches package dependencies and compiles; no bottle is published yet.

      The CLI and its resource bundle live under libexec; `scs` in PATH
      is a thin wrapper so Bundle.module (init templates) resolves correctly.

      Prebuilt GitHub Release archives (no local Swift compile) are documented
      in docs/binaries.md when you prefer a download over a source build.
    EOS
  end

  test do
    assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/scs --version"))
    # Bundle.module must resolve (regression for bin-only install).
    system bin/"scs", "init", "myspecs"
    assert_path_exists testpath/"myspecs/.specticus/config.yml"
    assert_path_exists testpath/"myspecs/001-document-metadata.md"
  end
end
