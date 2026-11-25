import Foundation

/// The lines of the make-a-ten explainer's watched steps (EXP-10), one per step plus the counts
/// and the answer. The app turns each into its string-library entry, filled with the problem's
/// values.
public enum MakeTenLine: Equatable, Hashable, Sendable {
    /// Before the first step: the problem, read with its operation's name ("8 plus 7").
    case intro
    case show
    case need
    case split
    case move
    case count
    /// One count: the empty boxes touched (1, 2), the top frame filling as dots arrive (9, 10),
    /// and the count on from ten (10, 11 …).
    case tick(Int)
    /// The last line: "10 plus 5 is 15. So 8 plus 7 is 15!", the answer emphasised.
    case answer

    /// Every line a problem's explainer can say, watched or done, in the order it says them.
    public static func all(for p: MakeTenProblem) -> [MakeTenLine] {
        var out: [MakeTenLine] = [.intro, .show, .need]
        out += (1...p.need).map { .tick($0) }
        out += [.split, .move]
        out += (p.big + 1...10).map { .tick($0) }
        out.append(.count)
        out += (10...p.sum).map { .tick($0) }
        out.append(.answer)
        var seen = Set<MakeTenLine>()
        return out.filter { seen.insert($0).inserted }
    }
}

/// The child version's lines for do it with me and try one (EXP-14): the instructions that are
/// not the watched step's own line, what is said once a step is done, and the kind lines met by a
/// mark the step cannot use. The app turns each into its string-library entry.
public enum MakeTenDoLine: Equatable, Hashable, Sendable {
    /// Before the first step: "Now let's do one together: 8 plus 7."
    case intro
    /// Touching the empty boxes: "How many more does 8 need to make ten? Touch each empty box."
    case need
    /// Dragging: "Drag 2 dots up into the empty boxes." (one dot, one box, when one is needed).
    case move
    /// Counting: "Count them: touch the full ten frame, then each dot left."
    case count
    /// Said once the empty boxes are touched: "8 needs 2 more."
    case needDone
    /// Said once the ten is made: "8 and 2 make 10!"
    case moved
    /// A touch outside the top ten frame while its empty boxes are touched.
    case touchEmpty
    /// A touch on a box that has a dot.
    case boxHasDot
    /// A dot let go outside the top ten frame: it goes back.
    case dropInBox
    /// A dot left touched before the full ten frame is counted.
    case tenFirst
    /// Try one: "Now you try one: 6 plus 9."
    case tryIntro
    /// Try one, under the problem: "Your turn. Make a ten first, then add what is left."
    case tryNote

    /// Every do line a problem's explainer can say.
    public static func all(for p: MakeTenProblem) -> [MakeTenDoLine] {
        [.intro, .need, .move, .count, .needDone, .moved, .touchEmpty, .boxHasDot, .dropInBox, .tenFirst, .tryIntro, .tryNote]
    }
}

/// The make-a-ten explainer's wording, from the string library. It has the child version only:
/// parent wording is a later piece of work (EXP-9).
public struct MakeTenWording: Sendable {
    public var line: @Sendable (MakeTenLine, MakeTenProblem) -> Line
    public var doLine: @Sendable (MakeTenDoLine, MakeTenProblem) -> Line
    /// The answer before it is counted.
    public var unknown: String
    /// The problem with `EquationSlot` marks for the numbers ("\u{E000} + \u{E001} = \u{E002}").
    public var equation: String
    /// A worked line under the number bond: "8 + 2 = 10", "10 + 5 = 15".
    public var sum: @Sendable (_ a: Int, _ b: Int, _ total: Int) -> String
    /// The count on from ten while the dots left are counted: "10 + 3".
    public var partial: @Sendable (_ a: Int, _ b: Int) -> String

    public init(
        line: @escaping @Sendable (MakeTenLine, MakeTenProblem) -> Line,
        doLine: @escaping @Sendable (MakeTenDoLine, MakeTenProblem) -> Line,
        unknown: String, equation: String,
        sum: @escaping @Sendable (_ a: Int, _ b: Int, _ total: Int) -> String,
        partial: @escaping @Sendable (_ a: Int, _ b: Int) -> String
    ) {
        self.line = line
        self.doLine = doLine
        self.unknown = unknown
        self.equation = equation
        self.sum = sum
        self.partial = partial
    }
}
