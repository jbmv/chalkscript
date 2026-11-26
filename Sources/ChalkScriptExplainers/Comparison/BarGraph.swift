import ChalkScript
import CoreGraphics
import Foundation

/// Reading a bar graph to compare two bars ("How many more children picked apples than pears?"):
/// the first-named bar's value `a`, the second's `b`, which graph, and which pair of its four
/// bars is asked about; the other two bars take values that are neither. The question asks about
/// the first bar, so it says "fewer" when a < b (EXP-2: the template's values).
public struct BarGraphProblem: Equatable, Hashable, Sendable {
    /// The graph's scale counts by ones to 20.
    public static let scaleMax = 20
    public static let values = 1...scaleMax
    /// The pairs of bars a question compares, by their place on the graph.
    public static let pairs: [(Int, Int)] = [(0, 3), (1, 2), (0, 2), (3, 1)]

    public enum Refusal: Error, Equatable {
        case outOfRange
        case same
    }

    public let a: Int
    public let b: Int
    /// Which graph: an index the wording takes from its own list, wrapping round.
    public let graph: Int
    public let pair: Int
    public let word: CompareWord
    /// The four bars' values, top to bottom.
    public let bars: [Int]

    public init(_ a: Int, _ b: Int, graph: Int = 0, pair: Int = 0) throws {
        guard Self.values.contains(a), Self.values.contains(b) else { throw Refusal.outOfRange }
        guard a != b else { throw Refusal.same }
        self.init(unchecked: a, b, graph: graph, pair: pair, word: CompareWord.asking(a, than: b), others: nil)
    }

    /// What if?'s problem: any value in range, equal bars included, the word held, and the other
    /// two bars kept where they were (`others`, the bars before), so only the dragged bar moves.
    init(unchecked a: Int, _ b: Int, graph: Int, pair: Int, word: CompareWord, others: [Int]?) {
        self.a = a
        self.b = b
        self.graph = graph
        self.pair = pair
        self.word = word
        let (i1, i2) = Self.pairs[pair % Self.pairs.count]
        var vals = others ?? [0, 0, 0, 0]
        vals[i1] = a
        vals[i2] = b
        if others == nil {
            // The other two bars: values that are neither amount nor each other.
            var fill = (a * 7 + b * 3) % 13 + 4
            for k in 0..<4 where k != i1 && k != i2 {
                while fill == a || fill == b || vals.contains(fill) { fill = fill % 19 + 2 }
                vals[k] = fill
                fill = (fill * 5) % 17 + 3
            }
        }
        bars = vals
    }

    /// The bars asked about, first and second, by their place.
    public var first: Int { Self.pairs[pair % Self.pairs.count].0 }
    public var second: Int { Self.pairs[pair % Self.pairs.count].1 }
    public var longer: Int { a >= b ? first : second }
    public var shorter: Int { a >= b ? second : first }
    public var big: Int { max(a, b) }
    public var small: Int { min(a, b) }
    public var difference: Int { big - small }

    /// Another problem of the same kind (EXP-3): `n` 1 for do it with me, 2 for try one. Another
    /// graph and pair of bars, a difference in the same size band (under 5, or 5 and more) and of
    /// another size, another smaller value, and the other question word for do it with me. The
    /// pick is fixed for a problem.
    public func isomorph(_ n: Int) -> BarGraphProblem {
        let d0 = difference
        var out: [(s: Int, d: Int)] = []
        for s in 2...17 {
            var d = 2
            while s + d <= Self.scaleMax {
                defer { d += 1 }
                if (d >= 5) != (d0 >= 5) || d == d0 || s == small { continue }
                out.append((s, d))
            }
        }
        let pick = out[(a * 31 + b * 17 + n * 97) % out.count]
        let flip = (a < b) != (n == 1)
        return try! BarGraphProblem(flip ? pick.s : pick.s + pick.d, flip ? pick.s + pick.d : pick.s, graph: n, pair: n % Self.pairs.count)
    }
}

