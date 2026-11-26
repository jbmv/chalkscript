import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

// Subtraction's do-it-with-me steps:
// break any ten, cross out the ones and the tens, touch each piece to count, tens first.

/// A line across a piece, from below its left edge to above its right edge, as a child crosses
/// out.
func across(_ r: CGRect) -> Mark {
    .stroke([CGPoint(x: r.minX - 6, y: r.maxY + 6), CGPoint(x: r.midX, y: r.midY), CGPoint(x: r.maxX + 6, y: r.minY - 6)])
}

func touch(_ r: CGRect) -> Mark { .tap(CGPoint(x: r.midX, y: r.midY)) }

struct SubtractionGuidedTests {
    func explainer(_ a: Int, _ b: Int) -> SubtractionExplainer {
        SubtractionExplainer(problem: try! SubtractionProblem(a, minus: b), version: .child, wording: Fixture.guidedWording())
    }

    func step(_ e: SubtractionExplainer, _ s: SubtractionProblem.Step) -> Int { e.steps.firstIndex(of: s)! }

    @Test func theDoableStepsAreTheMarksOnTheWorksheet() {
        let e = explainer(54, 26)
        #expect(e.guidedSteps.map(\.id) == ["show", "short", "trade", "takeOnes", "takeTens", "count"])
        #expect(e.guidedSteps.map(\.doable) == [false, false, true, true, true, true])
        #expect(e.guidedSteps.map(\.countsAloud) == [false, false, false, false, false, true])
    }

    /// The watched steps of the guided explainer are the paced explainer's, picture for picture.
    @Test func watchedStepsAreThePacedExplainers() {
        for (a, b) in Fixture.edges {
            let e = explainer(a, b)
            var s = e.start
            for k in 0..<e.stepCount {
                let (s1, motion) = e.watch(k, from: s)
                #expect(motion.script == e.script(for: k))
                for t in [0, 0.3, 0.9, motion.script.duration] {
                    #expect(motion.picture(t) == e.scene(step: k, at: t), "\(a) - \(b) step \(k) at \(t)")
                }
                #expect(e.picture(s1, marking: k) == e.still(after: k))
                s = s1
            }
        }
    }

    @Test func aLineThroughAnyWholeTenBreaksIt() {
        let e = explainer(54, 26)
        let k = step(e, .trade)
        var s = e.state(after: k - 1)
        #expect(e.instruction(k, s).display == "Break one ten.")
        // A touch, a line through a one, a line through nothing: kind lines, no change.
        let tap = e.read(touch(e.layout.tens[1]), step: k, s)
        #expect(tap.note == .miss(e.doLine(.tradeTapped)) && tap.state == s && !tap.finished)
        let one = e.read(across(e.layout.looseOnes[0]), step: k, s)
        #expect(one.note == .miss(e.doLine(.tradeOnOne)))
        let none = e.read(across(CGRect(x: 400, y: 450, width: 30, height: 30)), step: k, s)
        #expect(none.note == .miss(e.doLine(.tradeMissed)))
        // The second ten, not the last: whichever the child chooses.
        let r = e.read(across(e.layout.tens[1]), step: k, s)
        #expect(r.finished && r.keepsStroke && r.state.tradedTen == 1)
        s = r.state
        let end = e.picture(s, marking: k)
        guard case let .ink(points, op) = end.element("ten.1.cross")?.kind else { Issue.record("the child's line is not kept"); return }
        #expect(op == .trade && points.count == 3)
        guard case let .arrow(arrow, _, _) = end.element("arrow")?.kind else { Issue.record("no arrow"); return }
        #expect(arrow.first?.x == e.layout.tens[1].midX, "the arrow comes from the ten the child broke")
        #expect(end.summary.contains("tens=5/1/1;") && end.summary.contains("boxed=10/0/0;"))
        // Its ones travel into the box, and the line about them is said once they are there.
        guard let motion = r.motion, case let .say(line, true)? = motion.script.events.last?.action else {
            Issue.record("no motion or line"); return
        }
        #expect(line == e.doLine(.traded))
        #expect(motion.end == end)
    }

