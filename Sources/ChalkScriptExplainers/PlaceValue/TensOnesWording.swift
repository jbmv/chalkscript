import ChalkScript
import Foundation

/// The lines of a tens-and-ones explainer (EXP-10), one per step plus the counts, the digits
/// written, the tens and ones put together, and the answer. The app turns each into its
/// string-library entry, filled with the question's values; which entry depends on the question
/// (reading a number, or writing one) and the version.
public enum TensOnesLine: Equatable, Hashable, Sendable {
    /// Before the first step: "47. Let's find its tens and ones!" or "What number do these make?"
    case intro
    /// Ten ones are bundled into a ten (writing only).
    case bundle
    /// The tens step's line.
    case tens
    /// The ones step's line; when there are no ones, it says so.
    case ones
    /// One count, shown on the piece it counts: 10, 20 … for tens, 1, 2 … for ones.
    case tick(Int)
    /// After the tens or the ones are counted and the digit written (writing only): "4 tens."
    case written(TensOnesQuestion.Step)
    /// The total step's line: "Put them together."
    case total
    /// "40 plus 7 is 47.", as "40 + 7" becomes 47; only when there are ones.
    case join
    /// The number said on its own as the total becomes it, when there are no ones: "40."
    case number
    /// The last line, the answer emphasised: "47 is 4 tens and 7 ones!"
    case answer

    /// Every line a question's explainer can say, in the order it says them.
    public static func all(for q: TensOnesQuestion) -> [TensOnesLine] {
        var out: [TensOnesLine] = [.intro]
        for step in q.steps {
            switch step {
            case .bundle: out.append(.bundle)
            case .tens:
                out.append(.tens)
                out += TensOnesExplainer.counts(q, .tens).map { .tick($0) }
                if !q.isReading { out.append(.written(.tens)) }
            case .ones:
                out.append(.ones)
                out += TensOnesExplainer.counts(q, .ones).map { .tick($0) }
                if !q.isReading && q.ones > 0 { out.append(.written(.ones)) }
            case .total:
                out.append(.total)
                out.append(q.ones > 0 ? .join : .number)
                out.append(.answer)
            }
        }
        return out
    }
}

/// A tens-and-ones explainer's wording, from the string library, for one version (child or
/// parent).
public struct TensOnesWording: Sendable {
    public var line: @Sendable (TensOnesLine, TensOnesQuestion) -> Line
    /// Under the tens and the ones of a drawing of rectangles and squares, and under the ring
    /// round a digit: the place's name ("tens", "ones").
    public var tensLabel: String
    public var onesLabel: String
    /// The chart's headings ("Tens", "Ones").
    public var tensHeading: String
    public var onesHeading: String
    /// A digit not yet written, in its place.
    public var unknown: String
    /// The total while the ones are counted: "40 + 7".
    public var runningTotal: @Sendable (_ tens: Int, _ ones: Int) -> String

    public init(
        line: @escaping @Sendable (TensOnesLine, TensOnesQuestion) -> Line, tensLabel: String, onesLabel: String,
        tensHeading: String, onesHeading: String, unknown: String,
        runningTotal: @escaping @Sendable (_ tens: Int, _ ones: Int) -> String
    ) {
        self.line = line
        self.tensLabel = tensLabel
        self.onesLabel = onesLabel
        self.tensHeading = tensHeading
        self.onesHeading = onesHeading
        self.unknown = unknown
        self.runningTotal = runningTotal
    }
}
