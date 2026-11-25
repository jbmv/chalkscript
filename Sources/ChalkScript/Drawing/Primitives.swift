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
    /// An operation's fill, its ink (for lines and text), or its pale tint.
    case fill(ExplainerOperation)
    case ink(ExplainerOperation)
    case soft(ExplainerOperation)

    public func rgb(_ palette: ExplainerPalette) -> RGB {
        switch self {
        case .text: palette.ink
        case .muted: palette.muted
        case .line: palette.line
        case .pencil: palette.pencil
        case .sheet: palette.sheet
        case let .fill(op): palette.colors(op).fill
        case let .ink(op): palette.colors(op).ink
        case let .soft(op): palette.colors(op).soft
        }
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
    /// The child face (true) or the body face.
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
