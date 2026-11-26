import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

// Three cards closest to a target: cards tapped up into the sum and
// down out of it, the three written lines,
// put-back cards in take-away's colour and the chosen three in the answer's, the swap when the
// three answer cards are put down, the total said on every tap, and Why? on the too-many step.

/// Synthetic wording shaped like the app's entries. The app's own tests
/// check the real entries.
enum ThreeCardsFixture {
    static func list(_ xs: [Int]) -> String {
        xs.count < 2 ? xs.map(String.init).joined() : xs.dropLast().map(String.init).joined(separator: ", ") + " and \(xs.last!)"
    }

    static let wording = ThreeCardsWording(
        line: { l, p in
            let pair = "\(p.cards[p.best.i]) and \(p.cards[p.best.j])"
            let kept = p.keep.map { p.cards[$0] }
            let display: String =
                switch l {
                case .intro: "Let's find three cards."
                case .read: "Which three cards add up to closest to \(p.target)? One way: add all five cards, then put two back."
                case .add: "Lifting a card adds it to the total. Lift up all five to add them all together."
                case let .total(n): "\(n)"
                case .over: "We have \(p.total), but we want \(p.target). \(p.total) minus \(p.target) is \(p.over), so we have \(p.over) too many."
                case .drop: p.exact ? "So we put back two cards that make \(p.over): \(pair)." : "No two cards make exactly \(p.over). \(pair) make \(p.best.sum), the closest. We put those back."
                case .check: p.exact ? "\(kept.map(String.init).joined(separator: " plus ")) is \(p.result). Exactly \(p.target)!" : "\(kept.map(String.init).joined(separator: " plus ")) is \(p.result), the closest."
                case .answer: "The three cards are \(list(kept))."
                case .whyAll: "All five cards make \(p.total)."
                case .whyWant: "We only want \(p.target)."
                case .whyDashed: "The dashed part is how many too many: \(p.over). So the two cards we put back must make \(p.over)."
                }
            return Line(
                key: "explain.test.threeCards.\(l)", display: display, spoken: NumberWords.replacingNumerals(in: display),
                emphasis: l == .answer ? list(kept) : nil)
        },
        doLine: { l, p in
            let display: String =
                switch l {
                case .intro: "Now let's do one together."
                case .add: "Lifting a card adds it to the total. Tap each card to lift it."
                case .drop: p.exact ? "Now put back two cards that make \(p.over). Tap a card to put it down." : "No two cards make exactly \(p.over). Put back the two that come closest."
                case .added: "All five make \(p.total)."
                case let .dropped(a, b): "\(a) and \(b) make \(a + b)."
                case let .foundThree(a, b, c, sum): "\(a), \(b) and \(c) make \(sum). You found the three we want!"
                case let .swapped(a, b): "So \(a) and \(b) go back. They make \(a + b)."
                case .justTwo: "Put back just two."
                case let .otherPair(sum): "Those make \(sum). We need two that make \(p.over)."
                case .tryIntro: "Now you try one. Which three cards add up to closest to \(p.target)?"
                }
            return Line(key: "explain.test.threeCards.do.\(l)", display: display, spoken: NumberWords.replacingNumerals(in: display))
        },
        text: { t, p in
            switch t {
            case .question: "Which three cards add up to closest to \(p.target)?"
            case .addLabel: "Add them all"
            case .overLabel: "Too many"
            case .backLabel: "Put back"
            case .tryNote: "Your turn: add them all, find how many too many, put two back."
            case .whyTitle: "Why take away \(p.target)?"
            case .whyAllName: "All five"
            case .whyWantName: "We want"
            case .whyWork: "\(p.total) − \(p.target) = \(p.over) too many"
            case .plus: "+"
            case .minus: "−"
            case .equals: "="
            }
        })

    static func explainer(_ cards: [Int], _ target: Int) -> ThreeCardsExplainer {
        ThreeCardsExplainer(problem: try! ThreeCardsProblem(cards, target: target), wording: wording)
    }

    static let prototype = explainer([7, 2, 9, 4, 5], 20)

