import Foundation

/// Builds the instruction prompt for notes generation. Agent-agnostic on
/// purpose: Codex, Claude Code and Cursor all receive the *same* instructions
/// (with the transcript delivered separately, e.g. via stdin), so notes quality
/// and structure stay consistent no matter which agent runs. Only the CLI
/// invocation differs between adapters.
///
/// The section structure mirrors CONTEXT.md → Notes.
enum NotesPrompt {
    /// Approximate context ceiling. Estimated by characters (≈4 chars/token)
    /// against ~100k tokens (CONTEXT.md → Context Cap). Checked before invoking
    /// an agent; over this, notes fail with a clear error and the transcript is
    /// still saved.
    static let maxTranscriptCharacters = 400_000

    /// The instructions an agent receives. The transcript itself is supplied to
    /// the agent out-of-band (stdin) so it never has to be shell-escaped.
    static func instructions(metadata: MeetingMetadata) -> String {
        """
        You are generating meeting notes from a transcript. The transcript is \
        provided to you as input. Each line is a timestamped, speaker-tagged \
        segment; "User" is the person running this app and "Others" is everyone \
        else. Timestamps are elapsed time (mm:ss or h:mm:ss) from the start of \
        the session.

        Write clear, faithful Markdown notes with exactly these sections, in \
        this order, each as a level-2 heading. Omit a section's bullets only if \
        it genuinely has no content (keep the heading and write "None").

        ## Summary
        A short paragraph capturing what the session was about and what happened.

        ## Decisions
        Concrete decisions that were made.

        ## Action Items
        Tasks to be done, each with the owner if identifiable (User/Others) and \
        the cited elapsed timestamp.

        ## Open Questions
        Unresolved questions raised during the session.

        ## Follow-ups
        Things to revisit or check on later.

        ## Source
        One line noting this was generated from the session transcript.

        Rules:
        - Base everything strictly on the transcript; do not invent content.
        - Cite elapsed timestamps in parentheses where they help, e.g. (12:34).
        - Output only the Markdown notes — no preamble, no code fences.
        """
    }

    /// Instructions for the dedicated one-word title call. The generated notes
    /// are supplied out-of-band (stdin); the agent replies with a single word
    /// used to name the Recording Folder.
    static let titleInstructions = """
        You are naming a session from its notes, which are provided to you as \
        input. Reply with exactly ONE word: a single, specific noun that \
        captures the heart of the session (e.g. "Roadmap", "Onboarding", \
        "Budget"). No punctuation, no quotes, no markdown, no explanation — \
        output only that one word.
        """
}
