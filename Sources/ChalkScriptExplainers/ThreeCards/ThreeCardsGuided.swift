import ChalkScript
import CoreGraphics
import Foundation

/// Three cards' child version (EXP-14, EXP-16): watch, do it with me, try one, with Why? on the
/// too-many step.
///
/// The child does two steps, the last first as fading runs backward:
/// - add: a tap lifts a card that is down and lowers one that is up; the equation above follows
///   every tap and the new total is said, cutting off the one before (EXP-10). Once all five are
///   up, the first written line is written.
/// - drop: a tap puts a card back (down, in take-away's colour) or lifts it again; the third
///   written line follows the cards put back. Two that make how many too many (or come closest)
///   finish the step. Two others are told what they make and what is needed; more than two are
///   asked for just two; and the three answer cards put down are recognised as the answer found
///   the direct way, and the cards swap so those up are the ones in the sum. None of these is a
///   miss.
extension ThreeCardsExplainer: GuidedExplainer {
    public typealias State = ThreeCardsState

    /// The steps the child can do.
    static let doable: Set<Step> = [.add, .drop]

    public var guidedSteps: [GuidedStep] {
        steps.map { GuidedStep($0.rawValue, doable: Self.doable.contains($0), countsAloud: $0 == .add) }
    }

    /// In do it with me the question is asked once, by the first step with the plan.
    public func intro(_ part: GuidedPart) -> Line { part == .doWithMe ? doLine(.intro) : line(.intro) }

    public func picture(_ state: ThreeCardsState, marking step: Int?) -> Scene { drawing(state) }

    public func watch(_ step: Int, from state: ThreeCardsState) -> (state: ThreeCardsState, motion: Motion) {
        let s1 = apply(steps[step], state)
        return (s1, watchMotion(step, from: state, to: s1))
    }

    public func instruction(_ step: Int, _ state: ThreeCardsState) -> Line {
        switch steps[step] {
        case .read: line(.read)
        case .add: doLine(.add)
        case .over: line(.over)
        case .drop: doLine(.drop)
        case .check: line(.check)
        }
    }

    public func begin(_ step: Int, _ state: ThreeCardsState) -> Reaction<ThreeCardsState> {
        switch steps[step] {
        case .add: Reaction(state, note: .clear, tally: Tally(state.up.count, of: ThreeCardsProblem.cardCount, op: .add))
        case .drop: Reaction(state, note: .clear)
        default: .ignored(state)
        }
    }

    public func read(_ mark: Mark, step: Int, _ state: ThreeCardsState) -> Reaction<ThreeCardsState> {
        // A line that starts on a card is read as a touch on it; it fades either way.
        guard let k = card(at: mark.at, state) else { return .ignored(state) }
        switch steps[step] {
        case .add: return readAdd(k, step, state)
        case .drop: return readDrop(k, step, state)
        default: return .ignored(state)
        }
    }

    // MARK: lifting all five

    func readAdd(_ k: Int, _ step: Int, _ s: ThreeCardsState) -> Reaction<ThreeCardsState> {
        var s1 = s
        if let i = s1.up.firstIndex(of: k) { s1.up.remove(at: i) } else { s1.up.append(k) }
        let n = ThreeCardsProblem.cardCount
        let move = Move(card: k, up: s1.up.contains(k), at: 0)
        let said = StepEvent(0, .say(line(.total(problem.sum(s1.up))), caption: false))
        guard s1.up.count == n else {
            return Reaction(
                s1, motion: tapMotion(from: s, to: s1, [move], events: [said]), interrupts: true, note: .clear,
                tally: Tally(s1.up.count, of: n, op: .add))
        }
        // All five up: the first line is written in the order they went up, then the total is said.
        s1.added = s1.up
        s1.work = max(s1.work, 1)
        let workAt = T.lift + T.beforeWork
        let end = workAt + T.workFade
        let (e, done) = (self, s1)
        let motion = Motion(
            script: StepScript(duration: end, events: [said, StepEvent(end, .say(doLine(.added), caption: true))]),
            picture: { t in
                if t >= end { return e.drawing(done) }
                var p = e.pose(done)
                e.lift(&p, [move], at: t)
                p.workOpacity[0] = progress(t, start: workAt, duration: T.workFade)
                return e.scene(p)
            })
        return Reaction(s1, motion: motion, interrupts: true, note: .clear, tally: Tally(n, of: n, op: .add), finished: true)
    }

    // MARK: putting two back