    /// A line down the ten at `a` that hooks at the bottom into the ten at `b`, 12 points past
    /// `b`'s near edge. Nine tens sit 33 apart (SubtractionLayout), 11 clear of each other, as
    /// small as the iPad mini draws them.
    func hook(_ e: SubtractionExplainer, down a: Int, into b: Int) -> [CGPoint] {
        let ta = e.layout.tens[a], tb = e.layout.tens[b]
        let endX = b < a ? tb.maxX - 12 : tb.minX + 12
        return [CGPoint(x: ta.midX, y: ta.minY), CGPoint(x: ta.midX + 4, y: ta.minY + 150), CGPoint(x: endX, y: ta.maxY)]
    }

    @Test func aLineThatGrazesANeighbouringTenBreaksTheOneItRunsThrough() {
        let e = explainer(94, 26)
        let k = step(e, .trade)
        let s = e.state(after: k - 1)
        #expect(e.layout.tens.count == 9 && e.layout.tens[1].minX - e.layout.tens[0].maxX < 12)
        // Down ten 3, hooking into ten 2: both cross, ten 3 by far the more.
        let points = hook(e, down: 3, into: 2)
        #expect(MarkGeometry.crosses(points, e.layout.tens[2]) && MarkGeometry.crosses(points, e.layout.tens[3]))
        let r = e.read(.stroke(points), step: k, s)
        #expect(r.finished && r.state.tradedTen == 3, "\(String(describing: r.state.tradedTen))")
        #expect(r.state.own[.ten(3)] == points && r.state.own[.ten(2)] == nil)
    }

    @Test func aGrazeBesideATenCrossedOutIsNotTaken() {
        let e = explainer(94, 26)
        let k = step(e, .takeTens)
        let s = e.state(after: k - 1)
        let broken = s.tradedTen!
        let whole = (0..<9).filter { $0 != broken }
        let a = whole[3], g = whole[2]
        // Down one ten and hooking into its lower neighbour: only the ten run through is crossed,
        // and the child's line is on it (this took the neighbour first, or both and a hint).
        let points = hook(e, down: a, into: g)
        #expect(MarkGeometry.crosses(points, e.layout.tens[g]) && g < a)
        let r = e.read(.stroke(points), step: k, s)
        #expect(r.state.tensGone == [a] && r.tally == Tally(1, of: 2) && !r.finished)
        #expect(r.state.own[.ten(a)] == points)
    }

    @Test func aLineDrawnThroughTwoPiecesTakesBothAndIsDrawnOnTheMoreCrossed() {
        let e = explainer(94, 26)
        let k = step(e, .takeTens)
        let s = e.state(after: k - 1)
        let whole = (0..<9).filter { $0 != s.tradedTen! }
        let a = whole[2], b = whole[3]
        // A line across the width of two tens side by side runs about as far in each.
        let ta = e.layout.tens[a], tb = e.layout.tens[b]
        let points = [CGPoint(x: ta.minX - 3, y: ta.midY + 10), CGPoint(x: tb.maxX + 3, y: ta.midY - 10)]
        #expect(MarkGeometry.crossed(points, among: [ta, tb]).count == 2)
        let r = e.read(.stroke(points), step: k, s)
        #expect(r.state.tensGone == [a, b] && r.finished)
        #expect(r.state.own[.ten(a)] == points && r.state.own[.ten(b)] == [])
    }

