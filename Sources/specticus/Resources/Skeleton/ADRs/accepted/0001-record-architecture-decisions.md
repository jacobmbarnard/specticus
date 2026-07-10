# ADR1. Record Architecture Decisions

**Status:** Accepted  
**Date:** 2026-07-02  
**Deciders:** Team

## Context

We need a way to record architectural decisions made for {{PROJECT_NAME}} in a consistent, searchable, and reviewable format. 

## Decision

We will use Architecture Decision Records (ADRs), stored in the `ADRs/` directory with subdirectories for status (`proposed/`, `accepted/`, `deprecated/`, `superseded/`).

Each ADR is a Markdown file with a standard template (Context, Decision, Consequences, Status).

## Consequences

- Decisions are documented and versioned alongside the code/docs.
- Easy to link from requirements and code.
- New team members can understand why choices were made.
- Status folders help track lifecycle of decisions.

## References

- https://adr.github.io/
