import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

/// Synthetic wording for the package's tests, shaped like a consuming app's wording
/// entries. The app's own tests check the real entries.
enum Fixture {
    static func wording(_ version: ExplainerVersion = .child) -> SubtractionWording {
        SubtractionWording(
            line: { l, p in
                let display: String =
                    switch l {
                    case .intro: "\(p.minuend) minus \(p.subtrahend). Let's see how!"
                    case .show: "This is \(p.minuend)."
                    case .short: "We need to take away \(p.subtrahendOnes) ones. But we only have \(p.minuendOnes)!"
                    case .enough: "We have \(p.minuendOnes). That's enough!"
                    case .trade: "Now we have \(p.onesAfterTrade) ones!"
                    case .takeOnes: "Cross out \(p.subtrahendOnes) ones."
                    case .takeTens: "Now cross out \(p.subtrahendTens) tens."
                    case .count: "Let's count what's left."
                    case let .tick(n): "\(n)"
                    case .join: "\(p.differenceTens * 10) plus \(p.differenceOnes) is \(p.difference)."
                    case .answer: "\(p.minuend) minus \(p.subtrahend) is \(p.difference)!"
                    }
                return Line(
                    key: "explain.test.\(version.rawValue).\(l)", display: display,
                    spoken: NumberWords.replacingNumerals(in: display),
                    emphasis: l == .answer ? String(p.difference) : nil)
            },
            tensLabel: "tens", onesLabel: "ones", unknown: "?",
            equation: "\(EquationSlot.first) − \(EquationSlot.second) = \(EquationSlot.answer)",
            runningTotal: { "\($0) + \($1)" })
    }

    static func explainer(_ a: Int, _ b: Int, _ version: ExplainerVersion = .child) -> SubtractionExplainer {
        SubtractionExplainer(problem: try! SubtractionProblem(a, minus: b), version: version, wording: wording(version))
    }

    /// The range's edges and three other problems (EXP-2): smallest and largest, with
    /// and without a trade, nothing left, only tens or only ones left, a one-digit number taken
    /// away, and the widest count area.
    static let edges: [(Int, Int)] = [
        (10, 1), (10, 9), (10, 10), (11, 1), (19, 9), (20, 1), (20, 11), (50, 20), (54, 26), (83, 12),
        (44, 5), (90, 89), (91, 9), (98, 20), (99, 1), (99, 9), (99, 10), (99, 90), (99, 98), (99, 99),
    ]
}

/// Synthetic wording for the tens-and-ones explainers, shaped like the app's entries.
/// The app's own tests check the real entries.
enum PlaceValueFixture {
    static func wording(_ version: ExplainerVersion = .child) -> TensOnesWording {
        TensOnesWording(
            line: { l, q in
                func tens(_ n: Int) -> String { n == 1 ? "1 ten" : "\(n) tens" }
                func ones(_ n: Int) -> String { n == 1 ? "1 one" : "\(n) ones" }
                let display: String =
                    switch (l, q.isReading) {
                    case (.intro, true): "\(q.number). Let's find its tens and ones!"
                    case (.intro, false): "What number do these make? Let's see!"
                    case (.bundle, _): "We have \(q.drawnOnes) ones. Ten ones make a ten!"
                    case (.tens, true): "The \(q.tens) is in the tens place. It means \(tens(q.tens))."
                    case (.tens, false): "Count the tens."
                    case (.ones, true): q.ones > 0
                        ? "The \(q.ones) is in the ones place. It means \(ones(q.ones))."
                        : "The \(q.ones) is in the ones place. It means no ones."
                    case (.ones, false): q.ones > 0 ? "Count the ones." : "There are no ones, so we write \(q.ones) in the ones place."
                    case let (.tick(n), _): "\(n)"
                    case (.written(.tens), _): "\(tens(q.tens))."
                    case (.written, _): "\(ones(q.ones))."
                    case (.total, _): "Put them together."
                    case (.join, _): "\(q.tensValue) plus \(q.ones) is \(q.number)."
                    case (.number, _): "\(q.number)."
                    case (.answer, true): "\(q.number) is \(tens(q.tens)) and \(ones(q.ones))!"
                    case (.answer, false): "\(tens(q.tens)) and \(ones(q.ones)) make \(q.number)!"
                    }
                return Line(
                    key: "explain.test.\(version.rawValue).\(l)", display: display,
                    spoken: NumberWords.replacingNumerals(in: display),
                    emphasis: l == .answer ? String(q.number) : nil)
            },
            tensLabel: "tens", onesLabel: "ones", tensHeading: "Tens", onesHeading: "Ones", unknown: "?",
            runningTotal: { "\($0) + \($1)" })
    }

    static func reading(_ n: Int, _ drawing: PlaceValueDrawing = .blocks, _ version: ExplainerVersion = .child) -> TensOnesExplainer {
        TensOnesExplainer(reading: try! TensOnesReading(n, drawing: drawing), version: version, wording: wording(version))
    }

