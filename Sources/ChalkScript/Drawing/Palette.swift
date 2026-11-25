import Foundation

/// An operation or a process a mark can stand for (EXP-6). Each has one colour, the same in every
/// explainer.
public enum ExplainerOperation: String, CaseIterable, Sendable {
    /// Subtract, take away: `--op-sub`. Second cue: the cross-out line, the minus sign.
    case subtract
    /// Trade, regroup: `--op-trade`. Second cue: the arrow and the box.
    case trade
    /// What is left, the answer: `--op-result`. Second cue: the count area, the equals sign.
    case result
    /// Add, join: `--op-add`. Second cue: a joining motion, the plus sign.
    case add
    /// Multiply, groups of: `--op-mul`. Second cue: rings around equal groups.
    case multiply
    /// Divide, share: `--op-div`. Second cue: dealing into equal groups.
    case divide

    /// The token's name in EXP-6.
    public var token: String {
        switch self {
        case .subtract: "--op-sub"
        case .trade: "--op-trade"
        case .result: "--op-result"
        case .add: "--op-add"
        case .multiply: "--op-mul"
        case .divide: "--op-div"
        }
    }
}

/// A colour as sRGB components, 0 to 1. Plain values, so the palette can be checked without a
/// screen (contrast, the table in EXP-6).
public struct RGB: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0xD55E00` style.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// `#D55E00`.
    public var hex: String {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    public var description: String { hex }

    /// WCAG 2 relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio with `other`, 1 to 21.
    public func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The explainers' colours for one appearance (EXP-6, EXP-13): the paper and pencil the pieces
/// are drawn in, and each operation's fill, ink and pale tint. The roles are fixed; their values
/// come from a style file (`ExplainerStyle`, EXP-19), light and dark, so a palette is swapped by
/// swapping the file. A view picks one from its colour scheme and the `explainerStyle` in its
/// environment.
public struct ExplainerPalette: Equatable, Sendable {
    /// The colours of one operation.
    public struct OperationColors: Equatable, Sendable {
        /// Fills and large marks.
        public var fill: RGB
        /// Thin strokes and text: at least 3:1 against the sheet (EXP-6).
        public var ink: RGB
        /// The pale tint behind a marked digit (and, later, a word problem's relationship words).
        public var soft: RGB
    }

    /// Behind the sheet.
    public var paper: RGB
    /// The sheet the drawing is on.
    public var sheet: RGB
    /// Text.
    public var ink: RGB
    /// Labels ("tens", "ones").
    public var muted: RGB
    /// Rules, the divider, unfilled progress dots.
    public var line: RGB
    /// Pencil pieces: base-ten pieces are pencil, never coloured by place (EXP-6).
    public var pencil: RGB
    /// Text on a filled result-coloured control.
    public var onResult: RGB
    public var operations: [ExplainerOperation: OperationColors]

    public func colors(_ op: ExplainerOperation) -> OperationColors { operations[op]! }

    /// The palette for a dark or light appearance, from the bundled style (EXP-19).
    public static func `for`(dark: Bool) -> ExplainerPalette { ExplainerStyle.standard.palette(dark: dark) }

    /// EXP-6's light values, as the bundled style file (`Resources/style.json`) gives them: add,
    /// multiply and divide use one value for fill and ink, chosen so every pair of operation
    /// colours stays apart under simulated colour-vision deficiency, and their tints are the ink
    /// at 16% over the sheet.
    public static var light: ExplainerPalette { ExplainerStyle.standard.light }

    /// EXP-6's dark values (one value for fill and ink), as the bundled style file gives them;
    /// the add, multiply and divide tints are the colour at 18% over the sheet.
    public static var dark: ExplainerPalette { ExplainerStyle.standard.dark }

    /// The colour of a role (EXP-6).
    public func rgb(_ ink: Ink) -> RGB { ink.rgb(self) }
}