    func readDrop(_ k: Int, _ step: Int, _ s: ThreeCardsState) -> Reaction<ThreeCardsState> {
        var s1 = s
        if let i = s1.up.firstIndex(of: k) {
            s1.up.remove(at: i)
            s1.down.append(k)
        } else {
            s1.up.append(k)
            s1.down.removeAll { $0 == k }
        }
        // The third line is written as the first card goes back, and follows every tap after.
        let writes = s.work < 3 && !s1.down.isEmpty
        if writes { s1.work = 3 }
        let move = Move(card: k, up: s1.up.contains(k), at: 0)
        let moved = T.lift + (writes ? T.workFade : 0)
        var events = [StepEvent(0, .say(line(.total(problem.sum(s1.up))), caption: false))]
        let p = problem
        let three = p.cards.count - 2
        if s1.down.count == three && abs(p.sum(s1.down) - p.target) == abs(p.result - p.target) {
            return swap(from: s, to: s1, move, step)
        }
        if s1.down.count > 2 {
            let hint = doLine(.justTwo)
            events.append(StepEvent(T.lift, .say(hint, caption: false)))
            return Reaction(s1, motion: tapMotion(from: s, to: s1, [move], events: events, writes: writes), interrupts: true, note: .hint(hint))
        }
        guard s1.down.count == 2 else {
            return Reaction(s1, motion: tapMotion(from: s, to: s1, [move], events: events, writes: writes), interrupts: true, note: .clear)
        }
        let (a, b) = (p.cards[s1.down[0]], p.cards[s1.down[1]])
        if abs(a + b - p.over) == p.bestDiff {
            events.append(StepEvent(moved, .say(doLine(.dropped(a, b)), caption: true)))
            return Reaction(
                s1, motion: tapMotion(from: s, to: s1, [move], events: events, writes: writes), interrupts: true, note: .clear,
                finished: true)
        }
        // Two that are not the pair: no mistake, just what they make and what we need.
        let hint = doLine(.otherPair(sum: a + b))
        events.append(StepEvent(moved, .say(hint, caption: false)))
        return Reaction(s1, motion: tapMotion(from: s, to: s1, [move], events: events, writes: writes), interrupts: true, note: .hint(hint))
    }

    /// The three answer cards put down: said so, then they swap with the two still up, so the
    /// cards up are the ones in the sum and the two down are those put back.
    func swap(from s0: ThreeCardsState, to s1: ThreeCardsState, _ move: Move, _ step: Int) -> Reaction<ThreeCardsState> {
        let p = problem
        let three = s1.down
        let two = s1.up
        var s2 = s1
        s2.up = three
        s2.down = two
        s2.swapped = true
        let k = three.map { p.cards[$0] }
        let found = doLine(.foundThree(k[0], k[1], k[2], sum: p.sum(three)))
        let swapAt = T.lift
        let end = swapAt + T.lift + T.afterSwap
        let swaps = two.map { Move(card: $0, up: false, at: swapAt) } + three.map { Move(card: $0, up: true, at: swapAt) }
        let events = [
            StepEvent(0, .say(line(.total(p.sum(s1.up))), caption: false)),
            StepEvent(swapAt, .say(found, caption: false)),
            StepEvent(swapAt, .waitForVoice),
            StepEvent(end, .say(doLine(.swapped(p.cards[two[0]], p.cards[two[1]])), caption: true)),
        ]
        let (e, swapped) = (self, s2)
        let motion = Motion(
            script: StepScript(duration: end, events: events),
            picture: { t in
                if t >= end { return e.drawing(swapped) }
                // While what the child found is said, the cards stand as the child left them.
                if t <= swapAt {
                    var q = e.pose(s1)
                    e.lift(&q, [move], at: t)
                    return e.scene(q)
                }
                var q = e.pose(swapped)
                e.lift(&q, swaps, at: t)
                // The Put back line changes once the cards have swapped.
                if t < swapAt + T.lift { q.work[2] = e.workTokens(2, s1) }
                return e.scene(q)
            })
        return Reaction(s2, motion: motion, interrupts: true, note: .hint(found), finished: true)
    }

    /// One tapped card going up or down from `s0` to `s1`: its colour and the equation above
    /// change at once; with `writes`, the third written line fades in once the card has moved.
    func tapMotion(
        from s0: ThreeCardsState, to s1: ThreeCardsState, _ moves: [Move], events: [StepEvent], writes: Bool = false
    ) -> Motion {
        let end = T.lift + (writes ? T.workFade : 0)
        let e = self
        return Motion(
            script: StepScript(duration: end, events: events),
            picture: { t in
                if t >= end { return e.drawing(s1) }
                var p = e.pose(s1)
                e.lift(&p, moves, at: t)
                if writes { p.workOpacity[2] = progress(t, start: T.lift, duration: T.workFade) }
                return e.scene(p)
            })
    }

    // MARK: Why?

    public func why(_ step: Int, _ state: ThreeCardsState) -> Motion? {
        steps[step] == .over ? whyMotion() : nil
    }

    // MARK: try one

    public var tryOne: (line: Line, scene: Scene) {
        var scene = drawing(start)
        scene.elements.append(SceneElement("try.note", .text(text(.tryNote), at: ThreeCardsLayout.tryNoteAt, style: .note)))
        return (doLine(.tryIntro), scene)
    }

    // MARK: the three problems

    /// The child version on `problem` and two other problems of its kind (EXP-3): `problem` is
    /// watched, the first other is done with the child, the second tried alone.
    public static func lesson(watching problem: ThreeCardsProblem, wording: ThreeCardsWording) -> GuidedLesson<ThreeCardsExplainer> {
        let make = { ThreeCardsExplainer(problem: $0, wording: wording) }
        return GuidedLesson(watch: make(problem), doWithMe: make(problem.isomorph(1)), tryOne: make(problem.isomorph(2)))
    }
}
