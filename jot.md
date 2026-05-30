# Jot

Jot is a native macOS menu bar app for AI-generated notes from any audio playing on the user's Mac. It records system audio and microphone audio while the user explicitly starts capture, transcribes the audio locally with Whisper, then sends the finished transcript to the user's authenticated Codex CLI to generate timestamp-cited notes.

The product is aimed at technical users first. V1 is for dogfooding: reliable enough to use in real calls, not polished enough for a broad public launch.

## Core Promise

Jot does not integrate with meeting apps. It listens to the Mac's system audio and microphone while capture is active.

The durable guarantee is the transcript. Notes are derived from the transcript and can be retried if the agent fails.

## V1 Scope

- Native Swift/SwiftUI macOS app.
- macOS 15+.
- Menu bar app with no full notes dashboard.
- Open source from day one.
- MIT license.
- Direct-download app first.
- Homebrew Cask later.
- English-only transcription.
- Local Whisper transcription only.
- Default Whisper model: `small.en`.
- Codex-only notes generation in v1.
- Architecture should make Claude Code easy to add later.

## Privacy Positioning

Jot should be described as local-first, not fully private.

- Audio is transcribed locally.
- Raw audio is deleted after successful transcription by default.
- The final transcript is sent to the user's configured local agent CLI for notes generation.
- Jot does not manage, read, or store Codex or Claude credentials.
- Jot does not manipulate interactive agent harnesses.
- Jot only invokes a local authenticated CLI non-interactively.

Setup copy should be explicit:

> Jot records microphone audio and system audio while capture is active. Any audio playing on your Mac during that time may be included.

## User Flow

The main controls are intentionally simple:

- Start
- Pause
- Resume
- Stop

After the user presses Stop, Jot immediately runs processing:

1. Finalize audio chunks.
2. Transcribe chunks locally.
3. Save `transcript.md`.
4. Run Codex once against the full transcript.
5. Save `notes.md`.

There is no transcript editing step in v1.

## First-Run Setup

Jot should require setup before recording is enabled.

Recommended setup order:

1. Choose notes directory.
2. Grant microphone permission.
3. Grant system audio/screen recording permission.
4. Detect the `codex` executable.
5. Run Codex authentication/self-test.
6. Download or verify the local Whisper `small.en` model.
7. Run a short test capture/transcription if practical.

The app should not work without an authenticated Codex CLI in v1.

## Capture Model

Jot captures two separate streams:

- Microphone audio: labeled `User`.
- System audio: labeled `Others`.

These streams should remain separate through transcription so Jot can provide basic speaker tags without ML diarization.

V1 does not perform app-specific filtering. Notification sounds, music, browser audio, videos, and other system sounds may be captured if they play while capture is active.

Headphones should work because the system audio capture should capture the system mix, not speaker output.

## Chunking

Audio is captured in 30-second chunks.

Pause behavior:

- Pause closes the current chunk and stops capturing.
- Resume starts a new chunk.
- Paused time is excluded from elapsed transcript timestamps.

Silence handling:

- Perform basic chunk-level silence detection.
- Skip transcription for effectively silent chunks.
- Do not attempt word-level silence trimming in v1.

## Transcript Format

The transcript is the durable checkpoint.

Example:

```md
[00:03:12] User: I think we should start with Codex only.
[00:03:18] Others: That sounds fine, but make retries obvious.
```

Ordering:

- Sort transcript segments by elapsed timestamp.
- If timestamps are effectively tied, prioritize `User` before `Others`.
- A tie window around 500 ms is acceptable.

No ML speaker diarization is included in v1.

## Notes Format

Notes are generated only after the full transcript has been saved.

Default `notes.md` structure:

```md
# {Generated Meeting Title}

## Summary
- ...

## Decisions
- ... [00:12:30]

## Action Items
- [ ] ... [00:18:04]

## Open Questions
- ... [00:21:10]

## Follow-ups
- ... [00:25:44]

## Source
- Transcript: ./transcript.md
```

Prompt requirements:

- Use concise Markdown.
- Cite timestamps for decisions, action items, and open questions.
- Do not invent owners, names, or commitments.
- Preserve uncertainty when the transcript is ambiguous.
- Generate a short safe meeting title from the transcript.

V1 uses rendered Markdown only. No structured JSON output is required yet.