    /// The range's edges (EXP-2): the smallest and largest cards and targets, a total just over
    /// the target and far over it, an exact answer and a closest one, ties between pairs, and
    /// cards repeated.
    static let edges: [([Int], Int)] = [
        ([7, 2, 9, 4, 5], 20), ([1, 1, 1, 1, 7], 10), ([9, 9, 9, 9, 9], 30), ([9, 9, 9, 9, 9], 10), ([2, 2, 2, 2, 3], 10),
        ([1, 2, 3, 4, 5], 14), ([6, 1, 8, 3, 9], 15), ([5, 5, 5, 5, 5], 16), ([9, 8, 7, 1, 2], 18), ([3, 9, 4, 8, 1], 13),
    ]

    static var all: [ThreeCardsExplainer] { edges.map { explainer($0.0, $0.1) } }
}

/// A touch in the middle of card `i` as it stands in `s`.
func touch(card i: Int, _ s: ThreeCardsState) -> Mark {
    let r = ThreeCardsLayout.card(i, lift: s.up.contains(i) ? 1 : 0)
    return .tap(CGPoint(x: r.midX, y: r.midY))
}

/// The cards' paint in a picture, by place.
func cardPaint(_ scene: Scene, _ i: Int) -> Paint? {
    guard case let .shape(_, paint) = scene.element("card.\(i)")?.kind else { return nil }
    return paint
}

/// The texts of written line `n`, run together, and the ink of each number in it.
func workLine(_ scene: Scene, _ n: Int) -> (text: String, inks: [Ink]) {
    let tokens = scene.elements("work.\(n).").filter { !$0.id.hasSuffix("label") && $0.opacity > 0 }
    var text: [String] = []
    var inks: [Ink] = []
    for t in tokens {
        guard case let .words(s, set) = t.kind else { continue }
        text.append(s)
        if Int(s) != nil { inks.append(set.ink) }
    }
    return (text.joined(separator: " "), inks)
}

func sumLine(_ scene: Scene) -> EquationLine? {
    guard case let .equation(eq) = scene.element("sum")?.kind else { return nil }
    return eq
}

struct ThreeCardsModelTests {
    @Test func thePrototypesProblem() {
        let p = ThreeCardsFixture.prototype.problem
        #expect(p.total == 27 && p.over == 7)
        #expect(p.best == ThreeCardsProblem.Pair(i: 1, j: 4, sum: 7), "2 and 5 make 7")
        #expect(p.keep == [0, 2, 3] && p.result == 20 && p.exact)
        #expect(p.steps == [.read, .add, .over, .drop, .check])
    }

    @Test func closestWhenNoTwoMakeItExactly() throws {
        // 1 + 2 + 3 + 4 + 5 = 15, target 14: one too many, and no two cards make 1.
        let p = try ThreeCardsProblem([1, 2, 3, 4, 5], target: 14)
        #expect(p.over == 1 && !p.exact && p.bestDiff == 2)
        #expect(p.best == ThreeCardsProblem.Pair(i: 0, j: 1, sum: 3), "the earliest of the closest pairs")
        #expect(p.result == 12)
    }

    /// EXP-2: a value outside the template's range is refused.
    @Test func valuesOutsideTheRangeAreRefused() {
        #expect(throws: ThreeCardsProblem.RangeError.card(0)) { try ThreeCardsProblem([0, 2, 9, 4, 5], target: 20) }
        #expect(throws: ThreeCardsProblem.RangeError.card(10)) { try ThreeCardsProblem([10, 2, 9, 4, 5], target: 20) }
        #expect(throws: ThreeCardsProblem.RangeError.target(9)) { try ThreeCardsProblem([7, 2, 9, 4, 5], target: 9) }
        #expect(throws: ThreeCardsProblem.RangeError.target(31)) { try ThreeCardsProblem([9, 9, 9, 9, 9], target: 31) }
        #expect(throws: ThreeCardsProblem.RangeError.notOver(total: 20, target: 20)) { try ThreeCardsProblem([4, 4, 4, 4, 4], target: 20) }
        #expect(throws: ThreeCardsProblem.RangeError.count(4)) { try ThreeCardsProblem([7, 2, 9, 4], target: 20) }
        #expect(ThreeCardsProblem.accepts([1, 1, 1, 1, 7], target: 10))
    }

