# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
as described in [docs/release-process.md](docs/release-process.md).

## [Unreleased]

### Added

- `specticus open` subcommand to launch built HTML in the default browser (#122)
- Maintainer-driven contribution guide (`CONTRIBUTING.md`)
- Security policy and private vulnerability reporting guidance (`SECURITY.md`)
- Release process, versioning, and changelog policy (`docs/release-process.md`)
- Simple project code of conduct (`CODE_OF_CONDUCT.md`)
- Homebrew formula (`Formula/specticus.rb`) and install docs (`docs/homebrew.md`)

### Changed

- README contributing section aligned with maintainer-driven posture; security
  and code of conduct pointers added
- README installation prefers Homebrew on macOS; source build is secondary

<!--
When cutting a release:
1. Rename this section to ## [X.Y.Z] - YYYY-MM-DD
2. Set Sources/specticus/specticus.swift version to "X.Y.Z"
3. Tag vX.Y.Z and create a GitHub Release
4. Add a new empty ## [Unreleased] section above
See docs/release-process.md.
-->
