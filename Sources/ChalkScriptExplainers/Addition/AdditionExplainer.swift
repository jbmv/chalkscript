import ChalkScript
import CoreGraphics
import Foundation

/// Two-digit addition on the worksheet's base-ten drawing, making a new ten when there are ten
/// or more ones (EXP-2, EXP-5, EXP-7). Its steps and timings, in seconds:
///
/// - show: the first number's tens fade in one after another, then its ones.
/// - add ones: the ones digit of the number added is marked; its ones come down from the digit to
///   their places one after another, counted on aloud from the ones already there ("9, 10, 11").
/// - check: a dashed pencil loop is drawn round all the ones, which stand still: ten or more make
///   a ten, fewer stay ones.
/// - bundle: a box is drawn round the first ten ones, then an arrow from it to where the new ten
///   goes; copies of the ten ones travel along the arrow and stack into the new ten, drawn in the
///   trade colour, while the ten ones stay behind as ghosts (EXP-5, as the tens-and-ones bundle).
/// - add tens: the tens digit is marked and its tens come down to their places.
/// - count: every piece is counted where it stands, tens first ("10, 20 … 60", then "1, 2, 3"),
///   each showing its count on itself; the total shows "60 + 3" until it becomes 63, with "60 + 3"
///   left under it, and the answer replaces the question mark.
///
/// Every picture is drawn from an `AdditionState`, so the learner's own choices in do it with me
/// (which ten ones are looped, with the learner's own loop) are drawn as they were made, and Show
/// me plays a step from them (AdditionGuided.swift). The explainer has a child version only.
public struct AdditionExplainer: Explainer {
    public typealias Step = AdditionProblem.Step

    public let problem: AdditionProblem
    public let wording: AdditionWording
    public let layout: AdditionLayout
    /// Do it with me's problem, whose steps leave out the check (`AdditionProblem.steps`).
    public let doing: Bool
    public let steps: [Step]

    public init(problem: AdditionProblem, wording: AdditionWording, doing: Bool = false) {
        self.problem = problem
        self.wording = wording
        self.layout = AdditionLayout(problem)
        self.doing = doing
        self.steps = problem.steps(doing: doing)
    }

    public var version: ExplainerVersion { .child }
    public var stepCount: Int { steps.count }
    public var intro: Line { line(.intro) }

    func line(_ l: AdditionLine) -> Line { wording.line(l, problem) }
    func doLine(_ l: AdditionDoLine) -> Line { wording.doLine(l, problem) }

    /// The counts said over the pieces: 10, 20 … for the tens, then 1, 2 … for the ones.
    public static func counts(_ p: AdditionProblem) -> [Int] {
        (0..<p.sumTens).map { ($0 + 1) * 10 } + (0..<p.sumOnes).map { $0 + 1 }
    }

    // MARK: timing (in seconds)

    enum T {
        static let tenFade = 0.32, tenEvery = 0.18, oneFade = 0.26, oneEvery = 0.16, onesAfterTens = 0.15, showTail = 0.45
        static let mark = 0.35
        /// A moment after the step's line, so the first count is said with its piece.
        static let first = 0.05
        static let arrive = 0.7, arriveOne = 0.62, arriveTen = 0.8, arriveTail = 0.3, tensWait = 0.7
        static let hint = 0.9, hintHold = 0.5
        static let boxDraw = 0.7, arrow = 0.7, travel = 1.5, travelEvery = 0.14, ghostFade = 0.4, newTen = 0.35, bundleTail = 0.25
        static let perTen = 0.85, perOne = 0.56, tag = 1.0, quickTag = 1.1
        static let beforeJoin = 0.25, pulse = 0.5, answerFade = 0.4
        static let place = 0.38, placeWait = 0.4, countWait = 0.5
    }

    /// When the bundle's phases start, from the moment its arrow begins (after the box in the
    /// watched step; at once after the learner's loop).
    struct StackTimes {
        let travelEnd = T.arrow + 9 * T.travelEvery + T.travel
        var newTenEnd: Double { travelEnd + T.newTen }
        var end: Double { newTenEnd + T.bundleTail }
        func travelStart(_ j: Int) -> Double { T.arrow + Double(j) * T.travelEvery }
    }

