import SwiftUI

/// The Jot Dot: the app's primary control surface. Collapsed it is a small
/// status-tinted dot; expanded it shows controls for the current phase.
struct DotView: View {
    let app: AppState

    /// Hover state owned by the view; expansion is `announce || hovering`.
    @State private var hovering = false
    @State private var collapseTask: Task<Void, Never>?

    var body: some View {
        let expanded = app.announce || hovering
        return ZStack {
            if expanded {
                expandedCard
                    .transition(.scale(scale: 0.4, anchor: .bottomTrailing)
                        .combined(with: .opacity))
            } else {
                collapsedPill
                    .transition(.scale(scale: 0.4, anchor: .bottomTrailing)
                        .combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(16)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: expanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: app.phase)
        // The Dot is always a dark surface, regardless of system appearance.
        .environment(\.colorScheme, .dark)
    }

    /// Debounced so the brief gap while the dot morphs into the card (or vice
    /// versa) doesn't cause a flicker.
    private func handleHover(_ inside: Bool) {
        collapseTask?.cancel()
        if inside {
            hovering = true
        } else {
            collapseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                if !Task.isCancelled { hovering = false }
            }
        }
    }

    // MARK: - Collapsed (Wispr Flow–style black pill)

    private var collapsedPill: some View {
        CollapsedPill(app: app)
            .contentShape(Capsule(style: .continuous))
            .onHover(perform: handleHover)
    }

    // MARK: - Expanded

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(14)
        .frame(width: 284, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onHover(perform: handleHover)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if case .idle = app.phase {
                // Brand mark: the same colored pencil as the menu bar icon.
                Image(nsImage: PencilIcon.image(size: 15))
            } else {
                Circle()
                    .fill(app.phase.status.color)
                    .frame(width: 9, height: 9)
            }
            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if app.phase.isRecording || app.phase == .paused {
                Text(timeString(app.elapsed))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // Complete is a terminal state with no Dismiss button in its action
            // row; this returns to Idle so the next session can be started.
            if case .complete = app.phase {
                Button(action: { app.dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Done — back to start")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch app.phase {
        case .idle:
            primaryButton("Start", systemImage: "record.circle", tint: .red) { app.start() }

        case .recording, .paused:
            LevelMeter(levels: app.levels, active: app.phase.isRecording)
                .frame(height: 26)
            HStack(spacing: 8) {
                if app.phase.isRecording {
                    secondaryButton("Pause", systemImage: "pause.fill") { app.pause() }
                } else {
                    secondaryButton("Resume", systemImage: "play.fill") { app.resume() }
                }
                primaryButton("Stop", systemImage: "stop.fill", tint: .red) { app.stop() }
            }

        case .processing:
            ThinkingView()

        case .complete:
            HStack(spacing: 8) {
                primaryButton("Open", systemImage: "doc.text", tint: .blue, wide: false) { app.openNotes() }
                secondaryButton("Copy", systemImage: "doc.on.doc") { app.copyNotes() }
                secondaryButton("Reveal", systemImage: "folder") { app.revealInFinder() }
            }

        case .failed(let kind):
            VStack(alignment: .leading, spacing: 8) {
                if let detail = kind.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if kind.isRetryable {
                        primaryButton("Retry", systemImage: "arrow.clockwise", tint: .blue, wide: false) {}
                    }
                    secondaryButton("Dismiss", systemImage: "xmark") { app.dismiss() }
                }
            }
        }
    }

    private var headerTitle: String {
        switch app.phase {
        case .idle: return "Jot"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .processing: return "Jot"
        case .complete: return app.generatedTitle ?? "Notes ready"
        case .failed(let kind): return kind.title
        }
    }

    // MARK: - Buttons

    private func primaryButton(_ title: String, systemImage: String, tint: Color, wide: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: wide ? .infinity : nil)
        }
        .buttonStyle(FilledButtonStyle(tint: tint))
        .fixedSize(horizontal: !wide, vertical: false)
    }

    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(SubtleButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// The resting Jot Dot: a compact black capsule (Wispr Flow style) showing
/// minimal state — a status dot, a per-phase glyph, and a live mini meter while
/// Recording. Hovering expands it into the full control card.
private struct CollapsedPill: View {
    let app: AppState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            statusDot
            content
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(
            Capsule(style: .continuous).fill(Color.black.opacity(0.9))
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        // Recording glow around the pill.
        .shadow(color: app.phase.status.color.opacity(app.phase.isRecording && pulse ? 0.55 : 0),
                radius: app.phase.isRecording && pulse ? 10 : 0)
        .animation(app.phase.isRecording ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true) : .default,
                   value: pulse)
        .onAppear { pulse = app.phase.isRecording }
        .onChange(of: app.phase.isRecording) { _, now in pulse = now }
    }

    private var statusDot: some View {
        Circle()
            .fill(app.phase.status.color)
            .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private var content: some View {
        switch app.phase {
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        case .recording, .paused:
            MiniMeter(levels: Array(app.levels.suffix(6)), active: app.phase.isRecording)
                .frame(width: 32, height: 14)
        case .processing:
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
        case .complete:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// Tiny inline waveform shown inside the collapsed pill while recording.
private struct MiniMeter: View {
    let levels: [Double]
    var active: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(active ? Color.red : Color.white.opacity(0.5))
                    .frame(width: 3, height: max(3, CGFloat(level) * 14))
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

/// Explicit-color filled button. Avoids `.borderedProminent`, which dims to
/// gray when the Dot's non-activating panel isn't the key window.
private struct FilledButtonStyle: ButtonStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                tint.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}

/// Explicit-color subtle button for secondary actions, key-state independent.
private struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(0.92))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.2 : 0.11),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}

/// Claude-Code-style "thinking" indicator shown during processing: a cycling
/// gerund verb with a shimmer sweep and a pulsing sparkle. Replaces the progress
/// bar — the work is short and the playful vibe matters more than a precise %.
private struct ThinkingView: View {
    private static let verbs = [
        "Transcribing", "Jotting", "Distilling", "Pondering", "Synthesizing",
        "Connecting dots", "Summarizing", "Noodling", "Percolating", "Musing",
        "Polishing", "Untangling", "Marinating", "Cogitating",
    ]

    @State private var index = Int.random(in: 0..<verbs.count)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .symbolEffect(.pulse, options: .repeating)
            Text(Self.verbs[index] + "…")
                .font(.system(size: 13, weight: .medium))
                .modifier(ShimmerText())
                .id(index)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500))
                withAnimation(.easeInOut(duration: 0.3)) {
                    index = (index + 1) % Self.verbs.count
                }
            }
        }
    }
}

/// A soft left-to-right highlight sweep across text — the "AI is thinking" look.
private struct ShimmerText: ViewModifier {
    @State private var move = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white.opacity(0.4))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.95), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: move ? geo.size.width : -geo.size.width * 0.55)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    move = true
                }
            }
    }
}

/// Single combined level meter (CONTEXT.md → Floating Overlay, B).
private struct LevelMeter: View {
    let levels: [Double]
    var active: Bool

    var body: some View {
        GeometryReader { geo in
            let count = levels.count
            let spacing: CGFloat = 3
            let barWidth = (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(active ? Color.red.opacity(0.85) : Color.secondary.opacity(0.4))
                        .frame(width: barWidth,
                               height: max(3, CGFloat(level) * geo.size.height))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}