    static func writing(_ t: Int, _ o: Int, _ drawing: PlaceValueDrawing = .blocks, _ version: ExplainerVersion = .child) -> TensOnesExplainer {
        TensOnesExplainer(writing: try! TensOnesWriting(tens: t, ones: o, drawing: drawing), version: version, wording: wording(version))
    }

    /// Every question both templates accept, in both drawings.
    static var all: [TensOnesQuestion] {
        PlaceValueDrawing.allCases.flatMap { d in
            TensOnesReading.all(drawing: d).map(TensOnesQuestion.reading) + TensOnesWriting.all(drawing: d).map(TensOnesQuestion.writing)
        }
    }

    /// The range's edges and other examples (EXP-2): smallest and largest, a zero ones
    /// digit, one ten and one one, and when writing: no ones, exactly ten ones, the most ones,
    /// and a bundle that makes 99 or a round number.
    static let readingEdges = [10, 11, 19, 20, 40, 47, 90, 99]
    static let writingEdges: [(Int, Int)] = [(1, 0), (1, 1), (1, 9), (1, 10), (1, 19), (3, 5), (4, 7), (4, 0), (3, 13), (8, 19), (9, 0), (9, 9), (5, 10)]

    static var edges: [TensOnesExplainer] {
        PlaceValueDrawing.allCases.flatMap { d in
            readingEdges.map { reading($0, d) } + writingEdges.map { writing($0.0, $0.1, d) }
        }
    }
}

// MARK: the child version

extension Fixture {
    /// The learner's wording with synthetic do-it-with-me lines.
    static func guidedWording() -> SubtractionWording {
        var w = wording(.child)
        w.doLine = { l, p in
            let display: String =
                switch l {
                case .intro: "Now let's do one together: \(p.minuend) minus \(p.subtrahend)."
                case .trade: "Break one ten."
                case .count: "Touch each piece, tens first."
                case .traded: "Now we have \(p.onesAfterTrade) ones."
                case .crossedOnes: "\(p.subtrahendOnes) ones crossed out."
                case .crossedTens: "\(p.subtrahendTens) tens crossed out."
                case .tradeTapped: "Draw a line through a ten."
                case .tradeOnOne: "That's a one."
                case .tradeMissed: "Draw a line right through a ten."
                case let .crossTapped(ones): "Draw a line across a \(ones ? "one" : "ten")."
                case let .crossedTooMany(left): "Cross out \(left) more."
                case .crossedTen: "That's a ten."
                case .crossedOne: "That's a one, not a ten."
                case let .crossMissed(ones): "Draw a line right across a \(ones ? "one" : "ten")."
                case .tensFirst: "Tens first."
                case .tryIntro: "Now you try one: \(p.minuend) minus \(p.subtrahend)."
                case .tryNote: "Your turn."
                }
            return Line(key: "explain.test.do.\(l)", display: display, spoken: NumberWords.replacingNumerals(in: display))
        }
        return w
    }

    static let guidedLabels = GuidedLabels(
        watch: "Watch", start: "Start", next: "Next", doWithMe: "Do it with me", whatIf: "What if?", tryOne: "Try one",
        watchAgain: "Watch again", again: "Again", showMe: "Show me", why: "Why?", gotIt: "Got it",
        orShowMe: Line(key: "explain.test.orShowMe", display: "Or tap Show me.", spoken: "Or tap Show me."),
        progress: { "Step \($0) of \($1)" }, tally: { "\($0) of \($1)" })
}


/// A voice that records each line and finishes only when the test says.
@MainActor
final class RecordingVoice: ExplainerVoice {
    var said: [Line] = []
    var stops = 0
    private var pending: [@MainActor () -> Void] = []
    var busy: Bool { !pending.isEmpty }
    /// When true, every line finishes as soon as it is said.
    var instant = false

    func say(_ line: Line, onFinish: @escaping @MainActor () -> Void) {
        #expect(pending.isEmpty, "a line was sent while another was still being said")
        said.append(line)
        if instant { onFinish() } else { pending.append(onFinish) }
    }

    func stop() {
        stops += 1
        pending = []
    }

    /// The line being said is heard to its end.
    func finish() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()()
    }
}

extension ExplainerPlayer {
    /// Runs the clock in frames until the step pauses, finishing each line as it is said.
    /// Returns the frames it took.
    @discardableResult
    func playToPause(_ voice: RecordingVoice, frame: Double = 1.0 / 60, limit: Int = 10_000) -> Int {
        var frames = 0
        while case .playing = phase, frames < limit {
            advance(by: frame)
            voice.finish()
            frames += 1
        }
        return frames
    }
}


extension GuidedPlayer {
    /// Runs the clock in frames, finishing each line as it is said, until the player waits on
    /// something other than its clock or voice: a control, or the learner's marks.
    @discardableResult
    func settle(_ voice: RecordingVoice, frame: Double = 1.0 / 60, limit: Int = 20_000) -> Int {
        var frames = 0
        while frames < limit {
            let busy: Bool =
                switch phase {
                case .playing: true
                case .doing: listening || voiceBusy || voice.busy || moving
                default: voiceBusy || voice.busy || moving
                }
            if !busy { break }
            advance(by: frame)
            voice.finish()
            frames += 1
        }
        return frames
    }
}
