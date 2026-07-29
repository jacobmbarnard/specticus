# Security Policy

Thank you for helping keep specticus and its users safe. This document describes
how to report vulnerabilities and what to expect from the project.

specticus is a **local command-line tool** that reads Markdown (and related
project files) and generates documentation. It is **maintainer-driven**: security
handling is performed by the **original creator** (and any collaborators the
original creator explicitly involves). There is no separate security team and
**no guaranteed response-time SLA**.

## Supported versions

Security fixes are considered for:

- The **latest tagged release**, when releases exist
- The current **`develop`** branch (primary line of development)

Older tags, forks, and long-lived unmaintained branches are generally **not**
supported. Pre-1.0 software may change rapidly; prefer reporting against current
sources when possible.

## How to report a vulnerability

**Do not open a public GitHub issue** for security problems that could be
exploited or that reveal sensitive details.

### Preferred: GitHub private vulnerability reporting

1. Open the repository on GitHub:  
   [https://github.com/jacobmbarnard/specticus](https://github.com/jacobmbarnard/specticus)
2. Use **Security → Report a vulnerability** (or the repository’s private
   advisory / vulnerability reporting flow, when enabled).
3. Include as much of the following as you can:
   - A clear description of the issue and its **impact**
   - **Steps to reproduce** (minimal example if possible)
   - Affected **version**, commit, or branch
   - Environment notes (OS, Swift version) when relevant
   - Any suggested fix or patch (optional but appreciated)

If private vulnerability reporting is not yet enabled on the repository, contact
the original creator through a **private, maintainer-visible channel on GitHub**
(for example a private advisory request or a confidential maintainer contact
path). Do not post exploit details in public issues, discussions, or pull
requests.

### What happens next

- Reports are reviewed as the original creator’s capacity allows.
- When practical, the project prefers **coordinated disclosure**: a fix or
  mitigation before broad public detail.
- Outcomes may include a fix, an advisory, a documented limitation, or a
  determination that the report is out of scope.
- Credit to reporters can be given in release notes or advisories when the
  reporter wants recognition and disclosure is appropriate.

There is **no bug bounty** and no commitment to assign CVEs for every report.

## In scope (examples)

Reports that reasonably affect the security of users running specticus are in
scope, for example:

- Unexpected **file read or write** outside the intended project or output paths
- **Command injection** or unsafe handling of untrusted paths, config, or
  content that specticus processes
- Issues that could compromise a machine, user data, or secrets when running
  specticus on attacker-controlled input
- Practical problems in **published release artifacts** or how the project
  distributes binaries (when such artifacts exist)

## Out of scope (examples)

The following are generally **not** handled under this security process:

- Ordinary bugs, UX issues, and **feature requests** — use public issues per
  [CONTRIBUTING.md](CONTRIBUTING.md)
- Theoretical issues with no realistic impact for a local documentation CLI
- Problems solely in **user-authored** specifications or content, not in
  specticus itself
- Vulnerabilities only in third-party dependencies with no practical impact on
  how specticus is built or run (dependency upgrades may still be tracked as
  normal maintenance)
- Social engineering, physical access, or attacks that require already having
  broad control of the reporter’s or victim’s machine unrelated to specticus

When unsure, a private report is still appropriate; the original creator may
reclassify it as a normal bug or close it as out of scope.

## Safe harbor

Good-faith security research that:

- Avoids privacy violations, destruction of data, and disruption of others’
  systems, and
- Does not exploit a vulnerability beyond what is needed to demonstrate it,

is welcome under this policy. This project cannot authorize testing against
third-party systems or infrastructure you do not own or have permission to test.

## Questions

For non-sensitive process questions, see [CONTRIBUTING.md](CONTRIBUTING.md).
For suspected vulnerabilities, use the private reporting path above.