    /// When the watched count's phases start.
    struct CountTimes {
        let ticks: [Double]
        let countEnd: Double
        let join: Double?
        let answer: Double
        let end: Double
        init(_ p: AdditionProblem) {
            var c = T.first
            var ticks: [Double] = []
            for i in 0..<(p.sumTens + p.sumOnes) {
                ticks.append(c)
                c += i < p.sumTens ? T.perTen : T.perOne
            }
            self.ticks = ticks
            countEnd = c
            if p.sumTens > 0 && p.sumOnes > 0 {
                join = c + T.beforeJoin
                answer = c + T.beforeJoin + T.pulse
            } else {
                join = nil
                answer = c
            }
            end = answer + T.answerFade
        }
    }

    var countTimes: CountTimes { CountTimes(problem) }

    public func script(for step: Int) -> StepScript {
        let s = steps[step]
        let p = problem
        switch s {
        case .show:
            return StepScript(
                duration: Double(p.firstTens) * T.tenEvery + T.showTail + Double(p.firstOnes) * T.oneEvery,
                events: [StepEvent(0, .say(line(.show), caption: true))])
        case .addOnes:
            // Counting on from the ones already there; the line is said first (EXP-10).
            var events = [StepEvent(0, .say(line(.addOnes), caption: true))]
            for j in 0..<p.secondOnes {
                let at = T.first + Double(j) * T.arriveOne
                events += [StepEvent(at, .waitForVoice), StepEvent(at, .say(line(.tick(p.firstOnes + j + 1)), caption: false))]
            }
            return StepScript(duration: T.first + Double(p.secondOnes) * T.arriveOne + T.arriveTail, events: events)
        case .check:
            return StepScript(duration: T.hint + T.hintHold, events: [StepEvent(0, .say(line(.check), caption: true))])
        case .bundle:
            return StepScript(duration: T.boxDraw + StackTimes().end, events: [StepEvent(0, .say(line(.bundle), caption: true))])
        case .addTens:
            return StepScript(
                duration: T.tensWait + Double(p.secondTens) * T.arriveTen + T.arriveTail,
                events: [StepEvent(0, .say(line(.addTens), caption: true))])
        case .count:
            let times = countTimes
            var events = [StepEvent(0, .say(line(.count), caption: true))]
            // Each count waits for the one before it to be heard, so the voice counts in time
            // with the pieces (EXP-10).
            for (n, at) in zip(Self.counts(p), times.ticks) {
                events += [StepEvent(at, .waitForVoice), StepEvent(at, .say(line(.tick(n)), caption: false))]
            }
            if let join = times.join {
                events += [StepEvent(join, .waitForVoice), StepEvent(join, .say(line(.join), caption: true))]
            }
            events += [
                StepEvent(times.answer, .waitForVoice), StepEvent(times.end, .waitForVoice),
                StepEvent(times.end, .say(line(.answer), caption: true)),
            ]
            return StepScript(duration: times.end, events: events)
        }
    }

    // MARK: pictures

    public func still(after step: Int) -> Scene {
        drawing(state(after: step), marking: step >= 0 ? step : nil).scene(self)
    }

    public func scene(step: Int, at t: Double) -> Scene {
        let s0 = state(after: step - 1)
        return motionPicture(step, from: s0, to: apply(steps[step], s0), at: t)
    }

    /// The picture `t` seconds into step `step` played from `s0` to `s1`.
    func motionPicture(_ step: Int, from s0: AdditionState, to s1: AdditionState, at t: Double) -> Scene {
        let duration = script(for: step).duration
        if t >= duration { return drawing(s1, marking: step).scene(self) }
        let t = max(0, t)
        let s = steps[step]
        var p = drawing(s0, marking: nil)
        p.mark = mark(for: s).map { ($0, progress(t, start: 0, duration: T.mark, .easeOut)) }
        switch s {
        case .show: animateShow(&p, t)
        case .addOnes:
            animateArrive(&p, t, ones: true, from: problem.firstOnes + s0.addedOnes, count: s1.addedOnes - s0.addedOnes,
                start: T.first, every: T.arriveOne)
        case .check: p.hint = progress(t, start: 0, duration: T.hint, .easeOut)
        case .bundle:
            p.box = progress(t, start: 0, duration: T.boxDraw, .easeOut)
            animateStack(&p, t - T.boxDraw, bundled: s1.bundled)
        case .addTens:
            animateArrive(&p, t, ones: false, from: tensFrom + s0.addedTens, count: s1.addedTens - s0.addedTens,
                start: T.tensWait, every: T.arriveTen)
        case .count: animateCount(&p, t, s0)
        }
        return p.scene(self)
    }

