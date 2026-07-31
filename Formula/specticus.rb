# Homebrew formula for specticus (source build via SwiftPM).
#
# Install (from this repository used as a tap):
#   brew tap jacobmbarnard/specticus https://github.com/jacobmbarnard/specticus
#   brew install specticus
#
# See docs/homebrew.md for maintainer notes (stable tags, sha/revision bumps).

class Specticus < Formula
  desc "Documentation-as-code CLI: Markdown specs to HTML with stable traceability IDs"
  homepage "https://github.com/jacobmbarnard/specticus"
  license "Apache-2.0"

  # Until the first annotated release tag exists, install from develop (HEAD).
  # After tagging vX.Y.Z, add a stable git url + revision (see docs/homebrew.md)
  # and keep head for unreleased work:
  #
  #   url "https://github.com/jacobmbarnard/specticus.git",
  #       tag:      "v0.1.0",
  #       revision: "REPLACE_WITH_FULL_COMMIT_SHA"
  #   version "0.1.0"
  #
  head "https://github.com/jacobmbarnard/specticus.git", branch: "develop"

  depends_on xcode: :build
  uses_from_macos "swift" => :build

  def install
    system "swift", "build",
           "--disable-sandbox",
           "--configuration", "release",
           "--product", "specticus"
    bin.install ".build/release/specticus"
  end

  def caveats
    <<~EOS
      specticus is built from source with the Swift Package Manager.
      Requires Xcode (or another Swift 6.2+ toolchain). The first install
      fetches package dependencies and compiles; no bottle is published yet.

      Prebuilt GitHub Release binaries are deferred (see project issue #120).
    EOS
  end

  test do
    assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/specticus --version"))
  end
end
