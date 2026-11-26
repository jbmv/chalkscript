import ChalkScript
import Foundation

/// The watched lines of the addition explainer (EXP-10), one per step plus the counts, the
/// joining of tens and ones, and the answer. The app turns each into its wording entry,
/// filled with the problem's values.
public enum AdditionLine: Equatable, Hashable, Sendable {
    /// Before the first step: the problem, read with its operation's name ("38 plus 25").
    case intro
    case show
    case addOnes
    /// The ones looked at: ten or more make a ten, or fewer stay ones.
    case check
    /// Ten ones bundled into a new ten, and how many are left over.
    case bundle
    case addTens
    case count
    /// One count over a piece: 10, 20 for tens, then 1, 2 and on for the ones; also each one
    /// counted on as the second number's ones arrive ("9, 10, 11").
    case tick(Int)
    /// Tens and ones put together: "60 plus 3 is 63".
    case join
    /// The last line: "38 plus 25 is 63!", the answer emphasised.
    case answer

    /// Every watched line a problem's explainer can say, in the order it says them.
    public static func all(for p: AdditionProblem) -> [AdditionLine] {
        var out: [AdditionLine] = [.intro]
        for step in p.steps() {
            switch step {
            case .show: out.append(.show)
            case .addOnes:
                out.append(.addOnes)
                out += (p.firstOnes + 1...p.onesTotal).map { .tick($0) }
            case .check: out.append(.check)
            case .bundle: out.append(.bundle)
            case .addTens: out.append(.addTens)
            case .count:
                out.append(.count)
                out += AdditionExplainer.counts(p).map { .tick($0) }
                if p.sumTens > 0 && p.sumOnes > 0 { out.append(.join) }
                out.append(.answer)
            }
        }
        var seen = Set<AdditionLine>()
        return out.filter { seen.insert($0).inserted }
    }
}

/// The lines of do it with me and try one (EXP-14): the instructions, what is said once a step is
/// done, and the kind lines met by a mark the step cannot use. The app turns each into its
/// wording entry.
public enum AdditionDoLine: Equatable, Hashable, Sendable {
    /// Before the first step: "Now let's do one together: 38 plus 25."
    case intro
    /// "Add 5 ones: touch the ones side to draw each one."
    case addOnes
    /// "Ten ones make a ten. Draw a loop around ten ones."
    case bundle
    /// "Now add 2 tens: touch the tens side to draw each one."
    case addTens
    /// "Let's count them all. Touch each piece, tens first."
    case count
    /// Said once the ones are drawn, with the loop round them: how many ones there are, and,
    /// with fewer than ten, that they do not make a ten.
    case addedOnes
    /// Said once ten ones are bundled: the tens and ones there are now.
    case bundled
    /// Said once the tens are drawn.
    case addedTens
    /// A touch on the tens side while ones are drawn.
    case onesOnTensSide
    /// A touch on the ones side while tens are drawn.
    case tensOnOnesSide
    /// A touch, or a loop round no ones, where a loop round ten ones is wanted.
    case loopMissed
    /// A loop round some ones, but not ten; `n` are inside it.
    case loopHas(Int)
    /// A one touched before every ten is counted.
    case tensFirst
    /// Try one: "Now you try one: 47 plus 36."
    case tryIntro
    /// Try one, under the problem: "Your turn. Draw it, make a ten if you can, and count."
    case tryNote

    /// Every do line a problem's explainer can say.
    public static func all(for p: AdditionProblem) -> [AdditionDoLine] {
        var out: [AdditionDoLine] = [.intro, .count, .tensFirst, .tryIntro, .tryNote]
        if p.secondOnes > 0 { out += [.addOnes, .addedOnes, .onesOnTensSide] }
        if p.regroups { out += [.bundle, .bundled, .loopMissed] + (1...p.onesTotal).filter { $0 != 10 }.map { .loopHas($0) } }
        if p.secondTens > 0 { out += [.addTens, .addedTens, .tensOnOnesSide] }
        return out
    }
}

/// An addition explainer's wording. The explainer has a child version
/// only: watch, do it with me and try one.
public struct AdditionWording: Sendable {
    public var line: @Sendable (AdditionLine, AdditionProblem) -> Line
    public var doLine: @Sendable (AdditionDoLine, AdditionProblem) -> Line
    /// Under the tens and the ones.
    public var tensLabel: String
    public var onesLabel: String
    /// The answer before it is counted.
    public var unknown: String
    /// The problem with `EquationSlot` marks for the numbers ("\u{E000} + \u{E001} = \u{E002}").
    public var equation: String
    /// The running total while the ones are counted, and the worked form under the total: "60 + 3".
    public var runningTotal: @Sendable (_ tens: Int, _ ones: Int) -> String

    public init(
        line: @escaping @Sendable (AdditionLine, AdditionProblem) -> Line,
        doLine: @escaping @Sendable (AdditionDoLine, AdditionProblem) -> Line, tensLabel: String, onesLabel: String,
        unknown: String, equation: String, runningTotal: @escaping @Sendable (_ tens: Int, _ ones: Int) -> String
    ) {
        self.line = line
        self.doLine = doLine
        self.tensLabel = tensLabel
        self.onesLabel = onesLabel
        self.unknown = unknown
        self.equation = equation
        self.runningTotal = runningTotal
    }
}
