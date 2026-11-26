import ChalkScript
import CoreGraphics
import Foundation

/// The bar graph's child version (EXP-14, EXP-15): watch, do it with me, What if? and try one.
///
/// The child does four steps:
/// - bars: touching each bar's number at the bottom reads it, the first-named bar first; touching
///   the bar's end drops its line to the scale, and the number is still the child's to touch.
/// - compare: a line drawn along from the shorter bar's end to the longer bar's end, on either
///   bar's row or along the numbers.
/// - equation: the two cards, as the tape diagram (the adding card's join, then greyed out).
/// - count: each square of the dashed part touched shows its count, said at once.
/// What if? drags the end of the first-named bar along the scale; the question, the dashed part
/// and the equation follow it, toward three goals. A release within 2 of an exact goal
/// snaps to it, as EXP-15 asks, although every value is a line.
extension BarGraphExplainer: GuidedExplainer {
    public typealias State = GraphState
    public typealias Tinker = DraggedBar

    static let doable: Set<Step> = [.bars, .compare, .equation, .count]

    static let drawTolerance: CGFloat = L.unit * 0.6
    static let drawTallest: CGFloat = 70

    public var guidedSteps: [GuidedStep] {
        steps.map { GuidedStep($0.rawValue, doable: Self.doable.contains($0), countsAloud: $0 == .count) }
    }

    public var start: GraphState { GraphState() }

    public func intro(_ part: GuidedPart) -> Line { line(part == .doWithMe ? .doIntro : .intro) }

    public func picture(_ state: GraphState, marking step: Int?) -> Scene { picture(state) }

    public func watch(_ step: Int, from state: GraphState) -> (state: GraphState, motion: Motion) {
        var s0 = state
        s0.cards = false
        s0.dropped = []
        if steps[step] == .bars { s0.read = [] }
        let s1 = apply(steps[step], s0)
        let (e, from) = (self, s0)
        return (s1, Motion(script: script(for: step), picture: { e.motionPicture(step, from: from, to: s1, at: $0) }))
    }

    public func instruction(_ step: Int, _ state: GraphState) -> Line {
        switch steps[step] {
        case .bars: line(.doBars)
        case .compare: line(.doCompare)
        case .equation: line(.doEquation)
        case .count: line(.doCount)
        case let s: line(lineFor(s))
        }
    }

    public func begin(_ step: Int, _ state: GraphState) -> Reaction<GraphState> {
        var s1 = state
        switch steps[step] {
        case .equation:
            s1.cards = true
            return Reaction(s1, note: .clear)
        case .count:
            s1.counting = true
            return Reaction(s1, note: .clear, tally: Tally(0, of: problem.difference, op: .result))
        default:
            return .ignored(state)
        }
    }

    public func read(_ mark: Mark, step: Int, _ state: GraphState) -> Reaction<GraphState> {
        switch steps[step] {
        case .bars: readBar(mark, step, state)
        case .compare: readDrawOn(mark, step, state)
        case .equation: readCards(mark, step, state)
        case .count: readCell(mark, step, state)
        default: .ignored(state)
        }
    }

    // MARK: reading the bars

    func readBar(_ mark: Mark, _ step: Int, _ s: GraphState) -> Reaction<GraphState> {
        guard s.read.count < 2 else { return .ignored(s) }
        let i = s.read.isEmpty ? problem.first : problem.second
        let value = problem.bars[i]
        let p = mark.at
        let y = Self.rowY(i)
        // Touching the bar's end drops the line to the scale; the number is still hers to read.
        if abs(p.x - Self.x(value)) <= L.unit * 0.6 && p.y >= y - 12 && p.y <= y + L.barHeight + 12 {
            var s1 = s
            if !s1.dropped.contains(i) { s1.dropped.append(i) }
            return Reaction(s1, motion: dropMotion(from: s, to: s1, bar: i, full: false, saying: line(.lands)), note: .clear)
        }
        // Once the line has dropped, a miss points at the number it lands on, not at the bar's end
        // the child has already touched.
        let landed = s.dropped.contains(i)
        if p.y < L.axisY - 10 || p.y > L.axisY + 50 { return miss(s, landed ? .landedMissed : .barMissed(bar: i)) }
        let v = min(BarGraphProblem.scaleMax, max(0, Int(((p.x - L.x0) / L.unit).rounded())))
        guard v == value else { return miss(s, landed ? .landedWrong(v) : .wrongNumber(v, bar: i)) }
        var s1 = s
        s1.read.append(i)
        let done = s1.read.count == 2
        let said = done ? line(.barsRead) : line(.nextBar(problem.second))
        return Reaction(s1, motion: dropMotion(from: s, to: s1, bar: i, full: true, saying: said), note: .clear, finished: done)
    }

