import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

/// The subtraction template (EXP-2, EXP-5, EXP-11).
struct SubtractionProblemTests {
    @Test func theRangeIsTwoDigitMinusOneOrTwoDigit() {
        #expect(SubtractionProblem.accepts(10, minus: 1))
        #expect(SubtractionProblem.accepts(99, minus: 99))
        #expect(SubtractionProblem.accepts(44, minus: 5))
        #expect(SubtractionProblem.all.count == (10...99).reduce(0) { $0 + $1 })
    }

    /// The tens taken away as a number, which the lines say ("take away 20").
    @Test func theTensTakenAwayAsANumber() throws {
        #expect(try SubtractionProblem(54, minus: 26).subtrahendTensValue == 20)
        #expect(try SubtractionProblem(44, minus: 5).subtrahendTensValue == 0)
        #expect(try SubtractionProblem(99, minus: 99).subtrahendTensValue == 90)
    }

    @Test(arguments: [(9, 1), (100, 1), (0, 0), (-5, 1), (54, 0), (54, 55), (54, -1), (10, 11), (99, 100)])
    func valuesOutsideTheRangeAreRefused(a: Int, b: Int) {
        #expect(!SubtractionProblem.accepts(a, minus: b))
        #expect(throws: SubtractionProblem.RangeError.self) { try SubtractionProblem(a, minus: b) }
    }

    @Test func theRefusalSaysWhichNumber() {
        #expect(throws: SubtractionProblem.RangeError.minuend(9)) { try SubtractionProblem(9, minus: 1) }
        #expect(throws: SubtractionProblem.RangeError.subtrahend(55, minuend: 54)) { try SubtractionProblem(54, minus: 55) }
    }

    /// The steps depend on the values: no trade when none is needed (EXP-2).
    @Test func theStepsFollowTheValues() throws {
        typealias S = SubtractionProblem.Step
        func steps(_ a: Int, _ b: Int) throws -> [S] { try SubtractionProblem(a, minus: b).steps }
        #expect(try steps(54, 26) == [.show, .short, .trade, .takeOnes, .takeTens, .count])
        #expect(try steps(83, 12) == [.show, .enough, .takeOnes, .takeTens, .count])
        #expect(try steps(44, 5) == [.show, .short, .trade, .takeOnes, .count])
        #expect(try steps(50, 20) == [.show, .takeTens, .count])
        #expect(try steps(10, 1) == [.show, .short, .trade, .takeOnes, .count])
        #expect(try steps(99, 99) == [.show, .enough, .takeOnes, .takeTens, .count])
    }
}

@MainActor
struct SubtractionMotionTests {
    /// EXP-11 and EXP-2: for every problem in the range, every step's motion ends on exactly its
    /// still picture, and starts from the picture of the step before. Bar the mark, which the
    /// next step replaces, and two things that appear at once: the labels under
    /// the drawing as the number is first shown, and the copies of what is left, which appear
    /// over the pieces they copy and then travel to the count area.
    @Test func everyStepEndsOnItsStillPictureAndStartsFromTheLast() {
        for p in SubtractionProblem.all {
            let e = SubtractionExplainer(problem: p, version: .child, wording: Fixture.wording())
            for k in 0..<e.stepCount {
                let d = e.script(for: k).duration
                #expect(d > 0, "\(p) step \(k) has no motion")
                #expect(e.scene(step: k, at: d) == e.still(after: k), "\(p) step \(k) does not end on its still")
                let appears = e.steps[k] == .show ? "label." : e.steps[k] == .count ? "count." : "-"
                let before = unmarked(e.still(after: k - 1), except: appears)
                let start = unmarked(e.scene(step: k, at: 0), except: appears)
                if before != start {
                    Issue.record("\(p) step \(k) jumps at its start")
                    return
                }
            }
        }
    }

