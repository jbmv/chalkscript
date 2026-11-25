import CoreGraphics
import Foundation

/// A one-step comparing word problem with the difference unknown ("How many fewer shells did Maya
/// find than Leo?"): the first-named person's amount `a`, the second's `b`, and which story and
/// names tell it. The question asks about the first person, so it says "fewer" when a < b and
/// "more" when a > b (EXP-2: the template's values).
public struct TapeDiagramProblem: Equatable, Hashable, Sendable {
    /// The amounts the template accepts.
    public static let amounts = 1...99

    public enum Refusal: Error, Equatable {
        case outOfRange
        case same
    }

    public let a: Int
    public let b: Int
    /// Which story and which pair of names tell it: indices the wording takes from its own lists
    /// (string-library entries), wrapping round.
    public let story: Int
    public let names: Int
    public let word: CompareWord

    public init(_ a: Int, _ b: Int, story: Int = 0, names: Int = 0) throws {
        guard Self.amounts.contains(a), Self.amounts.contains(b) else { throw Refusal.outOfRange }
        guard a != b else { throw Refusal.same }
        self.init(unchecked: a, b, story: story, names: names, word: CompareWord.asking(a, than: b))
    }

    /// What if?'s problem: any amount in range, the bars equal included, the word held.
    init(unchecked a: Int, _ b: Int, story: Int, names: Int, word: CompareWord) {
        self.a = a
        self.b = b
        self.story = story
        self.names = names
        self.word = word
    }

    public var big: Int { max(a, b) }
    public var small: Int { min(a, b) }
    public var difference: Int { big - small }
    /// The first-named person has the shorter bar (drawn on top).
    public var firstIsShorter: Bool { a < b }

    /// The jumps counting on from the smaller amount to the bigger: tens while they fit, then
    /// the ones left.
    public var hops: [(from: Int, to: Int)] {
        var out: [(Int, Int)] = []
        var x = small
        while x < big {
            let to = big - x >= 10 ? x + 10 : big
            out.append((x, to))
            x = to
        }
        return out
    }

    /// Another problem of the same kind (EXP-3): `n` 1 for do it with me, 2 for try one. The gap
    /// has the same shape (ten or more, a whole number of tens, or neither) and another size, the
    /// smaller amount is another, the story and names are the next ones, and the question word is
    /// the other one for do it with me, so "more" and "fewer" are seen to be the same gap. The
    /// pick is fixed for a problem.
    public func isomorph(_ n: Int) -> TapeDiagramProblem {
        let d0 = difference
        var out: [(s: Int, d: Int)] = []
        for s in 12...80 {
            var d = 3
            while s + d <= 95 {
                defer { d += 1 }
                if (d >= 10) != (d0 >= 10) || (d % 10 == 0) != (d0 % 10 == 0) || d == d0 { continue }
                if small == s { continue }
                out.append((s, d))
            }
        }
        let pick = out[(a * 31 + b * 17 + n * 97) % out.count]
        let flip = (a < b) != (n == 1)
        return try! TapeDiagramProblem(flip ? pick.s : pick.s + pick.d, flip ? pick.s + pick.d : pick.s, story: n, names: n)
    }
}

/// The tape diagram's lines (EXP-10), each a string-library entry the app fills with the
/// problem's amounts, names and story.
public enum TapeLine: Equatable, Hashable, Sendable {
    /// Before the first step of watch, and of do it with me.
    case intro
    case doIntro
    /// The watched steps' lines.
    case read
    case bars
    case compare
    case equation
    case count
    /// Do it with me: what the child is asked to do.
    case doCompare
    case doEquation
    case doCount
    /// Said once the child has drawn the shorter bar on, and once the take-away card is chosen.
    case compared
    case chose
    /// A number reached, counting on (spoken only).
    case tick(Int)
    /// The tens and ones of the count put together: "10 plus 8 is 18."
    case countJoin
    /// The last line, the difference emphasised.
    case answer
    /// A line that does not draw the shorter bar on: a touch, a line up and down, one that starts
    /// away from the shorter bar's end, stops short, or goes past.
    case tapped
    case notAlong
    case startOff
    case short
    case past
    /// A touch away from the number line while counting on.
    case countMissed
    /// The adding card's join: what adding puts together, its total, and what we want instead.
    case joined
    case joinedTotal
    case joinedBut
    /// What if?'s goals and what is said when each is met (EXP-15).
    case goalSame
    case goalSameMet
    case goalExactly(Int)
    case goalExactlyMet(Int)
    case goalFlip(CompareWord)
    case goalFlipMet(CompareWord)
    /// Try one: the story the child tries alone.
    case tryIntro

