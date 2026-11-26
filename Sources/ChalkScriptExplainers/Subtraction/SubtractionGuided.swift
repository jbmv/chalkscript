import ChalkScript
import CoreGraphics
import Foundation

/// Subtraction's child version (EXP-14): watch, do it with me, try one.
///
/// The learner does four steps, the last ones first as fading runs backward:
/// - trade: a line through any whole ten breaks it; the ten's ones then travel into the box.
/// - take ones, take tens: a line across a piece crosses it out, and one line may cross several,
///   up to the number still to take away; the learner's own line stays, in take-away's colour.
/// - count: what is left is gathered to the count area, then each piece is touched, tens first,
///   and its count is said at once, cutting off the one before.
/// Each mark it cannot use is met with a kind line saying what to do instead.
extension SubtractionExplainer: GuidedExplainer {
    public typealias State = SubtractionState

    /// The steps the learner can do.
    static let doable: Set<Step> = [.trade, .takeOnes, .takeTens, .count]

    public var guidedSteps: [GuidedStep] {
        steps.map { GuidedStep($0.rawValue, doable: Self.doable.contains($0), countsAloud: $0 == .count && speaksCounts) }
    }

    func doLine(_ l: SubtractionDoLine) -> Line {
        guard let f = wording.doLine else { preconditionFailure("the child version needs the do-it-with-me lines") }
        return f(l, problem)
    }

    public func intro(_ part: GuidedPart) -> Line { part == .doWithMe ? doLine(.intro) : line(.intro) }

    public func picture(_ state: SubtractionState, marking step: Int?) -> Scene {
        drawing(state, marking: step).scene(self)
    }

    public func watch(_ step: Int, from state: SubtractionState) -> (state: SubtractionState, motion: Motion) {
        let s1 = apply(steps[step], state)
        let e = self
        return (
            s1,
            Motion(
                script: script(step, from: state.shot), cameraMoves: cameraMoves(step, from: state.shot),
                picture: { e.motionPicture(step, from: state, to: s1, at: $0) })
        )
    }

    /// The camera eases to the step's shot while its instruction is said (EXP-18), so the pieces
    /// to mark are framed, and large, before the learner can mark them.
    public func approach(_ step: Int, _ state: SubtractionState) -> (state: SubtractionState, motion: Motion)? {
        let s = steps[step]
        let lead = lead(step, from: state.shot)
        guard lead > 0 else { return nil }
        var framed = state
        framed.shot = shot(s) ?? state.shot
        let (e, s1, move) = (self, framed, move(s))
        return (
            s1,
            Motion(
                script: StepScript(duration: lead, events: []), cameraMoves: [move.at...lead],
                picture: { t in
                    if t >= lead { return e.picture(s1, marking: step) }
                    var p = e.drawing(state, marking: step)
                    p.camera = e.frame?.plan.camera(from: state.shot, to: s1.shot, move: move, at: t)
                    return p.scene(e)
                })
        )
    }

    public func instruction(_ step: Int, _ state: SubtractionState) -> Line {
        switch steps[step] {
        case .trade: doLine(.trade)
        case .count: doLine(.count)
        case .takeOnes: line(.takeOnes)
        case .takeTens: line(.takeTens)
        case .show: line(.show)
        case .short: line(.short)
        case .enough: line(.enough)
        }
    }

    public func begin(_ step: Int, _ state: SubtractionState) -> Reaction<SubtractionState> {
        switch steps[step] {
        case .takeOnes: return Reaction(state, note: .clear, tally: Tally(0, of: problem.subtrahendOnes))
        case .takeTens: return Reaction(state, note: .clear, tally: Tally(0, of: problem.subtrahendTens))
        case .count:
            // What is left is gathered to the count area before it is touched; then the camera
            // comes in close on it, where the step says so, so each piece is large enough to touch
            // (EXP-18). The learner's touches wait for both.
            var s1 = state
            s1.gathered = true
            if countCount == 0 {
                s1.answered = true
                return Reaction(s1, motion: .still(picture(s1, marking: step), saying: [line(.answer)]), finished: true)
            }
            s1.shot = motion.steps[Step.count.rawValue]?.doShot ?? state.shot
            return Reaction(s1, motion: gatherMotion(step, from: state, to: s1))
        default: return .ignored(state)
        }
    }

