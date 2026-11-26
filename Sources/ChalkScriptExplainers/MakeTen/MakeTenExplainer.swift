import ChalkScript
import CoreGraphics
import Foundation

/// Adding within 20 by making a ten, on two ten frames (EXP-2, EXP-5, EXP-7). Its steps
/// and timings, in seconds:
///
/// - show: the frames are drawn with the number each holds beside it; the bigger number's
///   counters (filled, in the top frame) fade in one after another, then the smaller number's
///   (open, in the bottom frame). Filled and open counters tell the two numbers apart without
///   colour (EXP-6).
/// - need: a dashed pencil circle is drawn in each empty box of the top frame, and each is
///   counted aloud ("one, two").
/// - split: the smaller number in the problem is marked in add's colour (EXP-5); the number bond
///   appears (the smaller number over what the ten needs and what is left), and a pencil loop
///   is drawn round the dots that will move, which stand still.
/// - move: each of those dots travels up into an empty box; it has moved, not been taken away,
///   so no ghost stays behind (EXP-5's ghosts are for what is traded or taken away).
///   "8 + 2 = 10" is written under the bond.
/// - count: the full frame is counted as ten, its counters filled in the answer's colour with a
///   "10" tag over it; then each dot left is counted on ("eleven", "twelve") with its count on
///   itself, the worked line running "10", "10 + 1" until it becomes "10 + 5 = 15"; the answer
///   replaces the question mark, and the last line says the whole problem.
///
/// Every picture is drawn from a `MakeTenState`, so the learner's own choices in do it with me
/// (which boxes were touched, which dots were dragged where, the order the dots were counted in)
/// are drawn as they were made, and Show me plays a step from them (MakeTenGuided.swift).
public struct MakeTenExplainer: Sendable {
    public typealias Step = MakeTenProblem.Step
    typealias L = MakeTenLayout

    public let problem: MakeTenProblem
    public let wording: MakeTenWording
    public let steps: [Step]

    public init(problem: MakeTenProblem, wording: MakeTenWording) {
        self.problem = problem
        self.wording = wording
        self.steps = problem.steps
    }

    public var stepCount: Int { steps.count }

    func line(_ l: MakeTenLine) -> Line { wording.line(l, problem) }
    func doLine(_ l: MakeTenDoLine) -> Line { wording.doLine(l, problem) }

    // MARK: timing (in seconds)

    enum T {
        static let dotFade = 0.26, dotEvery = 0.12, bottomGap = 3.0, showTail = 0.4
        static let markDraw = 0.42, markGap = 0.3
        static let bondFade = 0.6, loopDraw = 0.8, splitTail = 0.4, digitMark = 0.35
        static let travel = 0.9, travelGap = 0.15, workFade = 0.4
        static let tenTag = 1.4, tenHold = 0.6, oneEvery = 0.56, oneTag = 1.0, beforeAnswer = 0.5, answerFade = 0.4
        /// The learner's own marks: a box's circle drawn, a dot settling, and the pause before the
        /// line said once a step is done.
        static let tapMark = 0.3, settle = 0.22, afterDone = 0.4
        /// The count starts just after the step's line, which a step that counts aloud says
        /// first (EXP-10).
        static let countStart = 0.02
    }

    /// When the count step's phases start.
    struct CountTimes {
        let ten = T.countStart
        let ones: [Double]
        let answer: Double
        let end: Double
        init(_ p: MakeTenProblem) {
            let first = T.countStart + T.tenHold
            ones = (1...p.rest).map { first + Double($0) * T.oneEvery }
            answer = (ones.last ?? first) + T.beforeAnswer
            end = answer + T.answerFade
        }
    }

    var countTimes: CountTimes { CountTimes(problem) }