## Storage

Jot uses temporary storage only for active processing.

Durable output goes into the user-selected notes directory:

```text
Chosen Notes Directory/
  2026-05-24 14-30 Generated Title/
    transcript.md
    notes.md
    metadata.json
```

Raw audio is deleted after successful transcript generation by default.

If transcription fails, Jot should keep recoverable audio/cache and offer retry transcription.

If notes generation fails, Jot should keep the transcript and offer retry with agent.

If the transcript is too large for Codex, Jot should save the transcript and show a clear failure message:

```text
Transcript saved, but it was too large for Codex notes generation.
```

Do not implement recursive summarization in v1.

## State Model

Primary states:

- Idle
- Recording
- Paused
- Finalizing audio
- Transcribing
- Saving transcript
- Generating notes with Codex
- Notes ready
- Failed

Failure states:

- Recording failed
- Transcription failed
- Notes failed

Rules:

- Only one active capture or processing pipeline is allowed in v1.
- While processing, no Start button appears.
- The UI should show progress instead.
- Jot should block system sleep while recording or processing.
- Jot should release the sleep assertion when idle or failed.

## UI

Jot is primarily a menu bar utility.

Menu bar panel:

- Idle: Start, latest notes, preferences.
- Recording: elapsed time, Pause, Stop, audio source status.
- Processing: progress text.
- Complete: Notes ready, Open Notes, Copy Notes, Reveal Folder.

Floating overlay:

- Configurable.
- Only appears while recording or processing.
- Compact, ambient companion style similar to Notion AI or Clicky.
- No transcript editor.
- No notes editor.

Overlay concept:

```text
Collapsed:
● 12:34

Expanded:
Recording 12:34
Pause
Stop
System + Mic
```

During processing, the overlay should show progress and then disappear or briefly show Notes Ready.

## Codex Integration

V1 uses a fixed Codex preset.

The user may override the executable path, but arbitrary command templates are not part of v1.

Jot should invoke Codex non-interactively with Swift `Process`, explicit arguments, stdin/stdout pipes, and a timeout.

Jot should never shell-interpolate transcript text or prompt text.

Conceptual adapter:

```swift
protocol NotesAgent {
    var displayName: String { get }
    func preflight() async throws -> AgentStatus
    func generateNotes(transcriptURL: URL, metadata: MeetingMetadata) async throws -> String
}
```

Ship only:

```swift
CodexAgent
```

Leave room for:

```swift
ClaudeAgent
```

## Transcription Integration

V1 uses local Whisper through an internal transcriber abstraction.

Recommended implementation:

- Embed or bundle `whisper.cpp` as a helper.
- Download or verify the `small.en` model during setup.
- Run transcription on completed chunks.
- Capture output in a structured format if available.
- Merge transcript segments from mic and system streams.

Conceptual adapter:

```swift
protocol Transcriber {
    func transcribe(audioChunk: URL, source: AudioSource) async throws -> [TranscriptSegment]
}
```

Ship only:

```swift
WhisperCppTranscriber
```

## Distribution

Dogfood first:

- Run locally from Xcode.
- Then signed/notarized direct download.
- Then Homebrew Cask.

Preferred install shape later:

```bash
brew install --cask jot
```

The app should eventually install to `/Applications`.

## README Positioning

Short description:

```md
Jot is a local-first macOS menu bar app that records system audio and microphone audio, transcribes the recording locally with Whisper, and asks your authenticated Codex CLI to generate timestamp-cited AI notes.
```

Important exclusions:

- No automatic meeting detection.
- No cloud transcription in v1.
- No agent credentials handled by Jot.
- No speaker diarization beyond `User` and `Others`.
- English-only v1.
- macOS 15+ v1.
- Codex-only v1.

## First Technical Spike

Before polishing UI, prove the core pipeline end to end:

1. Swift menu bar app.
2. Start and Stop.
3. Capture microphone and system audio separately.
4. Write 30-second chunks.
5. Transcribe chunks with local Whisper `small.en`.
6. Merge transcript with `User` and `Others` labels.
7. Save `transcript.md`.
8. Run fixed Codex preset.
9. Save `notes.md`.

The biggest unresolved engineering risk is native macOS audio capture: system audio plus microphone as separate streams, with reliable chunking and permissions.