    /// A bar's line drawn down to the scale: alone (its end touched) or with its number ringed and
    /// written (its number touched); `saying` is said once it is drawn.
    func dropMotion(from s0: GraphState, to s1: GraphState, bar i: Int, full: Bool, saying: Line) -> Motion {
        let e = self
        return Motion(
            script: StepScript(duration: T.doDrop, events: [StepEvent(T.doDrop, .say(saying, caption: true))]),
            picture: { t in
                var p = e.drawing(s1)
                p.reading[i] = (progress(t, start: 0, duration: T.doDrop, .easeOut), full ? 1 : 0, full ? 1 : 0)
                if !full { p.state.dropped.removeAll { $0 == i } }
                return e.scene(p)
            })
    }

    // MARK: drawing the shorter bar on

    func readDrawOn(_ mark: Mark, _ step: Int, _ s: GraphState) -> Reaction<GraphState> {
        switch DrawOn.read(mark, from: xs, to: xb, tolerance: Self.drawTolerance, tallest: Self.drawTallest) {
        case .drawn:
            let s1 = apply(.compare, s)
            let end = T.drawnGrow + T.gapRest
            let e = self
            let motion = Motion(
                script: StepScript(duration: end, events: [StepEvent(end, .say(line(.compared), caption: true))]),
                picture: { t in
                    var p = e.drawing(s1)
                    e.gapMotion(&p, t, drawn: true)
                    return e.scene(p)
                })
            return Reaction(s1, motion: motion, note: .clear, finished: true)
        case .tapped: return miss(s, .tapped)
        case .notAlong: return miss(s, .notAlong)
        case .startOff: return miss(s, .startOff)
        case .short: return miss(s, .short)
        case .past: return miss(s, .past)
        }
    }

    // MARK: the equation cards

    func readCards(_ mark: Mark, _ step: Int, _ s: GraphState) -> Reaction<GraphState> {
        guard s.cards, let card = cards.card(at: mark.at) else { return .ignored(s) }
        switch card {
        case .add:
            guard !s.addShown else { return .ignored(s) }
            var s1 = s
            s1.addShown = true
            return Reaction(s1, motion: joinMotion(s1), note: .clear)
        case .subtract:
            let s1 = apply(.equation, s)
            var chosen = drawing(s)
            chosen.chosen = true
            return Reaction(
                s1, motion: .still(scene(chosen), saying: [line(.chose)], duration: T.chosen).delayingLines(to: T.chosen),
                note: .clear, finished: true)
        }
    }

    /// The adding card chosen: the two bars joined end to end, the longer first as the card
    /// reads. The whole graph shrinks about its top left, the title and question staying
    /// full size; the joined bar goes under the scale's label, so the graph shrinks at least
    /// enough for it and its sum to stay clear of the cards.
    func joinMotion(_ s: GraphState) -> Motion {
        let sum = equationRuns(text(.addFormat), first: String(problem.big), second: String(problem.small), answer: String(problem.big + problem.small))
        let join = Join(
            bars: [(Self.rowY(problem.longer), CGFloat(problem.big) * L.unit), (Self.rowY(problem.shorter), CGFloat(problem.small) * L.unit)],
            origin: L.joinOrigin, x0: L.x0, y: L.joinY, height: L.barHeight, fill: .line, kMax: L.joinKMax, sum: sum.runs,
            sign: sum.sign)
        let base = picture(s)
        return Motion(
            script: join.script(line(.joined), line(.joinedTotal), after: line(.joinedBut)),
            picture: { t in join.apply(to: base, at: t, scaled: Self.inGraph) })
    }

    /// What the join shrinks: everything but the title, the question and the cards.
    @Sendable static func inGraph(_ e: SceneElement) -> Bool {
        !(e.id.hasPrefix("title") || e.id.hasPrefix("question") || e.id.hasPrefix("card"))
    }

    // MARK: counting the squares

