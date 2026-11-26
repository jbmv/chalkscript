import ChalkScript
import CoreGraphics
import Foundation

/// Addition's child version (EXP-14): watch, do it with me, try one.
///
/// The child does four steps, the last ones first as fading runs backward:
/// - add ones: each touch on the ones side draws the next one in its place, and its count is
///   said, counting on; once all are drawn, a pencil loop goes round all the ones and how many
///   there are is said (do it with me has no separate check step).
/// - bundle: a loop drawn round any ten ones bundles them; the child's loop stays, in the trade's
///   colour, and copies of the ten ones travel into the new ten.
/// - add tens: each touch on the tens side draws the next ten.
/// - count: each piece is touched, tens first, and its count is said at once, cutting off the one
///   before.
/// Each mark it cannot use is met with a kind line saying what to do instead.
extension AdditionExplainer: GuidedExplainer {
    public typealias State = AdditionState

    /// The steps the child can do.
    static let doable: Set<Step> = [.addOnes, .bundle, .addTens, .count]

    public var guidedSteps: [GuidedStep] {
        steps.map { GuidedStep($0.rawValue, doable: Self.doable.contains($0), countsAloud: $0 == .addOnes || $0 == .count) }
    }

    public func intro(_ part: GuidedPart) -> Line { part == .doWithMe ? doLine(.intro) : line(.intro) }

    public func picture(_ state: AdditionState, marking step: Int?) -> Scene {
        drawing(state, marking: step).scene(self)
    }

    public func watch(_ step: Int, from state: AdditionState) -> (state: AdditionState, motion: Motion) {
        let s1 = apply(steps[step], state)
        let e = self
        return (s1, Motion(script: script(for: step), picture: { e.motionPicture(step, from: state, to: s1, at: $0) }))
    }

    public func instruction(_ step: Int, _ state: AdditionState) -> Line {
        switch steps[step] {
        case .addOnes: doLine(.addOnes)
        case .bundle: doLine(.bundle)
        case .addTens: doLine(.addTens)
        case .count: doLine(.count)
        case .show: line(.show)
        case .check: line(.check)
        }
    }

    public func begin(_ step: Int, _ state: AdditionState) -> Reaction<AdditionState> {
        switch steps[step] {
        case .addOnes: Reaction(state, note: .clear, tally: Tally(state.addedOnes, of: problem.secondOnes, op: .add))
        case .addTens: Reaction(state, note: .clear, tally: Tally(state.addedTens, of: problem.secondTens, op: .add))
        default: .ignored(state)
        }
    }

    public func read(_ mark: Mark, step: Int, _ state: AdditionState) -> Reaction<AdditionState> {
        switch steps[step] {
        case .addOnes: readAdd(mark, step, state, ones: true)
        case .addTens: readAdd(mark, step, state, ones: false)
        case .bundle: readLoop(mark, step, state)
        case .count: readCount(mark, step, state)
        default: .ignored(state)
        }
    }

    // MARK: adding

    /// A touch on the side being added to draws the next piece there, wherever on that side it
    /// lands; a touch on the other side is met with a line saying where the pieces go.
    func readAdd(_ mark: Mark, _ step: Int, _ s: AdditionState, ones: Bool) -> Reaction<AdditionState> {
        let side = ones ? layout.onesSide : layout.tensSide
        let other = ones ? layout.tensSide : layout.onesSide
        guard MarkGeometry.inside(mark.at, side, pad: 0) else {
            if MarkGeometry.inside(mark.at, other, pad: 0) { return miss(s, ones ? .onesOnTensSide : .tensOnOnesSide) }
            return .ignored(s)
        }
        let need = ones ? problem.secondOnes : problem.secondTens
        let placed = ones ? s.addedOnes : s.addedTens
        guard placed < need else { return .ignored(s) }
        var s1 = s
        let finished = placed + 1 == need
        if ones {
            s1.addedOnes += 1
            s1.onesRinged = finished
        } else {
            s1.addedTens += 1
        }
        let piece: Ref = ones ? .one(problem.firstOnes + placed) : .ten(tensFrom + placed)
        return Reaction(
            s1, motion: placeMotion(step, from: s, to: s1, piece: piece, touched: mark.at, ones: ones, finished: finished),
            interrupts: ones, note: .clear, tally: Tally(placed + 1, of: need, op: .add), finished: finished)
    }