    public func script(for step: Int) -> StepScript {
        switch steps[step] {
        case .show:
            let n = Double(problem.big + problem.small)
            return StepScript(
                duration: (n + T.bottomGap) * T.dotEvery + T.showTail, events: [StepEvent(0, .say(line(.show), caption: true))])
        case .need:
            var events = [StepEvent(0, .say(line(.need), caption: true))]
            for k in 0..<problem.need {
                let at = Double(k) * (T.markDraw + T.markGap)
                // Each count waits for the one before it to be heard, so the voice counts in time
                // with the boxes (EXP-10).
                if k > 0 { events.append(StepEvent(at, .waitForVoice)) }
                events.append(StepEvent(at + T.markDraw, .say(line(.tick(k + 1)), caption: false)))
            }
            return StepScript(duration: Double(problem.need) * (T.markDraw + T.markGap), events: events)
        case .split:
            return StepScript(duration: T.bondFade + T.loopDraw + T.splitTail, events: [StepEvent(0, .say(line(.split), caption: true))])
        case .move:
            return StepScript(
                duration: Double(problem.need) * (T.travel + T.travelGap) + T.workFade,
                events: [StepEvent(0, .say(line(.move), caption: true))])
        case .count:
            let times = countTimes
            var events = [
                StepEvent(0, .say(line(.count), caption: true)),
                StepEvent(times.ten, .say(line(.tick(10)), caption: false)),
                StepEvent(times.ten + T.tenHold, .waitForVoice),
            ]
            for (k, at) in times.ones.enumerated() {
                events.append(StepEvent(at, .waitForVoice))
                events.append(StepEvent(at, .say(line(.tick(11 + k)), caption: false)))
            }
            events.append(StepEvent(times.end, .waitForVoice))
            events.append(StepEvent(times.end, .say(line(.answer), caption: true)))
            return StepScript(duration: times.end, events: events)
        }
    }

    // MARK: states

    /// The state before the first step.
    public var start: MakeTenState { MakeTenState() }

    /// The state after `step` with every step played as watched; -1 is the state before the first.
    public func state(after step: Int) -> MakeTenState {
        var s = start
        if step >= 0 { for k in 0...step { s = apply(steps[k], s) } }
        return s
    }

    /// Step `s` as the watched explainer does it, from `state`: the empty boxes in order, the
    /// last dots of the bottom frame moved (so those left stay together at its start), the dots
    /// left counted in order.
    public func apply(_ s: Step, _ state: MakeTenState) -> MakeTenState {
        var n = state
        n.dragging = nil
        switch s {
        case .show: n.shown = true
        case .need: n.marked = Array(problem.big..<10)
        case .split: n.split = true
        case .move: n.moved = watchedMoves
        case .count:
            n.countedTen = true
            n.countedOnes = remaining(n)
            n.answered = true
        }
        return n
    }

    /// The moves the watched step makes: the last dot to the first empty box, and so on.
    var watchedMoves: [MakeTenMove] {
        (0..<problem.need).map { MakeTenMove(dot: problem.small - 1 - $0, cell: problem.big + $0) }
    }

    /// The dots still in the bottom frame, in order.
    func remaining(_ s: MakeTenState) -> [Int] {
        (0..<problem.small).filter { i in !s.moved.contains { $0.dot == i } }
    }

    /// The empty boxes of the top frame no dot has moved into.
    func free(_ s: MakeTenState) -> [Int] {
        (problem.big..<10).filter { c in !s.moved.contains { $0.cell == c } }
    }

    // MARK: pictures

    /// The digit a step acts on (EXP-5): the smaller number, in add's colour, while it is split
    /// and while its part moves up.
    func marksSmall(_ s: Step) -> Bool { s == .split || s == .move }