    /// EXP-3: do it with me and try one are other problems of the same kind: exact when the
    /// learner's is exact, one closest pair, never the learner's total, and different from each other.
    @Test func theOtherProblemsAreOfTheSameKind() throws {
        for (cards, target) in ThreeCardsFixture.edges {
            let p = try ThreeCardsProblem(cards, target: target)
            let first = p.isomorph(1)
            let second = p.isomorph(2)
            for q in [first, second] {
                #expect(q != p && q.exact == p.exact && q.total != p.total && !q.bestIsShared, "\(p): \(q)")
                #expect(Set(q.cards).count == 5 && (15...20).contains(q.target))
            }
            #expect(first.total != second.total, "\(p): \(first) and \(second)")
            #expect(p.isomorph(1) == first, "the same problem always gets the same others")
        }
    }
}

struct ThreeCardsWatchTests {
    @Test func theStepsAndWhatTheChildDoes() {
        let e = ThreeCardsFixture.prototype
        #expect(e.guidedSteps.map(\.id) == ["read", "add", "over", "drop", "check"])
        #expect(e.guidedSteps.map(\.doable) == [false, true, false, true, false])
        #expect(e.guidedSteps.map(\.countsAloud) == [false, true, false, false, false])
    }

    /// Every step played for the range's edges ends on its still picture (EXP-11), and the
    /// still pictures show the palette's colours (EXP-6).
    @Test func everyStepEndsOnItsStillPicture() {
        for e in ThreeCardsFixture.all {
            var s = e.start
            for k in e.steps.indices {
                let (s1, motion) = e.watch(k, from: s)
                #expect(motion.end == e.picture(s1, marking: k), "\(e.problem) step \(k)")
                for t in stride(from: 0, through: motion.script.duration, by: 0.1) { _ = motion.picture(t) }
                s = s1
            }
            #expect(s.done && s.up.count == 3 && s.down == [e.problem.best.i, e.problem.best.j])
        }
    }

