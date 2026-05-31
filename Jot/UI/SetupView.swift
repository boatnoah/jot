import SwiftUI

/// First-run setup: a minimal, one-step-at-a-time screen on a forced-dark
/// surface (CONTEXT.md → First-Run Setup). No sidebar — a friendly headline, the
/// step's action, a small "step N of 7" whisper, and a ‹ back chevron. Pencil
/// yellow is the single accent. Each step has its own composition (centered vs.
/// icon-beside-text) and a staggered entrance so the wizard feels alive; the
/// finish is a brief celebratory beat before the Dot hatches into existence.
struct SetupView: View {
    let state: SetupState

    /// Called when the user finishes setup from the completion screen. The host
    /// closes the window, restores accessory activation, and shows the Dot.
    var onComplete: () -> Void

    @State private var actionTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            background
            Group {
                if showsCompletion {
                    CompletionView(onComplete: onComplete)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    wizard
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showsCompletion)

            #if DEBUG
            if state.previewMode {
                VStack { Spacer(); previewBar }
            }
            #endif
        }
        .frame(minWidth: 560, minHeight: 480)
        .environment(\.colorScheme, .dark)
        .onDisappear { actionTask?.cancel() }
    }

    /// In debug preview, the completion screen is driven *only* by paging past
    /// the last step — never by `isComplete`, otherwise an already-satisfied
    /// setup would pin the preview on the completion screen. Outside preview it
    /// reflects the real gate.
    private var showsCompletion: Bool {
        #if DEBUG
        if state.previewMode { return state.previewShowCompletion }
        #endif
        return state.isComplete
    }

    #if DEBUG
    /// Free Prev/Next paging for design review, overlaid at the bottom.
    private var previewBar: some View {
        HStack(spacing: 10) {
            previewButton("‹ Prev") { state.previewBack() }
            Text("PREVIEW")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.pencilYellow)
                .tracking(1.5)
                .padding(.horizontal, 4)
            previewButton("Next ›") { state.previewNext() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .padding(.bottom, 12)
    }

    private func previewButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation { action() } }) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.10), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Wizard

    private var wizard: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            StepContentView(check: state.current, state: state,
                            runAct: runAct, cancelAct: { actionTask?.cancel() })
                .id(state.currentIndex)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            Spacer(minLength: 0)
            stepCounter
        }
        .padding(28)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: state.currentIndex)
    }

    private var topBar: some View {
        HStack {
            if state.canGoBack {
                Button(action: { withAnimation { state.back() } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
            Spacer()
        }
        .frame(height: 30)
    }

    private var stepCounter: some View {
        Text("step \(state.stepNumber) of \(state.stepCount)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.3))
            .contentTransition(.numericText())
            .animation(.easeInOut, value: state.stepNumber)
            .frame(height: 20)
    }

    private func runAct() {
        actionTask?.cancel()
        actionTask = Task { await state.act() }
    }

    private var background: some View {
        // Two-tone dark so the centered content sits in a subtle pool of light.
        RadialGradient(
            colors: [Color(white: 0.13), Color(white: 0.07)],
            center: .center, startRadius: 40, endRadius: 460
        )
        .ignoresSafeArea()
    }
}

// MARK: - Per-step content

/// Renders one setup step. Recreated per step (via `.id`), so its `appeared`
/// state replays the staggered entrance each time — including when stepping back
/// to revisit a finished step.
private struct StepContentView: View {
    let check: any SetupCheck
    let state: SetupState
    let runAct: () -> Void
    let cancelAct: () -> Void

    @State private var appeared = false

    private var style: StepStyle { StepStyle.style(for: check.step) }

    var body: some View {
        Group {
            switch style.layout {
            case .centered: centered
            case .sideBySide: sideBySide
            }
        }
        .frame(maxWidth: 460)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: check.status)
        .onAppear { appeared = true }
    }

    // MARK: Layouts

    private var centered: some View {
        VStack(spacing: 16) {
            staggered(hero(size: 88, icon: 40), delay: 0)
            staggered(headline.multilineTextAlignment(.center), delay: 0.08)
            staggered(bodyCopy.multilineTextAlignment(.center).frame(maxWidth: 380), delay: 0.16)
            staggered(actionArea(alignment: .center), delay: 0.24)
            if let detail = check.detail {
                staggered(detailLine(detail), delay: 0.30)
            }
        }
    }

    private var sideBySide: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                staggered(hero(size: 66, icon: 30), delay: 0)
                VStack(alignment: .leading, spacing: 8) {
                    staggered(headline.multilineTextAlignment(.leading), delay: 0.08)
                    staggered(
                        bodyCopy.multilineTextAlignment(.leading)
                            .frame(maxWidth: 320, alignment: .leading),
                        delay: 0.16)
                }
            }
            staggered(actionArea(alignment: .leading), delay: 0.24)
            if let detail = check.detail {
                staggered(detailLine(detail), delay: 0.30)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private func hero(size: CGFloat, icon: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.pencilYellow.opacity(0.14))
                .frame(width: size, height: size)
            Image(systemName: style.symbol)
                .font(.system(size: icon, weight: .semibold))
                .foregroundStyle(Color.pencilYellow)
                .symbolEffect(.bounce, value: appeared)
        }
    }

    private var headline: some View {
        Text(check.headline)
            .font(.system(size: 27, weight: .bold))
            .foregroundStyle(.white)
    }

    private var bodyCopy: some View {
        Text(check.body)
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.62))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func actionArea(alignment: HorizontalAlignment) -> some View {
        let frameAlignment: Alignment = alignment == .leading ? .leading : .center
        Group {
            switch check.status {
            case .unsatisfied:
                yellowButton(check.actionTitle) { runAct() }

            case .running(let fraction):
                if let fraction {
                    VStack(alignment: alignment, spacing: 10) {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .tint(.pencilYellow)
                            .frame(width: 280)
                        Button("Cancel", action: cancelAct)
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    ProgressView().controlSize(.small).tint(.white)
                }

            case .satisfied:
                yellowButton("Continue") { withAnimation { state.advance() } }

            case .failed(let message):
                VStack(alignment: alignment, spacing: 12) {
                    Text(message)
                        .font(.system(size: 13))
                        .multilineTextAlignment(alignment == .leading ? .leading : .center)
                        .foregroundStyle(Color.eraserRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380)
                    // Screen Recording grants only apply after a relaunch.
                    if check.step == .screenRecordingPermission {
                        yellowButton("Relaunch Jot") { AppRelaunch.now() }
                    } else {
                        yellowButton(check.actionTitle) { runAct() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private func detailLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 380)
    }

    // MARK: Animation helper

    /// Spring + blur-to-sharp reveal, offset per element so the step assembles
    /// itself top-to-bottom.
    private func staggered(_ view: some View, delay: Double) -> some View {
        view
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .blur(radius: appeared ? 0 : 6)
            .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay), value: appeared)
    }

    private func yellowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .frame(minWidth: 180)
        }
        .buttonStyle(YellowButtonStyle())
    }
}