/// The bar graph's lines (EXP-10), each a wording entry the app fills with the problem's
/// values and the graph's words.
public enum BarGraphLine: Equatable, Hashable, Sendable {
    case intro
    case doIntro
    case read
    case bars
    case compare
    case equation
    case count
    /// Do it with me: reading the first bar, then the second (`nextBar`, by its place).
    case doBars
    case nextBar(Int)
    /// The bar's end touched: its line drops to the scale.
    case lands
    /// A touch away from the bar's end and the scale, or on another number, reading bar `bar`.
    case barMissed(bar: Int)
    case wrongNumber(Int, bar: Int)
    /// The same two misses once the bar's line has dropped to the scale: they point at the number
    /// where the line lands, not at the bar's end.
    case landedMissed
    case landedWrong(Int)
    /// Both bars read.
    case barsRead
    case doCompare
    case doEquation
    case doCount
    case compared
    case chose
    /// A square counted (spoken only).
    case tick(Int)
    case answer
    case tapped
    case notAlong
    case startOff
    case short
    case past
    case countMissed
    case joined
    case joinedTotal
    case joinedBut
    case goalSame
    case goalSameMet
    case goalExactly(Int)
    case goalExactlyMet(Int)
    case goalFlip(CompareWord)
    case goalFlipMet(CompareWord)
    case tryIntro

    /// Every line a problem's explainer can say, for the app's checks.
    public static func all(for p: BarGraphProblem) -> [BarGraphLine] {
        var out: [BarGraphLine] = [
            .intro, .doIntro, .read, .bars, .compare, .equation, .count, .doBars, .nextBar(p.second), .lands,
            .barMissed(bar: p.first), .barMissed(bar: p.second),
        ]
        for v in 0...BarGraphProblem.scaleMax {
            if v != p.a { out.append(.wrongNumber(v, bar: p.first)) }
            if v != p.b { out.append(.wrongNumber(v, bar: p.second)) }
            out.append(.landedWrong(v))
        }
        out.append(.landedMissed)
        out += [.barsRead, .doCompare, .doEquation, .doCount, .compared, .chose]
        out += (1...max(1, p.difference)).map { .tick($0) }
        out += [
            .answer, .tapped, .notAlong, .startOff, .short, .past, .countMissed, .joined, .joinedTotal, .joinedBut, .goalSame,
            .goalSameMet, .goalExactly(BarGraphExplainer.exactly), .goalExactlyMet(BarGraphExplainer.exactly), .goalFlip(.fewer),
            .goalFlip(.more), .goalFlipMet(.fewer), .goalFlipMet(.more), .tryIntro,
        ]
        return out
    }
}

/// Text the bar graph draws, as the app fills it from its wording.
public enum BarGraphText: Equatable, Sendable {
    case title
    /// The name of the bar in place `n`.
    case category(Int)
    /// Under the scale: what it counts.
    case axis
    case subtractFormat
    case addFormat
    case unknown
    case same
    case tryNote
}

/// The bar graph's wording.
public struct BarGraphWording: Sendable {
    public var line: @Sendable (BarGraphLine, BarGraphProblem) -> Line
    public var text: @Sendable (BarGraphText, BarGraphProblem) -> String
    public var question: @Sendable (BarGraphProblem) -> [Phrase]

    public init(
        line: @escaping @Sendable (BarGraphLine, BarGraphProblem) -> Line,
        text: @escaping @Sendable (BarGraphText, BarGraphProblem) -> String,
        question: @escaping @Sendable (BarGraphProblem) -> [Phrase]
    ) {
        self.line = line
        self.text = text
        self.question = question
    }
}

/// The bar graph's picture: the bars read, the dashed part and its squares counted, and for the
/// child version the cards.
public struct GraphState: Equatable, Sendable {
    /// Bars read off the scale (by place): a line down to the scale, the number ringed there and
    /// written inside the bar's end.
    public var read: [Int] = []
    /// Bars whose end the learner touched: only the line down is drawn, the number is still the learner's to
    /// read.
    public var dropped: [Int] = []
    public var gap = false
    public var equation = false
    /// The squares of the dashed part counted, in the order touched.
    public var counted: [Int] = []
    /// The squares are being counted: the dashed part's question mark is put away.
    public var counting = false
    public var answered = false
    public var cards = false
    public var addShown = false

    public init() {}
}

