import Foundation

/// The lines of a subtraction explainer (EXP-10), one per step plus the counts, the joining of
/// tens and ones, and the answer. The app turns each into its string-library entry, filled with
/// the problem's values.
public enum SubtractionLine: Equatable, Hashable, Sendable {
    /// Before the first step: the problem, read with its operation's name ("54 minus 26").
    case intro
    case show
    case short
    case enough
    case trade
    case takeOnes
    case takeTens
    case count
    /// One count over a piece: 10, 20 for tens, then 1, 2 and on for the ones.
    case tick(Int)
    /// Tens and ones put together: "20 plus 8 is 28".
    case join
    /// The last line: "54 minus 26 is 28!", the answer emphasised.
    case answer

    /// Every line a problem's explainer can say, in the order it says them.
    public static func all(for p: SubtractionProblem) -> [SubtractionLine] {
        var out: [SubtractionLine] = [.intro]
        for step in p.steps {
            switch step {
            case .show: out.append(.show)
            case .short: out.append(.short)
            case .enough: out.append(.enough)
            case .trade: out.append(.trade)
            case .takeOnes: out.append(.takeOnes)
            case .takeTens: out.append(.takeTens)
            case .count:
                out.append(.count)
                out += SubtractionExplainer.counts(p).map { .tick($0) }
                if p.differenceTens > 0 && p.differenceOnes > 0 { out.append(.join) }
                out.append(.answer)
            }
        }
        return out
    }
}

/// The child version's lines for do it with me and try one (EXP-14): the instructions that are
/// not the watched step's own line, what is said once a step is done, and the kind lines met by
/// a mark the step cannot use. The app turns each into its string-library entry.
public enum SubtractionDoLine: Equatable, Hashable, Sendable {
    /// Before the first step: "Now let's do one together: 54 minus 26."
    case intro
    /// Breaking a ten: "We need more ones. Break one ten: draw a line through a ten."
    case trade
    /// Counting: "Let's count what's left. Touch each piece, tens first."
    case count
    /// Said once the ten is broken: the ones there are now, and that it is enough.
    case traded
    /// Said once the ones, or the tens, are crossed out.
    case crossedOnes
    case crossedTens
    /// A touch where a line through a ten is wanted.
    case tradeTapped
    /// A line through a one where a ten is wanted.
    case tradeOnOne
    /// A line that crosses no ten.
    case tradeMissed
    /// A touch where a line across a one (or a ten) is wanted.
    case crossTapped(ones: Bool)
    /// A line across more pieces than are still to cross out; `left` are.
    case crossedTooMany(left: Int)
    /// A line across a ten while ones are crossed out, or across a one while tens are.
    case crossedTen
    case crossedOne
    /// A line that crosses nothing it can.
    case crossMissed(ones: Bool)
    /// A one touched before every ten is counted.
    case tensFirst
    /// Try one: "Now you try one: 41 minus 17."
    case tryIntro
    /// Try one, under the problem: "Your turn. Draw it, cross out, and count."
    case tryNote

    /// Every do line a problem's explainer can say.
    public static func all(for p: SubtractionProblem) -> [SubtractionDoLine] {
        var out: [SubtractionDoLine] = [.intro, .count, .tensFirst, .tryIntro, .tryNote]
        if p.regroups { out += [.trade, .traded, .tradeTapped, .tradeOnOne, .tradeMissed] }
        if p.subtrahendOnes > 0 {
            out += [.crossedOnes, .crossTapped(ones: true), .crossedTen, .crossMissed(ones: true)]
            out += (1..<max(2, p.subtrahendOnes)).map { .crossedTooMany(left: $0) }
        }
        if p.subtrahendTens > 0 {
            out += [.crossedTens, .crossTapped(ones: false), .crossedOne, .crossMissed(ones: false)]
            out += (1..<max(2, p.subtrahendTens)).map { .crossedTooMany(left: $0) }
        }
        var seen = Set<SubtractionDoLine>()
        return out.filter { seen.insert($0).inserted }
    }
}

/// Where the numbers go in the problem written across the top: the app fills its equation entry
/// with these marks, and the template puts each number, digit by digit, in its place.
public enum EquationSlot {
    public static let first = "\u{E000}"
    public static let second = "\u{E001}"
    public static let answer = "\u{E002}"
}

/// A subtraction explainer's wording, from the string library, for one version (child or
/// parent).
public struct SubtractionWording: Sendable {
    public var line: @Sendable (SubtractionLine, SubtractionProblem) -> Line
    /// Under the tens and the ones.
    public var tensLabel: String
    public var onesLabel: String
    /// The answer before it is counted.
    public var unknown: String
    /// The problem with `EquationSlot` marks for the numbers ("\u{E000} − \u{E001} = \u{E002}").
    public var equation: String
    /// The running total while the ones are counted: "20 + 8".
    public var runningTotal: @Sendable (_ tens: Int, _ ones: Int) -> String
    /// The child version's do-it-with-me and try-one lines; nil where only the watched steps
    /// are played (the parent version).
    public var doLine: (@Sendable (SubtractionDoLine, SubtractionProblem) -> Line)?

    public init(
        line: @escaping @Sendable (SubtractionLine, SubtractionProblem) -> Line, tensLabel: String,
        onesLabel: String, unknown: String, equation: String,
        runningTotal: @escaping @Sendable (_ tens: Int, _ ones: Int) -> String,
        doLine: (@Sendable (SubtractionDoLine, SubtractionProblem) -> Line)? = nil
    ) {
        self.line = line
        self.tensLabel = tensLabel
        self.onesLabel = onesLabel
        self.unknown = unknown
        self.equation = equation
        self.runningTotal = runningTotal
        self.doLine = doLine
    }
}