    /// What right marks bring: the traded line, the crossed-out line, or each piece's count
    /// (tens first), the join and the answer.
    public func doneLines(_ step: Int, _ state: SubtractionState) -> [Line] {
        switch steps[step] {
        case .trade: return [doLine(.traded)]
        case .takeOnes: return problem.subtrahendOnes > 0 ? [doLine(.crossedOnes)] : []
        case .takeTens: return problem.subtrahendTens > 0 ? [doLine(.crossedTens)] : []
        case .count:
            let tens = problem.differenceTens
            if countCount == 0 { return [line(.answer)] }
            var out = (1...countCount).map { n in line(.tick(n <= tens ? n * 10 : n - tens)) }
            if tens > 0 && problem.differenceOnes > 0 { out.append(line(.join)) }
            return out + [line(.answer)]
        default: return watch(step, from: state).motion.said
        }
    }

    public func read(_ mark: Mark, step: Int, _ state: SubtractionState) -> Reaction<SubtractionState> {
        switch steps[step] {
        case .trade: readTrade(mark, step, state)
        case .takeOnes: readCross(mark, step, state, ones: true)
        case .takeTens: readCross(mark, step, state, ones: false)
        case .count: readCount(mark, step, state)
        default: .ignored(state)
        }
    }

    // MARK: breaking a ten

    func readTrade(_ mark: Mark, _ step: Int, _ s: SubtractionState) -> Reaction<SubtractionState> {
        guard case let .stroke(points) = mark else { return miss(s, .tradeTapped) }
        // Whichever whole ten the line goes through: the one it runs through most, not the first
        // it touches.
        let whole = wholeTens(s)
        if let k = MarkGeometry.crossed(points, among: whole.map { layout.tens[$0] }).first {
            let i = whole[k]
            var s1 = s
            s1.tradedTen = i
            s1.own[.ten(i)] = points
            return Reaction(s1, motion: tradeMotion(step, from: s, to: s1, ten: i), note: .clear, keepsStroke: true, finished: true)
        }
        if keptOnes(s).contains(where: { MarkGeometry.crosses(points, rect($0)) }) { return miss(s, .tradeOnOne) }
        return miss(s, .tradeMissed)
    }

    /// The broken ten's ones travel into the box; the learner's line stays on it.
    func tradeMotion(_ step: Int, from s0: SubtractionState, to s1: SubtractionState, ten i: Int) -> Motion {
        let duration = tradeTimes.end
        let e = self
        return Motion(
            script: StepScript(duration: duration, events: [StepEvent(duration, .say(doLine(.traded), caption: true))]),
            picture: { t in
                if t >= duration { return e.picture(s1, marking: step) }
                var p = e.drawing(s0, marking: step)
                p.tens[i].own = s1.own[.ten(i)]
                e.animateTrade(&p, t, ten: i, drawn: true)
                return p.scene(e)
            })
    }

    // MARK: crossing out

    func readCross(_ mark: Mark, _ step: Int, _ s: SubtractionState, ones: Bool) -> Reaction<SubtractionState> {
        guard case let .stroke(points) = mark else { return miss(s, .crossTapped(ones: ones)) }
        let need = ones ? problem.subtrahendOnes : problem.subtrahendTens
        let done = ones ? s.onesGone.count : s.tensGone.count
        let free: [Ref] = ones ? keptOnes(s) : wholeTens(s).map(Ref.ten)
        // Most-crossed first; a piece the line only grazes beside it is left alone.
        let hit = MarkGeometry.crossed(points, among: free.map(rect)).map { free[$0] }
        if !hit.isEmpty && hit.count <= need - done {
            var s1 = s
            for (j, r) in hit.enumerated() {
                // The learner's line is drawn on the piece it crossed most; the others are crossed
                // by it too.
                s1.own[r] = j == 0 ? points : []
                if case let .ten(i) = r { s1.tensGone.append(i) } else { s1.onesGone.append(r) }
            }
            let finished = done + hit.count == need
            let said = finished ? doLine(ones ? .crossedOnes : .crossedTens) : nil
            return Reaction(
                s1, motion: crossMotion(step, from: s, to: s1, saying: said), note: .clear,
                tally: Tally(done + hit.count, of: need), keepsStroke: true, finished: finished)
        }
        if !hit.isEmpty { return Reaction(s, note: .hint(doLine(.crossedTooMany(left: need - done)))) }
        let other: [Ref] = ones ? wholeTens(s).map(Ref.ten) : keptOnes(s)
        if other.contains(where: { MarkGeometry.crosses(points, rect($0)) }) {
            return miss(s, ones ? .crossedTen : .crossedOne)
        }
        return miss(s, .crossMissed(ones: ones))
    }

