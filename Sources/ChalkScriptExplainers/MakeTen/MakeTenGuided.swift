import ChalkScript
import CoreGraphics
import Foundation

/// Make a ten's child version (EXP-14): watch, do it with me, try one.
///
/// The learner does three steps, the last ones first as fading runs backward:
/// - need: a touch on each empty box of the top frame circles it and counts it aloud.
/// - move: the learner drags a dot of the bottom frame up; let go anywhere over the top frame, it
///   drops into the nearest empty box, and the top frame's new count is said ("nine, ten");
///   let go anywhere else, it goes back. No ghost is left where it was.
/// - count: a touch on the full top frame counts it as ten, then a touch on each dot left counts
///   on from ten; each count is said at once, cutting off the one before (EXP-10).
/// Each mark it cannot use is met with a kind line saying what to do instead.
extension MakeTenExplainer: GuidedExplainer {
    public typealias State = MakeTenState

    /// The steps the learner can do.
    static let doable: Set<Step> = [.need, .move, .count]

    public var guidedSteps: [GuidedStep] {
        steps.map {
            GuidedStep($0.rawValue, doable: Self.doable.contains($0), countsAloud: $0 == .need || $0 == .count,
                input: $0 == .move ? .drag : .marks)
        }
    }

    public func intro(_ part: GuidedPart) -> Line { part == .doWithMe ? doLine(.intro) : line(.intro) }

    public func picture(_ state: MakeTenState, marking step: Int?) -> Scene {
        drawing(state, marking: step).scene(self)
    }

    public func watch(_ step: Int, from state: MakeTenState) -> (state: MakeTenState, motion: Motion) {
        var from = state
        from.dragging = nil
        let (s0, s1) = (from, apply(steps[step], from))
        let e = self
        return (s1, Motion(script: script(for: step), picture: { e.motionPicture(step, from: s0, to: s1, at: $0) }))
    }

    public func instruction(_ step: Int, _ state: MakeTenState) -> Line {
        switch steps[step] {
        case .need: doLine(.need)
        case .move: doLine(.move)
        case .count: doLine(.count)
        case .show: line(.show)
        case .split: line(.split)
        }
    }

    public func begin(_ step: Int, _ state: MakeTenState) -> Reaction<MakeTenState> {
        switch steps[step] {
        case .need: Reaction(state, note: .clear, tally: Tally(state.marked.count, of: problem.need, op: .add))
        case .move: Reaction(state, note: .clear, tally: Tally(state.moved.count, of: problem.need, op: .add))
        case .count: Reaction(state, note: .clear)
        default: .ignored(state)
        }
    }

    public func read(_ mark: Mark, step: Int, _ state: MakeTenState) -> Reaction<MakeTenState> {
        switch steps[step] {
        case .need: readNeed(mark.at, step, state)
        case .count: readCount(mark.at, step, state)
        default: .ignored(state)
        }
    }

    public func read(_ drag: Drag, step: Int, _ state: MakeTenState) -> Reaction<MakeTenState> {
        guard steps[step] == .move else { return .ignored(state) }
        return readDrag(drag, step, state)
    }

    // MARK: touching the empty boxes

    func readNeed(_ p: CGPoint, _ step: Int, _ s: MakeTenState) -> Reaction<MakeTenState> {
        guard let k = (0..<10).first(where: { MarkGeometry.inside(p, L.box(top: true, $0), pad: L.boxPad) }) else {
            return miss(s, .touchEmpty)
        }
        if k < problem.big { return miss(s, .boxHasDot) }
        if s.marked.contains(k) { return .ignored(s) }
        var s1 = s
        s1.marked.append(k)
        let n = s1.marked.count
        let finished = n == problem.need
        if finished { s1.marked.sort() }
        let duration = finished ? T.tapMark + T.afterDone : T.tapMark
        var events = [StepEvent(0, .say(line(.tick(n)), caption: false))]
        if finished {
            events += [StepEvent(duration, .waitForVoice), StepEvent(duration, .say(doLine(.needDone), caption: true))]
        }
        let (e, s0, end) = (self, s, s1)
        let motion = Motion(script: StepScript(duration: duration, events: events)) { t in
            if t >= duration { return e.picture(end, marking: step) }
            var p = e.drawing(s0, marking: step)
            p.marks[k - e.problem.big] = progress(t, start: 0, duration: T.tapMark, .easeOut)
            return p.scene(e)
        }
        return Reaction(
            s1, motion: motion, interrupts: true, note: .clear, tally: Tally(n, of: problem.need, op: .add), finished: finished)
    }

    // MARK: dragging the dots up

    func readDrag(_ drag: Drag, _ step: Int, _ s: MakeTenState) -> Reaction<MakeTenState> {
        switch drag {
        case let .began(p):
            let left = remaining(s)
            guard let i = left.first(where: { hypot(p.x - L.center(top: false, $0).x, p.y - L.center(top: false, $0).y) <= L.pickUp })
            else { return .ignored(s) }
            var s1 = s
            s1.dragging = MakeTenDrag(dot: i, at: p)
            return Reaction(s1)
        case let .moved(p):
            guard var d = s.dragging else { return .ignored(s) }
            var s1 = s
            d.at = p
            s1.dragging = d
            return Reaction(s1)
        case let .ended(p):
            guard let d = s.dragging else { return .ignored(s) }
            var back = s
            back.dragging = nil
            let open = free(s)
            guard L.overTopFrame(p), !open.isEmpty else { return miss(back, .dropInBox) }
            // The nearest empty box.
            let cell = open.min { distance(p, L.center(top: true, $0)) < distance(p, L.center(top: true, $1)) }!
            return drop(d.dot, at: p, into: cell, step, back)
        }
    }

