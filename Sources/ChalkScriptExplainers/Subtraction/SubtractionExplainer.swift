import ChalkScript
import CoreGraphics
import Foundation

/// Two-digit subtraction on a base-ten drawing, by trading a ten when the ones are short (EXP-2,
/// EXP-5, EXP-7). Its steps and timings, in seconds:
///
/// - show: the tens drop in one after another, then the ones.
/// - short or enough: the ones digit of the number taken away is marked, and a dashed pencil loop
///   is drawn round the ones, which stand still (motion only where it carries meaning).
/// - trade: the arrow is drawn from the last ten to where the box will be; the ten splits into
///   ten ones over it, fades to a ghost and is crossed out; the ones separate, rise, follow the
///   arrow and drop into place one after another; the box is drawn round them.
/// - take ones, take tens: the digit acted on is marked; each piece taken away is crossed out and
///   fades to a ghost, one at a time, ones from the loose ones first.
/// - count: what is left is copied to the count area and counted, tens first ("10, 20") and then
///   the ones ("1 … 8"), the total shown as "20 + 8" until it becomes 28; the answer replaces
///   the question mark, and the last line says the whole problem. The parent version counts
///   2.5 times as fast and shows the counts without saying them (EXP-9).
///
/// The timings are the motion file's (`Resources/subtraction-motion.json`, EXP-19); the code
/// holds none of its own.
///
/// Laid out for a tall drawing area (`laidOut(for:)`, EXP-17), the count area is under the
/// worksheet and the drawing is seen through a camera (EXP-18) that frames each step's shot, as
/// the motion file names them: the whole drawing to begin, in on the ones while they are looked
/// at and crossed out, back to the ten and the ones for the trade, over to the tens, and back
/// for the count; in do it with me the count is framed close once the pieces are gathered, so
/// each piece is large enough to touch. The problem stays fixed above the camera. A step whose
/// shot differs from the last moves the camera first, while its line is said, and then plays.
///
/// Every picture is drawn from a `SubtractionState`, so the learner's own choices in do it with me
/// (which ten is broken, which ones are crossed out, with the learner's own lines) are drawn as
/// they were made, and Show me plays a step from them (SubtractionGuided.swift).
public struct SubtractionExplainer: Explainer {
    public typealias Step = SubtractionProblem.Step

    public let problem: SubtractionProblem
    public let version: ExplainerVersion
    public let wording: SubtractionWording
    public let layout: SubtractionLayout
    public let steps: [Step]
    /// The shots and timings (EXP-19).
    public let motion: ExplainerMotion
    /// The drawing area it is laid out for, with its camera; nil on the stage (EXP-17).
    public let frame: SubtractionFrame?

    public init(
        problem: SubtractionProblem, version: ExplainerVersion, wording: SubtractionWording,
        motion: ExplainerMotion = SubtractionExplainer.standardMotion
    ) {
        self.init(problem: problem, version: version, wording: wording, motion: motion, area: nil)
    }

    init(problem: SubtractionProblem, version: ExplainerVersion, wording: SubtractionWording, motion: ExplainerMotion, area: CGSize?) {
        self.problem = problem
        self.version = version
        self.wording = wording
        self.motion = motion
        self.steps = problem.steps
        let stacked = area.map(SubtractionFrame.suits) ?? false
        let layout = SubtractionLayout(problem, stacked: stacked)
        self.layout = layout
        self.frame = stacked ? area.map { SubtractionFrame(area: $0, layout: layout, problem: problem, motion: motion) } : nil
    }

    /// The explainer laid out for a drawing area of `area` points (EXP-17): the count area under
    /// the worksheet and the camera framing each step (EXP-18). An area much wider than tall (a
    /// phone in landscape) keeps the stage, scaled to fit.
    public func laidOut(for area: CGSize) -> SubtractionExplainer {
        SubtractionExplainer(problem: problem, version: version, wording: wording, motion: motion, area: area)
    }

    public func laidOutExplainer(for area: CGSize) -> any Explainer { laidOut(for: area) }