    /// The pieces just crossed out fade to ghosts with the learner's line on them; `saying` is said
    /// once they have.
    func crossMotion(_ step: Int, from s0: SubtractionState, to s1: SubtractionState, saying: Line?) -> Motion {
        let gone = s1.onesGone.filter { !s0.onesGone.contains($0) } + s1.tensGone.filter { !s0.tensGone.contains($0) }.map(Ref.ten)
        let s = steps[step]
        let duration = sec(s, .takeFade)
        let fadeCurve = ease(s, .takeFade)
        let e = self
        return Motion(
            script: StepScript(duration: duration, events: saying.map { [StepEvent(duration, .say($0, caption: true))] } ?? []),
            picture: { t in
                if t >= duration { return e.picture(s1, marking: step) }
                var p = e.drawing(s0, marking: step)
                let fade = mix(1, Components.ghostOpacity, progress(t, start: 0, duration: duration, fadeCurve))
                for r in gone {
                    p[r].own = s1.own[r]
                    p[r].cross = 1
                    p[r].opacity = fade
                    p[r].crossOpacity = fade
                }
                return p.scene(e)
            })
    }

    // MARK: counting

    /// The count area's pieces: its tens, then its ones.
    var countRects: [CGRect] { layout.countTens + layout.countOnes }

    /// How far round a piece in the count area a touch still counts it, in the drawing's units.
    static let countTouchPad: CGFloat = 10

    func readCount(_ mark: Mark, _ step: Int, _ s: SubtractionState) -> Reaction<SubtractionState> {
        guard s.gathered, let i = countRects.firstIndex(where: { MarkGeometry.inside(mark.at, $0, pad: Self.countTouchPad) }),
            !s.counted.contains(i)
        else { return .ignored(s) }
        let tens = problem.differenceTens
        if i >= tens && s.counted.filter({ $0 < tens }).count < tens { return miss(s, .tensFirst) }
        var s1 = s
        s1.counted.insert(i)
        let last = s1.counted.count == countCount
        if last { s1.answered = true }
        return Reaction(s1, motion: countMotion(step, from: s, to: s1, piece: i), interrupts: true, note: .clear, finished: last)
    }

    /// What is left is copied to the count area, as the watched count step begins; then, when
    /// `s1` holds a closer shot, the camera eases in on the count area (EXP-18).
    func gatherMotion(_ step: Int, from s0: SubtractionState, to s1: SubtractionState) -> Motion {
        let times = countTimes
        let kept = keptPieces(s0)
        let e = self
        let move = move(.count)
        let moves = frame?.plan.moves(from: s0.shot, to: s1.shot) ?? false
        let start = times.copyEnd
        let end = moves ? start + move.end : start
        var unmoved = s1
        unmoved.shot = s0.shot
        let gathered = unmoved
        return Motion(
            script: StepScript(duration: end, events: []), cameraMoves: moves ? [start + move.at...end] : [],
            picture: { t in
                if t >= end { return e.picture(s1, marking: step) }
                if t >= start {
                    var p = e.drawing(gathered, marking: step)
                    p.camera = e.frame?.plan.camera(from: s0.shot, to: s1.shot, move: move, at: t - start)
                    return p.scene(e)
                }
                var p = e.drawing(s0, marking: step)
                e.animateCount(&p, t, kept: kept)
                return p.scene(e)
            })
    }

    /// The piece touched shows its count and the count is said; once every piece is counted, tens
    /// and ones are put together and the answer is written and said (EXP-5, EXP-10).
    func countMotion(_ step: Int, from s0: SubtractionState, to s1: SubtractionState, piece i: Int) -> Motion {
        let n = s1.counted.count
        let tens = problem.differenceTens
        let value = i < tens ? n * 10 : n - tens
        let c = Step.count
        let quick = sec(c, .tapTag)
        let (tagCurve, pulseCurve, answerCurve) = (ease(c, .tapTag), ease(c, .pulse), ease(c, .answerFade))
        let (pulse, answerFade) = (sec(c, .pulse), sec(c, .answerFade))
        var events = [StepEvent(0, .say(line(.tick(value)), caption: false))]
        var join: Double?
        var answerAt: Double?
        var duration = quick
        if s1.answered {
            let f = sec(c, .afterLast)
            events.append(StepEvent(f, .waitForVoice))
            if tens > 0 && problem.differenceOnes > 0 {
                let j = f + sec(c, .beforeJoin)
                join = j
                events += [StepEvent(j, .waitForVoice), StepEvent(j, .say(line(.join), caption: true))]
                answerAt = j + pulse
            } else {
                answerAt = f
            }
            let a = answerAt ?? f
            let end = a + answerFade
            events += [StepEvent(a, .waitForVoice), StepEvent(end, .waitForVoice), StepEvent(end, .say(line(.answer), caption: true))]
            duration = max(quick, end)
        }
        var counting = s1
        counting.answered = false
        let (e, end, joinAt, writeAt, base) = (self, duration, join, answerAt, counting)
        return Motion(
            script: StepScript(duration: duration, events: events),
            picture: { t in
                if t >= end { return e.picture(s1, marking: step) }
                var p = e.drawing(base, marking: step)
                let q = progress(t, start: 0, duration: quick, tagCurve)
                p.tags[i].opacity = keyframes([(0, 0), (0.15, 1), (0.75, 1), (1, 0)], q)
                p.tags[i].scale = keyframes([(0, 0.6), (0.2, 1), (1, 1)], q)
                if let join = joinAt, t >= join {
                    p.total = String(e.problem.difference)
                    p.totalScale = keyframes([(0, 1), (0.5, 1.15), (1, 1)], progress(t, start: join, duration: pulse, pulseCurve))
                }
                if let answerAt = writeAt, t >= answerAt {
                    p.answer = String(e.problem.difference)
                    p.answerOpacity = progress(t, start: answerAt, duration: answerFade, answerCurve)
                }
                return p.scene(e)
            })
    }

