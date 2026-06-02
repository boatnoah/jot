import XCTest
@testable import Jot

/// Covers the default, agent-agnostic title derivation backing
/// `NotesAgent.generateTitle`.
final class NotesTitleTests: XCTestCase {
    func testDerivesFirstSentenceOfSummary() {
        let notes = """
        ## Summary
        The team aligned on the Q3 roadmap. Several follow-ups were noted.

        ## Decisions
        Ship on Friday.
        """
        XCTAssertEqual(NotesTitle.derive(fromNotes: notes), "The team aligned on the Q3 roadmap")
    }

    func testStripsMarkdownAndCapsWords() {
        let notes = "## Summary\n**One** _two_ three four five six seven eight nine ten."
        let title = NotesTitle.derive(fromNotes: notes)
        XCTAssertEqual(title, "One two three four five six seven eight")
    }

    func testFallsBackToFirstContentLineWhenNoSummary() {
        let notes = "## Decisions\nAdopt the new pipeline design."
        XCTAssertEqual(NotesTitle.derive(fromNotes: notes), "Adopt the new pipeline design.")
    }

    func testReturnsNilWhenNothingUsable() {
        XCTAssertNil(NotesTitle.derive(fromNotes: ""))
        XCTAssertNil(NotesTitle.derive(fromNotes: "## Summary\nNone"))
        XCTAssertNil(NotesTitle.derive(fromNotes: "## Summary\n\n## Decisions\n"))
    }

    // MARK: - singleWord (dedicated one-word agent call)

    func testSingleWordTakesFirstTokenAndCapitalizes() {
        XCTAssertEqual(NotesTitle.singleWord(from: "roadmap"), "Roadmap")
        XCTAssertEqual(NotesTitle.singleWord(from: "Onboarding plan for Q3"), "Onboarding")
    }

    func testSingleWordStripsQuotesPunctuationAndMarkdown() {
        XCTAssertEqual(NotesTitle.singleWord(from: "\"Budget.\""), "Budget")
        XCTAssertEqual(NotesTitle.singleWord(from: "**Kickoff**"), "Kickoff")
        XCTAssertEqual(NotesTitle.singleWord(from: "  \n\n  Sync!  "), "Sync")
        XCTAssertEqual(NotesTitle.singleWord(from: "Q3"), "Q3")
    }

    func testSingleWordReturnsNilWhenEmptyOrNone() {
        XCTAssertNil(NotesTitle.singleWord(from: ""))
        XCTAssertNil(NotesTitle.singleWord(from: "\n  \n"))
        XCTAssertNil(NotesTitle.singleWord(from: "none"))
        XCTAssertNil(NotesTitle.singleWord(from: "!!!"))
    }
}