    /// EXP-2: every step at the range's edges plays, and every number shown is the model's.
    @Test(arguments: Fixture.edges) func everyStepPlaysAtTheEdges(a: Int, b: Int) {
        let e = Fixture.explainer(a, b)
        let p = e.problem
        let end = e.still(after: e.stepCount - 1)
        // The worksheet: every ten and one of the number taken from is drawn, and stays.
        #expect(end.visible.filter { $0.id.hasPrefix("ten.") && !$0.id.hasSuffix(".cross") }.count == p.minuendTens)
        #expect(end.visible.filter { $0.id.hasPrefix("one.") && !$0.id.hasSuffix(".cross") }.count == p.minuendOnes)
        // Ghosts: what was traded or taken away is crossed and faded, never removed (EXP-5).
        let ghosts = end.visible.filter { !$0.id.hasSuffix(".cross") && $0.opacity == Components.ghostOpacity }
        #expect(ghosts.count == p.subtrahendTens + (p.regroups ? 1 : 0) + p.subtrahendOnes, "\(p)")
        // The traded ten's ten ones are in the box.
        #expect(end.visible.filter { $0.id.hasPrefix("boxed.") && !$0.id.hasSuffix(".cross") }.count == (p.regroups ? 10 : 0))
        // What is left is in the count area, tens and ones, and the total and the answer are the difference.
        #expect(end.visible.filter { $0.id.hasPrefix("count.ten.") }.count == p.differenceTens)
        #expect(end.visible.filter { $0.id.hasPrefix("count.one.") }.count == p.differenceOnes)
        #expect(total(end) == String(p.difference))
        #expect(equation(end) == "\(a) − \(b) = \(p.difference)")
        #expect(equation(e.still(after: -1)) == "\(a) − \(b) = ?")
        // Inside the stage.
        for el in end.visible {
            switch el.kind {
            case let .ten(r, _), let .one(r, _):
                #expect(r.minX >= 0 && r.maxX <= Scene.stage.width && r.minY >= 0 && r.maxY <= Scene.stage.height, "\(p) \(el.id) at \(r)")
            default: break
            }
        }
        // Every step plays through in the player, and the counts are said in order.
        let voice = RecordingVoice()
        let player = ExplainerPlayer(explainer: e, voice: voice, drivesItself: false)
        for k in 0..<e.stepCount {
            player.primary()
            #expect(player.phase == .playing(k))
            player.playToPause(voice)
            #expect(player.phase == .paused(k))
        }
        let ticks = voice.said.filter { $0.key.contains(".tick(") }.map(\.display)
        #expect(ticks == SubtractionExplainer.counts(p).map(String.init))
        #expect(voice.said.last?.display == "\(a) minus \(b) is \(p.difference)!")
    }

    /// EXP-5: at most two things are marked at any moment of any step.
    @Test(arguments: Fixture.edges) func noMoreThanTwoThingsAreMarked(a: Int, b: Int) {
        let e = Fixture.explainer(a, b)
        for k in 0..<e.stepCount {
            let d = e.script(for: k).duration
            for i in 0...200 {
                let s = e.scene(step: k, at: d * Double(i) / 200)
                #expect(s.markedCount <= 2, "\(e.problem) step \(k) at \(d * Double(i) / 200)s marks \(s.markedCount)")
            }
            #expect(e.still(after: k).markedCount <= 2)
        }
    }