/// Comparing two bars on a bar graph, as a worksheet draws it: bars across, a scale counting by
/// ones to 20 with a line for every number. The two bars are read off the scale, the shorter bar
/// is drawn on, dashed, to the longer one's length, and the dashed part's squares are counted
/// one by one like pieces. Its steps and timings:
///
/// - read: the graph and its question, the comparison words tinted (EXP-6).
/// - bars: each bar's line drops to the scale, its number is ringed there and written inside the
///   bar's end.
/// - compare: a dashed line marks where the longer bar ends; the shorter bar is drawn on to it.
/// - equation: the longer value minus the shorter appears.
/// - count: each square of the dashed part shows its count on itself; then the counts give way
///   to the total on the dashed part.
///
/// The child version (BarGraphGuided.swift) adds do it with me, What if? and try one.
public struct BarGraphExplainer: Sendable {
    public enum Step: String, CaseIterable, Sendable {
        case read, bars, compare, equation, count
    }

    public let problem: BarGraphProblem
    public let wording: BarGraphWording

    public init(problem: BarGraphProblem, wording: BarGraphWording) {
        self.problem = problem
        self.wording = wording
    }

    public var steps: [Step] { Step.allCases }

    /// What if?'s exact goal: the dashed part exactly 5.
    public static let exactly = 5

    func line(_ l: BarGraphLine) -> Line { wording.line(l, problem) }
    func text(_ t: BarGraphText) -> String { wording.text(t, problem) }

    // MARK: layout (in scene units)

    enum L {
        static let x0: CGFloat = 210, unit: CGFloat = 32, row0: CGFloat = 112, row: CGFloat = 56, barHeight: CGFloat = 36
        static let axisY: CGFloat = 112 + 4 * 56, equationY: CGFloat = 512
        static let titleY: CGFloat = 36, questionY: CGFloat = 74, titleSize: Double = 26
        static let nameSize: Double = 22, valueSize: Double = 24, tickSize: Double = 20, labelSize: Double = 18
        static let ringRadii = CGSize(width: 17, height: 15)
        static let joinOrigin = CGPoint(x: 100, y: 100), joinKMax = 0.85
        static var joinY: CGFloat { axisY + 74 }
        static let cardsTop: CGFloat = equationY - 50
    }

    static func x(_ v: Int) -> CGFloat { L.x0 + CGFloat(v) * L.unit }
    static func rowY(_ i: Int) -> CGFloat { L.row0 + CGFloat(i) * L.row + (L.row - L.barHeight) / 2 }

    var xs: CGFloat { Self.x(problem.small) }
    var xb: CGFloat { Self.x(problem.big) }
    var shorterY: CGFloat { Self.rowY(problem.shorter) }

    /// The dashed part, and its square `k`.
    var gapRect: CGRect { CGRect(x: xs, y: shorterY, width: xb - xs, height: L.barHeight) }
    func cell(_ k: Int) -> CGRect { CGRect(x: xs + CGFloat(k) * L.unit, y: shorterY, width: L.unit, height: L.barHeight) }

    // MARK: timing (in seconds)

    enum T {
        static let read = 0.4
        static let drop = 0.65, ringFade = 0.3, valueFade = 0.3, readRest = 0.5
        static let doDrop = 0.45
        static let guide = 0.6, gapGrow = 0.9, drawnGrow = 0.5, gapRest = 0.3
        static let equationFade = 0.5, equationRest = 0.4
        static let cell = 0.52, tagFade = 0.2, beforeFinish = 0.4, tagsAway = 0.4, pulse = 0.45
        static let chosen = 0.7
    }

    static var readTime: Double { T.drop + T.ringFade + T.valueFade + T.readRest }

    /// The count's phases: each square, then the counts giving way to the total.
    struct CountTimes {
        let cells: [Double]
        let finish: Double
        var end: Double { finish + T.pulse }

        /// Every square counted in turn, as watched.
        init(cells n: Int) {
            cells = (0..<n).map { Double($0) * T.cell }
            finish = Double(n) * T.cell + T.beforeFinish
        }

        /// One square the learner touches; the last also finishes the count.
        init(oneCell last: Bool) {
            cells = [0]
            finish = last ? T.beforeFinish : .infinity
        }
    }

    // MARK: steps