    func miss(_ s: SubtractionState, _ l: SubtractionDoLine) -> Reaction<SubtractionState> {
        Reaction(s, note: .miss(doLine(l)))
    }

    // MARK: try one

    /// Where try one writes the problem, its answer box and the note under it.
    static let tryProblemAt = CGPoint(x: 470, y: 270)
    static let tryBox = CGRect(x: 650, y: 185, width: 120, height: 92)
    static let tryNoteAt = CGPoint(x: 500, y: 372)

    public var tryOne: (line: Line, scene: Scene) {
        let text = wording.equation
            .replacingOccurrences(of: EquationSlot.first, with: String(problem.minuend))
            .replacingOccurrences(of: EquationSlot.second, with: String(problem.subtrahend))
            .replacingOccurrences(of: EquationSlot.answer, with: "")
        let scene = Scene(elements: [
            SceneElement("try.problem", .text(text, at: Self.tryProblemAt, style: .problem)),
            SceneElement("try.answer", .target(Self.tryBox)),
            SceneElement("try.note", .text(doLine(.tryNote).display, at: Self.tryNoteAt, style: .note)),
        ])
        return (doLine(.tryIntro), scene)
    }

    // MARK: the three problems

    /// The child version on `problem` and two other problems of its kind (EXP-3): `problem` is
    /// watched, the first other is done with the learner, the second tried alone.
    public static func lesson(watching problem: SubtractionProblem, wording: SubtractionWording) -> GuidedLesson<SubtractionExplainer> {
        let make = { SubtractionExplainer(problem: $0, version: .child, wording: wording) }
        return GuidedLesson(watch: make(problem), doWithMe: make(problem.isomorph(1)), tryOne: make(problem.isomorph(2)))
    }
}

extension SubtractionProblem {
    /// What makes two problems the same kind (EXP-3): whether the first number is a whole
    /// number of tens, whether a ten is traded, whether tens and ones are taken away, and whether
    /// tens and ones are left.
    var kind: [Bool] {
        [
            minuendOnes == 0, regroups, subtrahendTens > 0, subtrahendOnes > 0, differenceTens > 0,
            differenceOnes > 0,
        ]
    }

    /// Another problem of the same kind (EXP-3): `n` 1 for do it with me, 2 for try one. Never
    /// this problem's first number, number taken away or answer, with the first number within two
    /// tens of this one's; the second is also a different answer and first number from the first.
    /// The pick is fixed for a problem, so the same problem always gets the same others. It is
    /// this problem itself when no other of its kind exists.
    public func isomorph(_ n: Int) -> SubtractionProblem {
        var out: [SubtractionProblem] = []
        for a in 21...98 {
            for b in 2..<a {
                guard let c = try? SubtractionProblem(a, minus: b), c.kind == kind, a != minuend, b != subtrahend,
                    c.difference != difference, abs(c.minuendTens - minuendTens) <= 2
                else { continue }
                out.append(c)
            }
        }
        guard !out.isEmpty else { return self }
        func pick(_ k: Int) -> SubtractionProblem { out[(minuend * 31 + subtrahend * 17 + k * 97) % out.count] }
        let first = pick(1)
        if n == 1 { return first }
        for k in 2..<40 {
            let c = pick(k)
            if c.difference != first.difference && c.minuend != first.minuend { return c }
        }
        return first
    }
}