    /// The piece drawn moves from where the child touched to its place; a one's count is said,
    /// counting on. After the last, the loop is drawn round all the ones (the ones step) and how
    /// many there are is said.
    func placeMotion(
        _ step: Int, from s0: AdditionState, to s1: AdditionState, piece: Ref, touched: CGPoint, ones: Bool, finished: Bool
    ) -> Motion {
        let ringAt = T.place + T.placeWait
        let duration = finished ? ringAt + (ones ? T.hint : 0) : T.place
        var events: [StepEvent] = []
        if ones { events.append(StepEvent(0, .say(line(.tick(onesDrawn(s1))), caption: false))) }
        if finished { events.append(StepEvent(duration, .say(doLine(ones ? .addedOnes : .addedTens), caption: true))) }
        let e = self
        return Motion(
            script: StepScript(duration: duration, events: events),
            picture: { t in
                if t >= duration { return e.picture(s1, marking: step) }
                var p = e.drawing(s0, marking: step)
                let r = e.rect(piece)
                let q = progress(t, start: 0, duration: T.place, .easeOut)
                p[piece].frame = r.offsetBy(dx: (touched.x - r.midX) * (1 - q), dy: (touched.y - r.midY) * (1 - q))
                p[piece].opacity = mix(0.4, 1, q)
                if finished && ones { p.hint = progress(t, start: ringAt, duration: T.hint, .easeOut) }
                return p.scene(e)
            })
    }

    // MARK: bundling

    /// A loop round exactly ten of the ones standing bundles them, whichever ten they are; a
    /// touch, or a loop round none, asks for a loop; a loop round some says how many it has.
    func readLoop(_ mark: Mark, _ step: Int, _ s: AdditionState) -> Reaction<AdditionState> {
        guard case let .stroke(points) = mark else { return miss(s, .loopMissed) }
        let inside = liveOnes(s).filter { Self.contains(points, CGPoint(x: layout.ones[$0].midX, y: layout.ones[$0].midY)) }
        guard inside.count == 10 else { return miss(s, inside.isEmpty ? .loopMissed : .loopHas(inside.count)) }
        var s1 = s
        s1.bundled = inside
        s1.newTen = true
        s1.loop = points
        return Reaction(s1, motion: loopMotion(step, from: s, to: s1), note: .clear, keepsStroke: true, finished: true)
    }

    /// The child's loop stays; the arrow is drawn from it to the new ten, and the ten ones travel
    /// along it and stack into the new ten. The line about the tens and ones there now is said
    /// once they have.
    func loopMotion(_ step: Int, from s0: AdditionState, to s1: AdditionState) -> Motion {
        let duration = StackTimes().end
        let e = self
        return Motion(
            script: StepScript(duration: duration, events: [StepEvent(duration, .say(doLine(.bundled), caption: true))]),
            picture: { t in
                if t >= duration { return e.picture(s1, marking: step) }
                var p = e.drawing(s0, marking: step)
                p.loop = s1.loop
                p.arrowFrom = e.bundleFrom(s1.loop)
                e.animateStack(&p, t, bundled: s1.bundled)
                return p.scene(e)
            })
    }

