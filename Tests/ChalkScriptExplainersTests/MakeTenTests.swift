import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

// Make a ten on two ten frames: watch, do it with me (touch the
// empty boxes, drag the dots up, count) and try one.

/// Synthetic wording shaped like the app's entries. The app's own tests
/// check the real entries.
enum MakeTenFixture {
    static func wording() -> MakeTenWording {
        MakeTenWording(
            line: { l, p in
                let display: String =
                    switch l {
                    case .intro: "\(p.first) plus \(p.second). Let's make a ten!"
                    case .show: "We put \(p.big) in the top ten frame, and \(p.small) in the bottom one."
                    case .need: "\(p.big) needs \(p.need) more to make ten."
                    case .split: "So we split \(p.small) into \(p.need) and \(p.rest)."
                    case .move: "Move \(p.need) up to make ten. \(p.big) and \(p.need) make 10!"
                    case .count: "Now count: ten, and \(p.rest) more."
                    case let .tick(n): "\(n)"
                    case .answer: "10 plus \(p.rest) is \(p.sum). So \(p.first) plus \(p.second) is \(p.sum)!"
                    }
                return Line(
                    key: "explain.test.makeTen.\(l)", display: display, spoken: NumberWords.replacingNumerals(in: display),
                    emphasis: l == .answer ? String(p.sum) : nil)
            },
            doLine: { l, p in
                let display: String =
                    switch l {
                    case .intro: "Now let's do one together: \(p.first) plus \(p.second)."
                    case .need: "How many more does \(p.big) need to make ten? Touch each empty box."
                    case .move: "Drag \(p.need) dots up into the empty boxes."
                    case .count: "Count them: touch the full ten frame, then each dot left."
                    case .needDone: "\(p.big) needs \(p.need) more."
                    case .moved: "\(p.big) and \(p.need) make 10!"
                    case .touchEmpty: "Touch the empty boxes in the top ten frame."
                    case .boxHasDot: "That box has a dot. Touch the empty ones."
                    case .dropInBox: "Drop it in an empty box in the top ten frame."
                    case .tenFirst: "Start with the full ten frame: that's ten."
                    case .tryIntro: "Now you try one: \(p.first) plus \(p.second)."
                    case .tryNote: "Your turn. Make a ten first, then add what is left."
                    }
                return Line(key: "explain.test.makeTen.do.\(l)", display: display, spoken: NumberWords.replacingNumerals(in: display))
            },
            unknown: "?", equation: "\(EquationSlot.first) + \(EquationSlot.second) = \(EquationSlot.answer)",
            sum: { "\($0) + \($1) = \($2)" }, partial: { "\($0) + \($1)" })
    }

    static func explainer(_ a: Int, _ b: Int) -> MakeTenExplainer {
        MakeTenExplainer(problem: try! MakeTenProblem(a, plus: b), wording: wording())
    }

    /// The range's edges (EXP-2): the smallest and largest totals, one needed and four needed, the
    /// bigger number first, second, and both equal, and 8 + 7.
    static let edges: [(Int, Int)] = [(2, 9), (9, 2), (6, 5), (5, 6), (6, 6), (8, 7), (7, 8), (9, 9), (6, 9), (9, 6), (4, 7)]
}

typealias MT = MakeTenLayout

func touch(_ p: CGPoint) -> Mark { .tap(p) }

struct MakeTenTests {
    func step(_ e: MakeTenExplainer, _ s: MakeTenProblem.Step) -> Int { e.steps.firstIndex(of: s)! }

    // MARK: the model (EXP-2)

    @Test func theTemplateTakesTwoOneDigitNumbersThatMakeATen() throws {
        #expect(MakeTenProblem.accepts(8, plus: 7) && MakeTenProblem.accepts(2, plus: 9) && MakeTenProblem.accepts(9, plus: 9))
        #expect(throws: MakeTenProblem.RangeError.number(1)) { try MakeTenProblem(1, plus: 9) }
        #expect(throws: MakeTenProblem.RangeError.number(10)) { try MakeTenProblem(8, plus: 10) }
        #expect(throws: MakeTenProblem.RangeError.noTen(total: 10)) { try MakeTenProblem(4, plus: 6) }
        // 2 to 9 each, totals 11 to 18.
        #expect(MakeTenProblem.all.count == 36)
        for p in MakeTenProblem.all {
            #expect(p.need >= 1 && p.need <= 4 && p.rest >= 1 && p.big + p.need == 10 && p.need + p.rest == p.small)
            #expect(p.steps == [.show, .need, .split, .move, .count])
        }
        let p = try MakeTenProblem(7, plus: 8)
        #expect(!p.firstOnTop && p.big == 8 && p.small == 7 && p.need == 2 && p.rest == 5 && p.sum == 15)
    }