    /// The digit a step acts on (EXP-5): the ones digit of the number added while its ones are
    /// drawn and looked at, its tens digit while its tens are drawn.
    func mark(for s: Step) -> AdditionPicture.Digit? {
        switch s {
        case .addOnes, .check: .secondOnes
        case .addTens: .secondTens
        case .show, .bundle, .count: nil
        }
    }

    typealias Ref = AdditionPiece

    /// The state before the first step.
    public var start: AdditionState { AdditionState() }

    /// The state after `step` with every step played as watched; -1 is the state before the first.
    public func state(after step: Int) -> AdditionState {
        var s = start
        if step >= 0 { for k in 0...step { s = apply(steps[k], s) } }
        return s
    }

    /// Step `s` as the watched explainer does it, from `state`: the first ten ones bundled.
    public func apply(_ s: Step, _ state: AdditionState) -> AdditionState {
        var n = state
        switch s {
        case .show: n.shown = true
        case .addOnes: n.addedOnes = problem.secondOnes
        case .check: break
        case .bundle:
            n.bundled = Array(0..<10)
            n.newTen = true
            n.loop = nil
        case .addTens: n.addedTens = problem.secondTens
        case .count:
            n.counted = Set(0..<countCount)
            n.answered = true
        }
        return n
    }

    /// The place of the second number's first ten: after the first number's tens and the new ten.
    var tensFrom: Int { problem.firstTens + (problem.regroups ? 1 : 0) }

    /// The ones drawn: the first number's and those of the second drawn so far.
    func onesDrawn(_ s: AdditionState) -> Int { problem.firstOnes + s.addedOnes }

    /// The ones still standing: drawn, and not bundled.
    func liveOnes(_ s: AdditionState) -> [Int] { (0..<onesDrawn(s)).filter { !s.bundled.contains($0) } }

    /// The tens drawn, in order: the first number's, the new ten, the second number's.
    func tensDrawn(_ s: AdditionState) -> [Int] {
        Array(0..<problem.firstTens) + (s.newTen ? [problem.firstTens] : []) + Array(tensFrom..<(tensFrom + s.addedTens))
    }

    /// The order the pieces are counted in: tens first, then the ones still standing.
    func countOrder(_ s: AdditionState) -> [Ref] { tensDrawn(s).map(Ref.ten) + liveOnes(s).map(Ref.one) }

    /// How many pieces are counted: the total's tens and ones.
    var countCount: Int { problem.sumTens + problem.sumOnes }

    func rect(_ r: Ref) -> CGRect {
        switch r {
        case let .ten(i): layout.tens[i]
        case let .one(i): layout.ones[i]
        }
    }

    /// The running total once `n` pieces are counted, tens first: "10", "20", then "60 + 1".
    func runningTotal(_ n: Int) -> String? {
        guard n > 0 else { return nil }
        let t = problem.sumTens
        if n <= t { return String(n * 10) }
        return t > 0 ? wording.runningTotal(t * 10, n - t) : String(n - t)
    }