    func readCell(_ mark: Mark, _ step: Int, _ s: GraphState) -> Reaction<GraphState> {
        guard s.counting, s.counted.count < problem.difference else { return .ignored(s) }
        let p = mark.at
        let k = Int(((p.x - xs) / L.unit).rounded(.down))
        guard p.y >= shorterY - 10, p.y <= shorterY + L.barHeight + 10, k >= 0, k < problem.difference else {
            return miss(s, .countMissed)
        }
        guard !s.counted.contains(k) else { return .ignored(s) }
        var s1 = s
        s1.counted.append(k)
        let last = s1.counted.count == problem.difference
        if last { s1.answered = true }
        let times = CountTimes(oneCell: last)
        var events = [StepEvent(0, .say(line(.tick(s1.counted.count)), caption: false))]
        let duration = last ? times.end : T.tagFade
        if last {
            events.append(StepEvent(times.end, .waitForVoice))
            events.append(StepEvent(times.end, .say(line(.answer), caption: true)))
        }
        let (e, end) = (self, s1)
        let motion = Motion(
            script: StepScript(duration: duration, events: events),
            picture: { t in t >= duration ? e.picture(end) : e.countPicture(from: s, cells: [k], times: times, at: t) })
        return Reaction(
            s1, motion: motion, interrupts: true, note: .clear, tally: Tally(s1.counted.count, of: problem.difference, op: .result),
            finished: last)
    }

    func miss(_ s: GraphState, _ l: BarGraphLine) -> Reaction<GraphState> { Reaction(s, note: .miss(line(l))) }

    // MARK: What if? (EXP-15)

    public var whatIf: (start: DraggedBar, goals: Int)? { (DraggedBar(a: problem.a, word: problem.word), 3) }

    /// What if?'s graph: the dragged bar at `s.a`, the other three where they were.
    func tinkered(_ s: DraggedBar) -> BarGraphExplainer {
        BarGraphExplainer(
            problem: BarGraphProblem(unchecked: s.a, problem.b, graph: problem.graph, pair: problem.pair, word: s.word, others: problem.bars),
            wording: wording)
    }

    public func goal(_ goal: Int, _ state: DraggedBar) -> (line: Line, state: DraggedBar) {
        var s = state
        s.dragging = false
        s.released = false
        if goal == 2 { s.flipTo = s.a > problem.b ? .fewer : .more }
        let l: BarGraphLine = goal == 0 ? .goalSame : goal == 1 ? .goalExactly(Self.exactly) : .goalFlip(s.flipTo ?? .fewer)
        return (tinkered(s).line(l), s)
    }

    public func picture(whatIf state: DraggedBar) -> Scene {
        let e = tinkered(state)
        var s = GraphState()
        s.read = [problem.first, problem.second]
        s.gap = true
        s.equation = true
        s.answered = true
        var p = e.drawing(s)
        p.handle = true
        return e.scene(p)
    }

    public func drag(_ drag: Drag, goal: Int, _ state: DraggedBar) -> DraggedBar {
        let y = Self.rowY(problem.first)
        return WhatIf.drag(
            drag, state, other: problem.b,
            onRow: { p in p.y >= y - 20 && p.y <= y + L.barHeight + 20 },
            amount: { p in min(BarGraphProblem.scaleMax, max(1, Int(((p.x - L.x0) / L.unit).rounded()))) })
    }

    public func settle(goal: Int, _ state: DraggedBar, showMe: Bool) -> Settle<DraggedBar> {
        let other = problem.b
        let goals = WhatIf.goals(other: other, exactly: Self.exactly, range: BarGraphProblem.values, flipBy: 4, snaps: true, flipTo: state.flipTo)
        let e = self
        return WhatIf.settle(
            goals[goal], state, showMe: showMe, other: other,
            glide: { from, to in WhatIf.glide(from, to, other: other, hold: { _ in 0.14 }, picture: { e.picture(whatIf: $0) }) },
            met: { s in
                let l: BarGraphLine = goal == 0 ? .goalSameMet : goal == 1 ? .goalExactlyMet(Self.exactly) : .goalFlipMet(s.flipTo ?? s.word)
                return e.tinkered(s).line(l)
            })
    }

    // MARK: try one

    public var tryOne: (line: Line, scene: Scene) {
        var scene = picture(start)
        scene.elements.append(SceneElement("try.note", .text(text(.tryNote), at: CGPoint(x: 500, y: L.equationY), style: .note)))
        return (line(.tryIntro), scene)
    }

    // MARK: the three problems

    public static func lesson(watching problem: BarGraphProblem, wording: BarGraphWording) -> GuidedLesson<BarGraphExplainer> {
        let make = { BarGraphExplainer(problem: $0, wording: wording) }
        return GuidedLesson(watch: make(problem), doWithMe: make(problem.isomorph(1)), tryOne: make(problem.isomorph(2)))
    }
}