/// Per-step visual treatment: alternating composition + a topical animated icon
/// so each step reads as its own moment rather than a form field.
private struct StepStyle {
    enum Layout { case centered, sideBySide }
    var layout: Layout
    var symbol: String

    static func style(for step: SetupStep) -> StepStyle {
        switch step {
        case .notesDirectory:            StepStyle(layout: .centered, symbol: "folder.fill")
        case .microphonePermission:      StepStyle(layout: .sideBySide, symbol: "mic.fill")
        case .screenRecordingPermission: StepStyle(layout: .sideBySide, symbol: "macwindow")
        case .codexExecutable:           StepStyle(layout: .centered, symbol: "terminal.fill")
        case .codexAuth:                 StepStyle(layout: .sideBySide, symbol: "checkmark.seal.fill")
        case .whisperModel:              StepStyle(layout: .centered, symbol: "arrow.down.circle.fill")
        case .testCapture:               StepStyle(layout: .sideBySide, symbol: "waveform")
        }
    }
}

// MARK: - Completion

/// The celebratory finish: the gate is satisfied. A brief warm beat, then the
/// user starts using Jot and the Dot appears for the first time.
private struct CompletionView: View {
    var onComplete: () -> Void
    @State private var pop = false
    @State private var sparkle = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.pencilYellow.opacity(0.16))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.pencilYellow)
                    .symbolEffect(.bounce, value: sparkle)
            }
            .scaleEffect(pop ? 1 : 0.5)
            .opacity(pop ? 1 : 0)

            Text("You're all set")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(.white)

            Text("Jot is ready. Your floating dot is waiting in the corner.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.62))
                .frame(maxWidth: 360)

            Button(action: onComplete) {
                Text("Start using Jot")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 200)
            }
            .buttonStyle(YellowButtonStyle())
            .padding(.top, 6)
        }
        .padding(40)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { pop = true }
            withAnimation(.easeInOut.delay(0.35)) { sparkle = true }
        }
    }
}

/// Filled pencil-yellow primary button with dark text — the one bold accent per
/// screen. Explicit colors (not `.borderedProminent`) so it never dims to gray.
private struct YellowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(white: 0.08))
            .padding(.vertical, 11)
            .padding(.horizontal, 22)
            .background(
                Color.pencilYellow.opacity(configuration.isPressed ? 0.82 : 1),
                in: Capsule(style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Capsule(style: .continuous))
    }
}
