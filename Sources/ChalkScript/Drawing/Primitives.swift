import CoreGraphics
import Foundation

/// A colour by its role in the palette (EXP-6), so an explainer's own shapes keep the colour
/// rules in light and dark: a shape is never given a raw colour.
public enum Ink: Hashable, Sendable {
    /// The text colour.
    case text
    /// Labels and notes.
    case muted
    /// Rules, card edges, empty dots.
    case line
    /// Worksheet pieces drawn in pencil.
    case pencil
    /// The drawing's sheet, and the fill of an empty piece.
    case sheet
    /// A hue's fill, its ink (for lines and text), or its pale tint.
    case fill(Hue)
    case ink(Hue)
    case soft(Hue)

    public func rgb(_ palette: ExplainerPalette) -> RGB {
        switch self {
        case .text: palette.ink
        case .muted: palette.muted
        case .line: palette.line
        case .pencil: palette.pencil
        case .sheet: palette.sheet
        case let .fill(hue): hue.colors(in: palette).fill
        case let .ink(hue): hue.colors(in: palette).ink
        case let .soft(hue): hue.colors(in: palette).soft
        }
    }
}

/// A curve of an ellipse: the points `[cx + rx * sin t, cy - ry * cos t]` for `t` from `from` to
/// `to`, in degrees clockwise from twelve, so that `from` 0 to 180 is the right half of a circle
/// and `from` 270 to -90 a whole circle drawn anticlockwise from nine o'clock. A negative radius
/// mirrors the curve on its axis. `to - from` is at most 360 in magnitude.
public struct Arc: Equatable, Sendable {
    public var centre: CGPoint
    public var rx: Double
    public var ry: Double
    public var from: Double
    public var to: Double

    public init(centre: CGPoint, rx: Double, ry: Double, from: Double, to: Double) {
        self.centre = centre
        self.rx = rx
        self.ry = ry
        self.from = from
        self.to = to
    }

    /// The most a piece of the curve may sweep when it is drawn as a Bézier curve, which keeps the
    /// curve within a ten-thousandth of its radius.
    static let pieceSweep = 45.0

    public var start: CGPoint { point(at: from) }
    public var end: CGPoint { point(at: to) }

    /// The curve's point at angle `t`, with the exact sine and cosine of the format's reference at
    /// multiples of 30 degrees.
    public func point(at t: Double) -> CGPoint {
        CGPoint(x: centre.x + rx * Evaluator.trigonometric(true, degrees: t), y: centre.y - ry * Evaluator.trigonometric(false, degrees: t))
    }

    /// The curve as cubic Bézier curves of at most `pieceSweep` degrees each, joined end to end,
    /// from `start` to `end`.
    public var curves: [(to: CGPoint, control1: CGPoint, control2: CGPoint)] {
        let sweep = to - from
        guard sweep != 0 else { return [] }
        let n = Int((abs(sweep) / Self.pieceSweep).rounded(.up))
        let step = sweep / Double(n)
        // The point's rate of change per radian, which a Bézier curve's control points follow.
        func slope(_ t: Double) -> CGPoint {
            CGPoint(x: rx * Evaluator.trigonometric(false, degrees: t), y: ry * Evaluator.trigonometric(true, degrees: t))
        }
        let k = 4.0 / 3.0 * tan(step * Double.pi / 180 / 4)
        return (0..<n).map { i in
            let a = from + step * Double(i)
            let b = i == n - 1 ? to : a + step
            let p = point(at: a)
            let q = point(at: b)
            let da = slope(a)
            let db = slope(b)
            return (q, CGPoint(x: p.x + k * da.x, y: p.y + k * da.y), CGPoint(x: q.x - k * db.x, y: q.y - k * db.y))
        }
    }

    /// The box round the curve, with its extreme points as well as its ends, after the curve is
    /// turned by `degrees` clockwise about `pivot` (not turned when 0).
    public func box(turned degrees: Double = 0, about pivot: CGPoint = .zero) -> CGRect {
        func place(_ t: Double) -> CGPoint {
            let p = point(at: t)
            return degrees == 0 ? p : Turning.turn(p, by: degrees, about: pivot)
        }
        // After the turn, x and y are each a constant plus u sin t + v cos t, which is most or
        // least where t is atan2(u, v) or half a turn from it.
        let s = degrees == 0 ? 0 : Evaluator.trigonometric(true, degrees: degrees)
        let c = degrees == 0 ? 1 : Evaluator.trigonometric(false, degrees: degrees)
        var candidates = [from, to]
        let lo = min(from, to)
        let hi = max(from, to)
        for (u, v) in [(rx * c, ry * s), (rx * s, -ry * c)] {
            let t = atan2(u, v) * 180 / Double.pi
            for base in [t, t + 180] {
                let exact = (base * 1e9).rounded() / 1e9
                var k = ((lo - exact) / 360).rounded(.up)
                while exact + 360 * k <= hi + 1e-9 {
                    candidates.append(exact + 360 * k)
                    k += 1
                }
            }
        }
        let points = candidates.map(place)
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

/// The outline of a shape an explainer draws itself, in scene units.
public enum Outline: Equatable, Sendable {
    case rect(CGRect, corner: CGFloat = 0)
    case ellipse(CGRect)
    /// Straight lines through `points`, closed back to the first when `closed`.
    case lines([CGPoint], closed: Bool = false)
    /// A path of segments, for curves such as a brace.
    case path([Segment])

    public enum Segment: Equatable, Sendable {
        case move(CGPoint)
        case line(CGPoint)
        /// An arc from its start, which is the point before it (a `line` to it comes first).
        case arc(Arc)
        case quad(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case close
    }
}

/// How a shape is painted: a fill, a stroke, both. `progress` draws the stroke on from its start
/// (a line being drawn).
public struct Paint: Equatable, Sendable {
    public var fill: Ink?
    public var stroke: Ink?
    public var width: CGFloat
    public var dash: [CGFloat]
    public var progress: Double

    public init(fill: Ink? = nil, stroke: Ink? = nil, width: CGFloat = Components.pencilWidth, dash: [CGFloat] = [], progress: Double = 1) {
        self.fill = fill
        self.stroke = stroke
        self.width = width
        self.dash = dash
        self.progress = progress
    }
}

/// Text an explainer sets itself: where, how large, in which face and colour, anchored at
/// `at` by its baseline's left end, middle or right end.
public struct Typeset: Equatable, Sendable {
    public enum Anchor: Equatable, Sendable { case leading, center, trailing }

    public var at: CGPoint
    public var size: Double
    public var ink: Ink
    /// The display face (true) or the body face.
    public var display: Bool
    public var anchor: Anchor

    public init(at: CGPoint, size: Double, ink: Ink = .text, display: Bool = true, anchor: Anchor = .center) {
        self.at = at
        self.size = size
        self.ink = ink
        self.display = display
        self.anchor = anchor
    }
}