    /// Every line a problem's explainer can say, for the app's checks.
    public static func all(for p: TapeDiagramProblem) -> [TapeLine] {
        var out: [TapeLine] = [
            .intro, .doIntro, .read, .bars, .compare, .equation, .count, .doCompare, .doEquation, .doCount, .compared, .chose,
        ]
        out += p.hops.map { .tick($0.to) }
        if p.difference >= 10 && p.difference % 10 > 0 { out.append(.countJoin) }
        out += [
            .answer, .tapped, .notAlong, .startOff, .short, .past, .countMissed, .joined, .joinedTotal, .joinedBut, .goalSame,
            .goalSameMet, .goalExactly(TapeDiagramExplainer.exactly), .goalExactlyMet(TapeDiagramExplainer.exactly),
            .goalFlip(.fewer), .goalFlip(.more), .goalFlipMet(.fewer), .goalFlipMet(.more), .tryIntro,
        ]
        return out
    }
}

/// Text the tape diagram draws, as the app fills it from the string library.
public enum TapeText: Equatable, Sendable {
    /// The story's two sentences across the top.
    case story
    /// The names beside the bars.
    case firstName
    case secondName
    /// Equations with `EquationSlot` marks: taking away, and putting together.
    case subtractFormat
    case addFormat
    /// The answer not yet found.
    case unknown
    /// What if?'s word beside two equal bars.
    case same
    /// A jump's label ("+10").
    case hop(Int)
    /// The running count: "20 + 8", or "20 + 8 = 28" once found.
    case running(tens: Int, ones: Int, total: Int?)
    /// Try one's notes under the story: its first and second line.
    case tryNote(Int)
}

/// The tape diagram's wording, from the string library.
public struct TapeDiagramWording: Sendable {
    public var line: @Sendable (TapeLine, TapeDiagramProblem) -> Line
    public var text: @Sendable (TapeText, TapeDiagramProblem) -> String
    /// The question as phrases, its word and "than" tinted.
    public var question: @Sendable (TapeDiagramProblem) -> [Phrase]

    public init(
        line: @escaping @Sendable (TapeLine, TapeDiagramProblem) -> Line,
        text: @escaping @Sendable (TapeText, TapeDiagramProblem) -> String,
        question: @escaping @Sendable (TapeDiagramProblem) -> [Phrase]
    ) {
        self.line = line
        self.text = text
        self.question = question
    }
}

/// The tape diagram's picture: what is drawn, and for the child version, the cards and the
/// number line the child works on.
public struct TapeState: Equatable, Sendable {
    public var bars = false
    public var gap = false
    public var equation = false
    /// The jumps drawn, counting on.
    public var hops = 0
    public var answered = false
    /// Do it with me: the equation cards are out; the adding card's join has been shown, so it is
    /// greyed out; the number line is drawn to be touched.
    public var cards = false
    public var addShown = false
    public var numberLine = false

    public init() {}
}

/// The comparing word problem on a tape diagram, as a worksheet draws it: a bar for each person
/// from the same start, and the shorter bar drawn on, dashed, until it is as long as the longer
/// one; the dashed part is the difference. Its steps and timings:
///
/// - read: the story and its question, the comparison words tinted (EXP-6).
/// - bars: each bar grows from the shared start to its amount.
/// - compare: a dashed line drops from where the longer bar ends; the shorter bar is drawn on to
///   it, dashed, with a brace and a question mark.
/// - equation: the longer amount minus the shorter appears, its minus in take-away's colour.
/// - count: counting on along a number line under the dashed part, ten at a time and then the
///   ones ("10", "10 + 8"), the number reached said at each jump; then the answer.
///
/// The child version (TapeGuided.swift) adds do it with me, What if? and try one.
public struct TapeDiagramExplainer: Sendable {
    public enum Step: String, CaseIterable, Sendable {
        case read, bars, compare, equation, count
    }

