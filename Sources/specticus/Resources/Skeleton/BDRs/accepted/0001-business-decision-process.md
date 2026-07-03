# BDR-0001. Use Business Decision Records

**Status:** Accepted  
**Date:** 2026-07-02  
**Deciders:** Team

## Context

For {{PROJECT_NAME}}, we need a way to record important *business* decisions (as opposed to purely technical/architectural ones) in a consistent format. These may include choices about scope, priorities, processes, vendor selection, etc.

## Decision

We will maintain Business Decision Records (BDRs) in the `BDRs/` directory using the same status-based subfolder structure as ADRs (`proposed/`, `accepted/`, `deprecated/`, `superseded/`).

BDRs use a similar Markdown template to ADRs but focus on business context, options considered, and business impact.

## Consequences

- Business decisions are documented separately from technical architecture decisions.
- Easy to reference from requirements and other sections.
- Clear separation of concerns between business and engineering decisions.
- Supports traceability and future reviews.

## References

- See `ADRs/0001-record-architecture-decisions.md` for the parallel technical process.
