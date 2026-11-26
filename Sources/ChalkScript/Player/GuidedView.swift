import SwiftUI

/// The child version on screen (EXP-8, EXP-14, EXP-17): the parts strip and progress dots, the
/// problem's question where the explainer gives it apart from the drawing, the drawing, which
/// takes the learner's Pencil or finger while a step waits for marks, the line with a hint or miss
/// and a tally, and the controls: Again; Why?, Show me and the large control. A tap on the drawing
/// does what the large control does while it waits.
///
/// It is arranged by the space it is given (`ScreenLayout`): taller than wide, the question at
/// the top, the drawing in the middle and the line and controls at the bottom; wider than tall,
/// one column on the side of the writing hand (`hand`) holds the parts, the question, the line
/// and the controls, and the drawing has the rest at full height. The drawing area's size is given
/// to the player, which lays the explainer out for it (`GuidedPlayer.layOut`). While a touch is on
/// the drawing and just after, presses on the controls do nothing (`GuidedPlayer.press`).
///
/// The learner's dots only show where the learner is (EXP-8). With `dotsJump`, which only an authoring
/// app sets, each dot is a control that plays its step.
public struct GuidedView: View {
    private let player: GuidedPlayer
    private let forceStill: Bool
    private let debugState: Bool
    private let dotsJump: Bool
    private let hand: WritingHand

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.explainerFonts) private var fonts
    @Environment(\.explainerStyle) private var style
    @State private var touching = false
    /// True while the drawing's gesture is live; SwiftUI resets it when the gesture is cancelled
    /// as well as when it ends, which `onEnded` is not called for.
    @GestureState private var gestureLive = false

    /// `hand` is the hand the learner writes with; right by default.
    public init(
        player: GuidedPlayer, forceStill: Bool = false, debugState: Bool = false, dotsJump: Bool = false,
        hand: WritingHand = .right
    ) {
        self.player = player
        self.forceStill = forceStill
        self.debugState = debugState
        self.dotsJump = dotsJump
        self.hand = hand
    }

    private var labels: GuidedLabels { player.labels }
    private var palette: ExplainerPalette { style.palette(dark: colorScheme == .dark) }
    private var still: Bool { systemReduceMotion || forceStill }

    public var body: some View {
        ScreenLayout(
            hand: hand, hasQuestion: player.question != nil,
            header: { inColumn in header(inColumn: inColumn) },
            question: { questionText },
            drawing: { drawingArea },
            line: { lines in lineBlock(lines: lines) },
            controls: { inColumn in controls(inColumn: inColumn) }
        )
        .overlay(alignment: .bottomLeading) { stateElement }
        .onAppear { player.reduceMotion = still }
        .onChange(of: still) { player.reduceMotion = still }
        .onDisappear { player.stop() }
        .sensoryFeedback(.impact(weight: .light), trigger: player.haptics)
    }

    /// The parts strip and the dots: in a row above the drawing, or one above the other at the
    /// top of the column.
    @ViewBuilder private func header(inColumn: Bool) -> some View {
        if inColumn {
            VStack(spacing: 10) {
                partsStrip
                dots
            }
        } else {
            HStack(spacing: 16) {
                partsStrip
                Spacer(minLength: 8)
                dots
            }
        }
    }

    /// The problem's question, where the explainer gives it apart from the drawing.
    @ViewBuilder private var questionText: some View {
        if let question = player.question {
            Text(verbatim: question.display)
                .font(fonts.display(26))
                .foregroundStyle(palette.ink.color)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("explain.question")
        }
    }

    // MARK: the drawing and the Pencil

    /// The drawing fills the space it is given; its size is given to the player, which lays the
    /// explainer out for it, and the picture is scaled to fit and centred in it (EXP-17).
    private var drawingArea: some View {
        GeometryReader { geo in
            let area = geo.size
            let scene = player.scene
            ZStack(alignment: .topLeading) {
                ExplainerStage(scene: scene)
                    .frame(width: area.width, height: area.height)
                if let why = player.whyScene { whyPanel(why, in: area) }
                inkLayer(scene, in: area)
            }
            .frame(width: area.width, height: area.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(pencil(scene, in: area))
            .onChange(of: gestureLive) { _, live in
                // Reset without `onEnded`: the touch was cancelled.
                if !live && touching {
                    touching = false
                    player.touchCancelled()
                }
            }
            .onAppear { player.layOut(for: area) }
            .onChange(of: area) { player.layOut(for: area) }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: player.caption.display))
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("explain.drawing")
        .accessibilityAction { player.tapDrawing() }
    }

    /// Every touch on the drawing goes to the player in the drawing's units, read through the
    /// scene's fit and its camera (EXP-18), so a framed piece is a larger target; the player
    /// reads it as a mark, a drag, or a tap that goes on.
    private func pencil(_ scene: Scene, in area: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($gestureLive) { _, live, _ in live = true }
            .onChanged { value in
                let p = scene.scenePoint(value.location, in: area)
                let start = scene.scenePoint(value.startLocation, in: area)
                if touching {
                    player.touchMoved(to: p)
                } else {
                    touching = true
                    player.touchBegan(at: start)
                    if p != start { player.touchMoved(to: p) }
                }
            }
            .onEnded { value in
                touching = false
                player.touchEnded(at: scene.scenePoint(value.location, in: area))
            }
    }

    /// The pencil line being drawn, and lines fading that were not read as marks, through the
    /// same fit and camera as the drawing.
    private func inkLayer(_ scene: Scene, in area: CGSize) -> some View {
        let ink = player.ink
        let transform = scene.drawingTransform(in: area)
        return TimelineView(.animation(paused: !ink.contains { $0.fadingSince != nil })) { _ in
            Canvas { context, _ in
                context.concatenate(transform)
                for stroke in ink where stroke.points.count > 1 {
                    var layer = context
                    layer.opacity = player.opacity(of: stroke)
                    var path = Path()
                    path.addLines(stroke.points)
                    layer.stroke(path, with: .color(palette.muted.color),
                        style: StrokeStyle(lineWidth: Components.liveInkWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Why? over the drawing: a veil, a panel inset from Why?'s own picture's edges, and the
    /// picture (EXP-16).
    private func whyPanel(_ why: Scene, in area: CGSize) -> some View {
        let (s, origin) = why.fit(in: area)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(palette.sheet.color.opacity(0.8))
            RoundedRectangle(cornerRadius: 22 * s)
                .fill(palette.sheet.color)
                .overlay(RoundedRectangle(cornerRadius: 22 * s).stroke(palette.line.color, lineWidth: 2.4 * s))
                .frame(width: (why.size.width - 60) * s, height: (why.size.height - 48) * s)
                .offset(x: origin.x + 30 * s, y: origin.y + 24 * s)
            ExplainerStage(scene: why)
                .frame(width: area.width, height: area.height)
        }
        .frame(width: area.width, height: area.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityIdentifier("explain.why.panel")
    }

    // MARK: parts and dots

    @ViewBuilder private var partsStrip: some View {
        let parts = player.parts
        let now = parts.firstIndex(of: player.part) ?? 0
        HStack(spacing: 14) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                Text(verbatim: labels.name(part))
                    .font(i == now ? fonts.display(17) : fonts.body(15))
                    .foregroundStyle((i == now ? palette.colors(.result).ink : i < now ? palette.ink : palette.muted).color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: labels.name(player.part)))
        .accessibilityIdentifier("explain.parts")
    }

    @ViewBuilder private var dots: some View {
        let states = player.dots
        if dotsJump {
            // For an authoring app: each dot plays its step.
            HStack(spacing: 0) {
                ForEach(Array(states.enumerated()), id: \.offset) { i, state in
                    Button { player.jump(toStep: i) } label: {
                        dot(state).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: labels.progress(i + 1, states.count)))
                    .accessibilityAddTraits(state.state == .current ? .isSelected : [])
                    .accessibilityIdentifier("explain.dot.\(i)")
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(Array(states.enumerated()), id: \.offset) { _, state in dot(state) }
            }
            .frame(height: 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: labels.progress((player.currentStep ?? -1) + 1, states.count)))
            .accessibilityIdentifier("explain.dots")
        }
    }

    private func dot(_ dot: GuidedPlayer.Dot) -> some View {
        Circle()
            .fill((dot.state == .done ? palette.ink : dot.state == .current ? palette.colors(.result).fill : palette.line).color)
            .frame(width: 12, height: 12)
            .overlay {
                if dot.learnerDoes {
                    Circle().stroke(palette.colors(.result).ink.color, lineWidth: 2).frame(width: 18, height: 18)
                }
            }
    }

    // MARK: the line

    /// The line, in room for `lines` lines whatever its length, so the drawing does not change
    /// size from step to step; a longer line is set a little smaller rather than cut.
    private func lineBlock(lines: Int) -> some View {
        VStack(spacing: 4) {
            Text(captionText)
                .font(fonts.display(26))
                .foregroundStyle(palette.ink.color)
                .multilineTextAlignment(.center)
                .lineLimit(lines, reservesSpace: true)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("explain.caption")
            Text(verbatim: player.note?.display ?? " ")
                .font(fonts.body(18))
                .foregroundStyle(palette.muted.color)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: false)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("explain.note")
                .accessibilityHidden(player.note == nil)
            tallyDots
        }
    }

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

    @ViewBuilder private var tallyDots: some View {
        let t = player.tally
        HStack(spacing: 6) {
            if let t {
                let colors = palette.colors(t.op)
                ForEach(0..<t.of, id: \.self) { i in
                    Circle()
                        .fill(i < t.done ? colors.fill.color : Color.clear)
                        .overlay(Circle().stroke(colors.ink.color, lineWidth: 2))
                        .frame(width: 14, height: 14)
                }
            }
        }
        .frame(height: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: t.map { labels.tally($0.done, $0.of) } ?? ""))
        .accessibilityHidden(t == nil)
        .accessibilityIdentifier("explain.tally")
    }

    // MARK: controls

    /// The controls: in a row under the line, Again on the left and the rest on the right; in the
    /// column, Why? and Show me above Again and the large control, which go one above the other
    /// where the column is too narrow for them side by side.
    @ViewBuilder private func controls(inColumn: Bool) -> some View {
        if inColumn {
            VStack(spacing: 12) {
                if player.whyOffered || player.showMeOffered {
                    HStack(spacing: 10) { secondaryControls }
                }
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
            }
        } else {
            HStack(spacing: 12) {
                againButton
                Spacer()
                HStack(spacing: 10) {
                    secondaryControls
                    primaryButton
                }
            }
        }
    }

    /// A button beside the drawing, under the palm rule.
    private func guarded(_ control: GuidedPlayer.ColumnControl) -> PalmGuardedStyle {
        PalmGuardedStyle { [player] in player.pressBegan(control) }
    }

    private var againButton: some View {
        Button { player.press(.again) } label: {
            Label(labels.again, systemImage: "arrow.counterclockwise")
                .font(fonts.body(18))
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
        }
        .buttonStyle(guarded(.again))
        .foregroundStyle(palette.ink.color)
        .overlay(Capsule().stroke(palette.line.color, lineWidth: 1.5))
        .opacity(player.againEnabled ? 1 : 0.35)
        .disabled(!player.againEnabled)
        .accessibilityIdentifier("explain.again")
    }

    @ViewBuilder private var secondaryControls: some View {
        if player.whyOffered {
            secondary(labels.why, id: "explain.why", control: .why, pulsing: false)
        }
        if player.showMeOffered {
            secondary(labels.showMe, id: "explain.showMe", control: .showMe, pulsing: player.showMeUrged && !still)
        }
    }

    private func secondary(_ title: String, id: String, control: GuidedPlayer.ColumnControl, pulsing: Bool) -> some View {
        Button { player.press(control) } label: {
            TimelineView(.animation(paused: !pulsing)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                Text(verbatim: title)
                    .font(fonts.display(20))
                    .foregroundStyle(palette.colors(.result).ink.color)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 56)
                    .overlay(Capsule().stroke(palette.colors(.result).ink.color, lineWidth: 2))
                    .scaleEffect(pulsing ? 1 + 0.03 * (1 - cos(2 * .pi * phase)) : 1)
            }
        }
        .buttonStyle(guarded(control))
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var primaryButton: some View {
        let control = player.primaryControl
        // While the voice makes the line the control starts with, the control is shown dimmed and
        // breathes slowly instead of pulsing, and cannot be pressed; no spinner.
        let preparing = control != nil && player.gettingReady
        let pulsing = control != nil && !still && !preparing
        Button { player.press(.primary) } label: {
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
        .buttonStyle(guarded(.primary))
        .opacity(control == nil ? 0 : 1)
        .disabled(control == nil || preparing)
        .accessibilityHidden(control == nil)
        .accessibilityIdentifier("explain.primary")
    }

    @ViewBuilder private func primaryLabel(_ control: GuidedPlayer.Control) -> some View {
        switch control {
        case .watch: Label(labels.watch, systemImage: "play.fill")
        case .start: Label(labels.start, systemImage: "play.fill")
        case .watchAgain: Label(labels.watchAgain, systemImage: "arrow.counterclockwise")
        case .next: onward(labels.next)
        case .doWithMe: onward(labels.doWithMe)
        case .whatIf: onward(labels.whatIf)
        case .tryOne: onward(labels.tryOne)
        case .gotIt: onward(labels.gotIt)
        }
    }

    private func onward(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: title)
            Image(systemName: "play.fill").accessibilityHidden(true)
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