    /// The box round the ten ones, or the bounds of the learner's loop round them: where the
    /// bundle's arrow starts.
    func bundleFrom(_ loop: [CGPoint]?) -> CGRect {
        guard let loop, let x0 = loop.map(\.x).min(), let x1 = loop.map(\.x).max(), let y0 = loop.map(\.y).min(),
            let y1 = loop.map(\.y).max()
        else { return layout.box }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// The still picture of `s`, with the digit step `step` acts on marked (EXP-5), and the pencil
    /// loop round the ones while a step looks at them.
    func drawing(_ s: AdditionState, marking step: Int?) -> AdditionPicture {
        let p0 = problem
        var p = AdditionPicture(self)
        if s.shown {
            p.labels = 1
            for i in 0..<p0.firstTens { p.tens[i].opacity = 1 }
            for i in 0..<p0.firstOnes { p.ones[i].opacity = 1 }
        }
        for i in p0.firstOnes..<onesDrawn(s) { p.ones[i].opacity = 1 }
        for i in s.bundled { p.ones[i].opacity = Components.ghostOpacity }
        if s.newTen, p0.regroups {
            p.tens[p0.firstTens].opacity = 1
            p.tens[p0.firstTens].style = .traded
            p.arrow = 1
            p.arrowFrom = bundleFrom(s.loop)
            if let loop = s.loop { p.loop = loop } else { p.box = 1 }
        }
        for i in tensFrom..<(tensFrom + s.addedTens) { p.tens[i].opacity = 1 }
        let order = countOrder(s)
        for k in s.counted where order.indices.contains(k) { p[order[k]].style = .counted }
        if !s.counted.isEmpty || s.answered {
            p.total = s.answered ? String(p0.sum) : runningTotal(s.counted.count)
        }
        if s.answered {
            p.answer = String(p0.sum)
            if p0.sumTens > 0 && p0.sumOnes > 0 { p.worked = wording.runningTotal(p0.sumTens * 10, p0.sumOnes) }
        }
        if let step, steps.indices.contains(step) {
            p.mark = mark(for: steps[step]).map { ($0, 1) }
            if steps[step] == .check || (steps[step] == .addOnes && s.onesRinged) { p.hint = 1 }
        }
        return p
    }

    // MARK: motion, step by step

    func animateShow(_ p: inout AdditionPicture, _ t: Double) {
        p.labels = 1
        for i in 0..<problem.firstTens {
            p.tens[i].opacity = progress(t, start: Double(i) * T.tenEvery, duration: T.tenFade)
        }
        let t0 = Double(problem.firstTens) * T.tenEvery + T.onesAfterTens
        for i in 0..<problem.firstOnes {
            p.ones[i].opacity = progress(t, start: t0 + Double(i) * T.oneEvery, duration: T.oneFade)
        }
    }

    /// `count` pieces come down from their digit in the problem to their places, from place
    /// `from`, one every `every` seconds from `start`: the second number joining the first (the
    /// add colour's joining motion, EXP-6).
    func animateArrive(_ p: inout AdditionPicture, _ t: Double, ones: Bool, from: Int, count: Int, start: Double, every: Double) {
        guard count > 0 else { return }
        let eq = equationRuns(answer: p.answer, answerOpacity: p.answerOpacity)
        let run = ones ? eq.onesRun : (eq.tensRun ?? eq.onesRun)
        let source = layout.digitBottom(eq.runs.map(\.text), run: run, size: Components.equationSize)
        for j in 0..<count {
            let i = from + j
            let r = ones ? layout.ones[i] : layout.tens[i]
            let q = progress(t, start: start + Double(j) * every, duration: T.arrive, .easeInOut)
            let d = CGPoint(x: source.x - r.midX, y: source.y - r.minY)
            let off = keyframes([(0, d), (0.3, CGPoint(x: d.x / 2, y: d.y / 2)), (1, .zero)], q)
            let frame = scaled(r, keyframes([(0, 0.6), (0.3, 1), (1, 1)], q)).offsetBy(dx: off.x, dy: off.y)
            let opacity = keyframes([(0, 0), (0.3, 1), (1, 1)], q)
            if ones {
                p.ones[i].frame = frame
                p.ones[i].opacity = opacity
            } else {
                p.tens[i].frame = frame
                p.tens[i].opacity = opacity
            }
        }
    }

    /// The bundle from the moment its arrow begins (`t` seconds after): the arrow is drawn, then
    /// copies of ones `bundled`, in the trade colour, rise, follow the arrow and stack into the
    /// new ten one after another, while the ones themselves fade to ghosts; the new ten appears
    /// over the stacked copies.
    func animateStack(_ p: inout AdditionPicture, _ t: Double, bundled: [Int]) {
        guard problem.regroups else { return }
        let times = StackTimes()
        let ten = layout.tens[problem.firstTens]
        let from = p.arrowFrom
        let top = layout.arrowY - 12
        p.arrow = progress(t, start: 0, duration: T.arrow, .easeOut)
        for (j, i) in bundled.enumerated() where p.movers.indices.contains(j) {
            let r = layout.ones[i]
            let q = progress(t, start: times.travelStart(j), duration: T.travel, .easeInOut)
            let at = keyframes([
                (0, r.origin), (0.35, CGPoint(x: from.midX - 10, y: top)), (0.7, CGPoint(x: ten.midX - 10, y: top)),
                (1, CGPoint(x: ten.minX + 1, y: ten.minY + CGFloat(j) * ten.height / 10 + 1)),
            ], q)
            p.movers[j].frame = CGRect(origin: at, size: r.size)
            p.movers[j].opacity = t >= T.arrow && t < times.newTenEnd ? 1 : 0
            p.ones[i].opacity = mix(1, Components.ghostOpacity, progress(t, start: T.arrow, duration: T.ghostFade))
        }
        p.tens[problem.firstTens].style = .traded
        p.tens[problem.firstTens].opacity = progress(t, start: times.travelEnd, duration: T.newTen)
    }

    /// The watched count: each piece in turn shows its count on itself and keeps the counted
    /// fill; then tens and ones are put together and the answer is written.
    func animateCount(_ p: inout AdditionPicture, _ t: Double, _ s0: AdditionState) {
        let times = countTimes
        let order = countOrder(s0)
        let tens = problem.sumTens
        let counts = Self.counts(problem)
        for (k, at) in times.ticks.enumerated() where t >= at && order.indices.contains(k) {
            p[order[k]].style = .counted
            p.total = runningTotal(k + 1)
            p.tags[k] = AdditionPicture.Tag(
                text: line(.tick(counts[k])).display, rect: Components.numberTag(on: rect(order[k]), ten: k < tens),
                opacity: keyframes([(0, 0), (0.15, 1), (0.75, 1), (1, 0)], progress(t, start: at, duration: T.tag)))
        }
        if let join = times.join, t >= join {
            p.total = String(problem.sum)
            p.totalScale = keyframes([(0, 1), (0.5, 1.15), (1, 1)], progress(t, start: join, duration: T.pulse))
            p.worked = wording.runningTotal(problem.sumTens * 10, problem.sumOnes)
        }
        if t >= times.countEnd, times.join == nil { p.total = String(problem.sum) }
        if t >= times.answer {
            p.answer = String(problem.sum)
            p.answerOpacity = progress(t, start: times.answer, duration: T.answerFade)
        }
    }

    func scaled(_ r: CGRect, _ s: Double) -> CGRect {
        if s >= 1 { return r }
        return r.insetBy(dx: r.width * (1 - s) / 2, dy: r.height * (1 - s) / 2)
    }

    /// The problem across the top from the wording's equation, each number in its slot; the
    /// number added is split into its digits so either can be marked. Returns the runs and which
    /// of them are the number added's tens and ones digits.
    func equationRuns(answer: String, answerOpacity: Double) -> (runs: [EquationLine.Run], tensRun: Int?, onesRun: Int) {
        var runs: [EquationLine.Run] = []
        var tensRun: Int?
        var onesRun = 0
        var literal = ""
        func flush() {
            if !literal.isEmpty { runs.append(.init(literal)) }
            literal = ""
        }
        for c in wording.equation {
            switch String(c) {
            case EquationSlot.first:
                flush()
                runs.append(.init(String(problem.first)))
            case EquationSlot.second:
                flush()
                if problem.secondTens > 0 {
                    tensRun = runs.count
                    runs.append(.init(String(problem.secondTens)))
                }
                onesRun = runs.count
                runs.append(.init(String(problem.secondOnes)))
            case EquationSlot.answer:
                flush()
                runs.append(.init(answer, .answer, opacity: answerOpacity))
            default:
                literal.append(c)
            }
        }
        flush()
        return (runs, tensRun, onesRun)
    }
}

/// A piece of the addition's drawing: a ten or a one, by its place.
public enum AdditionPiece: Hashable, Sendable {
    case ten(Int)
    case one(Int)
}

/// Everything an addition picture can show (EXP-2): what has been drawn, bundled and counted, and
/// the learner's own loop (EXP-14).
public struct AdditionState: Equatable, Sendable {
    /// The first number is drawn as tens and ones.
    public var shown = false
    /// The second number's ones drawn so far.
    public var addedOnes = 0
    /// The ones put into the new ten, in the order they stack; ghosts from then on.
    public var bundled: [Int] = []
    /// The new ten is made.
    public var newTen = false
    /// The second number's tens drawn so far.
    public var addedTens = 0
    /// The learner's adding step ended with the loop round the ones (do it with me's adding step
    /// does what the watched check step does).
    public var onesRinged = false
    /// The learner's own loop round the ten ones bundled, drawn in place of the box.
    public var loop: [CGPoint]?
    /// The pieces counted, by their place in the count (tens first, then the ones standing).
    public var counted: Set<Int> = []
    /// The answer is written.
    public var answered = false