    @Test func crossingOutTakesAsManyAsAreLeftToTake() {
        let e = explainer(54, 26)
        let k = step(e, .takeOnes)
        var s = e.state(after: k - 1)  // the last ten broken by the watched steps
        let begin = e.begin(k, s)
        #expect(begin.tally == Tally(0, of: 6))
        // One line across two loose ones crosses both; the line is drawn on the one it runs through most (the second here).
        let pair = Mark.stroke([CGPoint(x: e.layout.looseOnes[0].minX - 4, y: e.layout.looseOnes[0].midY), CGPoint(x: e.layout.looseOnes[0].maxX + 4, y: e.layout.looseOnes[1].midY + 20), CGPoint(x: e.layout.looseOnes[1].maxX + 4, y: e.layout.looseOnes[1].midY)])
        let r = e.read(pair, step: k, s)
        #expect(Set(r.state.onesGone) == [.loose(0), .loose(1)] && r.tally == Tally(2, of: 6) && r.keepsStroke && !r.finished)
        #expect(r.state.own[.loose(1)]?.isEmpty == false && r.state.own[.loose(0)] == [])
        s = r.state
        // A ten is not a one; a touch is not a line.
        #expect(e.read(across(e.layout.tens[0]), step: k, s).note == .miss(e.doLine(.crossedTen)))
        #expect(e.read(touch(e.layout.looseOnes[2]), step: k, s).note == .miss(e.doLine(.crossTapped(ones: true))))
        // The box's ones count as ones.
        for i in 0..<3 {
            s = e.read(across(e.layout.boxedOnes[i]), step: k, s).state
        }
        #expect(s.onesGone.count == 5)
        // A line across more than are left is not taken: a hint, not a miss.
        let both = Mark.stroke([CGPoint(x: e.layout.boxedOnes[4].minX - 4, y: e.layout.boxedOnes[4].midY), CGPoint(x: e.layout.boxedOnes[5].maxX + 4, y: e.layout.boxedOnes[5].midY)])
        let tooMany = e.read(both, step: k, s)
        #expect(tooMany.note == .hint(e.doLine(.crossedTooMany(left: 1))) && tooMany.state == s && !tooMany.keepsStroke)
        let last = e.read(across(e.layout.looseOnes[3]), step: k, s)
        #expect(last.finished && last.tally == Tally(6, of: 6))
        guard case let .say(line, true)? = last.motion?.script.events.last?.action else { Issue.record("no line at the end"); return }
        #expect(line == e.doLine(.crossedOnes))
        // Three loose ones and three of the box's are ghosts; the one crossed by the line drawn on
        // another shows no line of its own.
        let summary = e.picture(last.state, marking: k).summary
        #expect(summary.contains("ones=4/3/2;") && summary.contains("boxed=10/3/3;"), "\(summary)")
    }

    @Test func crossingOutTensTakesWholeTensOnly() {
        let e = explainer(54, 26)
        let k = step(e, .takeTens)
        var s = e.state(after: k - 1)
        let broken = s.tradedTen!
        // The broken ten is not whole: a line across it crosses nothing it can.
        #expect(e.read(across(e.layout.tens[broken]), step: k, s).note == .miss(e.doLine(.crossMissed(ones: false))))
        #expect(e.read(across(e.layout.boxedOnes[9]), step: k, s).note == .miss(e.doLine(.crossedOne)))
        s = e.read(across(e.layout.tens[0]), step: k, s).state
        let r = e.read(across(e.layout.tens[2]), step: k, s)
        #expect(r.finished && r.state.tensGone == [0, 2])
    }

    @Test func countingIsTouchingEachPieceTensFirst() {
        let e = explainer(54, 26)
        let k = step(e, .count)
        let s0 = e.state(after: k - 1)
        let begin = e.begin(k, s0)
        #expect(begin.state.gathered && !begin.finished && begin.motion != nil, "what is left is gathered first")
        var s = begin.state
        let L = e.layout
        // A one before the tens: a kind line; a touch on nothing: nothing.
        #expect(e.read(touch(L.countOnes[0]), step: k, s).note == .miss(e.doLine(.tensFirst)))
        #expect(e.read(.tap(CGPoint(x: 10, y: 500)), step: k, s).note == nil)
        let first = e.read(touch(L.countTens[1]), step: k, s)
        #expect(first.interrupts, "a count said in answer to a tap cuts off the one before")
        guard case let .say(tick, false)? = first.motion?.script.events.first?.action else { Issue.record("no count said"); return }
        #expect(tick.display == "10")
        s = first.state
        #expect(e.read(touch(L.countTens[1]), step: k, s).state == s, "a piece counted once is not counted again")
        s = e.read(touch(L.countTens[0]), step: k, s).state
        #expect(e.picture(s, marking: k).summary.contains("total=20"))
        for i in 0..<7 { s = e.read(touch(L.countOnes[i]), step: k, s).state }
        #expect(e.picture(s, marking: k).summary.contains("total=20 + 7"))
        let last = e.read(touch(L.countOnes[7]), step: k, s)
        #expect(last.finished && last.state.answered)
        let said = last.motion!.script.events.compactMap { if case let .say(l, _) = $0.action { l.display } else { nil } }
        #expect(said == ["8", "20 plus 8 is 28.", "54 minus 26 is 28!"])
        #expect(e.picture(last.state, marking: k) == e.still(after: k), "the child's count ends where the watched one does")
    }

