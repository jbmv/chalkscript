import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

// Two-digit addition: the ones added and
// counted on, bundled into a new ten with a loop round any ten ones, then the tens, then the
// count; watch, do it with me and try one.

/// Synthetic wording for the addition tests, shaped like the consuming app's entries (keys
/// under explain.add.). The app's own tests check the real entries.
enum AdditionFixture {
    static func wording() -> AdditionWording {
        AdditionWording(
            line: { l, p in
                let display: String =
                    switch l {
                    case .intro: "\(p.first) plus \(p.second). Let's see how!"
                    case .show: "This is \(p.first)."
                    case .addOnes: "Add \(p.secondOnes) ones."
                    case .check: p.regroups ? "We have \(p.onesTotal) ones. Ten ones make a ten!" : "We have \(p.onesTotal) ones."
                    case .bundle: "Put ten ones together. \(p.onesLeftOver) left over."
                    case .addTens: "Now add \(p.secondTens) tens."
                    case .count: "Let's count them all."
                    case let .tick(n): "\(n)"
                    case .join: "\(p.sumTens * 10) plus \(p.sumOnes) is \(p.sum)."
                    case .answer: "\(p.first) plus \(p.second) is \(p.sum)!"
                    }
                return Line(
                    key: "explain.test.add.\(l)", display: display, spoken: NumberWords.replacingNumerals(in: display),
                    emphasis: l == .answer ? String(p.sum) : nil)
            },
            doLine: { l, p in
                let display: String =
                    switch l {
                    case .intro: "Now let's do one together: \(p.first) plus \(p.second)."
                    case .addOnes: "Add \(p.secondOnes) ones: touch the ones side."
                    case .bundle: "Draw a loop around ten ones."
                    case .addTens: "Now add \(p.secondTens) tens: touch the tens side."
                    case .count: "Touch each piece, tens first."
                    case .addedOnes: "Now we have \(p.onesTotal) ones."
                    case .bundled: "Now we have \(p.firstTens + 1) tens and \(p.onesLeftOver) ones."
                    case .addedTens: "Now we have \(p.sumTens) tens."
                    case .onesOnTensSide: "That's the tens side."
                    case .tensOnOnesSide: "That's the ones side."
                    case .loopMissed: "Draw a loop all the way around ten ones."
                    case let .loopHas(n): "That loop has \(n)."
                    case .tensFirst: "Tens first."
                    case .tryIntro: "Now you try one: \(p.first) plus \(p.second)."
                    case .tryNote: "Your turn."
                    }
                return Line(key: "explain.test.add.do.\(l)", display: display, spoken: NumberWords.replacingNumerals(in: display))
            },
            tensLabel: "tens", onesLabel: "ones", unknown: "?",
            equation: "\(EquationSlot.first) + \(EquationSlot.second) = \(EquationSlot.answer)",
            runningTotal: { "\($0) + \($1)" })
    }

    static func explainer(_ a: Int, _ b: Int, doing: Bool = false) -> AdditionExplainer {
        AdditionExplainer(problem: try! AdditionProblem(a, plus: b), wording: wording(), doing: doing)
    }

    /// The range's edges and one other problem (EXP-2): smallest and largest, with and
    /// without a new ten, exactly ten ones, the most ones, ones or tens only added, a round first
    /// number, a round total, and the total 99.
    static let edges: [(Int, Int)] = [
        (10, 1), (10, 89), (11, 9), (19, 1), (19, 9), (20, 20), (38, 25), (38, 5), (38, 20), (31, 5), (45, 45),
        (49, 49), (50, 49), (55, 5), (61, 9), (89, 10), (90, 9), (91, 8), (98, 1), (79, 19), (10, 80),
    ]
}

/// A loop round `rect`, grown by 6, as a child draws one: round and back to where it began.
func loop(around rect: CGRect) -> Mark {
    let r = rect.insetBy(dx: -6, dy: -6)
    return .stroke([
        CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY),
        CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX + 4, y: r.minY),
    ])
}

struct AdditionTests {
    func step(_ e: AdditionExplainer, _ s: AdditionProblem.Step) -> Int { e.steps.firstIndex(of: s)! }

    // MARK: the template (EXP-2)