    public func apply(_ step: Step, _ s: GraphState) -> GraphState {
        var n = s
        switch step {
        case .read: break
        case .bars: n.read = [problem.first, problem.second]
        case .compare: n.gap = true
        case .equation:
            n.equation = true
            n.cards = false
        case .count:
            n.counted = Array(0..<problem.difference)
            n.answered = true
        }
        return n
    }

    func lineFor(_ s: Step) -> BarGraphLine {
        switch s {
        case .read: .read
        case .bars: .bars
        case .compare: .compare
        case .equation: .equation
        case .count: .count
        }
    }

    public func script(for step: Int) -> StepScript {
        let s = steps[step]
        let said = StepEvent(0, .say(line(lineFor(s)), caption: true))
        switch s {
        case .read: return StepScript(duration: T.read, events: [said])
        case .bars: return StepScript(duration: 2 * Self.readTime, events: [said])
        case .compare: return StepScript(duration: T.guide + T.gapGrow + T.gapRest, events: [said])
        case .equation: return StepScript(duration: T.equationFade + T.equationRest, events: [said])
        case .count:
            let times = CountTimes(cells: problem.difference)
            var events = [said]
            for (k, at) in times.cells.enumerated() {
                events.append(StepEvent(at, .waitForVoice))
                events.append(StepEvent(at, .say(line(.tick(k + 1)), caption: false)))
            }
            events.append(StepEvent(times.end, .waitForVoice))
            events.append(StepEvent(times.end, .say(line(.answer), caption: true)))
            return StepScript(duration: times.end, events: events)
        }
    }

    // MARK: pictures

    struct Picture {
        var state: GraphState
        /// A bar being read: its line drawn so far, its ring's and its number's opacity.
        var reading: [Int: (drop: Double, ring: Double, value: Double)] = [:]
        var guide: Double = 1
        var gapGrow: Double = 1
        var cells = true
        /// The dashed part's number, its opacity and its pulse.
        var tag: String?
        var tagOpacity: Double = 1
        var tagScale: Double = 1
        /// The squares' own counts as they appear, and as they give way to the total.
        var countOpacity: [Int: Double] = [:]
        var countsAway: Double = 1
        var equationOpacity: Double = 1
        var chosen = false
        var handle = false
    }

    func drawing(_ s: GraphState) -> Picture { Picture(state: s) }

    func scene(_ p: Picture) -> Scene {
        var pen = Pen()
        let s = p.state
        pen.words("title", text(.title), at: CGPoint(x: 500, y: L.titleY), size: L.titleSize)
        pen.question("question", wording.question(problem), center: CGPoint(x: 500, y: L.questionY), size: L.titleSize)
        graph(&pen)
        for i in s.dropped where !s.read.contains(i) && p.reading[i] == nil {
            readMark(&pen, i, drop: 1, ring: 0, value: 0)
        }
        for i in s.read {
            let r = p.reading[i] ?? (1, 1, 1)
            readMark(&pen, i, drop: r.drop, ring: r.ring, value: r.value)
        }
        for (i, r) in p.reading.sorted(by: { $0.key < $1.key }) where !s.read.contains(i) {
            readMark(&pen, i, drop: r.drop, ring: r.ring, value: r.value)
        }
        let unknown = text(.unknown)
        let answer = p.tag ?? (s.answered ? String(problem.difference) : unknown)
        if s.gap && problem.difference > 0 {
            let top = min(shorterY, Self.rowY(problem.longer)) - 4
            let bottom = max(shorterY, Self.rowY(problem.longer)) + L.barHeight + 4
            var guide = Look.drop
            guide.progress = p.guide
            pen.line("guide", CGPoint(x: xb, y: top), CGPoint(x: xb, y: bottom), guide)
            if p.gapGrow > 0 {
                var r = gapRect
                r.size.width *= p.gapGrow
                pen.shape("gap", .rect(r), Look.openGap)
            }
            if p.cells {
                for k in 0..<problem.difference {
                    let counted = s.answered || s.counted.contains(k)
                    let paint = counted
                        ? Paint(fill: .soft(.result), stroke: .ink(.result), width: 1.4)
                        : Paint(stroke: .ink(.result), width: 1.4)
                    pen.shape("cell.\(k)", .rect(cell(k)), paint, opacity: counted ? 1 : 0.7)
                }
                for (n, k) in s.counted.enumerated() where !s.answered || p.countsAway < 1 {
                    let o = (p.countOpacity[k] ?? 1) * (s.answered ? p.countsAway : 1)
                    let r = cell(k).insetBy(dx: 1, dy: 0)
                    pen.add("count.\(k)", .numberTag(String(n + 1), in: Components.numberTag(on: r, ten: false), scale: 1), opacity: o)
                }
                let hidden = s.counting && !s.answered && p.tag == nil
                pen.add("gap.tag", .numberTag(answer, in: Components.numberTag(on: gapRect, ten: true), scale: p.tagScale), opacity: hidden ? 0 : p.tagOpacity)
            }
        }
        if s.equation {
            let eq = equationRuns(text(.subtractFormat), first: String(problem.big), second: String(problem.small), answer: answer)
            let runs = eq.runs.enumerated().map { i, r in EquationLine.Run(r, i == eq.answer ? .answer : .plain) }
            pen.add("equation", .equation(EquationLine(
                runs: runs, mark: .init(run: eq.sign, op: .subtract, progress: 0), center: CGPoint(x: 500, y: L.equationY),
                size: TapeDiagramExplainer.L.equationSize)), opacity: p.equationOpacity)
        }
        if s.cards {
            cards.draw(&pen, add: cardText(.add), subtract: cardText(.subtract), addGone: s.addShown, chosen: p.chosen)
        }
        if p.handle { handle(&pen) }
        return pen.scene
    }