    public let problem: TapeDiagramProblem
    public let wording: TapeDiagramWording
    /// Scene units per unit of amount: the longer bar fills the row, or What if?'s scale to 99.
    let scale: CGFloat

    public init(problem: TapeDiagramProblem, wording: TapeDiagramWording) {
        self.init(problem: problem, wording: wording, scaleMax: problem.big)
    }

    init(problem: TapeDiagramProblem, wording: TapeDiagramWording, scaleMax: Int) {
        self.problem = problem
        self.wording = wording
        self.scale = L.length / CGFloat(max(1, scaleMax))
    }

    public var steps: [Step] { Step.allCases }

    /// What if?'s exact goal: the dashed part exactly 10.
    public static let exactly = 10

    func line(_ l: TapeLine) -> Line { wording.line(l, problem) }
    func text(_ t: TapeText) -> String { wording.text(t, problem) }

    // MARK: layout (in scene units)

    /// Rows from the top: the story, the two bars with their braces, the number line and its
    /// hops, the running count, the equation; spaced so no label meets another at any pair of
    /// amounts.
    enum L {
        static let x0: CGFloat = 200, length: CGFloat = 620, barHeight: CGFloat = 42
        static let topY: CGFloat = 158, bottomY: CGFloat = 238, lineY: CGFloat = 407, equationY: CGFloat = 510
        static let storyY: CGFloat = 42, questionY: CGFloat = 80, storySize: Double = 26
        /// A brace's point is 16 from its bar; its number stands 9 clear of the point.
        static let braceGap: CGFloat = 8, above: CGFloat = -25, below: CGFloat = 43
        static let nameSize: Double = 22, valueSize: Double = 24, gapValueSize: Double = 26
        static let equationSize: Double = 44, tickSize: Double = 20, hopSize: Double = 20
        /// Where the joined bars go, and what the drawing shrinks about.
        static let joinY: CGFloat = 360, joinOrigin = CGPoint(x: 110, y: 130)
        static let cardsTop: CGFloat = equationY - 62
    }

    var xs: CGFloat { L.x0 + CGFloat(problem.small) * scale }
    var xb: CGFloat { L.x0 + CGFloat(problem.big) * scale }
    func x(_ v: Int) -> CGFloat { L.x0 + CGFloat(v) * scale }

    /// The row the dashed part is on (the shorter bar's), which way its brace points, and where
    /// its number stands.
    var gapRow: (y: CGFloat, dir: CGFloat, braceY: CGFloat, labelY: CGFloat) {
        let top = problem.firstIsShorter
        let y = top ? L.topY : L.bottomY
        let dir: CGFloat = top ? -1 : 1
        let by = dir < 0 ? y - L.braceGap : y + L.barHeight + L.braceGap
        return (y, dir, by, by + (dir < 0 ? L.above : L.below))
    }

    // MARK: timing (in seconds)

    enum T {
        static let read = 0.4
        static let barGrow = 1.1, barRest = 0.25
        static let drop = 0.7, gapGrow = 0.8, gapBrace = 0.6, gapMark = 0.3, gapRest = 0.3
        static let equationFade = 0.5, equationRest = 0.4
        static let hopArc = 0.65, hopLabel = 0.25, hopRest = 0.5, beforeFinish = 0.3, pulse = 0.45
        static let chosen = 0.7
    }

    /// The compare step's phases, from where the dashed line is drawn (watched) or already there
    /// (the child drew it on).
    struct GapTimes {
        let grow: Double
        var brace: Double { grow + T.gapGrow }
        var mark: Double { brace + T.gapBrace }
        var end: Double { mark + T.gapMark + T.gapRest }
        init(dropped: Bool) { grow = dropped ? 0 : T.drop }
    }