    /// The still picture of `s`, with the digit step `step` acts on marked, and the pencil loop
    /// of the split step, as its motion ends (EXP-11).
    func drawing(_ s: MakeTenState, marking step: Int?) -> MakeTenPicture {
        var p = MakeTenPicture(self)
        if s.shown {
            p.labels = 1
            for i in p.top.indices { p.top[i].opacity = 1 }
            for i in p.bottom.indices { p.bottom[i].opacity = 1 }
        }
        for c in s.marked { p.marks[c - problem.big] = 1 }
        for mv in s.moved {
            p.bottom[mv.dot].opacity = 0
            p.arrived[mv.cell - problem.big] = MakeTenPicture.Dot(center: L.center(top: true, mv.cell), opacity: 1)
            p.marks[mv.cell - problem.big] = 0
        }
        if s.countedTen {
            for i in p.top.indices { p.top[i].counted = true }
            for j in p.arrived.indices { p.arrived[j].counted = true }
            p.work2 = s.countedOnes.isEmpty ? String(10) : wording.partial(10, s.countedOnes.count)
        }
        for i in s.countedOnes { p.bottom[i].counted = true }
        if s.split { p.bond = 1 }
        if s.moved.count == problem.need || s.answered { p.work1 = 1 }
        if s.answered {
            p.work2 = wording.sum(10, problem.rest, problem.sum)
            p.answer = String(problem.sum)
        }
        if let d = s.dragging {
            p.bottom[d.dot].opacity = 0
            p.drag = d.at
        }
        if let step, steps.indices.contains(step) {
            if marksSmall(steps[step]) { p.digitMark = 1 }
            if steps[step] == .split { p.hint = 1 }
        }
        return p
    }

    /// The picture `t` seconds into step `step` played from `s0` to `s1`.
    func motionPicture(_ step: Int, from s0: MakeTenState, to s1: MakeTenState, at t: Double) -> Scene {
        let duration = script(for: step).duration
        if t >= duration { return drawing(s1, marking: step).scene(self) }
        let t = max(0, t)
        var p = drawing(s0, marking: nil)
        let s = steps[step]
        if marksSmall(s) { p.digitMark = progress(t, start: 0, duration: T.digitMark, .easeOut) }
        switch s {
        case .show: animateShow(&p, t)
        case .need: animateNeed(&p, t)
        case .split:
            p.bond = progress(t, start: 0, duration: T.bondFade)
            p.hint = progress(t, start: T.bondFade, duration: T.loopDraw, .easeOut)
        case .move: animateMove(&p, t, s1.moved.filter { !s0.moved.contains($0) })
        case .count: animateCount(&p, t, ones: remaining(s0))
        }
        return p.scene(self)
    }

    func animateShow(_ p: inout MakeTenPicture, _ t: Double) {
        p.labels = 1
        for i in p.top.indices {
            p.top[i].opacity = progress(t, start: Double(i) * T.dotEvery, duration: T.dotFade)
        }
        for i in p.bottom.indices {
            let k = Double(problem.big + i) + T.bottomGap
            p.bottom[i].opacity = progress(t, start: k * T.dotEvery, duration: T.dotFade)
        }
    }

    func animateNeed(_ p: inout MakeTenPicture, _ t: Double) {
        for k in 0..<problem.need {
            p.marks[k] = progress(t, start: Double(k) * (T.markDraw + T.markGap), duration: T.markDraw, .easeOut)
        }
    }

    /// Each dot travels up to its box, along a curve: out to the right and up.
    func animateMove(_ p: inout MakeTenPicture, _ t: Double, _ moves: [MakeTenMove]) {
        for (j, mv) in moves.enumerated() {
            let start = Double(j) * (T.travel + T.travelGap)
            guard t >= start else { continue }
            p.bottom[mv.dot].opacity = 0
            let to = L.center(top: true, mv.cell)
            let from = L.center(top: false, mv.dot)
            let d = CGPoint(x: from.x - to.x, y: from.y - to.y)
            let q = progress(t, start: start, duration: T.travel, .easeInOut)
            let off = keyframes([(0, d), (0.5, CGPoint(x: d.x * 0.4 + 30, y: d.y * 0.5)), (1, .zero)], q)
            p.arrived[mv.cell - problem.big] = MakeTenPicture.Dot(center: CGPoint(x: to.x + off.x, y: to.y + off.y), opacity: 1)
        }
        let written = Double(moves.count) * (T.travel + T.travelGap)
        p.work1 = progress(t, start: written, duration: T.workFade)
    }

