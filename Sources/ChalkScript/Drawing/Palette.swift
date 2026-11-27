import Foundation

/// An operation or a process a mark can stand for (EXP-6). Each has one colour, the same in every
/// explainer.
public enum ExplainerOperation: String, CaseIterable, Sendable {
    /// Subtract, take away. Second cue: the cross-out line, the minus sign.
    case subtract
    /// Trade, regroup. Second cue: the arrow and the box.
    case trade
    /// What is left, the answer. Second cue: the count area, the equals sign.
    case result
    /// Add, join. Second cue: a joining motion, the plus sign.
    case add
    /// Multiply, groups of. Second cue: rings around equal groups.
    case multiply
    /// Divide, share. Second cue: dealing into equal groups.
    case divide
}

/// A colour a document names for itself (EXP-20): one value for fill and ink in each appearance,
/// with the soft form derived from the ink over the sheet.
public struct DocumentColour: Hashable, Sendable {
    public var name: String
    public var light: RGB
    public var dark: RGB

    public init(name: String, light: RGB, dark: RGB) {
        self.name = name
        self.light = light
        self.dark = dark
    }

    /// The share of the ink in its soft form, over the light sheet and over the dark one.
    public static let softShare = (light: 0.16, dark: 0.18)

    /// The soft form of `ink` over `sheet`.
    public static func soft(_ ink: RGB, over sheet: RGB, dark: Bool) -> RGB {
        let a = dark ? softShare.dark : softShare.light
        return RGB(
            red: a * ink.red + (1 - a) * sheet.red, green: a * ink.green + (1 - a) * sheet.green,
            blue: a * ink.blue + (1 - a) * sheet.blue)
    }
}

/// What a colour stands for in a drawing: an operation, or a colour a document names (EXP-20).
public enum Hue: Hashable, Sendable {
    case operation(ExplainerOperation)
    case document(DocumentColour)

    public static let subtract = Hue.operation(.subtract)
    public static let trade = Hue.operation(.trade)
    public static let result = Hue.operation(.result)
    public static let add = Hue.operation(.add)
    public static let multiply = Hue.operation(.multiply)
    public static let divide = Hue.operation(.divide)

    /// The operation's name, or the document's name for the colour.
    public var rawValue: String {
        switch self {
        case let .operation(op): op.rawValue
        case let .document(c): c.name
        }
    }

    /// Its fill, ink and soft form in `palette`'s appearance.
    public func colors(in palette: ExplainerPalette) -> ExplainerPalette.OperationColors {
        switch self {
        case let .operation(op): return palette.colors(op)
        case let .document(c):
            let ink = palette.isDark ? c.dark : c.light
            return ExplainerPalette.OperationColors(
                fill: ink, ink: ink, soft: DocumentColour.soft(ink, over: palette.sheet, dark: palette.isDark))
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
    /// Whether this is the dark appearance, which a colour a document gives for each appearance
    /// is drawn by.
    public var isDark = false
    /// The profile's suggested colours (EXP-20), each as the one value it is drawn in.
    public var suggested: [String: RGB] = [:]

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