    /// The count's phases: each jump, then the tens and ones put together and the answer.
    struct CountTimes {
        let hops: [Double]
        let finish: Double
        let fill: Double
        let end: Double
        /// Counting on from the first jump, as watched.
        init(hops n: Int, joins: Bool) {
            hops = (0..<n).map { Double($0) * (T.hopArc + T.hopRest) }
            finish = Double(n) * (T.hopArc + T.hopRest) + T.beforeFinish
            fill = finish + (joins ? 0.002 : 0)
            end = fill + T.pulse
        }

        /// One jump the child makes with a touch; the last also finishes the count.
        init(oneHop last: Bool, joins: Bool) {
            hops = [0]
            if last {
                finish = T.hopArc + T.beforeFinish
                fill = finish + (joins ? 0.002 : 0)
                end = fill + T.pulse
            } else {
                finish = .infinity
                fill = .infinity
                end = T.hopArc + T.hopLabel
            }
        }
    }

    /// Whether the count puts tens and ones together before the answer ("10 plus 8 is 18").
    var countJoins: Bool { problem.difference >= 10 && problem.difference % 10 > 0 }

    /// What the running count says after `n` jumps: the tens as they are jumped ("10", "20"), then
    /// the ones joined on ("20 + 8"), then the total.
    func running(_ n: Int, answered: Bool) -> String {
        let done = problem.hops.prefix(n)
        let tens = done.filter { $0.to - $0.from == 10 }.count * 10
        let ones = done.filter { $0.to - $0.from < 10 }.reduce(0) { $0 + $1.to - $1.from }
        if done.isEmpty { return "" }
        if ones == 0 { return String(tens) }
        if tens == 0 { return String(ones) }
        return text(.running(tens: tens, ones: ones, total: answered ? problem.difference : nil))
    }

    // MARK: steps

    public func apply(_ step: Step, _ s: TapeState) -> TapeState {
        var n = s
        switch step {
        case .read: break
        case .bars: n.bars = true
        case .compare: n.gap = true
        case .equation:
            n.equation = true
            n.cards = false
        case .count:
            n.hops = problem.hops.count
            n.answered = true
            n.numberLine = true
        }
        return n
    }

    public func script(for step: Int) -> StepScript {
        let s = steps[step]
        let said = StepEvent(0, .say(line(lineFor(s)), caption: true))
        switch s {
        case .read: return StepScript(duration: T.read, events: [said])
        case .bars: return StepScript(duration: 2 * (T.barGrow + T.barRest), events: [said])
        case .compare: return StepScript(duration: GapTimes(dropped: false).end, events: [said])
        case .equation: return StepScript(duration: T.equationFade + T.equationRest, events: [said])
        case .count:
            let times = CountTimes(hops: problem.hops.count, joins: countJoins)
            var events = [said]
            for (h, at) in zip(problem.hops, times.hops) {
                events.append(StepEvent(at, .waitForVoice))
                events.append(StepEvent(at, .say(line(.tick(h.to)), caption: false)))
            }
            events += finishEvents(times)
            return StepScript(duration: times.end, events: events)
        }
    }

    func lineFor(_ s: Step) -> TapeLine {
        switch s {
        case .read: .read
        case .bars: .bars
        case .compare: .compare
        case .equation: .equation
        case .count: .count
        }
    }

    /// The count's end: the tens and ones put together (said, not shown as the caption),
    /// then the answer filled in, and the answer line.
    func finishEvents(_ times: CountTimes) -> [StepEvent] {
        var events: [StepEvent] = []
        if countJoins {
            events.append(StepEvent(times.finish, .waitForVoice))
            events.append(StepEvent(times.finish, .say(line(.countJoin), caption: false)))
            events.append(StepEvent(times.finish + 0.001, .waitForVoice))
        }
        events.append(StepEvent(times.end, .waitForVoice))
        events.append(StepEvent(times.end, .say(line(.answer), caption: true)))
        return events
    }

