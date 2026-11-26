import SwiftUI

/// The player's control names.
public struct ExplainerLabels: Sendable {
    public var watch: String
    public var next: String
    public var watchAgain: String
    public var again: String
    /// VoiceOver's reading of the progress dots: "Step 2 of 6".
    public var progress: @Sendable (_ step: Int, _ count: Int) -> String

    public init(
        watch: String, next: String, watchAgain: String, again: String,
        progress: @escaping @Sendable (_ step: Int, _ count: Int) -> String
    ) {
        self.watch = watch
        self.next = next
        self.watchAgain = watchAgain
        self.again = again
        self.progress = progress
    }
}

/// An explainer's watched steps on screen (EXP-8, EXP-17): the progress dots, the drawing, the
/// line in large type, and the controls: a small Again and the large Watch, Next or Watch again,
/// which waits on a gentle pulse. A tap on the drawing does what Next does. The dots are controls
/// only in the parent version (EXP-9).
///
/// It is arranged as the child version is (`ScreenLayout`), in the app's `arrangement`: with the
/// caption below, the dots above the drawing and the line and controls under it; with it beside,
/// one column on the side of the writing hand (`hand`) holds the dots, the line and the controls,
/// and the drawing has the rest at full height. Automatic, the default, puts the caption below in
/// a space taller than wide and beside it in a wider one. The picture is scaled to fit and centred
/// in the area the explainer was laid out for (`ExplainerPlayer.areaUse`). While a touch is on the
/// drawing and just after, presses on the controls do nothing (`PalmGuard`). Only where too little
/// height is left for the drawing (a phone in landscape) does it scroll.
public struct ExplainerView: View {
    private let player: ExplainerPlayer
    private let labels: ExplainerLabels
    private let forceStill: Bool
    private let debugState: Bool
    private let hand: WritingHand
    private let arrangement: ScreenArrangement

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.explainerFonts) private var fonts
    @Environment(\.explainerStyle) private var style
    @State private var palm = PalmGuard()
    /// True while a touch is on the drawing; SwiftUI resets it when the gesture is cancelled as
    /// well as when it ends, so the palm rule never stays held.
    @GestureState private var touchLive = false

    /// `forceStill` shows the still pictures whatever the system's Reduce Motion setting is (for
    /// an authoring app). `debugState` adds an invisible element whose accessibility value
    /// is `ExplainerPlayer.stateSummary`, for UI tests. `hand` is the hand the learner writes with;
    /// right by default.
    public init(
        player: ExplainerPlayer, labels: ExplainerLabels, forceStill: Bool = false, debugState: Bool = false,
        hand: WritingHand = .right, arrangement: ScreenArrangement = .automatic
    ) {
        self.player = player
        self.labels = labels
        self.forceStill = forceStill
        self.debugState = debugState
        self.hand = hand
        self.arrangement = arrangement
    }

    private var palette: ExplainerPalette { style.palette(dark: colorScheme == .dark) }
    private var still: Bool { systemReduceMotion || forceStill }

    public var body: some View {
        ScreenLayout(
            hand: hand, arrangement: arrangement, hasQuestion: false, captionBand: ScreenPlan.captionBand,
            header: { _ in
                dots.frame(maxWidth: .infinity, alignment: .leading)
            },
            question: { EmptyView() },
            drawing: { drawing },
            line: { lines in caption(lines: lines) },
            controls: { inColumn in controls(inColumn: inColumn) }
        )
        .overlay(alignment: .bottomLeading) { stateElement }
        .onAppear { player.reduceMotion = still }
        .onChange(of: still) { player.reduceMotion = still }
        .onDisappear { player.stop() }
    }

    /// The drawing fills the space it is given: its size is given to the player, which lays the
    /// explainer out for it (EXP-17), and the picture is scaled to fit and centred in the area the
    /// explainer was laid out for, which is smaller where the document does not declare the
    /// space's shape. A touch on it holds the controls (the palm rule); a tap goes on.
    private var drawing: some View {
        GeometryReader { geo in
            ExplainerStage(scene: player.scene, areaUse: player.areaUse)
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear { player.layOut(for: geo.size) }
                .onChange(of: geo.size) { player.layOut(for: geo.size) }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { player.tapDrawing() }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($touchLive) { _, live, _ in live = true })
            .onChange(of: touchLive) { _, live in
                if live { palm.penDown() } else { palm.penUp() }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: player.caption.display))
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("explain.drawing")
    }

    /// Again and the large control: in a row under the line, or in the column, one above the other
    /// where it is too narrow for them side by side.
    @ViewBuilder private func controls(inColumn: Bool) -> some View {
        if inColumn {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    againButton
                    Spacer(minLength: 0)
                    primaryButton
                }
                VStack(spacing: 10) {
                    primaryButton
                    againButton
                }
            }
        } else {
            HStack(spacing: 12) {
                againButton
                Spacer()
                primaryButton
            }
        }
    }

    /// A button beside the drawing, under the palm rule.
    private func guarded(_ id: String) -> PalmGuardedStyle {
        PalmGuardedStyle { [palm] in palm.pressBegan(id) }
    }

    // MARK: parts

    @ViewBuilder private var dots: some View {
        let states = player.dots
        let count = states.count
        if player.explainer.version.dotsAreControls {
            HStack(spacing: 0) {
                ForEach(Array(states.enumerated()), id: \.offset) { i, state in
                    Button { player.jump(to: i) } label: {
                        dot(state).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: labels.progress(i + 1, count)))
                    .accessibilityAddTraits(state == .current ? .isSelected : [])
                    .accessibilityIdentifier("explain.dot.\(i)")
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(Array(states.enumerated()), id: \.offset) { _, state in dot(state) }
            }
            .frame(height: 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: labels.progress((player.currentStep ?? -1) + 1, count)))
            .accessibilityIdentifier("explain.dots")
        }
    }

    private func dot(_ state: ExplainerPlayer.Dot) -> some View {
        Circle()
            .fill(
                (state == .done ? palette.ink : state == .current ? palette.colors(.result).fill : palette.line).color
            )
            .frame(width: 12, height: 12)
    }

    /// The line, in room for `lines` lines whatever its length, so the drawing does not change
    /// size from step to step; a line longer than that is set a little smaller rather than cut.
    private func caption(lines: Int) -> some View {
        Text(captionText)
            .font(fonts.display(26))
            .foregroundStyle(palette.ink.color)
            .multilineTextAlignment(.center)
            .lineLimit(lines, reservesSpace: true)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("explain.caption")
    }

    /// The line, with its emphasis (the answer) in the result colour.
    private var captionText: AttributedString {
        let line = player.caption
        var text = AttributedString(line.display)
        if let range = line.emphasisRange,
            let lower = AttributedString.Index(range.lowerBound, within: text),
            let upper = AttributedString.Index(range.upperBound, within: text)
        {
            text[lower..<upper].foregroundColor = palette.colors(.result).ink.color
        }
        return text
    }

    private var againButton: some View {
        Button { if palm.accepts("again") { player.again() } } label: {
            Label(labels.again, systemImage: "arrow.counterclockwise")
                .font(fonts.body(18))
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
        }
        .buttonStyle(guarded("again"))
        .foregroundStyle(palette.ink.color)
        .overlay(Capsule().stroke(palette.line.color, lineWidth: 1.5))
        .opacity(player.againEnabled ? 1 : 0.35)
        .disabled(!player.againEnabled)
        .accessibilityIdentifier("explain.again")
    }

    @ViewBuilder private var primaryButton: some View {
        let control = player.primaryControl
        // It pulses only while it waits, not while the parent version offers it during a step.
        // While the voice makes the line the control starts with, the control is shown dimmed and
        // breathes slowly instead of pulsing, and cannot be pressed; no spinner.
        let preparing = control != nil && player.gettingReady
        let pulsing = control != nil && player.waiting && !still && !preparing
        Button { if palm.accepts("primary") { player.primary() } } label: {
            // The gentle pulse while it waits (1.6 s, to 1.06), computed from the
            // clock rather than animated, so the label and visibility change at once and are
            // never cross-faded. None with Reduce Motion.
            TimelineView(.animation(paused: !pulsing && (!preparing || still))) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                let breath = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                primaryLabel(control ?? .next)
                    .font(fonts.display(24))
                    .foregroundStyle(palette.onResult.color)
                    .padding(.horizontal, 30)
                    .frame(minWidth: 170, minHeight: 64)
                    .background(Capsule().fill(palette.colors(.result).fill.color))
                    .scaleEffect(pulsing ? 1 + 0.03 * (1 - cos(2 * .pi * phase)) : 1)
                    .opacity(preparing ? (still ? 0.45 : 0.4 + 0.15 * (1 - cos(2 * .pi * breath)) / 2) : 1)
            }
        }
        .buttonStyle(guarded("primary"))
        .opacity(control == nil ? 0 : 1)
        .disabled(control == nil || preparing)
        .accessibilityHidden(control == nil)
        .accessibilityIdentifier("explain.primary")
    }

    @ViewBuilder private func primaryLabel(_ control: ExplainerPlayer.PrimaryControl) -> some View {
        switch control {
        case .watch: Label(labels.watch, systemImage: "play.fill")
        case .watchAgain: Label(labels.watchAgain, systemImage: "arrow.counterclockwise")
        case .next:
            HStack(spacing: 8) {
                Text(verbatim: labels.next)
                Image(systemName: "play.fill").accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var stateElement: some View {
        if debugState {
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityIdentifier("explain.debug.state")
                .accessibilityValue(Text(verbatim: player.stateSummary))
        }
    }
}

extension ExplainerPlayer {
    /// The phase and the picture in a compact form for UI tests: not shown and not spoken.
    public var stateSummary: String {
        let phase: String =
            switch self.phase {
            case .ready: "ready"
            case let .playing(k): "playing:\(k)"
            case let .paused(k): "paused:\(k)"
            }
        return "phase=\(phase);" + scene.summary
    }
}

extension Scene {
    /// What can be seen, by kind: how many tens, ones, traded ones and counted pieces are drawn,
    /// how many of each are ghosts, whether the arrow and box are drawn, the marked digit and its
    /// colour, the equation and the total. For tests.
    public var summary: String {
        var parts: [String] = []
        func pieces(_ name: String, _ prefix: String) {
            let shown = visible.filter { $0.id.hasPrefix(prefix) && !$0.id.hasSuffix(".cross") }
            let ghosts = shown.filter { abs($0.opacity - Components.ghostOpacity) < 0.001 }
            // A cross-out drawn whole, or the learner's own line over the piece.
            let crossed = visible.filter {
                guard $0.id.hasPrefix(prefix), $0.id.hasSuffix(".cross") else { return false }
                switch $0.kind {
                case let .crossOut(_, _, p): return p >= 1
                case .ink: return true
                default: return false
                }
            }
            parts.append("\(name)=\(shown.count)/\(ghosts.count)/\(crossed.count)")
        }
        pieces("tens", "ten.")
        pieces("ones", "one.")
        pieces("boxed", "boxed.")
        pieces("countTens", "count.ten.")
        pieces("countOnes", "count.one.")
        func drawn(_ id: String) -> String {
            guard let e = element(id), e.isVisible else { return "0" }
            switch e.kind {
            case let .arrow(_, p, _), let .box(_, p, _): return p >= 1 ? "1" : "part"
            default: return "1"
            }
        }
        parts.append("arrow=\(drawn("arrow"))")
        parts.append("box=\(drawn("box"))")
        if let e = element("equation"), case let .equation(eq) = e.kind {
            parts.append("equation=\(eq.text)")
            if let m = eq.mark, m.progress > 0 {
                parts.append("mark=\(eq.runs[m.run].text):\(m.op.rawValue)")
            } else {
                parts.append("mark=")
            }
        }
        if let e = element("total"), e.isVisible, case let .total(text, _, _) = e.kind {
            parts.append("total=\(text)")
        } else {
            parts.append("total=")
        }
        // The shot the camera holds on, or is moving to (EXP-18).
        if let camera { parts.append("shot=\(camera.shot ?? "")") }
        return parts.joined(separator: ";")
    }
}