    public init() {}
}

/// Everything an addition step can show, as values; `scene` turns it into elements with the
/// shared components. The same elements, in the same order, at every moment, so a piece keeps
/// its id through a step.
struct AdditionPicture {
    enum Digit { case secondTens, secondOnes }

    struct Piece {
        var frame: CGRect
        var style: PieceStyle
        var opacity = 0.0
    }

    /// The count a piece shows on itself while it is counted.
    struct Tag {
        var text = ""
        var rect = CGRect.zero
        var opacity = 0.0
    }

    var labels = 0.0
    var tens: [Piece]
    var ones: [Piece]
    /// The copies of the ten ones that travel into the new ten.
    var movers: [Piece]
    var box = 0.0
    var loop: [CGPoint]?
    var arrow = 0.0
    var arrowFrom: CGRect
    var hint = 0.0
    /// By place in the count.
    var tags: [Tag]
    var total: String?
    var totalScale = 1.0
    var worked: String?
    var mark: (Digit, Double)?
    var answer: String
    var answerOpacity = 1.0

    init(_ e: AdditionExplainer) {
        let l = e.layout
        tens = l.tens.map { Piece(frame: $0, style: .pencil) }
        ones = l.ones.map { Piece(frame: $0, style: .pencil) }
        movers = e.problem.regroups ? (0..<10).map { Piece(frame: l.ones[$0], style: .traded) } : []
        arrowFrom = l.box
        tags = Array(repeating: Tag(), count: e.countCount)
        answer = e.wording.unknown
    }