    /// EXP-3: the other two problems are the same kind (bigger number first or second as the
    /// learner's), never the learner's problem or its total, and the two differ in total.
    @Test func theOtherProblemsAreOfTheSameKind() {
        for p in MakeTenProblem.all {
            let (one, two) = (p.isomorph(1), p.isomorph(2))
            for q in [one, two] {
                #expect(q != p && q.sum != p.sum && q.firstOnTop == p.firstOnTop, "\(p): \(q)")
            }
            #expect(one.sum != two.sum, "\(p): \(one) and \(two)")
            #expect(p.isomorph(1) == one, "the pick is fixed for a problem")
        }
    }

    @Test func theDoableStepsAreTouchDragAndCount() {
        let e = MakeTenFixture.explainer(8, 7)
        #expect(e.guidedSteps.map(\.id) == ["show", "need", "split", "move", "count"])
        #expect(e.guidedSteps.map(\.doable) == [false, true, false, true, true])
        #expect(e.guidedSteps.map(\.countsAloud) == [false, true, false, false, true])
        #expect(e.guidedSteps.map(\.input) == [.marks, .marks, .marks, .drag, .marks])
    }

    // MARK: watch

    /// Every step of every problem: the motion ends on the still picture (EXP-11), keeps its
    /// elements' ids from moment to moment, marks at most three things (EXP-5), and every line is
    /// said; the last picture has the answer.
    @Test func everyProblemPlaysEveryStep() {
        for p in MakeTenProblem.all {
            let e = MakeTenExplainer(problem: p, wording: MakeTenFixture.wording())
            var s = e.start
            let ids = e.picture(s, marking: nil).elements.map(\.id)
            for k in 0..<e.stepCount {
                let (s1, motion) = e.watch(k, from: s)
                #expect(motion.script == e.script(for: k))
                #expect(motion.end == e.picture(s1, marking: k), "\(p) step \(k)")
                #expect(e.picture(s1, marking: k) == e.still(after: k))
                for f in stride(from: 0.0, through: 1.0, by: 0.1) {
                    let scene = motion.picture(motion.script.duration * f)
                    #expect(scene.elements.map(\.id) == ids, "\(p) step \(k) at \(f)")
                    #expect(scene.markedCount <= 3, "\(p) step \(k) at \(f)")
                }
                s = s1
            }
            #expect(s.answered && s.countedTen && s.countedOnes == Array(0..<p.rest))
            guard case let .equation(eq)? = e.still(after: e.stepCount - 1).element("equation")?.kind else {
                Issue.record("no equation"); continue
            }
            #expect(eq.text == "\(p.first) + \(p.second) = \(p.sum)")
        }
    }

    @Test func showDrawsTheBiggerNumberFilledOnTopAndTheSmallerOpenBelow() {
        let e = MakeTenFixture.explainer(7, 8)
        let still = e.still(after: 0)
        #expect(still.elements("top.dot.").count == 8 && still.elements("bottom.dot.").count == 7)
        guard case let .shape(_, filled)? = still.element("top.dot.0")?.kind,
            case let .shape(_, open)? = still.element("bottom.dot.0")?.kind
        else { Issue.record("no counters"); return }
        #expect(filled.fill == .pencil && open.fill == .sheet && open.stroke == .pencil)
        // Halfway through, the top counters have come in one after another and the bottom ones
        // not yet.
        let mid = e.scene(step: 0, at: 0.5)
        #expect(mid.element("top.dot.0")!.opacity == 1 && mid.element("top.dot.7")!.opacity == 0)
        #expect(mid.element("bottom.dot.0")!.opacity == 0)
    }