    public var stepCount: Int { steps.count }
    public var intro: Line { line(.intro) }
    /// The learner hears each count; the parent sees the counts and hears the step's line and the
    /// total.
    public var speaksCounts: Bool { version == .child }

    /// How long the count step's motions take against the learner's: an adult needs no time to
    /// follow each count (EXP-9). The learner's pace is the motion file's (EXP-8).
    public static func countPace(_ version: ExplainerVersion) -> Double { version == .child ? 1 : 0.4 }

    var countTimes: CountTimes { CountTimes(self, pace: Self.countPace(version)) }
    var tradeTimes: TradeTimes { TradeTimes(self) }

    func line(_ l: SubtractionLine) -> Line { wording.line(l, problem) }

    /// The counts said over what is left: 10, 20 … for the tens, then 1, 2 … for the ones.
    public static func counts(_ p: SubtractionProblem) -> [Int] {
        (0..<p.differenceTens).map { ($0 + 1) * 10 } + (0..<p.differenceOnes).map { $0 + 1 }
    }

    // MARK: timing (the motion file's, in seconds)

    /// When the trade's phases start.
    struct TradeTimes {
        let cubesAppear: Double
        let fade: Double
        let cross: Double
        let travel: Double
        let box: Double
        let ghost: Double
        let end: Double
        let travelDelay: Double
        let travelEvery: Double
        init(_ e: SubtractionExplainer) {
            func v(_ n: SubtractionTiming) -> Double { e.sec(.trade, n) }
            cubesAppear = v(.arrow)
            fade = v(.arrow) + 9 * v(.cubeEvery) + v(.cubeAppear)
            cross = fade + v(.crossDelay)
            travel = cross + v(.crossDraw)
            box = travel + v(.travelDelay) + 9 * v(.travelEvery) + v(.travel)
            ghost = box + v(.boxDraw)
            end = ghost + v(.ghostFade)
            travelDelay = v(.travelDelay)
            travelEvery = v(.travelEvery)
        }
        func travelStart(_ i: Int) -> Double { travel + travelDelay + Double(9 - i) * travelEvery }
    }

    /// When the count step's phases start, at `pace` times the motion file's durations (1 for the
    /// learner, less for the parent).
    struct CountTimes {
        let pace: Double
        let copyEnd: Double
        let ticks: [Double]
        let countEnd: Double
        let join: Double?
        let answer: Double
        let end: Double
        init(_ e: SubtractionExplainer, pace: Double = 1) {
            func v(_ n: SubtractionTiming) -> Double { e.sec(.count, n) }
            let p = e.problem
            self.pace = pace
            let n = p.differenceTens + p.differenceOnes
            // With nothing left (54 - 54) there is nothing to copy or count; the answer still
            // waits a moment, so the question mark does not change as the step begins.
            copyEnd = pace * (n == 0 ? v(.nothingLeft) : v(.copy) + Double(n - 1) * v(.copyEvery))
            var c = copyEnd
            var ticks: [Double] = []
            for i in 0..<n {
                ticks.append(c)
                c += pace * (i < p.differenceTens ? v(.perTen) : v(.perOne))
            }
            self.ticks = ticks
            countEnd = c
            if p.differenceTens > 0 && p.differenceOnes > 0 {
                join = c + pace * v(.beforeJoin)
                answer = c + pace * (v(.beforeJoin) + v(.pulse))
            } else {
                join = nil
                answer = c
            }
            end = answer + pace * v(.answerFade)
        }
    }

    // MARK: the camera (EXP-18)

    /// The shot step `s` plays in, as the motion file names it; nil keeps the shot it is in.
    func shot(_ s: Step) -> String? { motion.steps[s.rawValue]?.shot }

    /// How the camera moves on step `s`.
    func move(_ s: Step) -> CameraMove {
        motion.steps[s.rawValue]?.camera ?? CameraMove(at: 0, duration: 0, easingName: "linear", easing: .linear)
    }

