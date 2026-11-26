import SwiftUI

/// The hand a learner writes with (EXP-17). It chooses the side of the column in landscape: the
/// side the writing hand's palm covers while it writes on the drawing. Right by default. The app
/// passes the learner's setting; the player's views take it as `hand`.
public enum WritingHand: String, CaseIterable, Sendable {
    case right
    case left
}

/// The palm rule for the controls beside the drawing (EXP-17): while a touch is on the
/// drawing (the Pencil, or a finger, writing) and for `quiet` after it lifts, a press on a control
/// does nothing; nor does a press that began then and ended later, as a palm resting on a control
/// does.
@MainActor
public final class PalmGuard {
    /// How long after a touch on the drawing lifts the controls still ignore presses.
    public static let quiet: Double = 1.0

    /// A touch with no sign of life (no `penDown` since) for this long is taken to have ended
    /// without telling us (a gesture cancelled by a sheet or a system gesture), so the rule can
    /// never be held by a touch that is gone. Moving touches renew it.
    public static let stuckAfter: Double = 20

    /// The clock, in seconds; tests set their own.
    var now: @MainActor () -> Double
    private var down = false
    private var downAt = -Double.infinity
    private var liftedAt = -Double.infinity
    private var voided: Set<String> = []

    public init() {
        let start = ContinuousClock.now
        now = {
            let d = start.duration(to: .now)
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
    }

    /// A touch on the drawing begins.
    public func penDown() {
        down = true
        downAt = now()
    }

    /// The touch on the drawing lifts.
    public func penUp() {
        down = false
        liftedAt = now()
    }

    /// Whether a press on a control is ignored now.
    public var holds: Bool { (down && now() - downAt < Self.stuckAfter) || now() - liftedAt < Self.quiet }

    /// A touch on control `id` begins. If the rule holds now, the press presses nothing, even if
    /// it ends after the rule has let go.
    public func pressBegan(_ id: String) {
        if holds { voided.insert(id) } else { voided.remove(id) }
    }

    /// A press on control `id` ends: whether it does what the control does.
    public func accepts(_ id: String) -> Bool {
        let void = voided.remove(id) != nil
        return !void && !holds
    }
}

/// A control beside the drawing: tells the palm rule when a touch on it begins, and draws its
/// label as the plain style does.
struct PalmGuardedStyle: ButtonStyle {
    let began: @MainActor () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { began() }
            }
    }
}

/// How the explainer screen is arranged round its drawing (EXP-17). The arrangement is the
/// app's choice, not the document's; the app passes it to `ExplainerView` or `GuidedView`.
public enum ScreenArrangement: String, CaseIterable, Sendable {
    /// Chosen by the space, never by the device: the caption below the drawing in a space taller
    /// than wide, beside it in a wider one.
    case automatic
    /// The parts and dots above the drawing, and the line and the controls below it, in any space.
    case captionBelow
    /// One column on the writing hand's side, holding the parts and dots, the question, the line
    /// and the controls, beside the drawing at full height, in any space.
    case captionBeside
}

/// The arrangement the screen takes in the space it is given (EXP-17).
enum ScreenPlan: Equatable {
    /// Top to bottom: the parts and dots, the question, the drawing in the middle, then the line
    /// and the controls.
    case stacked
    /// One column of `width` on the writing hand's side (`onLeft` for a left-handed learner)
    /// holds the parts and dots, the question, the line and the controls; the drawing has the rest
    /// of the width at full height.
    case column(width: CGFloat, onLeft: Bool)
    /// Too little height for the drawing (a phone in landscape): the stacked arrangement, with the
    /// drawing at the stage's shape, which scrolls.
    case scroll
    /// Too little height for the drawing, with the caption beside it: the column arrangement at a
    /// height of `scrollBelow`, which scrolls.
    case scrollingColumn(width: CGFloat, onLeft: Bool)

    /// Less height than this, and the screen scrolls rather than shrink the drawing further.
    static let scrollBelow: CGFloat = 400
    /// The column is never narrower than this, so the controls fit in it side by side.
    static let minColumn: CGFloat = 340
    /// Nor wider than this share of the width.
    static let maxColumnShare: CGFloat = 0.45

    /// The heights of the bands above and below the drawing in the stacked arrangement. They are
    /// fixed, so the drawing area is known before the screen is laid out; what is in a band is
    /// set smaller rather than cut.
    static let headerBand: CGFloat = 44
    static let controlsBand: CGFloat = 64
    /// The watched steps' line: three lines of the display face at 26 points.
    static let captionBand: CGFloat = 90
    /// The height the stacked arrangement of the watched steps takes besides the drawing: the
    /// bands, the gaps between the parts and the card's margins.
    static let stackedChrome: CGFloat = 14 + headerBand + 8 + 8 + captionBand + 8 + controlsBand + 18

    static func choose(for size: CGSize, hand: WritingHand, arrangement: ScreenArrangement = .automatic) -> ScreenPlan {
        let onLeft = hand == .left
        switch arrangement {
        case .automatic:
            if size.height < scrollBelow { return .scroll }
            return size.width > size.height ? .column(width: columnWidth(for: size), onLeft: onLeft) : .stacked
        case .captionBelow:
            return size.height < scrollBelow ? .scroll : .stacked
        case .captionBeside:
            guard size.height < scrollBelow else { return .column(width: columnWidth(for: size), onLeft: onLeft) }
            let laidOut = CGSize(width: size.width, height: scrollBelow)
            return .scrollingColumn(width: columnWidth(for: laidOut), onLeft: onLeft)
        }
    }