    // MARK: pictures

    /// A picture of the tape diagram, with what a motion changes as it plays.
    struct Picture {
        var state: TapeState
        /// How far each bar has grown, top and bottom.
        var grow: [Double] = [1, 1]
        var drop: Double = 1
        var gapGrow: Double = 1
        var gapBrace: Double = 1
        var gapMark: Double = 1
        var gapScale: Double = 1
        /// The gap's number, and the equation's answer: the difference once it is counted.
        var gapText: String?
        var equationOpacity: Double = 1
        /// The jump being drawn (its index), how far, and its label's opacity.
        var hop: (index: Int, arc: Double, label: Double)?
        var run: String?
        /// The cards: out, and whether the take-away card is chosen.
        var chosen = false
        /// What if?'s handle, at the first bar's end.
        var handle = false
    }

    func drawing(_ s: TapeState) -> Picture { Picture(state: s) }

    func scene(_ p: Picture) -> Scene {
        var pen = Pen()
        let s = p.state
        pen.words("story", text(.story), at: CGPoint(x: 500, y: L.storyY), size: L.storySize)
        pen.question("question", wording.question(problem), center: CGPoint(x: 500, y: L.questionY), size: L.storySize)
        guard s.bars else { return pen.scene }
        bar(&pen, "top", y: L.topY, value: problem.a, name: text(.firstName), dir: -1, grow: p.grow[0])
        bar(&pen, "bottom", y: L.bottomY, value: problem.b, name: text(.secondName), dir: 1, grow: p.grow[1])
        let unknown = text(.unknown)
        let answer = p.gapText ?? (s.answered ? String(problem.difference) : unknown)
        if s.gap && problem.difference > 0 {
            let g = gapRow
            pen.line("drop", CGPoint(x: xb, y: L.topY - 4), CGPoint(x: xb, y: L.bottomY + L.barHeight + 4), progressed(Look.drop, p.drop))
            if p.gapGrow > 0 {
                pen.shape("gap", .rect(CGRect(x: xs, y: g.y, width: (xb - xs) * p.gapGrow, height: L.barHeight), corner: 3), Look.gap)
            }
            pen.shape("gap.brace", brace(xs + 2, xb, g.braceY, dir: g.dir), progressed(Look.gapBrace, p.gapBrace))
            let at = CGPoint(x: (xs + xb) / 2, y: g.labelY)
            pen.words("gap.value", answer, at: at, size: L.gapValueSize, ink: .ink(.result), opacity: p.gapMark,
                transform: scaling(p.gapScale, about: CGPoint(x: at.x, y: at.y - 9)))
        }
        if s.equation {
            let eq = equationRuns(text(.subtractFormat), first: String(problem.big), second: String(problem.small), answer: answer)
            let runs = eq.runs.enumerated().map { i, r in EquationLine.Run(r, i == eq.answer ? .answer : .plain) }
            pen.add("equation", .equation(EquationLine(
                runs: runs, mark: .init(run: eq.sign, op: .subtract, progress: 0), center: CGPoint(x: 500, y: L.equationY),
                size: L.equationSize)), opacity: p.equationOpacity)
        }
        if s.numberLine || s.hops > 0 || p.hop != nil {
            numberLine(&pen)
            for k in 0..<s.hops { hop(&pen, k, arc: 1, label: 1) }
            if let h = p.hop { hop(&pen, h.index, arc: h.arc, label: h.label) }
            let run = p.run ?? running(s.hops, answered: s.answered)
            pen.words("run", run, at: CGPoint(x: xb + 28, y: L.lineY + 8), size: L.hopSize, ink: .ink(.result), anchor: .leading)
        }
        if s.cards {
            cards.draw(&pen, add: cardText(.add), subtract: cardText(.subtract), addGone: s.addShown, chosen: p.chosen)
        }
        if p.handle { handle(&pen) }
        return pen.scene
    }

    func progressed(_ paint: Paint, _ p: Double) -> Paint {
        var paint = paint
        paint.progress = p
        return paint
    }

