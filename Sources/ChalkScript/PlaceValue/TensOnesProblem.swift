import Foundation

/// How the child's assignment draws tens and ones. The explainer draws in the style of the
/// child's own page, so the problem names it (EXP-7).
public enum PlaceValueDrawing: String, CaseIterable, Sendable {
    /// A tall rectangle per ten and a small square per one, labelled "tens" and "ones" underneath.
    case blocks
    /// A stick per ten and a circle per one, in a chart headed Tens | Ones.
    case chart
}

/// The model of "47 is how many tens and ones?" (EXP-2): a two-digit number, read into its tens
/// and ones from its digits. Every number the explainer draws, shows or says is computed from it.
public struct TensOnesReading: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The numbers the template accepts: two-digit numbers.
    public static let numbers = 10...99

    public enum RangeError: Error, Equatable, Sendable {
        /// The number is not two-digit.
        case number(Int)
    }

    public let number: Int
    public let drawing: PlaceValueDrawing

    /// Refuses a number outside the template's range (EXP-2), so no explainer is offered for it.
    public init(_ number: Int, drawing: PlaceValueDrawing = .blocks) throws(RangeError) {
        guard Self.numbers.contains(number) else { throw .number(number) }
        self.number = number
        self.drawing = drawing
    }

    public static func accepts(_ number: Int) -> Bool { numbers.contains(number) }

    /// Every problem the template accepts in `drawing`, smallest first.
    public static func all(drawing: PlaceValueDrawing = .blocks) -> [TensOnesReading] {
        numbers.map { try! TensOnesReading($0, drawing: drawing) }
    }

    public var tens: Int { number / 10 }
    public var ones: Int { number % 10 }

    public var description: String { "\(number) (\(drawing.rawValue))" }
}

/// The model of "What number do these make?" (EXP-2): a drawing of tens and ones, counted and
/// written as a number. With ten or more ones, ten of them are first bundled into a ten, so up
/// to 19 ones are accepted, as long as the number made is two-digit.
public struct TensOnesWriting: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The tens drawn.
    public static let tensDrawn = 1...9
    /// The ones drawn: ten or more are bundled into a ten first.
    public static let onesDrawn = 0...19
    /// The largest number the drawing may make.
    public static let largest = 99

    public enum RangeError: Error, Equatable, Sendable {
        case tens(Int)
        case ones(Int)
        /// The tens and ones make more than 99.
        case total(Int)
    }

    /// The tens and ones drawn, before any bundling.
    public let drawnTens: Int
    public let drawnOnes: Int
    public let drawing: PlaceValueDrawing

    /// Refuses values outside the template's range (EXP-2), so no explainer is offered for them.
    public init(tens: Int, ones: Int, drawing: PlaceValueDrawing = .blocks) throws(RangeError) {
        guard Self.tensDrawn.contains(tens) else { throw .tens(tens) }
        guard Self.onesDrawn.contains(ones) else { throw .ones(ones) }
        guard tens * 10 + ones <= Self.largest else { throw .total(tens * 10 + ones) }
        self.drawnTens = tens
        self.drawnOnes = ones
        self.drawing = drawing
    }

    public static func accepts(tens: Int, ones: Int) -> Bool {
        (try? TensOnesWriting(tens: tens, ones: ones)) != nil
    }

    /// Every problem the template accepts in `drawing`, by tens and then ones.
    public static func all(drawing: PlaceValueDrawing = .blocks) -> [TensOnesWriting] {
        tensDrawn.flatMap { t in
            onesDrawn.compactMap { try? TensOnesWriting(tens: t, ones: $0, drawing: drawing) }
        }
    }

    /// Ten ones are bundled into a ten: there are ten or more.
    public var bundles: Bool { drawnOnes >= 10 }
    public var tens: Int { drawnTens + (bundles ? 1 : 0) }
    public var ones: Int { drawnOnes - (bundles ? 10 : 0) }
    public var number: Int { tens * 10 + ones }

    public var description: String { "\(drawnTens) tens \(drawnOnes) ones (\(drawing.rawValue))" }
}

/// One of the two tens-and-ones questions (one explainer per question), with the values every
/// line and picture is computed from.
public enum TensOnesQuestion: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// "47 is how many tens and ones?": the number is shown and taken apart.
    case reading(TensOnesReading)
    /// "What number do these make?": tens and ones are drawn and the number is written.
    case writing(TensOnesWriting)

    public var drawing: PlaceValueDrawing {
        switch self {
        case let .reading(p): p.drawing
        case let .writing(p): p.drawing
        }
    }

    public var isReading: Bool {
        if case .reading = self { return true }
        return false
    }

    /// The tens and ones drawn before any step (none for reading: they are drawn as they are read).
    public var drawnTens: Int {
        switch self {
        case let .reading(p): p.tens
        case let .writing(p): p.drawnTens
        }
    }

    public var drawnOnes: Int {
        switch self {
        case let .reading(p): p.ones
        case let .writing(p): p.drawnOnes
        }
    }

    /// Whether ten ones are bundled into a ten first (only when writing, with ten or more ones).
    public var bundles: Bool {
        if case let .writing(p) = self { return p.bundles }
        return false
    }

    /// The tens digit and the ones digit of the number.
    public var tens: Int {
        switch self {
        case let .reading(p): p.tens
        case let .writing(p): p.tens
        }
    }

    public var ones: Int {
        switch self {
        case let .reading(p): p.ones
        case let .writing(p): p.ones
        }
    }

    public var number: Int { tens * 10 + ones }
    /// The tens as a number: 40 for 47.
    public var tensValue: Int { tens * 10 }

    public var description: String {
        switch self {
        case let .reading(p): "reading \(p)"
        case let .writing(p): "writing \(p)"
        }
    }

    /// The steps, which depend on the values (EXP-2): a bundle only
    /// when ten or more ones are drawn; then the tens, the ones (even when there are none, to say
    /// so) and the two put together.
    public enum Step: String, CaseIterable, Sendable {
        /// Ten ones are boxed and become a new ten, in the trade colour.
        case bundle
        /// The tens digit and the tens, counted by tens.
        case tens
        /// The ones digit and the ones, counted by ones.
        case ones
        /// "40 + 7" becomes 47.
        case total
    }

    public var steps: [Step] { (bundles ? [.bundle] : []) + [.tens, .ones, .total] }
}