    @Test func theRangeIsTheTemplates() {
        #expect(AdditionProblem.accepts(10, plus: 1) && AdditionProblem.accepts(98, plus: 1) && AdditionProblem.accepts(10, plus: 89))
        #expect(!AdditionProblem.accepts(9, plus: 1), "the first number is two-digit")
        #expect(!AdditionProblem.accepts(99, plus: 0) && !AdditionProblem.accepts(99, plus: 1))
        #expect(!AdditionProblem.accepts(50, plus: 50), "the total stays under 100")
        #expect(!AdditionProblem.accepts(38, plus: 0))
        #expect(throws: AdditionProblem.RangeError.second(62, first: 38)) { try AdditionProblem(38, plus: 62) }
        #expect(AdditionProblem.all.count == (1...89).reduce(0, +))
    }

    @Test func theStepsDependOnTheValues() {
        func ids(_ a: Int, _ b: Int, doing: Bool = false) -> [String] { AdditionFixture.explainer(a, b, doing: doing).steps.map(\.rawValue) }
        #expect(ids(38, 25) == ["show", "addOnes", "check", "bundle", "addTens", "count"])
        // Do it with me has no separate check step.
        #expect(ids(38, 25, doing: true) == ["show", "addOnes", "bundle", "addTens", "count"])
        #expect(ids(31, 25) == ["show", "addOnes", "check", "addTens", "count"], "no bundle with fewer than ten ones")
        #expect(ids(38, 5) == ["show", "addOnes", "check", "bundle", "count"], "no tens step when no tens are added")
        #expect(ids(38, 20) == ["show", "addTens", "count"], "no ones step when no ones are added")
        #expect(ids(45, 45) == ["show", "addOnes", "check", "bundle", "addTens", "count"], "exactly ten ones make a ten")
    }

    @Test func theDoableStepsAreTheMarksOnTheWorksheet() {
        let e = AdditionFixture.explainer(38, 25, doing: true)
        #expect(e.guidedSteps.map(\.doable) == [false, true, true, true, true])
        #expect(e.guidedSteps.map(\.countsAloud) == [false, true, false, false, true], "the ones are counted on, then all are counted")
    }

    // MARK: the watched steps

    /// Every step of every edge plays to its still picture; the guided explainer's watched steps
    /// are the paced explainer's; nothing marks more than three things (EXP-5) or leaves the stage.
    @Test func everyStepPlaysToItsStillPicture() {
        let stage = CGRect(origin: .zero, size: Scene.stage)
        for (a, b) in AdditionFixture.edges {
            for doing in [false, true] {
                let e = AdditionFixture.explainer(a, b, doing: doing)
                var s = e.start
                for k in 0..<e.stepCount {
                    let (s1, motion) = e.watch(k, from: s)
                    #expect(motion.script == e.script(for: k))
                    #expect(motion.end == e.still(after: k), "\(a) + \(b) step \(k)")
                    #expect(e.picture(s1, marking: k) == e.still(after: k))
                    let d = motion.script.duration
                    for t in stride(from: 0, through: d, by: max(0.05, d / 40)) {
                        let scene = motion.picture(t)
                        #expect(scene == e.scene(step: k, at: t))
                        #expect(scene.markedCount <= 3, "\(a) + \(b) step \(k) at \(t)")
                        for el in scene.visible {
                            switch el.kind {
                            case let .ten(r, _), let .one(r, _):
                                #expect(stage.contains(r), "\(a) + \(b) step \(k) at \(t): \(el.id) at \(r)")
                            default: break
                            }
                        }
                    }
                    s = s1
                }
            }
        }
    }

    @Test func theOnesAreCountedOnAsTheyArrive() {
        let e = AdditionFixture.explainer(38, 25)
        let script = e.script(for: step(e, .addOnes))
        let said = script.events.compactMap { ev -> String? in
            if case let .say(line, _) = ev.action { return line.display }
            return nil
        }
        #expect(said == ["Add 5 ones.", "9", "10", "11", "12", "13"])
        // The digit acted on is the number added's ones, in the add colour (EXP-5, EXP-6).
        let mid = e.scene(step: step(e, .addOnes), at: 1)
        guard case let .equation(eq) = mid.element("equation")?.kind, let mark = eq.mark else { Issue.record("no mark"); return }
        #expect(eq.runs[mark.run].text == "5" && mark.op == .add)
        #expect(eq.text == "38 + 25 = ?")
    }

