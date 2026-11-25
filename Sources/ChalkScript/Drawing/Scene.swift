import CoreGraphics
import Foundation

/// One moment of an explainer's drawing: what is drawn, where and how strongly, in the scene's
/// own units: `size`, which is `Scene.stage` (1000 by 540) unless the
/// explainer has been laid out for the drawing area it is shown in (`GuidedExplainer.laidOut`,
/// EXP-17). A template computes a scene for any moment of any step; `ExplainerStage` draws it
/// with the shared components (EXP-13), scaled to fit and centred in the space it is given.
/// Plain values, so tests can read a step's picture without a screen.
public struct Scene: Equatable, Sendable {
    /// The stage's size in scene units for an explainer not laid out for its drawing area.
    public static let stage = CGSize(width: 1000, height: 540)

    public var elements: [SceneElement]
    /// The scene's size in its own units; the drawing area shows all of it, keeping its shape.
    public var size: CGSize
    /// The camera the drawing is seen through (EXP-18), or nil to draw every element as it is.
    /// With a camera, every element not `fixed` is in the drawing's own units and is mapped into
    /// the camera's viewport; a fixed one (the problem's question) stays where it is.
    public var camera: Camera?

    public init(elements: [SceneElement] = [], size: CGSize = Scene.stage, camera: Camera? = nil) {
        self.elements = elements
        self.size = size
        self.camera = camera
    }

    /// How the scene sits in a drawing area of `area` points: scaled to fit, keeping its shape,
    /// and centred (EXP-17). `scale` is points per scene unit; `origin` is where the scene's
    /// top-left corner falls in the area.
    public func fit(in area: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        guard size.width > 0, size.height > 0, area.width > 0, area.height > 0 else { return (1, .zero) }
        let s = min(area.width / size.width, area.height / size.height)
        return (s, CGPoint(x: (area.width - size.width * s) / 2, y: (area.height - size.height * s) / 2))
    }

    /// A point in a drawing area of `area` points, in the drawing's units: through the scene's
    /// fit and, when there is one, its camera, so a touch is read against the pieces as they are
    /// shown (EXP-17, EXP-18).
    public func scenePoint(_ p: CGPoint, in area: CGSize) -> CGPoint {
        p.applying(drawingTransform(in: area).inverted())
    }

    /// The elements that can be seen: not fully transparent, and with something drawn.
    public var visible: [SceneElement] { elements.filter(\.isVisible) }

    public func element(_ id: String) -> SceneElement? { elements.first { $0.id == id } }

    /// The elements whose id starts with `prefix`.
    public func elements(_ prefix: String) -> [SceneElement] { elements.filter { $0.id.hasPrefix(prefix) } }

    /// How many things are marked at this moment, to hold EXP-5's limit (at most two, three when
    /// a step compares two amounts): the marked or ringed digit; a cross-out being drawn; a
    /// trade's arrow or box being drawn; the counted pieces and their counts. A finished
    /// cross-out, arrow or box is the page's record, as on the child's own paper, and no longer a
    /// mark.
    public var markedCount: Int {
        var digit = false
        var crossing = false
        var trading = false
        var counted = false
        for e in visible {
            switch e.kind {
            case let .equation(eq): digit = digit || (eq.mark?.progress ?? 0) > 0
            case let .crossOut(_, _, p): crossing = crossing || p < 1
            case let .arrow(_, p, _), let .box(_, p, _): trading = trading || p < 1
            case let .ten(_, style), let .one(_, style), let .stick(_, style), let .circle(_, style):
                counted = counted || style == .counted
            case .numberTag: counted = true
            case let .numeral(n): digit = digit || (n.ring?.progress ?? 0) > 0
            case let .hint(_, p): digit = digit || p > 0
            default: break
            }
        }
        return [digit, crossing, trading, counted].filter { $0 }.count
    }
}

/// How a base-ten piece is drawn (EXP-6, EXP-7): in pencil on the worksheet, in the trade's ink
/// once it has come from a traded ten (or is bundled into one), and in the result's colour once
/// it is counted, in the count area or where it stands; a counted piece keeps its pale fill, so
/// what has been counted stays visible.
public enum PieceStyle: Equatable, Sendable {
    case pencil
    case traded
    case counted
}

