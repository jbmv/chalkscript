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

/// How the explainer screen is arranged in the space it is given (EXP-17), chosen by that space,
/// never by the device, so it works on every iPad and in a window of any size.
enum ScreenArrangement: Equatable {
    /// Taller than wide: the parts and dots, the question, the drawing in the middle, then the
    /// line and the controls at the bottom.
    case portrait
    /// Wider than tall: one column of `width` on the writing hand's side (`onLeft` for a
    /// left-handed learner) holds the parts and dots, the question, the line and the controls; the
    /// drawing has the rest of the width at full height.
    case column(width: CGFloat, onLeft: Bool)
    /// Too little height for the drawing (a phone in landscape): the portrait arrangement, which
    /// scrolls.
    case scroll

    /// Less height than this, and the screen scrolls rather than shrink the drawing further.
    static let scrollBelow: CGFloat = 400
    /// The column is never narrower than this, so the controls fit in it side by side.
    static let minColumn: CGFloat = 340
    /// Nor wider than this share of the width.
    static let maxColumnShare: CGFloat = 0.45

    static func choose(for size: CGSize, hand: WritingHand) -> ScreenArrangement {
        if size.height < scrollBelow { return .scroll }
        guard size.width > size.height else { return .portrait }
        // The drawing about square: the column takes what the height leaves of the width.
        let width = min(max(size.width - size.height, minColumn), size.width * maxColumnShare)
        return .column(width: width.rounded(), onLeft: hand == .left)
    }
}

/// The explainer screen's layout (EXP-17), shared by the child version (`GuidedView`) and the
/// watched steps (`ExplainerView`): the card, arranged for the space it is given. The drawing is
/// the one flexible part; it is given all the space the rest leave, and the explainer lays its
/// picture out for that space or is scaled to fit and centred in it.
struct ScreenLayout<Header: View, Question: View, Drawing: View, LineBlock: View, Controls: View>: View {
    let hand: WritingHand
    /// Whether there is a question to show apart from the drawing; with none, its area takes no
    /// space.
    let hasQuestion: Bool
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
            switch ScreenArrangement.choose(for: geo.size, hand: hand) {
            case .scroll:
                ScrollView {
                    portrait(drawingHeight: geo.size.width * Scene.stage.height / Scene.stage.width)
                }
            case .portrait:
                portrait(drawingHeight: nil)
                    .frame(width: geo.size.width, height: geo.size.height)
            case let .column(width, onLeft):
                sideBySide(column: width, onLeft: onLeft)
                    .frame(width: geo.size.width, height: geo.size.height)
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
    private func portrait(drawingHeight: CGFloat?) -> some View {
        card(
            VStack(spacing: 8) {
                header(false)
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
                    .padding(.horizontal, 26)
                controls(false)
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