    @Test func checkLoopsTheOnesAndBundleMakesANewTen() {
        let e = AdditionFixture.explainer(38, 25)
        let check = e.still(after: step(e, .check))
        guard case let .hint(ring, p)? = check.element("hint")?.kind else { Issue.record("no loop round the ones"); return }
        #expect(p == 1 && e.layout.ones.allSatisfy { ring.contains($0) })
        let bundled = e.still(after: step(e, .bundle))
        // Ten ones stay as ghosts; the new ten stands after the first number's tens, in the trade
        // colour; the box and the arrow stay (EXP-5).
        let ghosts = bundled.elements("one.").filter { abs($0.opacity - Components.ghostOpacity) < 0.001 }
        #expect(ghosts.map(\.id) == (0..<10).map { "one.\($0)" })
        guard case let .ten(_, style)? = bundled.element("ten.3")?.kind else { Issue.record("no new ten"); return }
        #expect(style == .traded && bundled.element("ten.3")?.opacity == 1)
        #expect(bundled.summary.contains("arrow=1;box=1;"), "\(bundled.summary)")
        #expect(bundled.element("hint").map { !$0.isVisible } ?? true, "the loop round the ones stays only for its step")
        // The box round the first ten ones never touches the ones left over.
        for (a, b) in AdditionFixture.edges where (try! AdditionProblem(a, plus: b)).regroups {
            let l = AdditionFixture.explainer(a, b).layout
            #expect(l.ones.dropFirst(10).allSatisfy { !$0.intersects(l.box.insetBy(dx: -4, dy: -4)) }, "\(a) + \(b)")
            #expect(l.ones.prefix(10).allSatisfy { l.box.contains($0) })
        }
    }

    @Test func theCountIsTensFirstAndTheTotalIsWorked() {
        let e = AdditionFixture.explainer(38, 25)
        let k = step(e, .count)
        let said = e.script(for: k).events.compactMap { ev -> String? in
            if case let .say(line, _) = ev.action { return line.display }
            return nil
        }
        #expect(said == ["Let's count them all.", "10", "20", "30", "40", "50", "60", "1", "2", "3", "60 plus 3 is 63.", "38 plus 25 is 63!"])
        let end = e.still(after: k)
        #expect(end.summary.hasSuffix("equation=38 + 25 = 63;mark=;total=63"), "\(end.summary)")
        guard case let .text(worked, _, _)? = end.element("worked")?.kind else { Issue.record("no worked total"); return }
        #expect(worked == "60 + 3" && end.element("worked")?.opacity == 1)
        // Every piece standing is counted; the ten ones bundled are not.
        let counted = end.visible.filter {
            switch $0.kind {
            case .ten(_, .counted), .one(_, .counted): true
            default: false
            }
        }
        #expect(counted.count == 9)
        // Midway, a piece shows its count on itself and the total runs "60 + 1".
        let times = e.countTimes
        let mid = e.scene(step: k, at: times.ticks[6] + 0.3)
        #expect(mid.summary.hasSuffix("total=60 + 1"), "\(mid.summary)")
        guard case let .numberTag(text, rect, _)? = mid.element("tag.6")?.kind else { Issue.record("no tag"); return }
        #expect(text == "1" && rect.midX == e.layout.ones[10].midX)
        // A round total has no worked form.
        let round = AdditionFixture.explainer(45, 45)
        #expect(round.still(after: round.stepCount - 1).element("worked")?.isVisible == false)
    }

    // MARK: do it with me (EXP-14)

    @Test func touchesOnTheOnesSideDrawTheOnes() {
        let e = AdditionFixture.explainer(38, 25, doing: true)
        let k = step(e, .addOnes)
        var s = e.state(after: k - 1)
        #expect(e.instruction(k, s).display == "Add 5 ones: touch the ones side.")
        #expect(e.begin(k, s).tally == Tally(0, of: 5, op: .add))
        // The tens side: a kind line saying where ones go; off the drawing: nothing.
        let wrong = e.read(.tap(CGPoint(x: 100, y: 250)), step: k, s)
        #expect(wrong.note == .miss(e.doLine(.onesOnTensSide)) && wrong.state == s)
        #expect(e.read(.tap(CGPoint(x: 800, y: 250)), step: k, s).note == nil)
        for n in 1...5 {
            let r = e.read(.tap(CGPoint(x: 520, y: 200 + CGFloat(n) * 10)), step: k, s)
            #expect(r.state.addedOnes == n && r.tally == Tally(n, of: 5, op: .add) && r.interrupts && r.finished == (n == 5))
            guard case let .say(tick, false)? = r.motion?.script.events.first?.action else { Issue.record("no count"); return }
            #expect(tick.display == String(8 + n), "counting on from the ones already there")
            if n == 5 {
                // The loop goes round all the ones, and how many there are is said.
                guard let motion = r.motion, case let .say(line, true)? = motion.script.events.last?.action else { Issue.record("no line"); return }
                #expect(line == e.doLine(.addedOnes))
                #expect(motion.end == e.picture(r.state, marking: k))
                #expect(motion.end.element("hint").map { $0.isVisible } == true)
            }
            s = r.state
        }
        #expect(e.picture(s, marking: k).summary.contains("ones=13/0/0;"))
    }