    @Test func liftedCardsAreAddsAndPutBackOnesTakeAways() {
        let e = ThreeCardsFixture.prototype
        let added = e.picture(e.state(after: 1), marking: 1)
        for i in 0..<5 {
            #expect(cardPaint(added, i)?.stroke == .ink(.add))
            if case let .shape(.rect(r, _), _) = added.element("card.\(i)")?.kind { #expect(r.minY == 150, "lifted") }
        }
        #expect(sumLine(added)?.text == "7 + 2 + 9 + 4 + 5 = 27")
        #expect(workLine(added, 0).text == "7 + 2 + 9 + 4 + 5 = 27")
        let over = e.picture(e.state(after: 2), marking: 2)
        #expect(workLine(over, 1).text == "27 − 20 = 7" && workLine(over, 1).inks.allSatisfy { $0 == .text })
        let dropped = e.picture(e.state(after: 3), marking: 3)
        for i in [1, 4] { #expect(cardPaint(dropped, i) == Paint(fill: .soft(.subtract), stroke: .ink(.subtract), width: 3.2)) }
        // The Put back line's numbers in take-away's ink, as the cards; its sum in ink.
        #expect(workLine(dropped, 2).text == "2 + 5 = 7")
        #expect(workLine(dropped, 2).inks == [.ink(.subtract), .ink(.subtract), .text])
        #expect(sumLine(dropped)?.text == "7 + 9 + 4 = 20" && sumLine(dropped)?.runs.allSatisfy { $0.role == .plain } == true)
        let checked = e.picture(e.state(after: 4), marking: 4)
        for i in [0, 2, 3] { #expect(cardPaint(checked, i) == Paint(fill: .soft(.result), stroke: .ink(.result), width: 3.2)) }
        // The equation above in the answer's colour: its numbers, not its signs.
        let roles = sumLine(checked)?.runs.map(\.role) ?? []
        #expect(roles == [.answer, .plain, .answer, .plain, .answer, .plain, .answer])
    }

    /// The adding step counts aloud: its line first, then each card rises and its total is said,
    /// each after the one before is heard (EXP-10).
    @Test func addingSaysEachNewTotalAsTheCardRises() {
        let e = ThreeCardsFixture.prototype
        let (_, motion) = e.watch(1, from: e.state(after: 0))
        let said = motion.script.events.compactMap { ev -> String? in
            if case let .say(l, _) = ev.action { return l.display }
            return nil
        }
        #expect(said == [e.line(.add).display, "7", "9", "18", "22", "27"])
        // The first card rises at once; the equation follows it.
        let early = motion.picture(0.13)
        #expect(sumLine(early)?.text == "7")
        if case let .shape(.rect(r, _), _) = early.element("card.0")?.kind { #expect(r.minY < 196 && r.minY > 150) }
        #expect(workLine(early, 0).text.isEmpty || early.element("work.0.0")?.opacity == 0)
    }

    @Test func checkSaysTheAnswerWithTheThreeEmphasised() {
        let e = ThreeCardsFixture.prototype
        let (_, motion) = e.watch(4, from: e.state(after: 3))
        guard case let .say(answer, true)? = motion.script.events.last?.action else {
            Issue.record("no answer")
            return
        }
        #expect(answer.display == "The three cards are 7, 9 and 4." && answer.emphasis == "7, 9 and 4")
    }

    /// Why? on the too-many step only (EXP-16): all five cards' bar, the target's, and the dashed
    /// part tagged with how many too many.
    @Test func whyIsOnTheTooManyStep() {
        let e = ThreeCardsFixture.prototype
        for k in e.steps.indices { #expect((e.why(k, e.state(after: k)) != nil) == (e.steps[k] == .over)) }
        guard let why = e.why(2, e.state(after: 2)) else { return }
        let end = why.end
        guard case let .shape(.rect(all, _), _) = end.element("why.all.bar")?.kind,
            case let .shape(.rect(want, _), _) = end.element("why.want.bar")?.kind,
            case let .shape(.rect(gap, _), gapPaint) = end.element("why.gap")?.kind
        else {
            Issue.record("no bars")
            return
        }
        #expect(abs(all.width - 620) < 0.001 && abs(want.width - 620 * 20 / 27) < 0.001)
        #expect(abs(gap.minX - want.maxX) < 0.001 && abs(gap.maxX - all.maxX) < 0.001, "the dashed part runs on to the longer bar")
        #expect(gapPaint.dash == ThreeCardsLayout.dashedDash && gapPaint.stroke == .ink(.result))
        guard case let .numberTag(over, _, _) = end.element("why.tag")?.kind else { return }
        #expect(over == "7")
        let lines = why.script.events.compactMap { ev -> String? in
            if case let .say(l, _) = ev.action { return l.display }
            return nil
        }
        #expect(lines == [e.line(.whyAll).display, e.line(.whyWant).display, e.line(.whyDashed).display])
        // Nothing of the dashed part shows before it is drawn.
        #expect(why.picture(0.1).element("why.gap")?.isVisible == false)
    }

    @Test func tryOneShowsTheCardsAndTheNote() {
        let e = ThreeCardsFixture.prototype
        let t = e.tryOne
        #expect(t.line.display == "Now you try one. Which three cards add up to closest to 20?")
        #expect(t.scene.element("try.note") != nil)
        for i in 0..<5 { #expect(cardPaint(t.scene, i)?.stroke == .pencil) }
    }

    /// The written lines stay on the stage at their widest: five cards, two-digit sum.
    @Test func theWrittenLinesFitTheStage() {
        let e = ThreeCardsFixture.explainer([9, 9, 9, 9, 9], 10)
        var s = e.state(after: 3)
        s.down = [0, 1, 2, 3, 4]
        let scene = e.picture(s, marking: 3)
        for n in 0..<3 {
            for el in scene.elements("work.\(n).") {
                guard case let .words(text, set) = el.kind else { continue }
                let room = ThreeCardsLayout.room(text, sign: Int(text) == nil, size: set.size)
                #expect(set.at.x + room / 2 < Scene.stage.width - 16, "\(el.id)")
            }
        }
    }
}

struct ThreeCardsDoTests {
    let e = ThreeCardsFixture.prototype

    /// A tap lifts a card that is down and lowers one that is up; the equation follows, and the
    /// new total is said, cutting off the one before (EXP-10).
    @Test func tapsLiftAndLowerCardsAndSayTheTotal() {
        var s = e.state(after: 0)
        #expect(e.begin(1, s).tally == Tally(0, of: 5, op: .add))
        var r = e.read(touch(card: 2, s), step: 1, s)
        #expect(r.state.up == [2] && r.interrupts && r.tally == Tally(1, of: 5, op: .add) && !r.finished)
        #expect(r.motion?.script.events.first?.action == .say(e.line(.total(9)), caption: false))
        s = r.state
        r = e.read(touch(card: 0, s), step: 1, s)
        s = r.state
        #expect(sumLine(e.picture(s, marking: 1))?.text == "9 + 7 = 16")
        // Lowered again: the total goes down.
        r = e.read(touch(card: 2, s), step: 1, s)
        #expect(r.state.up == [0] && r.motion?.script.events.first?.action == .say(e.line(.total(7)), caption: false))
        // A tap off the cards is ignored, not a miss.
        let off = e.read(.tap(CGPoint(x: 500, y: 470)), step: 1, r.state)
        #expect(off.state == r.state && off.note == nil && off.motion == nil)
    }

    @Test func theFifthCardWritesTheFirstLineInTheOrderTheyWentUp() {
        var s = e.state(after: 0)
        var r = e.read(touch(card: 4, s), step: 1, s)
        for k in [3, 0, 1, 2] {
            s = r.state
            r = e.read(touch(card: k, s), step: 1, s)
        }
        #expect(r.finished && r.state.added == [4, 3, 0, 1, 2] && r.state.work == 1)
        #expect(workLine(e.picture(r.state, marking: 1), 0).text == "5 + 4 + 7 + 2 + 9 = 27")
        guard case let .say(after, true)? = r.motion?.script.events.last?.action else {
            Issue.record("nothing said after")
            return
        }
        #expect(after.display == "All five make 27.")
    }

    @Test func theTwoThatMakeTooManyFinishTheStep() {
        let s = e.state(after: 2)
        var r = e.read(touch(card: 4, s), step: 3, s)
        #expect(r.state.down == [4] && r.state.work == 3 && !r.finished)
        let painted = e.picture(r.state, marking: 3)
        #expect(cardPaint(painted, 4)?.fill == .soft(.subtract))
        #expect(workLine(painted, 2).text == "5" && workLine(painted, 2).inks == [.ink(.subtract)])
        r = e.read(touch(card: 1, r.state), step: 3, r.state)
        #expect(r.finished && r.state.down == [4, 1] && r.note == .clear)
        guard case let .say(after, true)? = r.motion?.script.events.last?.action else { return }
        #expect(after.display == "5 and 2 make 7.")
    }

    /// Two that are not the pair: what they make and what is needed, never a miss; lifting
    /// one again takes it out of the Put back line.
    @Test func twoOthersAreToldWhatTheyMake() {
        let s = e.state(after: 2)
        var r = e.read(touch(card: 0, s), step: 3, s)
        r = e.read(touch(card: 2, r.state), step: 3, r.state)
        #expect(!r.finished && r.note == .hint(e.doLine(.otherPair(sum: 16))))
        #expect(r.motion?.script.events.contains { $0.action == .say(e.doLine(.otherPair(sum: 16)), caption: false) } == true)
        r = e.read(touch(card: 2, r.state), step: 3, r.state)
        #expect(r.state.down == [0] && r.state.up.contains(2))
        #expect(workLine(e.picture(r.state, marking: 3), 2).text == "7")
        #expect(cardPaint(e.picture(r.state, marking: 3), 2)?.stroke == .ink(.add))
    }

    @Test func moreThanTwoAreAskedForJustTwo() {
        var s = e.state(after: 2)
        for k in [0, 1] { s = e.read(touch(card: k, s), step: 3, s).state }
        let r = e.read(touch(card: 4, s), step: 3, s)
        #expect(r.state.down == [0, 1, 4] && r.note == .hint(e.doLine(.justTwo)) && !r.finished)
    }

    /// The three answer cards put down: recognised, then they swap with the other two, so those
    /// up are the ones in the sum.
    @Test func theThreeAnswerCardsPutDownAreRecognisedAndSwap() {
        var s = e.state(after: 2)
        for k in [2, 0] { s = e.read(touch(card: k, s), step: 3, s).state }
        let r = e.read(touch(card: 3, s), step: 3, s)
        let found = e.doLine(.foundThree(9, 7, 4, sum: 20))
        #expect(r.finished && r.note == .hint(found))
        #expect(r.state.up == [2, 0, 3] && r.state.down == [1, 4] && r.state.swapped)
        guard let motion = r.motion else { return }
        let actions = motion.script.events.map(\.action)
        #expect(actions.contains(.say(found, caption: false)))
        #expect(actions.last == .say(e.doLine(.swapped(2, 5)), caption: true))
        // While what the learner found is said, the cards stand as the learner left them.
        guard let at = motion.script.events.first(where: { $0.action == .waitForVoice })?.time else { return }
        let held = motion.picture(at)
        #expect(cardPaint(held, 3)?.fill == .soft(.subtract) && cardPaint(held, 1)?.stroke == .ink(.add))
        let after = motion.end
        #expect(workLine(after, 2).text == "2 + 5 = 7")
        #expect(cardPaint(after, 1)?.fill == .soft(.subtract) && cardPaint(after, 2)?.stroke == .ink(.add))
        // Then the check names the three as chosen.
        let checked = e.picture(e.apply(.check, r.state), marking: 4)
        #expect(sumLine(checked)?.text == "9 + 7 + 4 = 20")
    }

    @Test func instructionsAndIntro() {
        #expect(e.intro(.watch).display == "Let's find three cards.")
        #expect(e.intro(.doWithMe).display == "Now let's do one together.")
        #expect(e.instruction(1, e.state(after: 0)) == e.doLine(.add))
        #expect(e.instruction(3, e.state(after: 2)).display == "Now put back two cards that make 7. Tap a card to put it down.")
        let closest = ThreeCardsFixture.explainer([1, 2, 3, 4, 5], 14)
        #expect(closest.instruction(3, closest.state(after: 2)).display == "No two cards make exactly 1. Put back the two that come closest.")
    }
}

// The whole child version in the player: watch, do it with me with every step the child's,
// Why? on the too-many step, and try one.
@MainActor
struct ThreeCardsPlayerTests {
    @Test func theChildVersionPlaysThrough() {
        let voice = RecordingVoice()
        let lesson = ThreeCardsExplainer.lesson(watching: ThreeCardsFixture.prototype.problem, wording: ThreeCardsFixture.wording)
        let p = GuidedPlayer(lesson: lesson, voice: voice, labels: Fixture.guidedLabels, drivesItself: false)
        #expect(p.parts == [.watch, .doWithMe, .tryOne])
        p.primary()
        p.settle(voice)
        while case let .paused(k) = p.phase, k < p.steps.count - 1 {
            if k == 2 {
                #expect(p.whyOffered)
                p.why()
                p.settle(voice)
                #expect(p.primaryControl == .gotIt && p.whyScene?.element("why.tag") != nil)
                p.primary()
                #expect(!p.whyShown && p.phase == .paused(2))
            } else {
                #expect(!p.whyOffered)
            }
            p.primary()
            p.settle(voice)
        }
        #expect(p.phase == .paused(4) && p.primaryControl == .doWithMe)
        #expect(voice.said.last?.display == "The three cards are 7, 9 and 4.")

        // Do it with me, on another problem of the same kind.
        p.primary()
        #expect(p.caption.display == "Now let's do one together.")
        let d = lesson.doWithMe
        // Do it with me runs on by itself: read is watched, then the learner's step.
        p.primary()
        p.settle(voice)
        #expect(p.phase == .doing(1) && p.readsMarks && p.tally == Tally(0, of: 5, op: .add))
        for i in 0..<5 {
            let r = ThreeCardsLayout.card(i, lift: 0)
            p.mark(.tap(CGPoint(x: r.midX, y: r.midY)))
        }
        // Over is watched, and then the learner's step.
        p.settle(voice)
        #expect(p.phase == .doing(3) && p.readsMarks)
        #expect(!p.whyOffered, "do it with me offers no Why?: it runs on")
        for i in [d.problem.best.i, d.problem.best.j] {
            let r = ThreeCardsLayout.card(i, lift: 1)
            p.mark(.tap(CGPoint(x: r.midX, y: r.midY)))
        }
        p.settle(voice)
        #expect(p.phase == .paused(4) && p.primaryControl == .tryOne)
        p.primary()
        #expect(p.phase == .tryOne && p.scene.element("try.note") != nil)
    }
}
