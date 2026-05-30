# Jot

Jot is a local-first macOS menu bar app that records system audio and microphone audio, transcribes the recording locally with Whisper, and asks your authenticated Codex CLI to generate timestamp-cited AI notes.

## Status

Early development. Not ready for general use.

## Requirements

- macOS 15+
- [Codex CLI](https://github.com/openai/codex) authenticated and in your `$PATH`

## Privacy

- Audio is transcribed locally using Whisper (`small.en` model)
- Raw audio is deleted after successful transcription by default
- The transcript is sent to your local Codex CLI for notes generation
- Jot does not manage or store Codex credentials

## What Jot does not do

- No automatic meeting detection
- No cloud transcription
- No speaker diarization beyond `User` and `Others`
- English-only (v1)
- Codex-only notes generation (v1)

## License

MIT