    /// A person's bar from the shared start, with their name before it and a brace and their
    /// amount above it (the top bar) or below (the bottom), grown `grow` of its length.
    func bar(_ pen: inout Pen, _ id: String, y: CGFloat, value: Int, name: String, dir: CGFloat, grow: Double) {
        let w = CGFloat(value) * scale
        pen.words("\(id).name", name, at: CGPoint(x: L.x0 - 16, y: y + L.barHeight / 2 + 8), size: L.nameSize, anchor: .trailing)
        if grow > 0 {
            pen.shape("\(id).bar", .rect(CGRect(x: L.x0, y: y, width: w * grow, height: L.barHeight), corner: 3), Look.bar)
        }
        let by = dir < 0 ? y - L.braceGap : y + L.barHeight + L.braceGap
        pen.shape("\(id).brace", brace(L.x0, L.x0 + w, by, dir: dir), Look.brace)
        pen.words("\(id).value", String(value), at: CGPoint(x: L.x0 + w / 2, y: by + (dir < 0 ? L.above : L.below)), size: L.valueSize)
    }

    /// The number line under the dashed part: a tick at every jump; a label too close to the next
    /// gives way to it, and when the whole gap is narrow the two ends are labelled outward.
    func numberLine(_ pen: inout Pen) {
        let nl = Paint(stroke: .pencil, width: 2.4)
        pen.line("line", CGPoint(x: xs - 10, y: L.lineY), CGPoint(x: xb + 10, y: L.lineY), nl)
        let marks = ([problem.small] + problem.hops.map(\.to)).map { (v: $0, x: x($0)) }
        for (i, m) in marks.enumerated() {
            pen.line("line.tick.\(i)", CGPoint(x: m.x, y: L.lineY - 8), CGPoint(x: m.x, y: L.lineY + 8), nl)
        }
        let shown = marks.enumerated().filter { i, m in i == 0 || i == marks.count - 1 || marks[i + 1].x - m.x >= 34 }.map(\.element)
        for (j, m) in shown.enumerated() {
            var anchor = Typeset.Anchor.center
            var dx: CGFloat = 0
            if j == 0, shown.count > 1, shown[1].x - m.x < 34 { (anchor, dx) = (.trailing, -3) }
            if j == 1, shown[1].x - shown[0].x < 34 { (anchor, dx) = (.leading, 3) }
            pen.words("line.label.\(j)", String(m.v), at: CGPoint(x: m.x + dx, y: L.lineY + 32), size: L.tickSize, ink: .muted, anchor: anchor)
        }
    }

    /// Jump `k` along the number line, its arc drawn `arc` of the way and its label at `label`.
    func hop(_ pen: inout Pen, _ k: Int, arc: Double, label: Double) {
        let h = problem.hops[k]
        let x1 = x(h.from), x2 = x(h.to), mid = (x1 + x2) / 2
        let top = L.lineY - 14 - min(18, (x2 - x1) / 3)
        let path = Outline.path([.move(CGPoint(x: x1, y: L.lineY - 4)), .quad(to: CGPoint(x: x2, y: L.lineY - 4), control: CGPoint(x: mid, y: top))])
        pen.shape("hop.\(k)", path, Paint(stroke: .ink(.result), width: 2.6, progress: arc))
        pen.words("hop.\(k).label", text(.hop(h.to - h.from)), at: CGPoint(x: mid, y: top - 4), size: L.hopSize, ink: .ink(.result), opacity: label)
    }

    var cards: Cards { Cards(top: L.cardsTop, addFirst: (problem.a + problem.b) % 2 == 0) }

    func cardText(_ kind: Cards.Kind) -> String {
        let unknown = text(.unknown)
        switch kind {
        case .add:
            return equationRuns(text(.addFormat), first: String(problem.a), second: String(problem.b), answer: unknown).runs.joined()
        case .subtract:
            return equationRuns(text(.subtractFormat), first: String(problem.big), second: String(problem.small), answer: unknown).runs.joined()
        }
    }