    /// The dot settles into its box from where it was let go, and the top frame's count is said;
    /// once the ten is made, "8 + 2 = 10" is written and said.
    func drop(_ dot: Int, at p: CGPoint, into cell: Int, _ step: Int, _ s: MakeTenState) -> Reaction<MakeTenState> {
        var s1 = s
        s1.moved.append(MakeTenMove(dot: dot, cell: cell))
        let n = s1.moved.count
        let finished = n == problem.need
        let duration = finished ? T.settle + T.afterDone : T.settle
        var events = [StepEvent(0, .say(line(.tick(problem.big + n)), caption: false))]
        if finished {
            events += [StepEvent(duration, .waitForVoice), StepEvent(duration, .say(doLine(.moved), caption: true))]
        }
        let (e, end) = (self, s1)
        let motion = Motion(script: StepScript(duration: duration, events: events)) { t in
            if t >= duration { return e.picture(end, marking: step) }
            var q = e.drawing(end, marking: step)
            let to = L.center(top: true, cell)
            q.arrived[cell - e.problem.big].center = mix(p, to, progress(t, start: 0, duration: T.settle, .easeOut))
            // "8 + 2 = 10" is written once the dot has settled and a moment has passed.
            q.work1 = 0
            return q.scene(e)
        }
        return Reaction(
            s1, motion: motion, interrupts: true, note: .clear, tally: Tally(n, of: problem.need, op: .add), finished: finished)
    }

    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // MARK: counting

    func readCount(_ p: CGPoint, _ step: Int, _ s: MakeTenState) -> Reaction<MakeTenState> {
        if MarkGeometry.inside(p, L.frame(top: true), pad: L.countPad) {
            if s.countedTen { return .ignored(s) }
            var s1 = s
            s1.countedTen = true
            let (e, end) = (self, s1)
            let motion = Motion(script: StepScript(duration: T.tenTag, events: [StepEvent(0, .say(line(.tick(10)), caption: false))])) { t in
                if t >= T.tenTag { return e.picture(end, marking: step) }
                var q = e.drawing(end, marking: step)
                q.tenTag = keyframes([(0, 0), (0.15, 1), (0.8, 1), (1, 0)], progress(t, start: 0, duration: T.tenTag))
                return q.scene(e)
            }
            return Reaction(s1, motion: motion, interrupts: true, note: .clear)
        }
        let left = remaining(s)
        guard let i = left.first(where: { MarkGeometry.inside(p, L.box(top: false, $0), pad: L.countPad) }), !s.countedOnes.contains(i)
        else { return .ignored(s) }
        if !s.countedTen { return miss(s, .tenFirst) }
        var s1 = s
        s1.countedOnes.append(i)
        let k = s1.countedOnes.count
        let finished = k == left.count
        if finished { s1.answered = true }
        let answerAt = T.beforeAnswer
        let duration = finished ? max(T.oneTag, answerAt + T.answerFade) : T.oneTag
        var events = [StepEvent(0, .say(line(.tick(10 + k)), caption: false))]
        if finished {
            let at = answerAt + T.answerFade
            events += [StepEvent(at, .waitForVoice), StepEvent(at, .say(line(.answer), caption: true))]
        }
        var counting = s1
        counting.answered = false
        let (e, base, end) = (self, counting, s1)
        let tag = line(.tick(10 + k)).display
        let motion = Motion(script: StepScript(duration: duration, events: events)) { t in
            if t >= duration { return e.picture(end, marking: step) }
            var q = e.drawing(base, marking: step)
            q.oneTags[i] = MakeTenPicture.Tag(
                text: tag, opacity: keyframes([(0, 0), (0.15, 1), (0.75, 1), (1, 0)], progress(t, start: 0, duration: T.oneTag)))
            if finished, t >= answerAt {
                q.work2 = e.wording.sum(10, e.problem.rest, e.problem.sum)
                q.answer = String(e.problem.sum)
                q.answerOpacity = progress(t, start: answerAt, duration: T.answerFade)
            }
            return q.scene(e)
        }
        return Reaction(s1, motion: motion, interrupts: true, note: .clear, finished: finished)
    }

    func miss(_ s: MakeTenState, _ l: MakeTenDoLine) -> Reaction<MakeTenState> {
        Reaction(s, note: .miss(doLine(l)))
    }

    // MARK: try one

    /// Where try one writes the problem, its answer box and the note under it (as subtraction's
    /// try one sets them).
    static let tryProblemAt = CGPoint(x: 480, y: 270)
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
    /// watched, the first other is done with the learner, the second tried alone.
    public static func lesson(watching problem: MakeTenProblem, wording: MakeTenWording) -> GuidedLesson<MakeTenExplainer> {
        let make = { MakeTenExplainer(problem: $0, wording: wording) }
        return GuidedLesson(watch: make(problem), doWithMe: make(problem.isomorph(1)), tryOne: make(problem.isomorph(2)))
    }
}
