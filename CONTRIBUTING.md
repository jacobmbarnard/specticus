# Contributing to specticus

Thank you for your interest in specticus. The project is released under the
[Apache License 2.0](LICENSE) so that anyone may use, study, and fork the
software. Contribution of changes to *this* repository is managed more
selectively, as described below.

## Project posture

specticus is **maintainer-driven**. Product direction, backlog, and day-to-day
workflow are owned by the **original creator** (and, over time, by collaborators
the original creator explicitly invites).

This posture is intentional:

- The project prioritizes a clear product vision over a large, open contribution
  pipeline.
- Coordinating unsolicited design work, drive-by refactors, and shared ticket
  ownership is not a current goal.
- Open source here means **public source and a permissive license**, not an
  open call for general co-maintainership.

None of this diminishes the value of community feedback. It simply sets
expectations so time is spent where it helps most.

## How you can help without a pull request

The following are always welcome:

1. **Use the tool** and report **reproducible bugs** (steps, expected vs. actual
   behavior, environment, and relevant output).
2. **Fork** the repository to experiment, extend, or maintain a private or
   public derivative under the terms of the license.
3. Share focused **ideas or pain points** via issues when they are specific and
   actionable. There is no commitment that every report will be accepted or
   scheduled.

Large unsolicited redesigns, speculative feature sets, and “rewrite half the
CLI” proposals are unlikely to be merged. That is a bandwidth and direction
choice, not a judgment of the work itself.

## Invited collaborators

People whom the **original creator** has invited to collaborate may contribute
code under the process below. If you have not been invited, please do **not**
open a pull request expecting review or merge. Reach out only if you already
have an agreed scope of work, or prefer a fork.

### Development setup

**Requirements**

- [Swift](https://swift.org) **6.2** or newer (see `Package.swift`)
- A normal development environment on macOS or Linux (Windows support may lag)

**Clone and build**

```bash
git clone https://github.com/jacobmbarnard/specticus.git
cd specticus
swift build
```

**Release build** (optional):

```bash
swift build -c release
```

**Run tests**

```bash
swift test
```

Continuous integration runs `swift build` and `swift test` on pull requests
targeting `develop` (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).
Prefer green local results before opening a PR.

**Run the CLI from a debug build**

```bash
swift run specticus --help
# or, after build:
.build/debug/specticus --help
```

### Coding conventions

- Prefer clear, focused changes that match existing structure and naming.
- Follow ordinary modern Swift style; avoid drive-by reformatting of unrelated
  files.
- Keep user-facing behavior and error messages consistent with the rest of the
  CLI.
- Add or update tests when behavior changes in a way that can reasonably be
  covered by the suite.

There is no separate style guide beyond “fit the codebase.” When in doubt,
mirror neighboring code.

### Pull request guidelines (invited work only)

1. Agree on scope with the original creator **before** substantial work.
2. Branch from `develop` (or the branch you were asked to use).
3. Keep the change set focused; one concern per pull request when practical.
4. Ensure `swift build` and `swift test` pass.
5. Describe **what** changed and **why** in the PR description; link related
   issues when applicable.
6. Expect review on the original creator’s schedule. There is no response-time
   SLA.

The original creator may request changes, defer, or decline a PR even after
invitation if it no longer fits direction or capacity.

## Issues and workflow

- **Bug reports** with a clear reproduction path are the most useful issue type
  for external reporters.
- **Feature requests** may be filed, but acceptance and prioritization remain
  with the original creator.
- Ticket ordering, milestones, and project boards are **not** a shared
  community queue. Please do not assume ownership of triage, assignment, or
  release process unless that responsibility has been explicitly delegated.

## Versioning and releases

Release authority stays with the original creator. Versioning (SemVer),
changelog maintenance, tagging, GitHub Releases, and backport policy are
defined in **[docs/release-process.md](docs/release-process.md)**. User-facing
history lives in **[CHANGELOG.md](CHANGELOG.md)**.

Invited collaborators should note user-visible changes under
`CHANGELOG.md`’s `[Unreleased]` section (or call them out in the PR so they can
be recorded before release). Do not cut tags or GitHub Releases unless that
step was explicitly delegated.

## Security

Do not file public issues for sensitive or exploitable security reports.
Follow the process in **[SECURITY.md](SECURITY.md)** (preferred: GitHub private
vulnerability reporting).

## License of contributions

By submitting a contribution that is accepted into this repository, you agree
that your contribution is provided under the same [Apache License 2.0](LICENSE)
that covers the project, and that you have the right to submit it under those
terms.

## Questions

If you are unsure whether a contribution is appropriate, the conservative
default is: **open a focused issue (for a bug or question), or fork—do not open
an unsolicited pull request.** When collaboration is wanted, the original
creator will say so.

Again, thank you for your interest in specticus.