    /// The smaller number is marked in add's colour while it is split and while its part moves
    /// (EXP-5); the moved dots leave no ghost; the worked lines are checked too.
    @Test func splitAndMoveMarkTheSmallerNumberAndLeaveNoGhost() {
        let e = MakeTenFixture.explainer(8, 7)
        guard case let .equation(eq)? = e.still(after: step(e, .split)).element("equation")?.kind else { Issue.record("no equation"); return }
        #expect(eq.mark?.op == .add && eq.runs[eq.mark!.run].text == "7")
        #expect(e.still(after: step(e, .split)).element("hint").map { $0.isVisible } == true)
        let moved = e.still(after: step(e, .move))
        // Dots 5 and 6 moved into boxes 8 and 9; their places in the bottom frame are empty.
        #expect(moved.element("bottom.dot.6")!.opacity == 0 && moved.element("bottom.dot.5")!.opacity == 0)
        #expect(moved.element("bottom.dot.4")!.opacity == 1)
        #expect(moved.element("top.moved.8")!.opacity == 1 && moved.element("top.moved.9")!.opacity == 1)
        guard case let .words(w1, _)? = moved.element("work.1")?.kind else { Issue.record("no worked line"); return }
        #expect(w1 == "8 + 2 = 10" && moved.element("work.1")!.opacity == 1)
        // Halfway along its path the first dot is between the frames.
        let travelling = e.scene(step: step(e, .move), at: 0.45)
        guard case let .shape(.ellipse(r), _)? = travelling.element("top.moved.8")?.kind else { Issue.record("no dot"); return }
        #expect(r.midY > MT.center(top: true, 8).y && r.midY < MT.center(top: false, 6).y)
    }

    @Test func theCountGoesTenThenOnFromTen() {
        let e = MakeTenFixture.explainer(8, 7)
        let k = step(e, .count)
        let script = e.script(for: k)
        let said = script.events.compactMap { ev -> String? in
            if case let .say(line, _) = ev.action { return line.display }
            return nil
        }
        #expect(said == ["Now count: ten, and 5 more.", "10", "11", "12", "13", "14", "15", "10 plus 5 is 15. So 8 plus 7 is 15!"])
        let end = e.still(after: k)
        guard case let .words(w2, _)? = end.element("work.2")?.kind else { Issue.record("no count line"); return }
        #expect(w2 == "10 + 5 = 15")
        guard case let .shape(_, paint)? = end.element("top.dot.0")?.kind else { Issue.record("no counter"); return }
        #expect(paint.fill == .fill(.result))
        // While the third one is counted, its tag shows 13 and the line runs "10 + 3".
        let times = e.countTimes
        let third = e.scene(step: k, at: times.ones[2] + 0.3)
        guard case let .numberTag(tag, _, _)? = third.element("tag.one.2")?.kind, case let .words(running, _)? = third.element("work.2")?.kind
        else { Issue.record("no tag"); return }
        #expect(tag == "13" && third.element("tag.one.2")!.opacity == 1 && running == "10 + 3")
    }

    // MARK: do it with me (EXP-14)

    @Test func touchingTheEmptyBoxesCountsThem() {
        let e = MakeTenFixture.explainer(8, 7)
        let k = step(e, .need)
        var s = e.state(after: k - 1)
        #expect(e.instruction(k, s) == e.doLine(.need))
        #expect(e.begin(k, s).tally == Tally(0, of: 2, op: .add))
        #expect(e.read(touch(CGPoint(x: 800, y: 300)), step: k, s).note == .miss(e.doLine(.touchEmpty)))
        #expect(e.read(touch(MT.center(top: true, 3)), step: k, s).note == .miss(e.doLine(.boxHasDot)))
        // The last box first: either order counts.
        let first = e.read(touch(MT.center(top: true, 9)), step: k, s)
        #expect(first.state.marked == [9] && first.tally == Tally(1, of: 2, op: .add) && first.interrupts && !first.finished)
        guard case let .say(one, false)? = first.motion?.script.events.first?.action else { Issue.record("no count"); return }
        #expect(one.display == "1")
        s = first.state
        #expect(e.read(touch(MT.center(top: true, 9)), step: k, s).state == s, "a box touched again is ignored")
        let last = e.read(.stroke([MT.center(top: true, 8), CGPoint(x: 400, y: 200)]), step: k, s)
        #expect(last.finished && last.state.marked == [8, 9])
        guard case let .say(done, true)? = last.motion?.script.events.last?.action else { Issue.record("no line at the end"); return }
        #expect(done.display == "8 needs 2 more.")
        #expect(last.motion?.end == e.picture(last.state, marking: k))
    }