    /// The grid and the scale, a line for every number as on the page, the four bars and their
    /// names.
    func graph(_ pen: inout Pen) {
        let grid = Paint(stroke: .line, width: 1.4)
        let axis = Paint(stroke: .pencil, width: 2.4)
        for v in 0...BarGraphProblem.scaleMax {
            pen.line("grid.\(v)", CGPoint(x: Self.x(v), y: L.row0 - 4), CGPoint(x: Self.x(v), y: L.axisY), grid)
            pen.words("tick.\(v)", String(v), at: CGPoint(x: Self.x(v), y: L.axisY + 26), size: L.tickSize, ink: .muted)
        }
        pen.line("axis.x", CGPoint(x: L.x0, y: L.axisY), CGPoint(x: Self.x(BarGraphProblem.scaleMax), y: L.axisY), axis)
        pen.line("axis.y", CGPoint(x: L.x0, y: L.row0 - 4), CGPoint(x: L.x0, y: L.axisY), axis)
        pen.words("axis.label", text(.axis), at: CGPoint(x: Self.x(BarGraphProblem.scaleMax / 2), y: L.axisY + 56), size: L.labelSize, ink: .muted, display: false)
        for (i, v) in problem.bars.enumerated() {
            let y = Self.rowY(i)
            pen.words("name.\(i)", text(.category(i)), at: CGPoint(x: L.x0 - 14, y: y + L.barHeight / 2 + 8), size: L.nameSize, anchor: .trailing)
            pen.shape("bar.\(i)", .rect(CGRect(x: L.x0, y: y, width: CGFloat(v) * L.unit, height: L.barHeight)), Look.graphBar)
        }
    }

    /// A bar read off the scale: a dashed line from its end down to the numbers, the number ringed
    /// there, and written just inside the bar's end, as a learner writes it on the page.
    func readMark(_ pen: inout Pen, _ i: Int, drop: Double, ring: Double, value: Double) {
        let v = problem.bars[i]
        let x = Self.x(v)
        var paint = Look.drop
        paint.progress = drop
        pen.line("read.\(i).drop", CGPoint(x: x, y: Self.rowY(i) + L.barHeight), CGPoint(x: x, y: L.axisY), paint)
        let c = CGPoint(x: x, y: L.axisY + 19)
        pen.shape("read.\(i).ring", .ellipse(CGRect(x: c.x - L.ringRadii.width, y: c.y - L.ringRadii.height, width: 2 * L.ringRadii.width, height: 2 * L.ringRadii.height)),
            Paint(stroke: .pencil, width: 2.6), opacity: ring)
        pen.words("read.\(i).value", String(v), at: CGPoint(x: x - 8, y: Self.rowY(i) + L.barHeight / 2 + 9), size: L.valueSize, anchor: .trailing, opacity: value)
    }

