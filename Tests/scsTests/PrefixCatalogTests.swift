import Foundation
import Testing
@testable import scs

// MARK: - Prefix catalog (#19)

@Test func prefixCatalogKnownPrefixesMatchHistoricalOrder() {
    #expect(PrefixCatalog.prefixes == [
        "BR", "TS", "UC", "ADR", "BDR", "TC", "BC", "REF", "DIAG", "REV"
    ])
    #expect(IdsManager.knownPrefixes == PrefixCatalog.prefixes)
    #expect(PrefixCatalog.isKnown("BR"))
    #expect(PrefixCatalog.isKnown("REF"))
    #expect(!PrefixCatalog.isKnown("XYZ"))
}

@Test func prefixCatalogTitleSpecificityLocksCurrentWinners() {
    // Specific phrases beat bare words.
    #expect(PrefixCatalog.inferFromTitle("Business requirement for login") == "BR")
    #expect(PrefixCatalog.inferFromTitle("A requirement for login") == "BR")
    #expect(PrefixCatalog.inferFromTitle("The system shall authenticate users") == "BR")
    #expect(PrefixCatalog.inferFromTitle("Technical specification for auth") == "TS")
    #expect(PrefixCatalog.inferFromTitle("API specification") == "TS")
    #expect(PrefixCatalog.inferFromTitle("Login use case") == "UC")
    #expect(PrefixCatalog.inferFromTitle("Happy-path test case") == "TC")
    #expect(PrefixCatalog.inferFromTitle("Master test plan") == "TC")

    // TC covers both test case and technical constraint.
    #expect(PrefixCatalog.inferFromTitle("Technical constraint: offline only") == "TC")
    #expect(PrefixCatalog.inferFromTitle("Business constraint: budget") == "BC")
    #expect(PrefixCatalog.inferFromTitle("Hard constraint on latency") == "BC")

    // Decision family: business → BDR; architecture / bare → ADR.
    #expect(PrefixCatalog.inferFromTitle("Business decision: vendor X") == "BDR")
    #expect(PrefixCatalog.inferFromTitle("Recorded in bdr notes") == "BDR")
    #expect(PrefixCatalog.inferFromTitle("Architecture decision: SQLite") == "ADR")
    #expect(PrefixCatalog.inferFromTitle("See adr for rationale") == "ADR")
    #expect(PrefixCatalog.inferFromTitle("A decision about caching") == "ADR")

    #expect(PrefixCatalog.inferFromTitle("System context diagram") == "DIAG")
    #expect(PrefixCatalog.inferFromTitle("Document revision history") == "REV")

    // Tie: both "requirement" and "specification" at specificity 50 → BR (earlier in prefixes).
    #expect(PrefixCatalog.inferFromTitle("requirement in the specification") == "BR")

    // REF is known but never inferred from title text.
    #expect(PrefixCatalog.inferFromTitle("Reference material only") == nil)
}

@Test func prefixCatalogFilenameSpecificityLocksCurrentWinners() {
    #expect(PrefixCatalog.inferFromFilename("001-business-requirements.md") == "BR")
    #expect(PrefixCatalog.inferFromFilename("002-technical-specifications.md") == "TS")
    #expect(PrefixCatalog.inferFromFilename("tech-spec.md") == "TS")
    #expect(PrefixCatalog.inferFromFilename("technical_specifications.md") == "TS")
    #expect(PrefixCatalog.inferFromFilename("003-business-constraints.md") == "BC")
    #expect(PrefixCatalog.inferFromFilename("004-technical-constraints.md") == "TC")
    #expect(PrefixCatalog.inferFromFilename("005-use-cases.md") == "UC")
    #expect(PrefixCatalog.inferFromFilename("006-test-cases.md") == "TC")
    #expect(PrefixCatalog.inferFromFilename("007-test-plan.md") == "TC")
    #expect(PrefixCatalog.inferFromFilename("008-business-decision.md") == "BDR")
    #expect(PrefixCatalog.inferFromFilename("009-architecture.md") == "ADR")
    #expect(PrefixCatalog.inferFromFilename("adr-010.md") == "ADR")
    #expect(PrefixCatalog.inferFromFilename("notes-adr.md") == "ADR")
    #expect(PrefixCatalog.inferFromFilename("011-diagram.md") == "DIAG")
    #expect(PrefixCatalog.inferFromFilename("012-revision.md") == "REV")

    // Weaker fallbacks.
    #expect(PrefixCatalog.inferFromFilename("misc-requirement.md") == "BR")
    #expect(PrefixCatalog.inferFromFilename("api-spec.md") == "TS")
    #expect(PrefixCatalog.inferFromFilename("specs.md") == "TS")
    #expect(PrefixCatalog.inferFromFilename("misc-constraint.md") == "BC")

    // technical-constraint beats bare constraint.
    #expect(PrefixCatalog.inferFromFilename("technical-constraint-notes.md") == "TC")
}

@Test func prefixCatalogFreeFormPrefersTitleThenFilenameShape() {
    #expect(PrefixCatalog.infer(from: "use case login") == "UC")
    #expect(PrefixCatalog.infer(from: "001-use-cases.md") == "UC")
    #expect(PrefixCatalog.infer(from: "plain words") == nil)
}