/// One drawn thing. `id` is stable from one moment of a step to the next, so a test can follow a
/// piece through its motion.
public struct SceneElement: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: Kind
    /// 0 to 1. A ghost is drawn at the palette's `ghostOpacity`.
    public var opacity: Double
    /// Applied to the element as it is drawn: part of a picture scaled to make room (a comparison's
    /// joined bars), or moved as a whole.
    public var transform: CGAffineTransform
    /// Drawn outside the camera, where it is in the scene's own units, and never dimmed: the
    /// problem's question, which stays still while the camera moves (EXP-18).
    public var fixed: Bool

    public init(_ id: String, _ kind: Kind, opacity: Double = 1, transform: CGAffineTransform = .identity, fixed: Bool = false) {
        self.id = id
        self.kind = kind
        self.opacity = opacity
        self.transform = transform
        self.fixed = fixed
    }

    public var isVisible: Bool {
        guard opacity > 0 else { return false }
        switch kind {
        case let .crossOut(_, _, p), let .arrow(_, p, _), let .box(_, p, _), let .hint(_, p): return p > 0
        case let .shape(_, paint): return paint.fill != nil || (paint.stroke != nil && paint.progress > 0)
        case let .words(text, _): return !text.isEmpty
        case let .ink(points, _): return points.count > 1
        default: return true
        }
    }

    public enum Kind: Equatable, Sendable {
        /// A ten: the worksheet's tall rectangle (EXP-7).
        case ten(CGRect, PieceStyle)
        /// A one: the worksheet's small square.
        case one(CGRect, PieceStyle)
        /// The crossed line over a piece taken away or traded, in the subtract colour, drawn from
        /// its start to `progress` of its length.
        case crossOut(from: CGPoint, to: CGPoint, progress: Double)
        /// A trade's arrow, through `points`, drawn to `progress` of its length; the head shows
        /// once it is drawn whole.
        case arrow(points: [CGPoint], progress: Double, op: ExplainerOperation)
        /// The box a traded ten's ones go into, drawn to `progress` of its outline.
        case box(CGRect, progress: Double, op: ExplainerOperation)
        /// The dashed line that sets off the count area.
        case divider(from: CGPoint, to: CGPoint)
        /// A small label under the drawing ("tens", "ones"); `at` is its baseline's left end.
        case label(String, at: CGPoint)
        /// The problem across the top, with the digit a step acts on marked.
        case equation(EquationLine)
        /// A count said over a piece ("ten", "twenty", "one"), centred on `at`'s x, baseline `at`.
        case count(String, at: CGPoint)
        /// The running total in the count area ("20 + 8", then "28"), centred, baseline at `at`.
        case total(String, at: CGPoint, scale: Double)
        /// A ten drawn as a stick, as in a Tens | Ones chart: a line down the middle of `rect`.
        case stick(CGRect, PieceStyle)
        /// A one drawn as a circle inside `rect`.
        case circle(CGRect, PieceStyle)
        /// The number a piece is counted as, shown on the piece while it is counted: a small card
        /// in `rect`, in the result colour, grown by `scale` about its centre.
        case numberTag(String, in: CGRect, scale: Double)
        /// A number written large across the top, digit by digit, with a pencil ring round the
        /// digit a step reads.
        case numeral(Numeral)
        /// Text in the drawing other than the problem and the counts, centred on `at`'s x with its
        /// baseline at `at`.
        case text(String, at: CGPoint, style: DrawingText)
        /// A ruled line of a chart drawn on the worksheet, in pencil.
        case rule(from: CGPoint, to: CGPoint)
        /// A line the child drew (EXP-14), through `points`: in the colour of the action it was
        /// read as (a cross-out in take-away's, a broken ten in the trade's), or in pencil while
        /// it is being drawn (`op` nil).
        case ink([CGPoint], op: ExplainerOperation?)
        /// A dashed pencil loop round `rect`, drawn to `progress` of its outline: pointing at
        /// pieces a step looks at, without moving them (motion only where it carries meaning).
        case hint(CGRect, progress: Double)
        /// A dashed box in the result colour where an answer is to be written (try one).
        case target(CGRect)
        /// A shape an explainer draws itself where the shared components have none (a bar, a
        /// dashed part, a brace, a card, a ten frame), painted in palette roles (EXP-6).
        case shape(Outline, Paint)
        /// Text an explainer sets itself.
        case words(String, Typeset)
    }
}