    /// 54 − 26, step by step (EXP-5).
    @Test func fiftyFourMinusTwentySix() {
        let e = Fixture.explainer(54, 26)
        let L = e.layout
        // show: the tens drop in one after another, then the ones grow in.
        let show = e.scene(step: 0, at: 0.1)
        #expect(show.element("ten.0")!.opacity > 0 && show.element("ten.0")!.opacity < 1)
        #expect(show.element("ten.1")!.opacity == 0)
        #expect(frame(show, "ten.0").minY < L.tens[0].minY, "a ten drops in from above")
        #expect(show.element("one.0")!.opacity == 0)
        // short: the ones digit of 26 is marked in the take-away colour while the ones are looked at.
        let short = e.still(after: 1)
        #expect(marked(short) == "6:subtract")
        // A dashed pencil loop is drawn round the ones, which stand still, and stays for
        // the step.
        let looking = e.scene(step: 1, at: 0.4)
        #expect(frame(looking, "one.0") == L.looseOnes[0], "the ones do not move")
        guard case let .hint(ring, drawn) = looking.element("hint")?.kind else { Issue.record("no loop"); return }
        #expect(drawn > 0 && drawn < 1 && ring.contains(L.looseOnes[3]))
        guard case .hint(_, 1) = short.element("hint")?.kind else { Issue.record("the loop does not stay"); return }
        // trade: the arrow is drawn first, from the last ten to the box.
        let traded = 4
        let arrowPoints = Components.tradeArrow(from: L.tens[traded], to: L.box, y: L.arrowY)
        let early = e.scene(step: 2, at: 0.35)
        guard case let .arrow(points, p0, op) = early.element("arrow")!.kind else { Issue.record("no arrow"); return }
        #expect(points == arrowPoints && p0 > 0 && p0 < 1 && op == .trade)
        #expect(early.element("boxed.0")!.opacity == 0, "the ones appear only once the arrow is drawn")
        // The ten splits into ten ones over itself, then fades to a ghost and is crossed out.
        let times = e.tradeTimes
        let split = e.scene(step: 2, at: times.fade)
        for i in 0..<10 {
            let r = frame(split, "boxed.\(i)")
            #expect(L.tens[traded].contains(CGPoint(x: r.midX, y: r.midY)), "one \(i) is over the ten")
        }
        let crossed = e.scene(step: 2, at: times.travel)
        #expect(crossed.element("ten.4")!.opacity == Components.ghostOpacity)
        #expect(crossProgress(crossed, "ten.4.cross") == 1)
        // Each one follows the arrow: up to it, along it over the box, and down into place.
        for i in [0, 4, 9] {
            let start = times.travelStart(i)
            let top = L.arrowY - 12
            let path = (0...3000).map { frame(e.scene(step: 2, at: start + e.sec(.trade, .travel) * Double($0) / 3000), "boxed.\(i)") }
            #expect(path.contains { abs($0.minY - top) < 1 && abs($0.minX - (L.tens[traded].minX + 1)) < 1 }, "one \(i) rises to the arrow")
            #expect(path.contains { abs($0.midX - L.box.midX) < 1 && abs($0.minY - top) < 1 }, "one \(i) crosses along the arrow")
            #expect(path.allSatisfy { $0.minY >= top - 0.001 }, "one \(i) never goes above the arrow")
            #expect(path.last == L.boxedOnes[i], "one \(i) ends in its place in the box")
        }
        // They go one after another, the last first.
        #expect(times.travelStart(9) < times.travelStart(0))
        // The box is drawn round them once they are in.
        #expect(crossProgress(e.scene(step: 2, at: times.box - 0.01), "box") == 0)
        let afterTrade = e.still(after: 2)
        #expect(crossProgress(afterTrade, "box") == 1)
        #expect(marked(afterTrade) == "", "nothing in the problem is marked during the trade")
        // takeOnes: the loose ones go first, then six from the box: 4 loose and 2 boxed.
        let ones = e.still(after: 3)
        #expect(marked(ones) == "6:subtract")
        #expect((0..<4).allSatisfy { ones.element("one.\($0)")!.opacity == Components.ghostOpacity })
        #expect((0..<2).allSatisfy { ones.element("boxed.\($0)")!.opacity == Components.ghostOpacity })
        #expect((2..<10).allSatisfy { ones.element("boxed.\($0)")!.opacity == 1 })
        // One at a time: the second cross starts after the first is drawn.
        let mid = e.scene(step: 3, at: 0.3)
        #expect(crossProgress(mid, "one.0.cross") == 1 && crossProgress(mid, "one.1.cross") == 0)
        // takeTens: the tens digit is marked; the last two whole tens are crossed.
        let tens = e.still(after: 4)
        #expect(marked(tens) == "2:subtract")
        #expect(tens.element("ten.2")!.opacity == Components.ghostOpacity && tens.element("ten.3")!.opacity == Components.ghostOpacity)
        #expect(tens.element("ten.0")!.opacity == 1 && tens.element("ten.1")!.opacity == 1)
        // count: what is left is copied over, from where it stands.
        let copying = e.scene(step: 5, at: 0)
        #expect(frame(copying, "count.ten.0").origin == L.tens[0].origin)
        #expect(frame(copying, "count.one.0").origin == L.boxedOnes[2].origin)
        // Counted tens first, then ones, the total "20 + 8" until it becomes 28.
        let t = e.countTimes
        #expect(t.ticks.count == 10)
        #expect(total(e.scene(step: 5, at: t.ticks[0] + 0.01)) == "10")
        #expect(total(e.scene(step: 5, at: t.ticks[1] + 0.01)) == "20")
        #expect(total(e.scene(step: 5, at: t.ticks[2] + 0.01)) == "20 + 1")
        #expect(total(e.scene(step: 5, at: t.ticks[9] + 0.01)) == "20 + 8")
        #expect(total(e.scene(step: 5, at: t.join! + 0.01)) == "28")
        // Each piece arrives in pencil, shows its count on itself (a tag centred on the piece), then keeps the counted style.
        #expect(style(copying, "count.ten.0") == .pencil && style(copying, "count.one.7") == .pencil)
        let first = e.scene(step: 5, at: t.ticks[1] + 0.1)
        #expect(tag(first) == ["tag.ten.1:20"])
        #expect(style(first, "count.ten.0") == .counted && style(first, "count.ten.1") == .counted && style(first, "count.one.0") == .pencil)
        if case let .numberTag(_, r, _) = first.element("tag.ten.1")!.kind {
            #expect(abs(r.midX - frame(first, "count.ten.1").midX) < 0.001 && abs(r.midY - frame(first, "count.ten.1").midY) < 0.001)
        }
        let oneTag = e.scene(step: 5, at: t.ticks[3] + 0.1)
        if case let .numberTag(text, r, _) = oneTag.element("tag.one.1")!.kind {
            #expect(text == "2" && abs(r.midY - frame(oneTag, "count.one.1").midY) < 0.001 && r.width == Components.oneTagSize.width)
        }
        #expect(tag(e.scene(step: 5, at: t.ticks[3] + 0.1)) == ["tag.one.1:2"], "a count shows only while its piece is counted")
        #expect(e.scene(step: 5, at: t.ticks[3] + 0.1).visible.allSatisfy { if case .count = $0.kind { false } else { true } }, "no floating count")
        #expect((0..<8).allSatisfy { style(e.still(after: 5), "count.one.\($0)") == .counted })
        #expect(equation(e.scene(step: 5, at: t.join! + 0.01)) == "54 − 26 = ?", "the answer comes after the total")
        #expect(equation(e.still(after: 5)) == "54 − 26 = 28")
    }