    /// The full frame counted as ten, then each of `ones` counted on, then the answer.
    func animateCount(_ p: inout MakeTenPicture, _ t: Double, ones: [Int]) {
        let times = countTimes
        guard t >= times.ten else { return }
        for i in p.top.indices { p.top[i].counted = true }
        for j in p.arrived.indices { p.arrived[j].counted = true }
        p.tenTag = keyframes([(0, 0), (0.15, 1), (0.8, 1), (1, 0)], progress(t, start: times.ten, duration: T.tenTag))
        p.work2 = String(10)
        for (k, at) in times.ones.enumerated() where t >= at && k < ones.count {
            let i = ones[k]
            p.bottom[i].counted = true
            p.oneTags[i] = MakeTenPicture.Tag(
                text: line(.tick(11 + k)).display,
                opacity: keyframes([(0, 0), (0.15, 1), (0.75, 1), (1, 0)], progress(t, start: at, duration: T.oneTag)))
            p.work2 = wording.partial(10, k + 1)
        }
        if t >= times.answer {
            p.work2 = wording.sum(10, problem.rest, problem.sum)
            p.answer = String(problem.sum)
            p.answerOpacity = progress(t, start: times.answer, duration: T.answerFade)
        }
    }
}

/// A dot moved from the bottom frame into a box of the top one.
public struct MakeTenMove: Equatable, Hashable, Sendable {
    /// The dot of the bottom frame, by its box (0 up to the smaller number).
    public var dot: Int
    /// The box of the top frame it moved into (the bigger number up to 9).
    public var cell: Int

    public init(dot: Int, cell: Int) {
        self.dot = dot
        self.cell = cell
    }
}

/// A dot the learner is dragging, and where it is now, in scene units.
public struct MakeTenDrag: Equatable, Sendable {
    public var dot: Int
    public var at: CGPoint

    public init(dot: Int, at: CGPoint) {
        self.dot = dot
        self.at = at
    }
}

/// Everything a make-a-ten picture can show (EXP-2): what has been drawn, touched, split, moved
/// and counted, including the learner's own choices (EXP-14).
public struct MakeTenState: Equatable, Sendable {
    /// The two numbers are drawn in the frames.
    public var shown = false
    /// The empty boxes of the top frame touched (or circled), in the order they were.
    public var marked: [Int] = []
    /// The number bond is drawn.
    public var split = false
    /// The dots moved up, in the order they were.
    public var moved: [MakeTenMove] = []
    /// The full top frame has been counted as ten.
    public var countedTen = false
    /// The dots left in the bottom frame counted on, in the order they were.
    public var countedOnes: [Int] = []
    /// The answer is written.
    public var answered = false
    /// The dot being dragged, while the learner drags one.
    public var dragging: MakeTenDrag?

    public init() {}
}

/// Everything a make-a-ten step can show, as values; `scene` turns it into elements. The same
/// elements, in the same order, at every moment, so a piece keeps its id through a step.
struct MakeTenPicture {
    typealias L = MakeTenLayout

    struct Dot {
        var center: CGPoint
        var opacity = 0.0
        var counted = false
    }

    struct Tag {
        var text = ""
        var opacity = 0.0
    }

    /// The frames and the numbers beside them.
    var labels = 0.0
    /// The bigger number's filled counters, in the top frame.
    var top: [Dot]
    /// The dashed circles in the top frame's empty boxes, by box from the bigger number on.
    var marks: [Double]
    /// The open counters moved into the top frame's empty boxes, by box.
    var arrived: [Dot]
    /// The smaller number's open counters, in the bottom frame.
    var bottom: [Dot]
    var bond = 0.0
    var hint = 0.0
    /// "8 + 2 = 10", and the count on from ten under it.
    var work1 = 0.0
    var work2: String?
    var tenTag = 0.0
    var oneTags: [Tag]
    var answer: String
    var answerOpacity = 1.0
    /// The smaller number marked in add's colour, growing in from 0 to 1.
    var digitMark = 0.0
    /// Where the dot being dragged is.
    var drag: CGPoint?