    @Test func aLoopRoundAnyTenOnesBundlesThem() throws {
        // 39 + 29: eighteen ones, in four columns.
        let e = AdditionFixture.explainer(39, 29, doing: true)
        let k = step(e, .bundle)
        let s = e.state(after: k - 1)
        let L = e.layout
        #expect(e.read(.tap(CGPoint(x: 420, y: 200)), step: k, s).note == .miss(e.doLine(.loopMissed)))
        #expect(e.read(loop(around: CGRect(x: 600, y: 440, width: 40, height: 40)), step: k, s).note == .miss(e.doLine(.loopMissed)))
        // The first column only: five.
        let five = e.read(loop(around: L.ones[0].union(L.ones[4])), step: k, s)
        #expect(five.note == .miss(e.doLine(.loopHas(5))) && !five.keepsStroke && five.state == s)
        // The second and third columns: ten ones that are not the first ten.
        let r = e.read(loop(around: L.ones[5].union(L.ones[14])), step: k, s)
        #expect(r.finished && r.keepsStroke && r.state.bundled == Array(5...14) && r.state.newTen)
        let end = e.picture(r.state, marking: k)
        #expect(end.element("box")?.isVisible == false, "the child's loop stands in place of the box")
        guard case let .ink(points, op)? = end.element("loop")?.kind else { Issue.record("the child's loop is not kept"); return }
        #expect(op == .trade && points.count == 6)
        guard case let .arrow(arrow, 1, .trade)? = end.element("arrow")?.kind else { Issue.record("no arrow"); return }
        #expect(abs(arrow[0].x - L.ones[5].union(L.ones[14]).midX) < 0.001, "the arrow starts at the child's loop")
        guard let motion = r.motion, case let .say(line, true)? = motion.script.events.last?.action else { Issue.record("no line"); return }
        #expect(line == e.doLine(.bundled) && motion.end == end)
        // Midway the copies travel; the ones looped fade to ghosts; then the count skips them.
        let mid = motion.picture(1.6)
        #expect(mid.elements("bundle.").filter(\.isVisible).count == 10)
        let order = e.countOrder(r.state)
        #expect(order.suffix(8) == [0, 1, 2, 3, 4, 15, 16, 17].map(AdditionPiece.one))
    }

    @Test func touchesOnTheTensSideDrawTheTens() {
        let e = AdditionFixture.explainer(38, 25, doing: true)
        let k = step(e, .addTens)
        var s = e.state(after: k - 1)
        #expect(e.read(.tap(CGPoint(x: 450, y: 250)), step: k, s).note == .miss(e.doLine(.tensOnOnesSide)))
        let first = e.read(.tap(CGPoint(x: 200, y: 250)), step: k, s)
        #expect(!first.interrupts && first.motion?.script.events.isEmpty == true, "tens are drawn without a count")
        s = first.state
        let last = e.read(.tap(CGPoint(x: 250, y: 300)), step: k, s)
        #expect(last.finished && last.state.addedTens == 2)
        guard case let .say(line, true)? = last.motion?.script.events.last?.action else { Issue.record("no line"); return }
        #expect(line == e.doLine(.addedTens))
        #expect(e.picture(last.state, marking: k).summary.hasPrefix("tens=6/0/0;"))
    }

    @Test func countingIsTouchingEachPieceTensFirst() {
        let e = AdditionFixture.explainer(38, 25, doing: true)
        let k = step(e, .count)
        var s = e.state(after: k - 1)
        let order = e.countOrder(s)
        #expect(order.count == 9)
        #expect(e.read(touch(e.rect(order[7])), step: k, s).note == .miss(e.doLine(.tensFirst)))
        #expect(e.read(.tap(CGPoint(x: 900, y: 500)), step: k, s).note == nil)
        // Any ten first: the third touched shows 30.
        for (n, i) in [5, 0, 3, 1, 2, 4].enumerated() {
            let r = e.read(touch(e.rect(order[i])), step: k, s)
            guard case let .say(tick, false)? = r.motion?.script.events.first?.action else { Issue.record("no count"); return }
            #expect(tick.display == String((n + 1) * 10) && r.interrupts)
            s = r.state
        }
        #expect(e.read(touch(e.rect(order[5])), step: k, s).note == nil, "a piece counted is not counted again")
        for i in 6...7 { s = e.read(touch(e.rect(order[i])), step: k, s).state }
        #expect(e.picture(s, marking: k).summary.hasSuffix("total=60 + 2"))
        let last = e.read(touch(e.rect(order[8])), step: k, s)
        #expect(last.finished && last.state.answered)
        let lines = last.motion?.script.events.compactMap { ev -> String? in
            if case let .say(line, _) = ev.action { return line.display }
            return nil
        }
        #expect(lines == ["3", "60 plus 3 is 63.", "38 plus 25 is 63!"])
        #expect(last.motion?.end == e.picture(last.state, marking: k))
    }

