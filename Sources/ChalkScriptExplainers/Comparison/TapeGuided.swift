import ChalkScript
import CoreGraphics
import Foundation

/// The tape diagram's child version (EXP-14, EXP-15): watch, do it with me, What if? and try one.
///
/// The child does the last three steps:
/// - compare: a line drawn along from the shorter bar's end to where the longer one ends, on
///   either bar; the shorter bar is then drawn on, dashed. The child's line fades.
/// - equation: two cards, adding the amounts or taking the shorter from the longer. The adding
///   card shows what adding would mean, the two bars joined end to end with their sum, and is
///   then greyed out; the take-away card is the step.
/// - count: each touch on the number line jumps on, ten at a time and then the ones, and the
///   number reached is said at once.
/// What if? drags the end of the first person's bar, and the story, the dashed part and the
/// equation follow it, toward three goals.
extension TapeDiagramExplainer: GuidedExplainer {
    public typealias State = TapeState
    public typealias Tinker = DraggedBar

    /// The steps the child can do.
    static let doable: Set<Step> = [.compare, .equation, .count]

    /// How far a draw-on line may start or end from the bars' ends, and how far it may rise or fall.
    static let drawTolerance: CGFloat = 26
    static let drawTallest: CGFloat = 60

    public var guidedSteps: [GuidedStep] {
        steps.map { GuidedStep($0.rawValue, doable: Self.doable.contains($0), countsAloud: $0 == .count) }
    }

    public var start: TapeState { TapeState() }

    public func intro(_ part: GuidedPart) -> Line { line(part == .doWithMe ? .doIntro : .intro) }

    public func picture(_ state: TapeState, marking step: Int?) -> Scene { picture(state) }

    public func watch(_ step: Int, from state: TapeState) -> (state: TapeState, motion: Motion) {
        var s0 = state
        s0.cards = false
        let s1 = apply(steps[step], s0)
        let (e, from) = (self, s0)
        return (s1, Motion(script: script(for: step), picture: { e.motionPicture(step, from: from, to: s1, at: $0) }))
    }

    public func instruction(_ step: Int, _ state: TapeState) -> Line {
        switch steps[step] {
        case .compare: line(.doCompare)
        case .equation: line(.doEquation)
        case .count: line(.doCount)
        case let s: line(lineFor(s))
        }
    }

    public func begin(_ step: Int, _ state: TapeState) -> Reaction<TapeState> {
        var s1 = state
        switch steps[step] {
        case .equation:
            s1.cards = true
            return Reaction(s1, note: .clear)
        case .count:
            s1.numberLine = true
            return Reaction(s1, note: .clear, tally: Tally(0, of: problem.hops.count, op: .result))
        default:
            return .ignored(state)
        }
    }

    public func read(_ mark: Mark, step: Int, _ state: TapeState) -> Reaction<TapeState> {
        switch steps[step] {
        case .compare: readDrawOn(mark, step, state)
        case .equation: readCards(mark, step, state)
        case .count: readHop(mark, step, state)
        default: .ignored(state)
        }
    }

    // MARK: drawing the shorter bar on