    init(_ e: MakeTenExplainer) {
        let p = e.problem
        top = (0..<p.big).map { Dot(center: L.center(top: true, $0)) }
        marks = Array(repeating: 0, count: p.need)
        arrived = (p.big..<10).map { Dot(center: L.center(top: true, $0)) }
        bottom = (0..<p.small).map { Dot(center: L.center(top: false, $0)) }
        oneTags = Array(repeating: Tag(), count: p.small)
        answer = e.wording.unknown
    }

    /// A counter: filled in pencil for the bigger number, open for the smaller; in the answer's
    /// colour once counted (filled solid, or open on its pale tint).
    func counter(_ id: String, _ d: Dot, open: Bool) -> SceneElement {
        let paint: Paint =
            switch (open, d.counted) {
            case (false, false): Paint(fill: .pencil, stroke: .pencil, width: L.filledWidth)
            case (false, true): Paint(fill: .fill(.result), stroke: .fill(.result), width: L.filledWidth)
            case (true, false): Paint(fill: .sheet, stroke: .pencil, width: L.openWidth)
            case (true, true): Paint(fill: .soft(.result), stroke: .fill(.result), width: L.openWidth)
            }
        return SceneElement(id, .shape(.ellipse(L.counter(at: d.center)), paint), opacity: d.opacity)
    }

    /// Text set by its baseline, `y`: the stage anchors text by
    /// its line's bottom, so the line is set a quarter of its size lower.
    static func words(_ text: String, x: CGFloat, y: CGFloat, size: Double, anchor: Typeset.Anchor = .center) -> SceneElement.Kind {
        .words(text, Typeset(at: CGPoint(x: x, y: y + CGFloat(size) * 0.25), size: size, ink: .text, anchor: anchor))
    }