    // MARK: the three problems (EXP-3)

    @Test func theOtherProblemsAreOfTheSameKind() {
        for (a, b) in AdditionFixture.edges {
            let p = try! AdditionProblem(a, plus: b)
            let one = p.isomorph(1), two = p.isomorph(2)
            for q in [one, two] where q != p {
                #expect(q.kind == p.kind && q.first != p.first && q.second != p.second && q.sum != p.sum, "\(p) -> \(q)")
                #expect(abs(q.firstTens - p.firstTens) <= 2 && abs(q.secondTens - p.secondTens) <= 2)
            }
            #expect(one == p.isomorph(1), "the pick is fixed for a problem")
            if one != p && two != one { #expect(two.sum != one.sum && two.first != one.first) }
        }
        let lesson = AdditionExplainer.lesson(watching: try! AdditionProblem(38, plus: 25), wording: AdditionFixture.wording())
        #expect(!lesson.watch.doing && lesson.doWithMe.doing && !lesson.tryOne.doing)
        #expect(lesson.doWithMe.problem.regroups && lesson.tryOne.problem.regroups)
    }

    @Test func tryOneShowsTheProblemToTry() {
        let e = AdditionFixture.explainer(47, 36)
        let t = e.tryOne
        #expect(t.line.display == "Now you try one: 47 plus 36.")
        guard case let .text(text, _, .problem)? = t.scene.element("try.problem")?.kind else { Issue.record("no problem"); return }
        #expect(text == "47 + 36 = ")
        #expect(t.scene.element("try.answer") != nil && t.scene.element("try.note") != nil)
    }

    // MARK: in the player

    /// The child version plays through: watch, do it with me with every step the child's, and
    /// try one.
    @MainActor @Test func theChildVersionPlaysThrough() {
        let lesson = AdditionExplainer.lesson(watching: try! AdditionProblem(38, plus: 25), wording: AdditionFixture.wording())
        let voice = RecordingVoice()
        let player = GuidedPlayer(lesson: lesson, voice: voice, labels: Fixture.guidedLabels, drivesItself: false)
        var guardCount = 0
        while player.part == .watch && guardCount < 20 {
            player.primary()
            player.settle(voice)
            guardCount += 1
        }
        #expect(player.part == .doWithMe && player.phase == .ready)
        #expect(voice.said.contains { $0.display == "38 plus 25 is 63!" })
        let e = lesson.doWithMe
        #expect(player.doSet == Set([1, 2, 3, 4]))
        // Step 0 is watched and runs on into the child's first step.
        player.primary()
        player.settle(voice)
        // Add the ones.
        #expect(player.phase == .doing(1) && player.readsMarks)
        for _ in 0..<e.problem.secondOnes {
            player.mark(.tap(CGPoint(x: 540, y: 260)))
            player.settle(voice)
        }
        // Loop the first ten ones.
        #expect(player.phase == .doing(2))
        player.mark(loop(around: e.layout.ones[0].union(e.layout.ones[9])))
        player.settle(voice)
        // Add the tens.
        #expect(player.phase == .doing(3))
        for _ in 0..<e.problem.secondTens {
            player.mark(.tap(CGPoint(x: 300, y: 260)))
            player.settle(voice)
        }
        // Count each piece, tens first.
        #expect(player.phase == .doing(4))
        let s = e.state(after: 3)
        for piece in e.countOrder(s) {
            player.mark(touch(e.rect(piece)))
            player.settle(voice)
        }
        #expect(player.phase == .paused(4))
        #expect(voice.said.last?.display == "\(e.problem.first) plus \(e.problem.second) is \(e.problem.sum)!")
        #expect(player.scene.summary.hasSuffix("total=\(e.problem.sum)"))
        player.primary()
        #expect(player.part == .tryOne && player.caption == lesson.tryOne.tryOne.line)
    }
}