    /// Whether `point` is inside the loop through `points`, closed back to its start (an
    /// even-odd test).
    static func contains(_ points: [CGPoint], _ point: CGPoint) -> Bool {
        guard points.count > 2 else { return false }
        var inside = false
        var j = points.count - 1
        for i in points.indices {
            let a = points[i], b = points[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: counting

    func readCount(_ mark: Mark, _ step: Int, _ s: AdditionState) -> Reaction<AdditionState> {
        let order = countOrder(s)
        guard let i = order.firstIndex(where: { MarkGeometry.inside(mark.at, rect($0), pad: 10) }), !s.counted.contains(i)
        else { return .ignored(s) }
        let tens = tensDrawn(s).count
        if i >= tens && s.counted.filter({ $0 < tens }).count < tens { return miss(s, .tensFirst) }
        var s1 = s
        s1.counted.insert(i)
        let last = s1.counted.count == order.count
        if last { s1.answered = true }
        return Reaction(s1, motion: countMotion(step, from: s, to: s1, piece: i), interrupts: true, note: .clear, finished: last)
    }

    /// The piece touched shows its count and the count is said; once every piece is counted, tens
    /// and ones are put together and the answer is written and said (EXP-5, EXP-10).
    func countMotion(_ step: Int, from s0: AdditionState, to s1: AdditionState, piece i: Int) -> Motion {
        let n = s1.counted.count
        let tens = tensDrawn(s1).count
        let value = i < tens ? n * 10 : n - tens
        var events = [StepEvent(0, .say(line(.tick(value)), caption: false))]
        var join: Double?
        var answerAt: Double?
        var duration = T.quickTag
        if s1.answered {
            let f = T.countWait
            events.append(StepEvent(f, .waitForVoice))
            if problem.sumTens > 0 && problem.sumOnes > 0 {
                let j = f + T.beforeJoin
                join = j
                events += [StepEvent(j, .waitForVoice), StepEvent(j, .say(line(.join), caption: true))]
                answerAt = j + T.pulse
            } else {
                answerAt = f
            }
            let a = answerAt ?? f
            let end = a + T.answerFade
            events += [StepEvent(a, .waitForVoice), StepEvent(end, .waitForVoice), StepEvent(end, .say(line(.answer), caption: true))]
            duration = max(T.quickTag, end)
        }
        var counting = s1
        counting.answered = false
        let order = countOrder(s1)
        let tag = AdditionPicture.Tag(text: line(.tick(value)).display, rect: Components.numberTag(on: rect(order[i]), ten: i < tens))
        let (e, end, joinAt, writeAt, base) = (self, duration, join, answerAt, counting)
        return Motion(
            script: StepScript(duration: duration, events: events),
            picture: { t in
                if t >= end { return e.picture(s1, marking: step) }
                var p = e.drawing(base, marking: step)
                p.tags[i] = tag
                p.tags[i].opacity = keyframes([(0, 0), (0.15, 1), (0.75, 1), (1, 0)], progress(t, start: 0, duration: T.quickTag))
                if let join = joinAt, t >= join {
                    p.total = String(e.problem.sum)
                    p.totalScale = keyframes([(0, 1), (0.5, 1.15), (1, 1)], progress(t, start: join, duration: T.pulse))
                    p.worked = e.wording.runningTotal(e.problem.sumTens * 10, e.problem.sumOnes)
                }
                if let answerAt = writeAt, t >= answerAt {
                    p.answer = String(e.problem.sum)
                    p.answerOpacity = progress(t, start: answerAt, duration: T.answerFade)
                }
                return p.scene(e)
            })
    }

    func miss(_ s: AdditionState, _ l: AdditionDoLine) -> Reaction<AdditionState> {
        Reaction(s, note: .miss(doLine(l)))
    }

    // MARK: try one

    /// Where try one writes the problem, its answer box and the note under it (as subtraction's).
    static let tryProblemAt = CGPoint(x: 470, y: 270)
    static let tryBox = CGRect(x: 650, y: 185, width: 120, height: 92)
    static let tryNoteAt = CGPoint(x: 500, y: 372)

    public var tryOne: (line: Line, scene: Scene) {
        let text = wording.equation
            .replacingOccurrences(of: EquationSlot.first, with: String(problem.first))
            .replacingOccurrences(of: EquationSlot.second, with: String(problem.second))
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
    /// watched, the first other is done with the child (without the separate check step), the
    /// second tried alone.
    public static func lesson(watching problem: AdditionProblem, wording: AdditionWording) -> GuidedLesson<AdditionExplainer> {
        GuidedLesson(
            watch: AdditionExplainer(problem: problem, wording: wording),
            doWithMe: AdditionExplainer(problem: problem.isomorph(1), wording: wording, doing: true),
            tryOne: AdditionExplainer(problem: problem.isomorph(2), wording: wording))
    }
}