    func scene(_ e: MakeTenExplainer) -> Scene {
        let p = e.problem
        var out: [SceneElement] = []
        out.append(SceneElement("equation", .equation(equation(e))))
        out.append(SceneElement("divider", .divider(from: L.dividerFrom, to: L.dividerTo)))
        for top in [true, false] {
            let name = top ? "top" : "bottom"
            let f = L.frame(top: top)
            let n = top ? p.big : p.small
            out.append(SceneElement("value.\(name)", Self.words(String(n), x: L.valueX, y: f.minY + L.cell + 10, size: L.valueSize, anchor: .trailing), opacity: labels))
            out.append(SceneElement("frame.\(name)", .shape(.rect(f, corner: L.frameCorner), Paint(stroke: .pencil, width: L.frameWidth)), opacity: labels))
            out.append(SceneElement("frame.\(name).lines", .shape(.path(L.frameLines(top: top)), Paint(stroke: .pencil, width: L.frameLineWidth)), opacity: labels))
        }
        for (i, d) in top.enumerated() { out.append(counter("top.dot.\(i)", d, open: false)) }
        for (j, m) in marks.enumerated() {
            let c = L.center(top: true, p.big + j)
            out.append(SceneElement("mark.\(p.big + j)", .shape(.ellipse(L.counter(at: c)),
                Paint(stroke: .muted, width: L.markWidth, dash: L.markDash, progress: m)), opacity: m > 0 ? 1 : 0))
        }
        for (j, d) in arrived.enumerated() { out.append(counter("top.moved.\(p.big + j)", d, open: true)) }
        for (i, d) in bottom.enumerated() { out.append(counter("bottom.dot.\(i)", d, open: true)) }
        // The number bond: the smaller number over what the ten needs and what is left.
        let b = L.bondCenter
        let parts = [(L.bondLeft, p.need, "need"), (L.bondRight, p.rest, "rest")]
        for (c, _, name) in parts {
            out.append(SceneElement("bond.line.\(name)", .shape(.lines([CGPoint(x: b.x, y: b.y + L.bondRadius), CGPoint(x: c.x, y: c.y - L.bondPartRadius)]),
                Paint(stroke: .pencil, width: L.bondWidth)), opacity: bond))
        }
        let circles = [(b, L.bondRadius, p.small, "small")] + parts.map { ($0.0, L.bondPartRadius, $0.1, $0.2) }
        for (c, r, n, name) in circles {
            out.append(SceneElement("bond.\(name)", .shape(.ellipse(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                Paint(fill: .sheet, stroke: .pencil, width: L.bondWidth)), opacity: bond))
            let at = L.bondText(at: c)
            out.append(SceneElement("bond.\(name).number", Self.words(String(n), x: at.x, y: at.y, size: L.bondTextSize), opacity: bond))
        }
        if let ring = Components.hint(around: (p.small - p.need..<p.small).map { L.counter(at: L.center(top: false, $0)) }) {
            out.append(SceneElement("hint", .hint(ring, progress: hint)))
        }
        out.append(SceneElement("work.1", Self.words(e.wording.sum(p.big, p.need, 10), x: b.x, y: L.workY.0, size: L.workSize), opacity: work1))
        out.append(SceneElement("work.2", Self.words(work2 ?? "", x: b.x, y: L.workY.1, size: L.workSize), opacity: work2 == nil ? 0 : 1))
        out.append(SceneElement("tag.ten", .numberTag(e.line(.tick(10)).display, in: L.tenTag(), scale: 1), opacity: tenTag))
        for (i, t) in oneTags.enumerated() {
            out.append(SceneElement("tag.one.\(i)", .numberTag(t.text, in: L.oneTag(i, digits: max(1, t.text.count)), scale: 1), opacity: t.opacity))
        }
        out.append(counter("drag", Dot(center: drag ?? L.center(top: false, 0), opacity: drag == nil ? 0 : 1), open: true))
        return Scene(elements: out)
    }

    /// The problem across the top from the wording's equation, each number in its slot; the
    /// smaller number can be marked.
    func equation(_ e: MakeTenExplainer) -> EquationLine {
        let p = e.problem
        var runs: [EquationLine.Run] = []
        var marked: Int?
        var literal = ""
        func flush() {
            if !literal.isEmpty { runs.append(.init(literal)) }
            literal = ""
        }
        for c in e.wording.equation {
            switch String(c) {
            case EquationSlot.first:
                flush()
                if !p.firstOnTop { marked = runs.count }
                runs.append(.init(String(p.first)))
            case EquationSlot.second:
                flush()
                if p.firstOnTop { marked = runs.count }
                runs.append(.init(String(p.second)))
            case EquationSlot.answer:
                flush()
                runs.append(.init(answer, .answer, opacity: answerOpacity))
            default:
                literal.append(c)
            }
        }
        flush()
        let m = digitMark > 0 ? marked.map { EquationLine.Mark(run: $0, op: .add, progress: digitMark) } : nil
        return EquationLine(runs: runs, mark: m, center: L.equationCenter, size: Components.equationSize)
    }
}

/// The watched steps as the paced player and the revision fingerprint reads an explainer
/// (`Explainer`): the child version's, since make a ten has no parent wording yet (EXP-9).
extension MakeTenExplainer: Explainer {
    public var version: ExplainerVersion { .child }
    public var intro: Line { line(.intro) }

    public func scene(step: Int, at t: Double) -> Scene {
        let s0 = state(after: step - 1)
        return motionPicture(step, from: s0, to: apply(steps[step], s0), at: t)
    }

    public func still(after step: Int) -> Scene {
        drawing(state(after: step), marking: step >= 0 ? step : nil).scene(self)
    }
}