    @Test func nothingLeftToCountFinishesAtOnce() {
        let e = explainer(54, 54)
        let k = step(e, .count)
        let r = e.begin(k, e.state(after: k - 1))
        #expect(r.finished && r.state.answered)
    }

    /// EXP-3: do it with me and try one are other problems of the same kind, never the watched
    /// problem's numbers or answer, and different from each other.
    @Test func theOtherProblemsAreOfTheSameKind() {
        for p in SubtractionProblem.all where (21...98).contains(p.minuend) {
            let d = p.isomorph(1), t = p.isomorph(2)
            if d == p { continue }  // no other of its kind
            #expect(d.kind == p.kind && t.kind == p.kind, "\(p): \(d), \(t)")
            #expect(d.minuend != p.minuend && d.subtrahend != p.subtrahend && d.difference != p.difference, "\(p): \(d)")
            #expect(t.difference != p.difference, "\(p): \(t)")
        }
        let p = try! SubtractionProblem(54, minus: 26)
        let d = p.isomorph(1), t = p.isomorph(2)
        #expect(d.regroups && t.regroups && d != t && d.difference != t.difference)
        #expect(SubtractionExplainer.lesson(watching: p, wording: Fixture.guidedWording()).doWithMe.problem == d)
    }

    @Test func tryOneShowsTheProblemWithAnEmptyAnswer() {
        let e = explainer(41, 17)
        let t = e.tryOne
        #expect(t.line.display == "Now you try one: 41 minus 17.")
        guard case let .text(text, _, .problem)? = t.scene.element("try.problem")?.kind else { Issue.record("no problem"); return }
        #expect(text == "41 − 17 = ")
        #expect(t.scene.element("try.answer") != nil)
    }

    /// The whole do it with me on 54 − 26's own isomorph, through the player, the child making
    /// every mark.
    @Test @MainActor func theChildDoesEveryStepThroughThePlayer() {
        let voice = RecordingVoice()
        let lesson = SubtractionExplainer.lesson(watching: try! SubtractionProblem(54, minus: 26), wording: Fixture.guidedWording())
        let p = GuidedPlayer(lesson: lesson, voice: voice, labels: Fixture.guidedLabels, drivesItself: false)
        p.jump(to: .doWithMe)
        let e = lesson.doWithMe
        let L = e.layout
        #expect(p.caption.display == "Now let's do one together: \(e.problem.minuend) minus \(e.problem.subtrahend).")
        // Start: the first two steps are watched and run on into the child's.
        p.primary()
        p.settle(voice)
        // Break the first ten.
        #expect(p.phase == .doing(2) && p.readsMarks)
        p.mark(across(L.tens[0]))
        // Its line is said with the trade's picture, and after a beat the next step opens.
        p.settle(voice)
        #expect(p.scene.summary.contains("boxed=10/0/0;"))
        // Cross out the ones, one at a time.
        #expect(p.phase == .doing(3))
        var s = e.state(after: 2)
        s.tradedTen = 0
        for r in e.keptOnes(s).prefix(e.problem.subtrahendOnes) {
            p.mark(across(e.rect(r)))
        }
        p.settle(voice)
        // Cross out the tens.
        #expect(p.phase == .doing(4))
        for i in Array((1..<e.problem.minuendTens).prefix(e.problem.subtrahendTens)) { p.mark(across(L.tens[i])) }
        p.settle(voice)
        // Count: tens first, then ones.
        #expect(p.phase == .doing(5))
        for r in L.countTens + L.countOnes { p.mark(touch(r)) }
        p.settle(voice)
        #expect(p.phase == .paused(5))
        #expect(p.scene.summary.contains("total=\(e.problem.difference)"))
        #expect(p.caption.display == "\(e.problem.minuend) minus \(e.problem.subtrahend) is \(e.problem.difference)!")
        #expect(p.primaryControl == .tryOne)
        #expect(p.shownSteps.isEmpty)
    }
}
