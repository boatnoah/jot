# 1. Pluggable notes agents via a CLI-adapter seam

Date: 2026-05-30

## Status

Accepted

## Context

Jot turns a session transcript into notes by invoking an external coding-agent
CLI (see CONTEXT.md → Notes Agent). v1 uses Codex, but Codex, Claude Code and
Cursor are all headless agent CLIs with the same essential shape: run
non-interactively, take a prompt, emit text. We want to ship Codex now without
painting ourselves into a corner — adding Claude Code or Cursor later should be
small and low-risk, and notes quality should not drift between agents.

The invocation details *do* differ per CLI:

- **Codex**: `codex exec`, prompt on stdin, final message captured via
  `--output-last-message <file>`; auth probed with `codex login status`.
- **Claude Code**: `claude -p --output-format text`, prompt on stdin, notes on
  stdout.
- **Cursor**: `cursor-agent -p --output-format text`, similar to Claude.

Transcripts can approach the context cap (~100k tokens ≈ 400k chars), which
exceeds `argv` limits — so the prompt/transcript must go over **stdin**, never
as a shell-interpolated argument.

## Decision

Introduce a layered seam:

1. **`ProcessRunner`** — one shared async, cancellable `Process` wrapper. Pipes
   stdin, drains stdout/stderr without deadlocking, enforces a timeout. No
   shell, arguments passed as an explicit array. Reused by every agent (and
   later by whisper-cli and setup preflight).
2. **`NotesAgent` protocol** — `displayName`, `preflight()`,
   `generateNotes(transcriptURL:metadata:)`. Each adapter is thin: declare the
   executable, build argv, choose output capture (stdout vs file), map errors.
3. **`NotesPrompt`** — agent-agnostic instructions (the Summary/Decisions/Action
   Items/Open Questions/Follow-ups/Source structure). Every agent receives the
   *same* prompt; only invocation differs, so notes stay consistent.
4. **`NotesAgentKind`** — registry enum + factory + persisted user selection,
   and the single source of each agent's command name and override-path key
   (also used by setup's executable detection via `ExecutableLocator`).

Adding an agent = one `NotesAgentKind` case + a ~30-line adapter; no new process
plumbing.

## Consequences

- **Good**: low cost to add agents; consistent prompt/quality; one tested
  process primitive; transcript delivery is injection-safe (stdin only); setup
  detection and runtime resolution share `ExecutableLocator`, so they can't
  drift.
- **Cost**: a tiny indirection for the single-agent v1; `NotesAgentKind`
  carries a small amount of always-compiled selection code even though only
  Codex exists today.
- **Deferred**: Claude Code and Cursor adapters; surfacing agent selection in
  setup; per-agent model/timeout configuration.