    @Test func aDotLetGoOverTheTopFrameDropsIntoTheNearestEmptyBox() {
        let e = MakeTenFixture.explainer(7, 8)  // 8 on top, 7 below: two to move
        let k = step(e, .move)
        var s = e.state(after: k - 1)
        #expect(e.begin(k, s).tally == Tally(0, of: 2, op: .add))
        // A drag that starts on no dot moves nothing.
        #expect(e.read(.began(CGPoint(x: 800, y: 300)), step: k, s).state.dragging == nil)
        // The first dot, not the last: whichever the learner takes.
        let start = MT.center(top: false, 0)
        s = e.read(.began(start), step: k, s).state
        #expect(s.dragging?.dot == 0)
        s = e.read(.moved(CGPoint(x: 520, y: 290)), step: k, s).state
        let dragging = e.picture(s, marking: k)
        #expect(dragging.element("bottom.dot.0")!.opacity == 0 && dragging.element("drag")!.opacity == 1)
        // Let go outside the top frame: it goes back, with a kind line.
        let back = e.read(.ended(CGPoint(x: 520, y: 290)), step: k, s)
        #expect(back.note == .miss(e.doLine(.dropInBox)) && back.state.dragging == nil && back.state.moved.isEmpty)
        #expect(e.picture(back.state, marking: k).element("bottom.dot.0")!.opacity == 1)
        // Let go just above the frame, nearest box 9: it drops there and "nine" is said.
        s = e.read(.began(start), step: k, back.state).state
        let near9 = CGPoint(x: MT.center(top: true, 4).x + 5, y: MT.topY - 12)
        let drop = e.read(.ended(near9), step: k, s)
        #expect(drop.state.moved == [MakeTenMove(dot: 0, cell: 9)] && drop.tally == Tally(1, of: 2, op: .add) && !drop.finished)
        guard case let .say(nine, false)? = drop.motion?.script.events.first?.action else { Issue.record("no count"); return }
        #expect(nine.display == "9")
        s = drop.state
        let afterFirst = e.picture(s, marking: k)
        #expect(afterFirst.element("bottom.dot.0")!.opacity == 0 && afterFirst.element("top.moved.9")!.opacity == 1)
        #expect(afterFirst.element("work.1")!.opacity == 0)
        // The second goes into the one box left, wherever over the frame it is let go.
        s = e.read(.began(MT.center(top: false, 6)), step: k, s).state
        let last = e.read(.ended(MT.center(top: true, 0)), step: k, s)
        #expect(last.finished && last.state.moved.last == MakeTenMove(dot: 6, cell: 8))
        guard case let .say(made, true)? = last.motion?.script.events.last?.action else { Issue.record("no line at the end"); return }
        #expect(made.display == "8 and 2 make 10!")
        #expect(e.picture(last.state, marking: k).element("work.1")!.opacity == 1)
        // The count then counts the dots the learner left, in the order touched.
        let c = step(e, .count)
        var t = last.state
        #expect(e.read(touch(MT.center(top: false, 1)), step: c, t).note == .miss(e.doLine(.tenFirst)))
        t = e.read(touch(MT.center(top: true, 2)), step: c, t).state
        #expect(t.countedTen)
        #expect(e.read(touch(MT.center(top: false, 0)), step: c, t).state == t, "a dot moved up is not in the bottom frame")
        for (n, i) in [5, 1, 2, 3, 4].enumerated() {
            let r = e.read(touch(MT.center(top: false, i)), step: c, t)
            guard case let .say(tick, false)? = r.motion?.script.events.first?.action else { Issue.record("no count"); return }
            #expect(tick.display == String(11 + n) && r.interrupts)
            t = r.state
            if n == 4 {
                #expect(r.finished && t.answered)
                guard case let .say(answer, true)? = r.motion?.script.events.last?.action else { Issue.record("no answer"); return }
                #expect(answer.display == "10 plus 5 is 15. So 7 plus 8 is 15!" && answer.emphasis == "15")
            }
        }
        #expect(t.countedOnes == [5, 1, 2, 3, 4])
    }