    /// 83 − 12 (no trade) and 44 − 5 (a one-digit number taken away).
    @Test func eightyThreeMinusTwelveAndFortyFourMinusFive() {
        let a = Fixture.explainer(83, 12)
        #expect(a.problem.regroups == false)
        #expect(a.still(after: 4).element("arrow") == nil, "no trade, so no arrow or box")
        #expect(marked(a.still(after: 1)) == "2:subtract")
        #expect(marked(a.still(after: 3)) == "1:subtract")
        #expect(total(a.still(after: 4)) == "71")

        let b = Fixture.explainer(44, 5)
        #expect(equation(b.still(after: -1)) == "44 − 5 = ?")
        #expect(marked(b.still(after: 3)) == "5:subtract")
        #expect(b.still(after: 3).elements("ten.").filter { !$0.id.hasSuffix(".cross") && $0.opacity == Components.ghostOpacity }.count == 1)
        let t = b.countTimes
        #expect(total(b.scene(step: 4, at: t.ticks.last! + 0.01)) == "30 + 9")
    }

    /// EXP-10: each count is said at its piece, and waits for the one before it.
    @Test func eachCountWaitsForTheOneBefore() {
        let e = Fixture.explainer(54, 26)
        let script = e.script(for: 5)
        let says = script.events.compactMap { ev -> (Double, String)? in
            if case let .say(line, _) = ev.action { return (ev.time, line.display) }
            return nil
        }
        #expect(says.map(\.1) == ["Let's count what's left.", "10", "20", "1", "2", "3", "4", "5", "6", "7", "8",
            "20 plus 8 is 28.", "54 minus 26 is 28!"])
        for (i, ev) in script.events.enumerated() {
            guard case let .say(line, _) = ev.action, line.display != "Let's count what's left." else { continue }
            guard case .waitForVoice = script.events[i - 1].action else {
                Issue.record("'\(line.display)' does not wait for the line before it")
                continue
            }
        }
        // The parent version shows the counts and says only the step's line, the total and the answer.
        let parent = Fixture.explainer(54, 26, .parent).script(for: 5)
        #expect(parent.events.filter { if case .say = $0.action { true } else { false } }.count == 3)
    }

    /// The parent's count, at every edge of the range, takes at most half the learner's
    /// time, from the first copy to the answer, and every gap between counts is at most half the
    /// learner's; it still ends on its still picture and starts from the step before (EXP-11).
    @Test(arguments: Fixture.edges) func theParentsCountIsAtLeastTwiceAsFast(a: Int, b: Int) {
        let child = Fixture.explainer(a, b, .child)
        let parent = Fixture.explainer(a, b, .parent)
        let k = child.stepCount - 1
        let (c, p) = (child.countTimes, parent.countTimes)
        #expect(p.end <= c.end / 2)
        #expect(parent.script(for: k).duration <= child.script(for: k).duration / 2)
        for (pg, cg) in zip(zip(p.ticks, p.ticks.dropFirst()).map { $1 - $0 }, zip(c.ticks, c.ticks.dropFirst()).map { $1 - $0 }) {
            #expect(pg <= cg / 2 + 1e-9)
        }
        let d = parent.script(for: k).duration
        #expect(parent.scene(step: k, at: d) == parent.still(after: k))
        // The parent's script never waits on a count: only the total and the answer wait.
        let waits = parent.script(for: k).events.filter { $0.action == .waitForVoice }.count
        #expect(waits == (c.join == nil ? 2 : 3))
    }

    @Test func theCountAreaFitsTheWidestDifference() {
        // 98 − 20 leaves 7 tens and 8 ones; tens 40 apart run past the stage there.
        for (a, b) in [(98, 20), (99, 10), (89, 0 + 10), (99, 1)] {
            let L = SubtractionLayout(try! SubtractionProblem(a, minus: b))
            let right = max(L.countTens.last?.maxX ?? 0, L.countOnes.map(\.maxX).max() ?? 0)
            #expect(right <= SubtractionLayout.countRight, "\(a) - \(b) reaches \(right)")
            if let lastTen = L.countTens.last, let firstOne = L.countOnes.first {
                #expect(firstOne.minX > lastTen.maxX, "the ones stand clear of the tens")
            }
        }
        // Where it fits, the tens are 40 apart.
        let L = SubtractionLayout(try! SubtractionProblem(54, minus: 26))
        #expect(L.countTens.map(\.minX) == [660, 700])
        #expect(L.countOnes.first?.minX == 754)
    }

    // MARK: reading a scene

    private func unmarked(_ s: Scene, except prefix: String) -> Scene {
        var s = s
        for i in s.elements.indices {
            if case var .equation(eq) = s.elements[i].kind {
                eq.mark = nil
                s.elements[i].kind = .equation(eq)
            }
        }
        // The loop round the ones is a mark too: it stays only for its step.
        return Scene(elements: s.visible.filter { !$0.id.hasPrefix(prefix) && $0.id != "hint" })
    }

    private func frame(_ s: Scene, _ id: String) -> CGRect {
        switch s.element(id)?.kind {
        case let .ten(r, _), let .one(r, _): r
        default: .null
        }
    }

    private func crossProgress(_ s: Scene, _ id: String) -> Double {
        switch s.element(id)?.kind {
        case let .crossOut(_, _, p), let .box(_, p, _), let .arrow(_, p, _): p
        default: -1
        }
    }

    private func equation(_ s: Scene) -> String {
        guard case let .equation(eq) = s.element("equation")?.kind else { return "" }
        return eq.text
    }

    private func marked(_ s: Scene) -> String {
        guard case let .equation(eq) = s.element("equation")?.kind, let m = eq.mark, m.progress > 0 else { return "" }
        return "\(eq.runs[m.run].text):\(m.op.rawValue)"
    }

    private func total(_ s: Scene) -> String? {
        guard let e = s.element("total"), e.isVisible, case let .total(text, _, _) = e.kind else { return nil }
        return text
    }

    private func tag(_ s: Scene) -> [String] {
        s.visible.compactMap { if case let .numberTag(text, _, _) = $0.kind { "\($0.id):\(text)" } else { nil } }
    }

    private func style(_ s: Scene, _ id: String) -> PieceStyle? {
        switch s.element(id)?.kind {
        case let .ten(_, st), let .one(_, st): st
        default: nil
        }
    }
}