    func readDrawOn(_ mark: Mark, _ step: Int, _ s: TapeState) -> Reaction<TapeState> {
        switch DrawOn.read(mark, from: xs, to: xb, tolerance: Self.drawTolerance, tallest: Self.drawTallest) {
        case .drawn:
            let s1 = apply(.compare, s)
            let times = GapTimes(dropped: true)
            let e = self
            let motion = Motion(
                script: StepScript(duration: times.end, events: [StepEvent(times.end, .say(line(.compared), caption: true))]),
                picture: { t in
                    var p = e.drawing(s1)
                    e.gapMotion(&p, t, times)
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

    func readCards(_ mark: Mark, _ step: Int, _ s: TapeState) -> Reaction<TapeState> {
        guard s.cards, let card = cards.card(at: mark.at) else { return .ignored(s) }
        switch card {
        case .add:
            // Shown once; after that the adding card is greyed out and does nothing.
            guard !s.addShown else { return .ignored(s) }
            var s1 = s
            s1.addShown = true
            return Reaction(s1, motion: joinMotion(s1), note: .clear)
        case .subtract:
            let s1 = apply(.equation, s)
            var chosen = drawing(s)
            chosen.chosen = true
            let still = scene(chosen)
            return Reaction(
                s1, motion: .still(still, saying: [line(.chose)], duration: T.chosen).delayingLines(to: T.chosen), note: .clear,
                finished: true)
        }
    }

    /// The adding card chosen: the two bars joined end to end. The tape diagram
    /// shrinks about the names' left edge and the top brace; the story, the question and the
    /// cards stay full size.
    func joinMotion(_ s: TapeState) -> Motion {
        let sum = equationRuns(text(.addFormat), first: String(problem.a), second: String(problem.b), answer: String(problem.a + problem.b))
        let join = Join(
            bars: [(L.topY, CGFloat(problem.a) * scale), (L.bottomY, CGFloat(problem.b) * scale)], origin: L.joinOrigin, x0: L.x0,
            y: L.joinY, height: L.barHeight, fill: .sheet, kMax: 1, sum: sum.runs, sign: sum.sign)
        let base = picture(s)
        return Motion(
            script: join.script(line(.joined), line(.joinedTotal), after: line(.joinedBut)),
            picture: { t in join.apply(to: base, at: t, scaled: Self.inDiagram) })
    }

    /// What the join shrinks: everything but the story, the question and the cards.
    @Sendable static func inDiagram(_ e: SceneElement) -> Bool {
        !(e.id.hasPrefix("story") || e.id.hasPrefix("question") || e.id.hasPrefix("card"))
    }

    // MARK: counting on

    func readHop(_ mark: Mark, _ step: Int, _ s: TapeState) -> Reaction<TapeState> {
        guard s.numberLine, s.hops < problem.hops.count else { return .ignored(s) }
        let top = L.topY - 60
        let zone = CGRect(x: xs - 30, y: top, width: xb - xs + 60, height: L.lineY + 40 - top)
        guard zone.contains(mark.at) else { return miss(s, .countMissed) }
        let k = s.hops
        var s1 = s
        s1.hops = k + 1
        let last = s1.hops == problem.hops.count
        if last { s1.answered = true }
        let times = CountTimes(oneHop: last, joins: countJoins)
        var events = [StepEvent(0, .say(line(.tick(problem.hops[k].to)), caption: false))]
        if last { events += finishEvents(times) }
        let (e, end) = (self, s1)
        let motion = Motion(
            script: StepScript(duration: times.end, events: events),
            picture: { t in t >= times.end ? e.picture(end) : e.countPicture(from: s, hopsFrom: k, times: times, at: t) })
        return Reaction(
            s1, motion: motion, interrupts: true, note: .clear, tally: Tally(s1.hops, of: problem.hops.count, op: .result),
            finished: last)
    }

    func miss(_ s: TapeState, _ l: TapeLine) -> Reaction<TapeState> { Reaction(s, note: .miss(line(l))) }

    // MARK: What if? (EXP-15)

    public var whatIf: (start: DraggedBar, goals: Int)? { (DraggedBar(a: problem.a, word: problem.word), 3) }

    /// What if? draws on a scale to 99, so the bar can be dragged across the whole range.
    func tinkered(_ s: DraggedBar) -> TapeDiagramExplainer {
        TapeDiagramExplainer(
            problem: TapeDiagramProblem(unchecked: s.a, problem.b, story: problem.story, names: problem.names, word: s.word),
            wording: wording, scaleMax: TapeDiagramProblem.amounts.upperBound)
    }

    public func goal(_ goal: Int, _ state: DraggedBar) -> (line: Line, state: DraggedBar) {
        var s = state
        s.dragging = false
        s.released = false
        if goal == 2 { s.flipTo = s.a > problem.b ? .fewer : .more }
        let l: TapeLine = goal == 0 ? .goalSame : goal == 1 ? .goalExactly(Self.exactly) : .goalFlip(s.flipTo ?? .fewer)
        return (tinkered(s).line(l), s)
    }

    public func picture(whatIf state: DraggedBar) -> Scene {
        let e = tinkered(state)
        var s = TapeState()
        s.bars = true
        s.gap = true
        s.equation = true
        s.answered = true
        var p = e.drawing(s)
        p.handle = true
        return e.scene(p)
    }

    public func drag(_ drag: Drag, goal: Int, _ state: DraggedBar) -> DraggedBar {
        let unit = L.length / CGFloat(TapeDiagramProblem.amounts.upperBound)
        return WhatIf.drag(
            drag, state, other: problem.b,
            onRow: { p in
                p.y >= L.topY - 40 && p.y <= L.topY + L.barHeight + 30 && p.x >= L.x0 - 20 && p.x <= L.x0 + L.length + 30
            },
            amount: { p in
                min(TapeDiagramProblem.amounts.upperBound, max(1, Int(((p.x - L.x0) / unit).rounded())))
            })
    }

    public func settle(goal: Int, _ state: DraggedBar, showMe: Bool) -> Settle<DraggedBar> {
        let other = problem.b
        let goals = WhatIf.goals(
            other: other, exactly: Self.exactly, range: TapeDiagramProblem.amounts, flipBy: 15, snaps: true, flipTo: state.flipTo)
        let e = self
        return WhatIf.settle(
            goals[goal], state, showMe: showMe, other: other,
            glide: { from, to in
                // The bar slides one number at a time, faster the further it has to go.
                WhatIf.glide(from, to, other: other, hold: { left in max(0.025, 0.32 / Double(max(1, left + 4))) }, picture: { e.picture(whatIf: $0) })
            },
            met: { s in
                let l: TapeLine = goal == 0 ? .goalSameMet : goal == 1 ? .goalExactlyMet(Self.exactly) : .goalFlipMet(s.flipTo ?? s.word)
                return e.tinkered(s).line(l)
            })
    }

    // MARK: try one

    public var tryOne: (line: Line, scene: Scene) {
        var pen = Pen()
        pen.words("story", text(.story), at: CGPoint(x: 500, y: L.storyY), size: L.storySize)
        pen.question("question", wording.question(problem), center: CGPoint(x: 500, y: L.questionY), size: L.storySize, tinted: false)
        pen.add("try.note.1", .text(text(.tryNote(1)), at: CGPoint(x: 500, y: 300), style: .note))
        pen.add("try.note.2", .text(text(.tryNote(2)), at: CGPoint(x: 500, y: 340), style: .note))
        return (line(.tryIntro), pen.scene)
    }

    // MARK: the three problems

    /// The child version on `problem` and two other problems of its kind (EXP-3): `problem` is
    /// watched, the first other is done with the child (and What if? starts from it), the second
    /// tried alone.
    public static func lesson(watching problem: TapeDiagramProblem, wording: TapeDiagramWording) -> GuidedLesson<TapeDiagramExplainer> {
        let make = { TapeDiagramExplainer(problem: $0, wording: wording) }
        return GuidedLesson(watch: make(problem), doWithMe: make(problem.isomorph(1)), tryOne: make(problem.isomorph(2)))
    }
}

extension Motion {
    /// The same motion with every line said at `time` instead of at its start.
    func delayingLines(to time: Double) -> Motion {
        Motion(
            script: StepScript(duration: script.duration, events: script.events.map { StepEvent(max($0.time, time), $0.action) }),
            picture: picture)
    }
}