    /// How long step `step` plays from `shot` before its own motion begins: the camera's move to
    /// its shot, when it has to move, and nothing otherwise (EXP-11: one change at a time).
    func lead(_ step: Int, from shot: String?) -> Double {
        guard let plan = frame?.plan else { return 0 }
        let s = steps[step]
        return plan.moves(from: shot, to: self.shot(s) ?? shot) ? move(s).end : 0
    }

    /// The camera holding on `shot`, when laid out with one.
    func camera(_ shot: String?) -> Camera? { frame?.plan.camera(shot) }

    /// When the camera moves on step `step` played from `shot`, on the step's clock.
    func cameraMoves(_ step: Int, from shot: String?) -> [ClosedRange<Double>] {
        let lead = lead(step, from: shot)
        guard lead > 0 else { return [] }
        return [move(steps[step]).at...lead]
    }

    public func script(for step: Int) -> StepScript { script(step, from: state(after: step - 1).shot) }

    /// Step `step`'s timing and lines played from `shot`: the camera's move first, when it moves,
    /// with the step's line said as it begins, then the step's own motion.
    func script(_ step: Int, from shot: String?) -> StepScript {
        let base = ownScript(step)
        let lead = lead(step, from: shot)
        guard lead > 0 else { return base }
        return StepScript(
            duration: base.duration + lead,
            events: base.events.map { $0.time <= 0 ? $0 : StepEvent($0.time + lead, $0.action) })
    }