    subscript(r: AdditionExplainer.Ref) -> Piece {
        get {
            switch r {
            case let .ten(i): tens[i]
            case let .one(i): ones[i]
            }
        }
        set {
            switch r {
            case let .ten(i): tens[i] = newValue
            case let .one(i): ones[i] = newValue
            }
        }
    }

    func scene(_ e: AdditionExplainer) -> Scene {
        let l = e.layout
        var out: [SceneElement] = []
        let eq = e.equationRuns(answer: answer, answerOpacity: answerOpacity)
        let marked: Int? =
            switch mark?.0 {
            case .secondOnes: eq.onesRun
            case .secondTens: eq.tensRun
            case nil: nil
            }
        let m = marked.flatMap { i in mark.map { EquationLine.Mark(run: i, op: .add, progress: $0.1) } }
        out.append(SceneElement("equation", .equation(EquationLine(runs: eq.runs, mark: m, center: l.equationCenter, size: Components.equationSize))))
        out.append(SceneElement("divider", .divider(from: l.dividerFrom, to: l.dividerTo)))
        out.append(SceneElement("label.tens", .label(e.wording.tensLabel, at: l.tensLabel), opacity: labels))
        out.append(SceneElement("label.ones", .label(e.wording.onesLabel, at: l.onesLabel), opacity: labels))
        for (i, p) in tens.enumerated() { out.append(SceneElement("ten.\(i)", .ten(p.frame, p.style), opacity: p.opacity)) }
        for (i, p) in ones.enumerated() { out.append(SceneElement("one.\(i)", .one(p.frame, p.style), opacity: p.opacity)) }
        if e.problem.regroups {
            out.append(SceneElement("box", .box(l.box, progress: box, op: .trade)))
            // The learner's own loop, in the trade's colour, in place of the box (EXP-14).
            out.append(SceneElement("loop", .ink(loop ?? [], op: .trade), opacity: loop == nil ? 0 : 1))
            let newTen = l.tens[e.problem.firstTens]
            out.append(SceneElement("arrow", .arrow(
                points: Components.bundleArrow(from: arrowFrom, to: newTen, y: l.arrowY), progress: arrow, op: .trade)))
        }
        if let ring = Components.hint(around: l.ones) {
            out.append(SceneElement("hint", .hint(ring, progress: hint)))
        }
        for (j, p) in movers.enumerated() { out.append(SceneElement("bundle.\(j)", .one(p.frame, p.style), opacity: p.opacity)) }
        for (k, t) in tags.enumerated() {
            out.append(SceneElement("tag.\(k)", .numberTag(t.text, in: t.rect, scale: 1), opacity: t.opacity))
        }
        out.append(SceneElement("total", .total(total ?? "", at: l.totalAt, scale: totalScale), opacity: total == nil ? 0 : 1))
        out.append(SceneElement("worked", .text(worked ?? "", at: l.workedAt, style: .worked), opacity: worked == nil ? 0 : 1))
        return Scene(elements: out)
    }
}