    /// The learner's whole do it with me through the player, with a finger's drags, then try one.
    @MainActor @Test func thePlayerRunsWatchDoItWithMeAndTryOne() {
        let voice = RecordingVoice()
        let lesson = MakeTenExplainer.lesson(watching: try! MakeTenProblem(8, plus: 7), wording: MakeTenFixture.wording())
        let player = GuidedPlayer(lesson: lesson, voice: voice, labels: Fixture.guidedLabels, drivesItself: false)
        #expect(player.parts == [.watch, .doWithMe, .tryOne])
        player.primary()
        for _ in 0..<5 {
            player.settle(voice)
            player.primary()
        }
        #expect(player.part == .doWithMe)
        #expect(player.doSet == [1, 3, 4])
        let e = lesson.doWithMe
        let p = e.problem
        // Start: show is watched and runs on into need, whose instruction is said first.
        player.primary()
        player.settle(voice)
        #expect(player.phase == .doing(1) && player.readsMarks)
        for c in p.big..<10 {
            player.touchBegan(at: MT.center(top: true, c))
            player.touchEnded(at: MT.center(top: true, c))
            player.settle(voice)
        }
        // Split is watched, and runs on into move.
        #expect(player.phase == .doing(3))
        for i in (p.small - p.need..<p.small).reversed() {
            player.touchBegan(at: MT.center(top: false, i))
            player.touchMoved(to: CGPoint(x: 300, y: 220))
            player.touchEnded(at: CGPoint(x: 300, y: 200))
            player.settle(voice)
        }
        // Count.
        #expect(player.phase == .doing(4))
        player.touchBegan(at: MT.center(top: true, 0))
        player.touchEnded(at: MT.center(top: true, 0))
        player.settle(voice)
        for i in 0..<p.rest {
            player.touchBegan(at: MT.center(top: false, i))
            player.touchEnded(at: MT.center(top: false, i))
            player.settle(voice)
        }
        #expect(player.phase == .paused(4))
        #expect(voice.said.last?.display == "10 plus \(p.rest) is \(p.sum). So \(p.first) plus \(p.second) is \(p.sum)!")
        player.primary()
        #expect(player.part == .tryOne)
        let t = lesson.tryOne.problem
        guard case let .text(problem, _, _)? = player.scene.element("try.problem")?.kind else { Issue.record("no problem"); return }
        #expect(problem == "\(t.first) + \(t.second) = ")
    }

    /// Show me on a half-done drag plays the step as watched, from where the step began.
    @MainActor @Test func showMeMovesTheDotsAsWatched() {
        let voice = RecordingVoice()
        // A problem whose do-it-with-me problem moves more than one dot.
        let watched = MakeTenProblem.all.first { $0.isomorph(1).need >= 2 }!
        let lesson = MakeTenExplainer.lesson(watching: watched, wording: MakeTenFixture.wording())
        let player = GuidedPlayer(lesson: lesson, voice: voice, labels: Fixture.guidedLabels, fading: 2, drivesItself: false)
        player.jump(to: .doWithMe)
        let p = lesson.doWithMe.problem
        player.primary()
        player.settle(voice)
        #expect(player.phase == .doing(3))
        player.touchBegan(at: MT.center(top: false, 0))
        player.touchEnded(at: MT.center(top: true, 9))
        player.settle(voice)
        #expect(player.phase == .doing(3) && player.tally == Tally(1, of: p.need, op: .add))
        player.showMe()
        // Show me plays the step as watched; it ends on the watched picture, and after a beat
        // the next step opens.
        while case .playing = player.phase {
            player.advance(by: 1.0 / 60)
            voice.finish()
        }
        #expect(player.phase == .paused(3) && player.primaryControl == nil)
        #expect(player.scene == lesson.doWithMe.picture(lesson.doWithMe.state(after: 3), marking: 3))
        #expect(lesson.doWithMe.state(after: 3).moved.count == p.need)
    }

    // MARK: colour (EXP-6)

    /// Make a ten shows add (the marked number) and the answer (the count, the tags, the answer)
    /// beside pencil; nothing in it is take-away's or the trade's colour.
    @Test(arguments: [false, true]) func makeATenShowsAddAndTheAnswerApart(dark: Bool) {
        var ops: Set<ExplainerOperation> = []
        for (a, b) in MakeTenFixture.edges { ops.formUnion(ColourVisionTests.operationsShown(by: MakeTenFixture.explainer(a, b))) }
        #expect(ops == [.add, .result])
        let p = ExplainerPalette.for(dark: dark)
        let c = ColourVisionTests.closest(ColourVisionTests.shown(.add, p), ColourVisionTests.shown(.result, p))
        #expect(c.distance >= ColourVisionTests.minimum)
        for op in ops {
            let neutral = ColourVisionTests.closest(ColourVisionTests.shown(op, p), [p.pencil, p.ink])
            #expect(neutral.distance >= ColourVisionTests.minimum, "\(op) and the pencil or text are \(neutral.distance) apart")
        }
    }

    /// Every element of every picture stays on the stage.
    @Test func nothingLeavesTheStage() {
        let stage = CGRect(origin: .zero, size: Scene.stage)
        for (a, b) in MakeTenFixture.edges {
            let e = MakeTenFixture.explainer(a, b)
            for k in -1..<e.stepCount {
                for el in e.still(after: k).visible {
                    switch el.kind {
                    case let .shape(.ellipse(r), _), let .shape(.rect(r, _), _), let .hint(r, _), let .numberTag(_, r, _):
                        #expect(stage.contains(r), "\(a) + \(b) step \(k): \(el.id)")
                    default: break
                    }
                }
            }
        }
    }
}