    /// Step `step`'s own timing and lines, without a camera move.
    func ownScript(_ step: Int) -> StepScript {
        let s = steps[step]
        switch s {
        case .show:
            let t0 = Double(problem.minuendTens) * sec(s, .tenEvery)
            return StepScript(
                duration: t0 + sec(s, .showTail) + Double(problem.minuendOnes) * sec(s, .oneEvery),
                events: [StepEvent(0, .say(line(.show), caption: true))])
        case .short, .enough:
            return StepScript(
                duration: problem.minuendOnes > 0 ? sec(s, .hint) + sec(s, .hintHold) : sec(s, .noOnesHold),
                events: [StepEvent(0, .say(line(s == .short ? .short : .enough), caption: true))])
        case .trade:
            return StepScript(duration: tradeTimes.end, events: [StepEvent(0, .say(line(.trade), caption: true))])
        case .takeOnes, .takeTens:
            let n = s == .takeOnes ? problem.subtrahendOnes : problem.subtrahendTens
            return StepScript(
                duration: Double(n) * sec(s, .takeEvery) + sec(s, .takeTail),
                events: [StepEvent(0, .say(line(s == .takeOnes ? .takeOnes : .takeTens), caption: true))])
        case .count:
            let times = countTimes
            var events = [StepEvent(0, .say(line(.count), caption: true))]
            // Each spoken count waits for the one before it to be heard, so the voice counts in
            // time with the pieces (EXP-10); the first waits for the step's line. Counts that are
            // only shown (the parent's) wait for nothing.
            if speaksCounts {
                for (n, at) in zip(Self.counts(problem), times.ticks) {
                    events.append(StepEvent(at, .waitForVoice))
                    events.append(StepEvent(at, .say(line(.tick(n)), caption: false)))
                }
            }
            if let join = times.join {
                events.append(StepEvent(join, .waitForVoice))
                events.append(StepEvent(join, .say(line(.join), caption: true)))
            }
            events.append(StepEvent(times.answer, .waitForVoice))
            events.append(StepEvent(times.end, .waitForVoice))
            events.append(StepEvent(times.end, .say(line(.answer), caption: true)))
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

    /// The picture `t` seconds into step `step` played from `s0` to `s1`: the camera moves from
    /// `s0`'s shot to `s1`'s first, then the step's own motion plays.
    func motionPicture(_ step: Int, from s0: SubtractionState, to s1: SubtractionState, at time: Double) -> Scene {
        let lead = lead(step, from: s0.shot)
        let duration = script(step, from: s0.shot).duration
        if time >= duration { return drawing(s1, marking: step).scene(self) }
        let t = max(0, time - lead)
        let s = steps[step]
        var p = drawing(s0, marking: nil)
        p.camera = frame?.plan.camera(from: s0.shot, to: s1.shot, move: move(s), at: time)
        p.mark = mark(for: s).map { ($0, progress(t, start: 0, duration: sec(s, .mark), ease(s, .mark))) }
        switch s {
        case .show: animateShow(&p, t)
        case .short, .enough: animateHint(&p, t)
        case .trade: animateTrade(&p, t, ten: s1.tradedTen ?? defaultTradedTen, drawn: false)
        case .takeOnes: animateTake(&p, t, s1.onesGone.filter { !s0.onesGone.contains($0) }, step: s)
        case .takeTens: animateTake(&p, t, s1.tensGone.filter { !s0.tensGone.contains($0) }.map(Ref.ten), step: s)
        case .count: animateCount(&p, t, kept: keptPieces(s0))
        }
        return p.scene(self)
    }

    /// The digit a step acts on (EXP-5): the ones digit of the number taken away while the ones
    /// are looked at and crossed out, its tens digit while the tens are.
    func mark(for s: Step) -> Picture.Digit? {
        switch s {
        case .short, .enough, .takeOnes: .secondOnes
        case .takeTens: .secondTens
        case .show, .trade, .count: nil
        }
    }

    typealias Ref = SubtractionPiece

    /// The ten broken when the watched steps break one: the last.
    var defaultTradedTen: Int { problem.minuendTens - 1 }

    var tradedTen: Int? { problem.regroups ? defaultTradedTen : nil }

    /// The state before the first step.
    public var start: SubtractionState { SubtractionState() }

    /// The state after `step` with every step played as watched; -1 is the state before the first.
    public func state(after step: Int) -> SubtractionState {
        var s = start
        if step >= 0 { for k in 0...step { s = apply(steps[k], s) } }
        return s
    }

    /// Step `s` as the watched explainer does it, from `state`: the last ten broken, the loose
    /// ones crossed out first, the last whole tens crossed out.
    public func apply(_ s: Step, _ state: SubtractionState) -> SubtractionState {
        var n = state
        n.shot = shot(s) ?? state.shot
        switch s {
        case .show: n.shown = true
        case .short, .enough: break
        case .trade: n.tradedTen = defaultTradedTen
        case .takeOnes: n.onesGone += keptOnes(state).prefix(problem.subtrahendOnes)
        case .takeTens:
            let need = max(0, problem.subtrahendTens - state.tensGone.count)
            n.tensGone += wholeTens(state).suffix(need)
        case .count:
            n.gathered = true
            n.counted = Set(0..<countCount)
            n.answered = true
        }
        return n
    }

    /// The tens still whole: not broken, not crossed out.
    func wholeTens(_ s: SubtractionState) -> [Int] {
        (0..<problem.minuendTens).filter { $0 != s.tradedTen && !s.tensGone.contains($0) }
    }

    /// The ones still standing: the loose ones, then the broken ten's, less those crossed out.
    func keptOnes(_ s: SubtractionState) -> [Ref] {
        let pool = (0..<problem.minuendOnes).map(Ref.loose) + (s.tradedTen != nil ? (0..<10).map(Ref.boxed) : [])
        return pool.filter { !s.onesGone.contains($0) }
    }

    /// Where a piece stands on the worksheet.
    func rect(_ r: Ref) -> CGRect {
        switch r {
        case let .ten(i): layout.tens[i]
        case let .loose(i): layout.looseOnes[i]
        case let .boxed(i): layout.boxedOnes[i]
        }
    }

    /// How many pieces the count area holds: the tens and ones of the difference.
    var countCount: Int { problem.differenceTens + problem.differenceOnes }

    /// The running total once `n` pieces are counted, tens first: "10", "20", then "20 + 1".
    func runningTotal(_ n: Int) -> String? {
        guard n > 0 else { return nil }
        let t = problem.differenceTens
        if n <= t { return String(n * 10) }
        return t > 0 ? wording.runningTotal(t * 10, n - t) : String(n - t)
    }

    /// The still picture of `s`, with the digit step `step` acts on marked (EXP-5), and the
    /// pencil loop of a step that looks at the ones.
    func drawing(_ s: SubtractionState, marking step: Int?) -> Picture {
        var p = Picture(self)
        p.camera = camera(s.shot)
        p.tradedTen = s.tradedTen ?? defaultTradedTen
        if s.shown {
            p.labels = 1
            for i in p.tens.indices { p.tens[i].opacity = 1 }
            for i in p.loose.indices { p.loose[i].opacity = 1 }
        }
        if let traded = s.tradedTen, problem.regroups {
            p.tens[traded].ghost()
            p.arrow = 1
            p.box = 1
            for i in p.boxed.indices { p.boxed[i].opacity = 1 }
        }
        for r in s.onesGone { p[r].ghost() }
        for i in s.tensGone { p[.ten(i)].ghost() }
        for (r, points) in s.own { p[r].own = points }
        if s.gathered {
            for i in p.counted.indices {
                p.counted[i].opacity = 1
                if s.counted.contains(i) { p.counted[i].style = .counted }
            }
            p.total = s.answered ? String(problem.difference) : runningTotal(s.counted.count)
        }
        if s.answered { p.answer = String(problem.difference) }
        if let step, steps.indices.contains(step) {
            p.mark = mark(for: steps[step]).map { ($0, 1) }
            if steps[step] == .short || steps[step] == .enough { p.hint = 1 }
        }
        return p
    }

    // MARK: motion, step by step

    func animateShow(_ p: inout Picture, _ t: Double) {
        let s = Step.show
        p.labels = 1
        for i in p.tens.indices {
            let q = progress(t, start: Double(i) * sec(s, .tenEvery), duration: sec(s, .tenDrop), ease(s, .tenDrop))
            p.tens[i].opacity = q
            p.tens[i].frame = layout.tens[i].offsetBy(dx: 0, dy: mix(-14, 0, q))
        }
        let t0 = Double(problem.minuendTens) * sec(s, .tenEvery) + sec(s, .onesAfterTens)
        for i in p.loose.indices {
            let q = progress(t, start: t0 + Double(i) * sec(s, .oneEvery), duration: sec(s, .oneGrow), ease(s, .oneGrow))
            p.loose[i].opacity = q
            p.loose[i].frame = scaled(layout.looseOnes[i], mix(0.4, 1, q))
        }
    }

    /// The pencil loop drawn round the ones; nothing moves.
    func animateHint(_ p: inout Picture, _ t: Double) {
        let s: Step = problem.regroups ? .short : .enough
        p.hint = progress(t, start: 0, duration: sec(s, .hint), ease(s, .hint))
    }

    /// Ten `traded` breaks into ten ones that travel along the arrow into the box. With `drawn`,
    /// the learner has already drawn the line through it (do it with me), so no cross-out is drawn.
    func animateTrade(_ p: inout Picture, _ t: Double, ten traded: Int, drawn: Bool) {
        guard problem.regroups else { return }
        let s = Step.trade
        let times = tradeTimes
        let ten = layout.tens[traded]
        p.tradedTen = traded
        p.arrow = progress(t, start: 0, duration: sec(s, .arrow), ease(s, .arrow))
        p.tens[traded].opacity = mix(1, Components.ghostOpacity, progress(t, start: times.fade, duration: sec(s, .tenFade), ease(s, .tenFade)))
        p.tens[traded].cross = drawn ? 1 : progress(t, start: times.cross, duration: sec(s, .crossDraw), ease(s, .crossDraw))
        p.tens[traded].crossOpacity = mix(
            1, Components.ghostOpacity, progress(t, start: times.ghost, duration: sec(s, .ghostFade), ease(s, .ghostFade)))
        let top = layout.arrowY - 12
        let boxX = layout.box.midX - Components.oneSide / 2
        for i in p.boxed.indices {
            let start = CGPoint(x: ten.minX + 1, y: ten.minY + CGFloat(i) * ten.height / 10 + 1)
            let end = layout.boxedOnes[i].origin
            let q = progress(t, start: times.travelStart(i), duration: sec(s, .travel), ease(s, .travel))
            let at = keyframes([
                (0, start), (0.15, CGPoint(x: start.x - 6, y: start.y + (CGFloat(i) - 4.5) * 3)),
                (0.4, CGPoint(x: start.x, y: top)), (0.7, CGPoint(x: boxX, y: top)), (1, end),
            ], q)
            p.boxed[i].frame = CGRect(origin: at, size: layout.boxedOnes[i].size)
            p.boxed[i].opacity = progress(
                t, start: times.cubesAppear + Double(i) * sec(s, .cubeEvery), duration: sec(s, .cubeAppear), ease(s, .cubeAppear))
        }
        p.box = progress(t, start: times.box, duration: sec(s, .boxDraw), ease(s, .boxDraw))
    }

    func animateTake(_ p: inout Picture, _ t: Double, _ targets: [Ref], step s: Step) {
        for (j, r) in targets.enumerated() {
            let start = Double(j) * sec(s, .takeEvery)
            p[r].cross = progress(t, start: start, duration: sec(s, .takeCross), ease(s, .takeCross))
            let fade = mix(
                1, Components.ghostOpacity, progress(t, start: start + sec(s, .takeCross), duration: sec(s, .takeFade), ease(s, .takeFade)))
            p[r].opacity = fade
            p[r].crossOpacity = fade
        }
    }

    func animateCount(_ p: inout Picture, _ t: Double, kept: [CGRect]) {
        let s = Step.count
        let times = countTimes
        let pace = times.pace
        for i in p.counted.indices {
            let q = progress(t, start: pace * Double(i) * sec(s, .copyEvery), duration: pace * sec(s, .copy), ease(s, .copy))
            let dest = p.counted[i].frame
            let from = kept[i]
            p.counted[i].frame = CGRect(origin: mix(from.origin, dest.origin, q), size: dest.size)
            p.counted[i].opacity = mix(0.9, 1, q)
        }
        let counts = Self.counts(problem)
        let tensSum = problem.differenceTens * 10
        for (i, at) in times.ticks.enumerated() where t >= at {
            let n = counts[i]
            let isTen = i < problem.differenceTens
            p.total = isTen || tensSum == 0 ? String(n) : wording.runningTotal(tensSum, n)
            p.counted[i].style = .counted
            let tq = progress(t, start: at, duration: pace * sec(s, isTen ? .tenTag : .oneTag), ease(s, isTen ? .tenTag : .oneTag))
            p.tags[i].opacity = keyframes([(0, 0), (0.2, 1), (0.75, 1), (1, 0)], tq)
            p.tags[i].scale = keyframes([(0, 0.6), (0.2, 1), (1, 1)], tq)
        }
        if let join = times.join, t >= join {
            p.total = String(problem.difference)
            p.totalScale = keyframes([(0, 1), (0.5, 1.15), (1, 1)], progress(t, start: join, duration: pace * sec(s, .pulse), ease(s, .pulse)))
        }
        if t >= times.countEnd, times.ticks.isEmpty { p.total = String(problem.difference) }
        if t >= times.answer {
            p.answer = String(problem.difference)
            p.answerOpacity = progress(t, start: times.answer, duration: pace * sec(s, .answerFade), ease(s, .answerFade))
        }
    }

    /// Where the pieces copied to the count area come from: the tens still standing, then the
    /// ones still standing (loose ones, then the box's).
    func keptPieces(_ s: SubtractionState) -> [CGRect] {
        wholeTens(s).map { layout.tens[$0] } + keptOnes(s).map(rect)
    }

    func scaled(_ r: CGRect, _ s: Double) -> CGRect {
        if s >= 1 { return r }
        return r.insetBy(dx: r.width * (1 - s) / 2, dy: r.height * (1 - s) / 2)
    }
}

/// A piece of the worksheet's drawing: a ten, a loose one, or one of a broken ten's ones in the
/// box.
public enum SubtractionPiece: Hashable, Sendable {
    case ten(Int)
    case loose(Int)
    case boxed(Int)
}

/// Everything a subtraction picture can show (EXP-2): what has been drawn, broken, crossed out,
/// gathered and counted, and the learner's own lines (EXP-14).
public struct SubtractionState: Equatable, Sendable {
    /// The number is drawn as tens and ones.
    public var shown = false
    /// The ten broken into ten ones.
    public var tradedTen: Int?
    /// The ones crossed out, in the order they were.
    public var onesGone: [SubtractionPiece] = []
    /// The tens crossed out, in the order they were.
    public var tensGone: [Int] = []
    /// What is left has been copied to the count area.
    public var gathered = false
    /// The count area's pieces counted, by index (tens first, then ones).
    public var counted: Set<Int> = []
    /// The answer is written.
    public var answered = false
    /// The learner's own lines, by piece, drawn in place of the cross-out; empty for a piece crossed
    /// by a line drawn over another.
    public var own: [SubtractionPiece: [CGPoint]] = [:]
    /// The shot the camera holds on (EXP-18), as the motion file names it; nil before the first
    /// step, the opening shot.
    public var shot: String?

    public init() {}
}

/// Everything a subtraction step can show, as values; `scene` turns it into elements with the
/// shared components. The same elements, in the same order, at every moment, so a piece keeps
/// its id through a step.
struct Picture {
    enum Digit { case secondTens, secondOnes }

    struct Piece {
        var frame: CGRect
        var style: PieceStyle
        var crossPad: CGFloat
        var opacity = 0.0
        var cross = 0.0
        var crossOpacity = 1.0
        /// The learner's own line over the piece, drawn in place of the cross-out; empty when a
        /// line drawn over another crossed it too.
        var own: [CGPoint]?

        /// Traded or taken away: crossed out and faded, never erased (EXP-5).
        mutating func ghost() {
            opacity = Components.ghostOpacity
            cross = 1
            crossOpacity = Components.ghostOpacity
        }
    }

    /// The count a piece shows on itself while it is counted.
    struct Tag {
        var text: String
        var rect: CGRect
        var opacity = 0.0
        var scale = 1.0
    }

    var labels = 0.0
    var hint = 0.0
    var tradedTen = 0
    var tens: [Piece]
    var loose: [Piece]
    var boxed: [Piece]
    var arrow = 0.0
    var box = 0.0
    var counted: [Piece]
    var tags: [Tag]
    var total: String?
    var totalScale = 1.0
    var mark: (Digit, Double)?
    var answer: String
    var answerOpacity = 1.0
    var camera: Camera?

    init(_ e: SubtractionExplainer) {
        let l = e.layout
        tens = l.tens.map { Piece(frame: $0, style: .pencil, crossPad: Components.tenCrossPad) }
        loose = l.looseOnes.map { Piece(frame: $0, style: .pencil, crossPad: Components.oneCrossPad) }
        boxed = e.problem.regroups
            ? l.boxedOnes.map { Piece(frame: $0, style: .traded, crossPad: Components.oneCrossPad) } : []
        counted = (l.countTens + l.countOnes).map {
            Piece(frame: $0, style: .pencil, crossPad: $0.height > Components.oneSide ? Components.tenCrossPad : Components.oneCrossPad)
        }
        let tensCount = l.countTens.count
        tags = SubtractionExplainer.counts(e.problem).enumerated().map { i, n in
            let isTen = i < tensCount
            let piece = isTen ? l.countTens[i] : l.countOnes[i - tensCount]
            return Tag(text: e.line(.tick(n)).display, rect: Components.numberTag(on: piece, ten: isTen))
        }
        answer = e.wording.unknown
    }

    subscript(r: SubtractionExplainer.Ref) -> Piece {
        get {
            switch r {
            case let .ten(i): tens[i]
            case let .loose(i): loose[i]
            case let .boxed(i): boxed[i]
            }
        }
        set {
            switch r {
            case let .ten(i): tens[i] = newValue
            case let .loose(i): loose[i] = newValue
            case let .boxed(i): boxed[i] = newValue
            }
        }
    }

    func scene(_ e: SubtractionExplainer) -> Scene {
        let l = e.layout
        var out: [SceneElement] = []
        // Laid out with a camera, the problem stays fixed above it (EXP-18).
        out.append(SceneElement("equation", .equation(equation(e)), fixed: e.frame != nil))
        out.append(SceneElement("divider", .divider(from: l.dividerFrom, to: l.dividerTo)))
        out.append(SceneElement("label.tens", .label(e.wording.tensLabel, at: l.tensLabel), opacity: labels))
        out.append(SceneElement("label.ones", .label(e.wording.onesLabel, at: l.onesLabel), opacity: labels))
        func add(_ id: String, _ piece: Piece, ten: Bool, op: ExplainerOperation = .subtract) {
            out.append(SceneElement(id, ten ? .ten(piece.frame, piece.style) : .one(piece.frame, piece.style), opacity: piece.opacity))
            let opacity = piece.opacity > 0 ? piece.crossOpacity : 0
            if let own = piece.own {
                // The learner's own line, in the colour of what it did (EXP-14).
                out.append(SceneElement(id + ".cross", .ink(own, op: op), opacity: piece.cross > 0 ? opacity : 0))
            } else {
                let x = Components.crossOut(over: piece.frame, pad: piece.crossPad)
                out.append(SceneElement(id + ".cross", .crossOut(from: x.from, to: x.to, progress: piece.cross), opacity: opacity))
            }
        }
        for (i, p) in tens.enumerated() { add("ten.\(i)", p, ten: true, op: e.problem.regroups && i == tradedTen ? .trade : .subtract) }
        for (i, p) in loose.enumerated() { add("one.\(i)", p, ten: false) }
        if e.problem.regroups {
            out.append(SceneElement("arrow", .arrow(
                points: Components.tradeArrow(from: l.tens[tradedTen], to: l.box, y: l.arrowY), progress: arrow, op: .trade)))
            out.append(SceneElement("box", .box(l.box, progress: box, op: .trade)))
        }
        if let ring = Components.hint(around: l.looseOnes) {
            out.append(SceneElement("hint", .hint(ring, progress: hint)))
        }
        for (i, p) in boxed.enumerated() { add("boxed.\(i)", p, ten: false) }
        let countedTens = l.countTens.count
        for (i, p) in counted.enumerated() {
            let id = i < countedTens ? "count.ten.\(i)" : "count.one.\(i - countedTens)"
            out.append(SceneElement(id, i < countedTens ? .ten(p.frame, p.style) : .one(p.frame, p.style), opacity: p.opacity))
        }
        for (i, t) in tags.enumerated() {
            out.append(SceneElement("tag.\(i < countedTens ? "ten" : "one").\(i < countedTens ? i : i - countedTens)",
                .numberTag(t.text, in: t.rect, scale: t.scale), opacity: t.opacity))
        }
        out.append(SceneElement("total", .total(total ?? "", at: l.totalAt, scale: totalScale), opacity: total == nil ? 0 : 1))
        return Scene(elements: out, size: e.frame?.size ?? Scene.stage, camera: camera)
    }

    /// The problem across the top from the wording's equation, each number in its slot; the
    /// number taken away is split into its digits so either can be marked.
    func equation(_ e: SubtractionExplainer) -> EquationLine {
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
                runs.append(.init(String(e.problem.minuend)))
            case EquationSlot.second:
                flush()
                if e.problem.subtrahendTens > 0 {
                    if case .secondTens = mark?.0 { marked = runs.count }
                    runs.append(.init(String(e.problem.subtrahendTens)))
                }
                if case .secondOnes = mark?.0 { marked = runs.count }
                runs.append(.init(String(e.problem.subtrahendOnes)))
            case EquationSlot.answer:
                flush()
                runs.append(.init(answer, .answer, opacity: answerOpacity))
            default:
                literal.append(c)
            }
        }
        flush()
        let m = marked.flatMap { i in mark.map { EquationLine.Mark(run: i, op: .subtract, progress: $0.1) } }
        return EquationLine(runs: runs, mark: m, center: e.frame?.equationCenter ?? e.layout.equationCenter, size: Components.equationSize)
    }
}