/// The kinds of text a drawing sets besides the problem and the counts (EXP-13).
public enum DrawingText: Equatable, Sendable {
    /// A place's name under the drawing ("tens", "ones"): small, in the label colour.
    case label
    /// A chart's heading ("Tens", "Ones"): the child's face, bold, in the text colour.
    case heading
    /// A worked form under the total ("40 + 7" under 47): the child's face, in the label colour.
    case worked
    /// A problem written large for the child to try (try one): the child's face, bold.
    case problem
    /// A note under a problem to try: the child's face, in the label colour.
    case note
}

/// A number written large across the top, one digit at a time (the tens-and-ones explainers):
/// each digit is set centred on its own x, as the child writes the number, with its digits
/// together. A digit to be written has a dashed slot; the digit a step reads or writes is ringed
/// in pencil with its place's name under the ring. The ring is centred on the digit's ink as
/// drawn, not on the box the face reserves for it, or on the slot when the digit is to be
/// written there (see `Components.ringCentre`).
public struct Numeral: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        /// Printed in the problem, in the text colour.
        case printed
        /// Written as the answer, in the result colour.
        case answer
        /// Not yet written ("?"), in the label colour.
        case unknown
    }

    public struct Digit: Equatable, Sendable {
        public var text: String
        public var role: Role
        public var opacity: Double
        /// The middle of the digit's advance, as text centred on a point is set.
        public var centerX: CGFloat
        /// The dashed box the digit is written in, or nil when it is printed.
        public var slot: CGRect?

        public init(text: String, role: Role, opacity: Double = 1, centerX: CGFloat, slot: CGRect? = nil) {
            self.text = text
            self.role = role
            self.opacity = opacity
            self.centerX = centerX
            self.slot = slot
        }
    }

    /// The pencil ring round one digit, drawn to `progress` of its outline, and the place's name
    /// under it, at `wordOpacity`.
    public struct Ring: Equatable, Sendable {
        public var digit: Int
        public var progress: Double
        public var word: String
        public var wordOpacity: Double

        public init(digit: Int, progress: Double, word: String, wordOpacity: Double) {
            self.digit = digit
            self.progress = progress
            self.word = word
            self.wordOpacity = wordOpacity
        }
    }

    public var digits: [Digit]
    public var baseline: CGFloat
    public var size: Double
    public var ring: Ring?
    /// The baseline of the place's name under the ring.
    public var wordBaseline: CGFloat

    public init(digits: [Digit], baseline: CGFloat, size: Double, ring: Ring? = nil, wordBaseline: CGFloat) {
        self.digits = digits
        self.baseline = baseline
        self.size = size
        self.ring = ring
        self.wordBaseline = wordBaseline
    }

    /// The number as one string.
    public var text: String { digits.map(\.text).joined() }
}

/// The problem written across the top: runs of text, one of which may carry the digit mark
/// (EXP-5: the digit a step acts on, in the colour of its action, on a pale tint).
public struct EquationLine: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case plain
        /// The answer, in the result colour (EXP-6): "?" until it is counted.
        case answer
    }

    public struct Run: Equatable, Sendable {
        public var text: String
        public var role: Role
        public var opacity: Double

        public init(_ text: String, _ role: Role = .plain, opacity: Double = 1) {
            self.text = text
            self.role = role
            self.opacity = opacity
        }
    }

    public struct Mark: Equatable, Sendable {
        /// The run marked.
        public var run: Int
        public var op: ExplainerOperation
        /// The tint behind it grows in from 0 to 1; the digit takes the colour at once.
        public var progress: Double

        public init(run: Int, op: ExplainerOperation, progress: Double) {
            self.run = run
            self.op = op
            self.progress = progress
        }
    }

    public var runs: [Run]
    public var mark: Mark?
    /// The middle of the line's baseline.
    public var center: CGPoint
    public var size: Double

    public init(runs: [Run], mark: Mark? = nil, center: CGPoint, size: Double) {
        self.runs = runs
        self.mark = mark
        self.center = center
        self.size = size
    }

    /// The line as one string.
    public var text: String { runs.map(\.text).joined() }
}