    /// What if?'s handle on the end of the first person's bar, and "Same!" beside two equal bars.
    func handle(_ pen: inout Pen) {
        let x = x(problem.a)
        pen.shape("handle", .rect(CGRect(x: x - 10, y: L.topY - 12, width: 20, height: L.barHeight + 24), corner: 8), Look.handle)
        for (i, dx) in [CGFloat(-3), 3].enumerated() {
            pen.line("handle.grip.\(i)", CGPoint(x: x + dx, y: L.topY + 6), CGPoint(x: x + dx, y: L.topY + L.barHeight - 6), Look.handleGrip)
        }
        if problem.difference == 0 {
            pen.words("same", text(.same), at: CGPoint(x: x + 22, y: L.topY + L.barHeight / 2 + 9), size: L.gapValueSize, ink: .ink(.result), anchor: .leading)
        }
    }

    // MARK: motion

    /// Step `step` played from `s0` to `s1`, `t` seconds in.
    func motionPicture(_ step: Int, from s0: TapeState, to s1: TapeState, at t: Double) -> Scene {
        let duration = script(for: step).duration
        if t >= duration { return scene(drawing(s1)) }
        switch steps[step] {
        case .read:
            return scene(drawing(s0))
        case .bars:
            var p = drawing(s1)
            p.grow = [
                progress(t, start: 0, duration: T.barGrow, .easeOut),
                progress(t, start: T.barGrow + T.barRest, duration: T.barGrow, .easeOut),
            ]
            return scene(p)
        case .compare:
            var p = drawing(s1)
            p.drop = progress(t, start: 0, duration: T.drop, .easeOut)
            gapMotion(&p, t, GapTimes(dropped: false))
            return scene(p)
        case .equation:
            var p = drawing(s1)
            p.equationOpacity = progress(t, start: 0, duration: T.equationFade)
            return scene(p)
        case .count:
            var base = s0
            base.numberLine = true
            return countPicture(from: base, hopsFrom: 0, times: CountTimes(hops: problem.hops.count, joins: countJoins), at: t)
        }
    }

    /// The shorter bar drawn on: the dashed part grows to the longer bar's length, its brace is
    /// drawn and its question mark appears.
    func gapMotion(_ p: inout Picture, _ t: Double, _ times: GapTimes) {
        p.gapGrow = progress(t, start: times.grow, duration: T.gapGrow, .easeOut)
        p.gapBrace = progress(t, start: times.brace, duration: T.gapBrace, .easeOut)
        p.gapMark = progress(t, start: times.mark, duration: T.gapMark)
        p.gapText = text(.unknown)
    }

    /// Counting on from `base` (with `hopsFrom` jumps already drawn), the jumps at `times.hops`,
    /// then the finish: the running count completed, the answer filled in with a pulse.
    func countPicture(from base: TapeState, hopsFrom k0: Int, times: CountTimes, at t: Double) -> Scene {
        var p = drawing(base)
        p.gapText = text(.unknown)
        var done = k0
        for (i, at) in times.hops.enumerated() where t >= at {
            let k = k0 + i
            let arcEnd = at + T.hopArc
            if t < arcEnd {
                p.hop = (k, progress(t, start: at, duration: T.hopArc, .easeOut), 0)
                p.run = running(k, answered: false)
            } else {
                p.hop = (k, 1, progress(t, start: arcEnd, duration: T.hopLabel))
                p.run = running(k + 1, answered: false)
                done = k + 1
            }
            p.state.hops = k
        }
        if t >= times.finish {
            p.state.hops = done
            p.hop = nil
            p.run = running(done, answered: true)
        }
        if t >= times.fill {
            p.gapText = String(problem.difference)
            p.state.answered = true
            p.gapScale = keyframes([(0, 1), (0.5, 1.2), (1, 1)], progress(t, start: times.fill, duration: T.pulse))
        }
        return scene(p)
    }

    /// The still picture of a state.
    func picture(_ s: TapeState) -> Scene { scene(drawing(s)) }
}