    /// The drawing about square where it can be: the column takes what the height leaves of the
    /// width, within its bounds.
    static func columnWidth(for size: CGSize) -> CGFloat {
        min(max(size.width - size.height, minColumn), size.width * maxColumnShare).rounded()
    }
}

/// The explainer screen's layout (EXP-17), shared by the child version (`GuidedView`) and the
/// watched steps (`ExplainerView`): the card, in the app's arrangement for the space it is given.
/// The drawing is the one flexible part; it is given all the space the rest leave, and the
/// explainer lays its picture out for that space or is scaled to fit and centred in it.
struct ScreenLayout<Header: View, Question: View, Drawing: View, LineBlock: View, Controls: View>: View {
    let hand: WritingHand
    let arrangement: ScreenArrangement
    /// Whether there is a question to show apart from the drawing; with none, its area takes no
    /// space.
    let hasQuestion: Bool
    /// The height of the line's band in the stacked arrangement; nil is the line's own height.
    let captionBand: CGFloat?
    /// The parts strip and the dots: `true` when they are in the column.
    @ViewBuilder let header: (_ inColumn: Bool) -> Header
    @ViewBuilder let question: () -> Question
    @ViewBuilder let drawing: () -> Drawing
    /// The line, in room for `lines` lines.
    @ViewBuilder let line: (_ lines: Int) -> LineBlock
    /// The controls: `true` when they are in the column.
    @ViewBuilder let controls: (_ inColumn: Bool) -> Controls

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.explainerStyle) private var style

    private var palette: ExplainerPalette { style.palette(dark: colorScheme == .dark) }

    var body: some View {
        GeometryReader { geo in
            switch ScreenPlan.choose(for: geo.size, hand: hand, arrangement: arrangement) {
            case .scroll:
                ScrollView {
                    stacked(drawingHeight: geo.size.width * Scene.stage.height / Scene.stage.width)
                }
            case .stacked:
                stacked(drawingHeight: nil)
                    .frame(width: geo.size.width, height: geo.size.height)
            case let .column(width, onLeft):
                sideBySide(column: width, onLeft: onLeft)
                    .frame(width: geo.size.width, height: geo.size.height)
            case let .scrollingColumn(width, onLeft):
                ScrollView {
                    sideBySide(column: width, onLeft: onLeft)
                        .frame(width: geo.size.width, height: ScreenPlan.scrollBelow)
                }
            }
        }
    }

    private func card(_ content: some View) -> some View {
        content
            .background(palette.sheet.color)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(palette.line.color, lineWidth: 1.5))
    }

    /// Top to bottom: the parts and dots, the question, the drawing, the line and the controls.
    private func stacked(drawingHeight: CGFloat?) -> some View {
        card(
            VStack(spacing: 8) {
                header(false)
                    .frame(height: ScreenPlan.headerBand)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                if hasQuestion {
                    question()
                        .padding(.horizontal, 20)
                }
                drawing()
                    .frame(maxWidth: .infinity)
                    .frame(height: drawingHeight)
                    .frame(maxHeight: drawingHeight == nil ? .infinity : nil)
                line(3)
                    .frame(height: captionBand)
                    .padding(.horizontal, 26)
                controls(false)
                    .frame(height: ScreenPlan.controlsBand)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            })
    }

    /// The column on the writing hand's side, and the drawing at full height beside it.
    private func sideBySide(column width: CGFloat, onLeft: Bool) -> some View {
        let column = VStack(spacing: 12) {
            header(true)
            if hasQuestion { question() }
            Spacer(minLength: 8)
            line(5)
            controls(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("explain.column")
        let picture = drawing()
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let rule = Rectangle().fill(palette.line.color).frame(width: 1.5)
        return card(
            HStack(spacing: 0) {
                if onLeft {
                    column
                    rule
                    picture
                } else {
                    picture
                    rule
                    column
                }
            })
    }
}

/// What the engine's screen gives the drawing (EXP-17), for an app that wants to know before it
/// lays anything out.
public enum ExplainerScreen {
    /// The drawing area `ExplainerView` gives for a space of `size` points, the writing `hand`
    /// and the `arrangement`: with the caption below, the space less the fixed bands above and
    /// below the drawing; with it beside, the space the drawing has beside the column, less its
    /// padding; the stage's shape where the screen scrolls with the caption below. Nil for an
    /// empty space. The child version (`GuidedView`) gives less with the caption below where it
    /// shows a question, and its line, with a hint and a tally, is taller.
    public static func drawingArea(
        for size: CGSize, hand: WritingHand = .right, arrangement: ScreenArrangement = .automatic
    ) -> CGSize? {
        guard size.width > 0, size.height > 0 else { return nil }
        // The column, the rule beside it, and the drawing's padding of 12 on each side.
        func beside(_ column: CGFloat, height: CGFloat) -> CGSize {
            CGSize(width: max(size.width - column - 1.5 - 24, 0), height: height - 24)
        }
        return switch ScreenPlan.choose(for: size, hand: hand, arrangement: arrangement) {
        case .scroll: CGSize(width: size.width, height: size.width * Scene.stage.height / Scene.stage.width)
        case .stacked: CGSize(width: size.width, height: size.height - ScreenPlan.stackedChrome)
        case let .column(width, _): beside(width, height: size.height)
        case let .scrollingColumn(width, _): beside(width, height: ScreenPlan.scrollBelow)
        }
    }
}