    var cards: Cards { Cards(top: L.cardsTop, addFirst: (problem.a + problem.b) % 2 == 0) }

    func cardText(_ kind: Cards.Kind) -> String {
        let unknown = text(.unknown)
        let format = text(kind == .add ? .addFormat : .subtractFormat)
        return equationRuns(format, first: String(problem.big), second: String(problem.small), answer: unknown).runs.joined()
    }

    /// What if?'s handle on the end of the first-named bar, and "Same!" beside two equal bars.
    func handle(_ pen: inout Pen) {
        let x = Self.x(problem.a), y = Self.rowY(problem.first)
        pen.shape("handle", .rect(CGRect(x: x - 10, y: y - 10, width: 20, height: L.barHeight + 20), corner: 8), Look.handle)
        for (i, dx) in [CGFloat(-3), 3].enumerated() {
            pen.line("handle.grip.\(i)", CGPoint(x: x + dx, y: y + 6), CGPoint(x: x + dx, y: y + L.barHeight - 6), Look.handleGrip)
        }
        if problem.difference == 0 {
            pen.words("same", text(.same), at: CGPoint(x: min(x + 40, 900), y: y + L.barHeight / 2 + 9), size: 26, ink: .ink(.result), anchor: .leading)
        }
    }

    // MARK: motion

    func motionPicture(_ step: Int, from s0: GraphState, to s1: GraphState, at t: Double) -> Scene {
        let duration = script(for: step).duration
        if t >= duration { return scene(drawing(s1)) }
        switch steps[step] {
        case .read:
            return scene(drawing(s0))
        case .bars:
            var p = drawing(s0)
            for (j, i) in [problem.first, problem.second].enumerated() {
                let base = Double(j) * Self.readTime
                guard t >= base else { continue }
                p.reading[i] = (
                    progress(t, start: base, duration: T.drop, .easeOut),
                    progress(t, start: base + T.drop, duration: T.ringFade),
                    progress(t, start: base + T.drop + T.ringFade, duration: T.valueFade)
                )
            }
            return scene(p)
        case .compare:
            var p = drawing(s1)
            gapMotion(&p, t, drawn: false)
            return scene(p)
        case .equation:
            var p = drawing(s1)
            p.equationOpacity = progress(t, start: 0, duration: T.equationFade)
            return scene(p)
        case .count:
            var base = s0
            base.counting = true
            return countPicture(from: base, cells: Array(0..<problem.difference), times: CountTimes(cells: problem.difference), at: t)
        }
    }

    /// The shorter bar drawn on: a dashed line marks where the longer bar ends (drawn when
    /// watched, there already when the learner drew it on), the dashed part grows to it, and its
    /// squares and question mark appear.
    func gapMotion(_ p: inout Picture, _ t: Double, drawn: Bool) {
        let grow = drawn ? 0 : T.guide
        p.guide = drawn ? 1 : progress(t, start: 0, duration: T.guide, .easeOut)
        p.gapGrow = progress(t, start: grow, duration: drawn ? T.drawnGrow : T.gapGrow, .easeOut)
        p.cells = t >= grow + (drawn ? T.drawnGrow : T.gapGrow)
        p.tag = text(.unknown)
    }

    /// Counting `cells` from `base` at `times.cells`: each shows its count on itself as it is
    /// counted; at the finish the counts give way to the total on the dashed part, with a pulse.
    func countPicture(from base: GraphState, cells: [Int], times: CountTimes, at t: Double) -> Scene {
        var p = drawing(base)
        for (k, at) in zip(cells, times.cells) where t >= at {
            p.state.counted.append(k)
            p.countOpacity[k] = progress(t, start: at, duration: T.tagFade)
        }
        if t >= times.finish {
            p.state.answered = true
            p.countsAway = 1 - progress(t, start: times.finish, duration: T.tagsAway)
            p.tag = String(problem.difference)
            p.tagScale = keyframes([(0, 1), (0.5, 1.2), (1, 1)], progress(t, start: times.finish, duration: T.pulse))
        }
        return scene(p)
    }

    func picture(_ s: GraphState) -> Scene { scene(drawing(s)) }
}
