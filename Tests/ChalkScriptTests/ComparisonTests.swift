import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript

// The comparing word problem (tape diagram) and the bar graph:
// the watched steps, do it with me (the draw-on line,
// the equation cards and the adding card's join, counting), What if? with snapping and Show me,
// and try one.

/// Synthetic wording shaped like the consuming app's entries (keys under explain.compare.); the
/// app's own tests check the real entries.
enum CompareFixture {
    static let names = ["Maya", "Leo", "Ana", "Ben", "Priya", "Omar"]
    static let things = ["shells", "stickers", "pages"]

    static func tape() -> TapeDiagramWording {
        TapeDiagramWording(
            line: { l, p in
                let (n1, n2) = (names[(p.names * 2) % names.count], names[(p.names * 2 + 1) % names.count])
                let display: String =
                    switch l {
                    case let .tick(n): "\(n)"
                    case .answer: "\(n1) found \(p.difference) \(p.word.rawValue)."
                    case let .goalExactly(n): "Make it exactly \(n)."
                    case let .goalExactlyMet(n): "\(n) \(p.word.rawValue)."
                    case let .goalFlip(w): "Can \(n1) have \(w.rawValue)?"
                    case let .goalFlipMet(w): "Now it asks how many \(w.rawValue)."
                    case .joined: "\(p.a) plus \(p.b) puts \(n1)'s and \(n2)'s bars together."
                    case .joinedTotal: "That makes \(p.a + p.b)."
                    default: "\(l) \(p.a) \(p.b) \(n1) \(n2)"
                    }
                return Line(key: "explain.test.tape.\(l)", display: display, spoken: NumberWords.replacingNumerals(in: display),
                    emphasis: l == .answer ? String(p.difference) : nil)
            },
            text: { t, p in
                switch t {
                case .story: "\(names[(p.names * 2) % names.count]) found \(p.a) \(things[p.story % things.count]). \(names[(p.names * 2 + 1) % names.count]) found \(p.b)."
                case .firstName: names[(p.names * 2) % names.count]
                case .secondName: names[(p.names * 2 + 1) % names.count]
                case .subtractFormat: "\(EquationSlot.first) − \(EquationSlot.second) = \(EquationSlot.answer)"
                case .addFormat: "\(EquationSlot.first) + \(EquationSlot.second) = \(EquationSlot.answer)"
                case .unknown: "?"
                case .same: "Same!"
                case let .hop(n): "+\(n)"
                case let .running(tens, ones, total): total.map { "\(tens) + \(ones) = \($0)" } ?? "\(tens) + \(ones)"
                case let .tryNote(n): "Note \(n)"
                }
            },
            question: { p in
                PhraseMarks.phrases("How many \(PhraseMarks.wrap(p.word.rawValue)) shells did Maya find \(PhraseMarks.wrap("than")) Leo?")
            })
    }

    static let cats = [["apples", "bananas", "grapes", "pears"], ["cats", "dogs", "fish", "rabbits"], ["lions", "giraffes", "penguins", "zebras"]]

    static func graph() -> BarGraphWording {
        BarGraphWording(
            line: { l, p in
                let display: String =
                    switch l {
                    case let .tick(n): "\(n)"
                    case .answer: "\(p.difference) \(p.word.rawValue) children picked \(cats[p.graph % 3][p.first])."
                    case let .wrongNumber(v, bar): "That's \(v). Follow the \(cats[p.graph % 3][bar]) bar."
                    case let .nextBar(bar): "Now the \(cats[p.graph % 3][bar]) bar."
                    default: "\(l) \(p.a) \(p.b)"
                    }
                return Line(key: "explain.test.graph.\(l)", display: display, spoken: NumberWords.replacingNumerals(in: display),
                    emphasis: l == .answer ? String(p.difference) : nil)
            },
            text: { t, p in
                switch t {
                case .title: "Favorite fruit"
                case let .category(i): cats[p.graph % 3][i]
                case .axis: "number of children"
                case .subtractFormat: "\(EquationSlot.first) − \(EquationSlot.second) = \(EquationSlot.answer)"
                case .addFormat: "\(EquationSlot.first) + \(EquationSlot.second) = \(EquationSlot.answer)"
                case .unknown: "?"
                case .same: "Same!"
                case .tryNote: "Your turn."
                }
            },
            question: { p in PhraseMarks.phrases("How many \(PhraseMarks.wrap(p.word.rawValue)) children picked \(PhraseMarks.wrap("than"))?") })
    }

    static func tape(_ a: Int, _ b: Int) -> TapeDiagramExplainer {
        TapeDiagramExplainer(problem: try! TapeDiagramProblem(a, b), wording: tape())
    }

    static func graph(_ a: Int, _ b: Int) -> BarGraphExplainer {
        BarGraphExplainer(problem: try! BarGraphProblem(a, b), wording: graph())
    }
}

/// A line drawn along from `x0` to `x1` at height `y`.
func along(_ x0: CGFloat, _ x1: CGFloat, y: CGFloat, rise: CGFloat = 0) -> Mark {
    .stroke([CGPoint(x: x0, y: y), CGPoint(x: (x0 + x1) / 2, y: y + rise / 2), CGPoint(x: x1, y: y + rise)])
}

extension Scene {
    func words(_ id: String) -> String? {
        guard let e = element(id), e.isVisible, case let .words(text, _) = e.kind else { return nil }
        return text
    }

    func equationText(_ id: String = "equation") -> String? {
        guard let e = element(id), e.isVisible, case let .equation(eq) = e.kind else { return nil }
        return eq.text
    }
}

struct ComparisonPartsTests {
    @Test func theQuestionsComparisonWordsAreTinted() {
        let phrases = PhraseMarks.phrases("How many \(PhraseMarks.wrap("fewer")) shells did Maya find \(PhraseMarks.wrap("than")) Leo?")
        #expect(phrases.map(\.text) == ["How many ", "fewer", " shells did Maya find ", "than", " Leo?"])
        #expect(phrases.map(\.tinted) == [false, true, false, true, false])
        var pen = Pen()
        pen.question("question", phrases, center: CGPoint(x: 500, y: 80), size: 26)
        // A tint behind each word, under the line itself, which is all in the text colour.
        #expect(pen.elements.map(\.id) == ["question.tint.1", "question.tint.3", "question"])
        guard case let .equation(tint) = pen.elements[0].kind, case let .equation(line) = pen.elements[2].kind else {
            Issue.record("not equations"); return
        }
        #expect(tint.mark == .init(run: 1, op: .subtract, progress: 1) && tint.runs.allSatisfy { $0.opacity == 0 })
        #expect(line.mark == nil && line.text == "How many fewer shells did Maya find than Leo?")
    }

    @Test func aDrawOnLineIsReadAlongFromTheShorterBar() {
        func read(_ m: Mark) -> DrawOn { DrawOn.read(m, from: 300, to: 500, tolerance: 26, tallest: 60) }
        #expect(read(along(305, 495, y: 180)) == .drawn)
        #expect(read(along(495, 305, y: 180)) == .drawn, "either way along")
        #expect(read(.tap(CGPoint(x: 300, y: 180))) == .tapped)
        #expect(read(along(305, 495, y: 180, rise: 80)) == .notAlong)
        #expect(read(along(200, 495, y: 180)) == .startOff)
        #expect(read(along(305, 420, y: 180)) == .short)
        #expect(read(along(305, 600, y: 180)) == .past)
    }

    @Test func theEquationsSignAndAnswerAreTheirOwnRuns() {
        let e = equationRuns("\(EquationSlot.first) − \(EquationSlot.second) = \(EquationSlot.answer)", first: "52", second: "34", answer: "?")
        #expect(e.runs == ["52", " − ", "34", " = ", "?"] && e.sign == 1 && e.answer == 4)
    }

    /// What if?'s goals (EXP-15): checked on letting go, never while dragging; a goal asking for an
    /// exact amount snaps within 2; Show me always meets it; the third turns the question.
    @Test func whatIfGoalsAreCheckedOnLettingGo() {
        let other = 30
        let goals = WhatIf.goals(other: other, exactly: 10, range: 1...99, flipBy: 15, snaps: true, flipTo: .more)
        let glide: (DraggedBar, DraggedBar) -> Motion = { _, to in .still(Scene(), duration: Double(abs(to.a))) }
        let met: (DraggedBar) -> Line = { _ in Line(key: "met", display: "Yes!", spoken: "Yes!") }
        var s = DraggedBar(a: 20, word: .fewer)
        // Dragged to 28, not let go: nothing is checked.
        s = WhatIf.drag(.began(CGPoint(x: 0, y: 0)), s, other: other, onRow: { _ in true }, amount: { _ in 28 })
        #expect(s.dragging && s.a == 28)
        let open = WhatIf.settle(goals[0], WhatIf.drag(.moved(.zero), s, other: other, onRow: { _ in true }, amount: { _ in 25 }), showMe: false, other: other, glide: glide, met: met)
        #expect(open.met == nil, "not let go")
        // Let go at 28: within 2 of 30, so it snaps there and is met.
        s = WhatIf.drag(.ended(.zero), s, other: other, onRow: { _ in true }, amount: { _ in 28 })
        let snapped = WhatIf.settle(goals[0], s, showMe: false, other: other, glide: glide, met: met)
        #expect(snapped.state.a == 30 && snapped.met != nil && snapped.motion != nil && snapped.state.word == .fewer, "the word holds at equal bars")
        // Let go at 25: too far to snap; no failure, the goal stays open.
        s = WhatIf.drag(.ended(.zero), WhatIf.drag(.began(.zero), s, other: other, onRow: { _ in true }, amount: { _ in 25 }), other: other, onRow: { _ in true }, amount: { _ in 25 })
        let far = WhatIf.settle(goals[0], s, showMe: false, other: other, glide: glide, met: met)
        #expect(far.state.a == 25 && far.met == nil)
        // A touch off the bar moves nothing and is not checked.
        let off = WhatIf.drag(.began(.zero), far.state, other: other, onRow: { _ in false }, amount: { _ in 70 })
        #expect(!off.dragging && off.a == 25)
        // Show me slides to the nearest exact difference and meets it.
        let shown = WhatIf.settle(goals[1], far.state, showMe: true, other: other, glide: glide, met: met)
        #expect(shown.state.a == 20 && shown.met != nil && shown.state.word == .fewer)
        // The third goal: the question turned to "more".
        #expect(goals[2].met(31) && !goals[2].met(30) && goals[2].target(20) == 45)
    }

    @Test func aGlideMovesOneNumberAtATime() {
        let g = WhatIf.glideTimes(from: 10, to: 14, hold: { _ in 0.1 })
        #expect(g.values == [11, 12, 13, 14] && zip(g.times, [0, 0.1, 0.2, 0.3]).allSatisfy { abs($0 - $1) < 1e-9 } && abs(g.duration - 0.4) < 1e-9)
    }
}

// MARK: the tape diagram

struct TapeDiagramTests {
    @Test func theTemplatesRange() {
        #expect((try? TapeDiagramProblem(0, 5)) == nil && (try? TapeDiagramProblem(5, 100)) == nil && (try? TapeDiagramProblem(7, 7)) == nil)
        let p = try! TapeDiagramProblem(34, 52)
        #expect(p.word == .fewer && p.difference == 18 && p.firstIsShorter)
        #expect(p.hops.map(\.to) == [44, 52])
        #expect(try! TapeDiagramProblem(52, 34).word == .more)
    }

    /// The other problems keep the gap's shape and turn the question for do it with me (EXP-3).
    @Test func otherProblemsAreOfTheSameKind() {
        for (a, b) in [(34, 52), (52, 34), (1, 99), (99, 1), (40, 50), (12, 13), (20, 90)] {
            let p = try! TapeDiagramProblem(a, b)
            for n in [1, 2] {
                let q = p.isomorph(n)
                #expect((q.difference >= 10) == (p.difference >= 10) && (q.difference % 10 == 0) == (p.difference % 10 == 0))
                #expect(q.difference != p.difference && q.small != p.small && q.story == n && q.names == n)
                #expect((q.word != p.word) == (n == 1), "\(a), \(b) isomorph \(n)")
            }
        }
    }

    @Test func theStepsAndWhatTheChildDoes() {
        let e = CompareFixture.tape(34, 52)
        #expect(e.guidedSteps.map(\.id) == ["read", "bars", "compare", "equation", "count"])
        #expect(e.guidedSteps.map(\.doable) == [false, false, true, true, true])
        #expect(e.guidedSteps.map(\.countsAloud) == [false, false, false, false, true])
        #expect(e.whatIf?.goals == 3)
    }

    /// Watched through, the picture builds: the bars, the shorter drawn on
    /// dashed to the longer's length, the equation, the jumps, and the answer in the dashed part
    /// and the equation.
    @Test func watchedStepsBuildThePicture() {
        let e = CompareFixture.tape(34, 52)
        var s = e.start
        var pictures: [Scene] = []
        for k in 0..<e.steps.count {
            let (s1, motion) = e.watch(k, from: s)
            #expect(motion.end == e.picture(s1, marking: k), "step \(k) ends on its still picture")
            pictures.append(motion.end)
            s = s1
        }
        #expect(pictures[0].element("top.bar") == nil && pictures[0].words("story") == "Maya found 34 shells. Leo found 52.")
        #expect(pictures[1].element("top.bar") != nil && pictures[1].element("gap") == nil)
        guard case let .shape(.rect(gap, _), paint)? = pictures[2].element("gap")?.kind else { Issue.record("no dashed part"); return }
        #expect(gap.minX == e.xs && abs(gap.maxX - e.xb) < 0.001 && gap.minY == TapeDiagramExplainer.L.topY && paint.dash == [8, 6])
        #expect(paint.stroke == .ink(.result))
        #expect(pictures[2].words("gap.value") == "?")
        #expect(pictures[3].equationText() == "52 − 34 = ?")
        #expect(pictures[4].words("gap.value") == "18" && pictures[4].equationText() == "52 − 34 = 18")
        #expect(pictures[4].elements("hop.").filter { $0.id.hasSuffix("label") }.compactMap { pictures[4].words($0.id) } == ["+10", "+8"])
        #expect(pictures[4].words("run") == "10 + 8 = 18")
        // The bars grow from the shared start, one after the other.
        let (_, bars) = e.watch(1, from: e.start)
        guard case let .shape(.rect(top, _), _)? = bars.picture(0.55).element("top.bar")?.kind else { Issue.record("no top bar"); return }
        #expect(top.width > 0 && top.width < 34 * e.scale && bars.picture(0.55).element("bottom.bar") == nil)
    }

    /// The count says the number reached at each jump, then puts the tens and ones together,
    /// then the answer (EXP-10).
    @Test func theCountSaysEachJump() {
        let e = CompareFixture.tape(34, 52)
        let said = e.script(for: 4).events.compactMap { ev -> String? in if case let .say(l, _) = ev.action { l.display } else { nil } }
        #expect(said == ["count 34 52 Maya Leo", "44", "52", "countJoin 34 52 Maya Leo", "Maya found 18 fewer."])
        let small = CompareFixture.tape(40, 47).script(for: 4).events.compactMap { ev -> String? in if case let .say(l, _) = ev.action { l.display } else { nil } }
        #expect(small == ["count 40 47 Maya Leo", "47", "Maya found 7 fewer."], "no tens: nothing to put together")
    }

    @Test func drawingTheShorterBarOn() {
        let e = CompareFixture.tape(34, 52)
        let k = 2
        let s = e.watch(1, from: e.start).state
        #expect(e.instruction(k, s).display.hasPrefix("doCompare"))
        let y = TapeDiagramExplainer.L.topY + 20
        let tap = e.read(.tap(CGPoint(x: e.xs, y: y)), step: k, s)
        #expect(tap.note == .miss(e.line(.tapped)) && !tap.finished)
        #expect(e.read(along(e.xs + 4, e.xb + 200, y: y), step: k, s).note == .miss(e.line(.past)))
        #expect(e.read(along(e.xs + 4, e.xb - 60, y: y), step: k, s).note == .miss(e.line(.short)))
        #expect(e.read(along(e.xs - 80, e.xb, y: y), step: k, s).note == .miss(e.line(.startOff)))
        #expect(e.read(along(e.xs, e.xb, y: y, rise: 90), step: k, s).note == .miss(e.line(.notAlong)))
        // Along the bottom bar works as well as along the top.
        let r = e.read(along(e.xs + 10, e.xb - 10, y: TapeDiagramExplainer.L.bottomY + 20), step: k, s)
        #expect(r.finished && r.state.gap && !r.keepsStroke)
        guard let motion = r.motion, case let .say(line, true)? = motion.script.events.last?.action else { Issue.record("no motion"); return }
        #expect(line == e.line(.compared))
        #expect(motion.end.element("drop") != nil && motion.picture(0).element("gap") == nil, "the guide is there, the dashed part grows")
    }

    /// The adding card shows the two bars joined end to end with their sum while the dashed part
    /// stays, and is then greyed out; the take-away card is the step.
    @Test func theAddingCardJoinsTheBars() throws {
        let e = CompareFixture.tape(34, 52)
        let k = 3
        let s0 = e.watch(2, from: e.watch(1, from: e.start).state).state
        let b = e.begin(k, s0)
        #expect(b.state.cards)
        let cards = e.cards.cards
        let add = try #require(cards.first { $0.kind == .add }).rect
        let sub = try #require(cards.first { $0.kind == .subtract }).rect
        #expect(e.picture(b.state).words("card.add.text") == "34 + 52 = ?" && e.picture(b.state).words("card.subtract.text") == "52 − 34 = ?")
        let r = e.read(.tap(CGPoint(x: add.midX, y: add.midY)), step: k, b.state)
        #expect(r.state.addShown && !r.finished)
        let motion = try #require(r.motion)
        let said = motion.script.events.compactMap { ev -> Line? in if case let .say(l, _) = ev.action { l } else { nil } }
        #expect(said == [e.line(.joined), e.line(.joinedTotal), e.line(.joinedBut)])
        // Mid-join: both bars joined under the drawing, the sum under them, the dashed part still
        // drawn, the drawing shrunk and the question and cards full size.
        let join = Join(bars: [(0, 34 * e.scale), (0, 52 * e.scale)], origin: TapeDiagramExplainer.L.joinOrigin, x0: TapeDiagramExplainer.L.x0,
            y: TapeDiagramExplainer.L.joinY, height: 42, fill: .sheet, kMax: 1, sum: [], sign: 1)
        let mid = motion.picture(join.heard + 0.001)
        #expect(mid.element("joined.0") != nil && mid.element("joined.1") != nil && mid.equationText("joined.sum") == "34 + 52 = 86")
        let gap = try #require(mid.element("gap"))
        #expect(join.k < 1 && gap.transform != .identity && mid.element("question")?.transform == .identity && mid.element("card.add")?.transform == .identity)
        guard case let .shape(_, joined)? = mid.element("joined.0")?.kind else { Issue.record("no joined bar"); return }
        #expect(joined.stroke == .ink(.add), "outlined in the add colour (EXP-6)")
        // At its end the drawing is back as it was, the adding card greyed out.
        let end = motion.end
        #expect(end.element("joined.0") == nil && end.element("gap")?.transform == .identity)
        #expect(end.element("card.add")?.opacity == Look.goneOpacity)
        // Greyed out, it does nothing.
        let again = e.read(.tap(CGPoint(x: add.midX, y: add.midY)), step: k, r.state)
        #expect(again.motion == nil && again.note == nil && again.state == r.state)
        // Taking away is the step.
        let done = e.read(.tap(CGPoint(x: sub.midX, y: sub.midY)), step: k, r.state)
        #expect(done.finished && done.state.equation && !done.state.cards)
        #expect(done.motion?.picture(0).element("card.subtract").map { if case let .shape(_, p) = $0.kind { p == Look.chosenCard } else { false } } == true)
    }

    @Test func countingOnByTouches() {
        let e = CompareFixture.tape(34, 52)
        let k = 4
        var s = e.start
        for i in 0..<4 { s = e.watch(i, from: s).state }
        let b = e.begin(k, s)
        #expect(b.tally == Tally(0, of: 2, op: .result) && b.state.numberLine)
        s = b.state
        let away = e.read(.tap(CGPoint(x: 950, y: 520)), step: k, s)
        #expect(away.note == .miss(e.line(.countMissed)))
        let first = e.read(.tap(CGPoint(x: e.xs + 20, y: TapeDiagramExplainer.L.lineY)), step: k, s)
        #expect(first.state.hops == 1 && first.interrupts && !first.finished && first.tally == Tally(1, of: 2, op: .result))
        #expect(e.picture(first.state).words("run") == "10")
        let second = e.read(.tap(CGPoint(x: e.xs + 20, y: TapeDiagramExplainer.L.lineY)), step: k, first.state)
        #expect(second.finished && second.state.answered)
        guard let motion = second.motion, case let .say(line, true)? = motion.script.events.last?.action else { Issue.record("no answer"); return }
        #expect(line == e.line(.answer) && motion.end.words("gap.value") == "18")
    }

    /// What if? (EXP-15): the story's number, the question's word, the dashed part and the
    /// equation follow the dragged bar; three goals, the exact ones snapping.
    @Test func whatIfFollowsTheDraggedBar() {
        let e = CompareFixture.tape(34, 52)
        guard let w = e.whatIf else { Issue.record("no What if?"); return }
        var s = e.goal(0, w.start).state
        #expect(e.picture(whatIf: s).element("handle") != nil)
        let unit = TapeDiagramExplainer.L.length / 99
        func x(_ v: Int) -> CGFloat { TapeDiagramExplainer.L.x0 + CGFloat(v) * unit }
        let row = TapeDiagramExplainer.L.topY + 20
        s = e.drag(.began(CGPoint(x: x(34), y: row)), goal: 0, s)
        s = e.drag(.moved(CGPoint(x: x(60), y: row)), goal: 0, s)
        let moved = e.picture(whatIf: s)
        #expect(moved.words("story") == "Maya found 60 shells. Leo found 52." && moved.equationText() == "60 − 52 = 8")
        #expect(moved.equationText("question") == "How many more shells did Maya find than Leo?")
        // Let go at 51: within 2 of the same length, it snaps and is met; "Same!" shows.
        s = e.drag(.ended(CGPoint(x: x(51), y: row)), goal: 0, s)
        let met = e.settle(goal: 0, s, showMe: false)
        #expect(met.state.a == 52 && met.met?.key == e.line(.goalSameMet).key && met.met?.display.contains("52 52") == true)
        #expect(e.picture(whatIf: met.state).words("same") == "Same!" && e.picture(whatIf: met.state).element("gap") == nil)
        // Exactly 10: Show me slides to the nearest.
        let g1 = e.goal(1, met.state).state
        let shown = e.settle(goal: 1, g1, showMe: true)
        #expect(abs(shown.state.a - 52) == 10 && shown.met != nil && shown.motion != nil)
        // The third goal turns the question; letting go on the other side meets it.
        let g2 = e.goal(2, shown.state)
        #expect(g2.state.flipTo == (shown.state.a > 52 ? .fewer : .more))
        var t = e.drag(.began(CGPoint(x: x(shown.state.a), y: row)), goal: 2, g2.state)
        t = e.drag(.ended(CGPoint(x: x(g2.state.flipTo == .fewer ? 40 : 70), y: row)), goal: 2, t)
        let flipped = e.settle(goal: 2, t, showMe: false)
        #expect(flipped.met != nil && flipped.state.word == g2.state.flipTo)
    }

    @Test func tryOneIsTheStoryAlone() {
        let e = CompareFixture.tape(34, 52)
        let t = e.tryOne
        #expect(t.line.display.hasPrefix("tryIntro"))
        #expect(t.scene.words("story") != nil && t.scene.element("question.tint.1") == nil && t.scene.element("top.bar") == nil)
    }

    /// The whole child version plays in the player: watch, do it with me with every step the
    /// child's, What if? and try one.
    @MainActor @Test func playsThroughEveryPart() throws {
        let voice = RecordingVoice()
        let lesson = TapeDiagramExplainer.lesson(watching: try TapeDiagramProblem(34, 52), wording: CompareFixture.tape())
        let p = GuidedPlayer(lesson: lesson, voice: voice, labels: Fixture.guidedLabels, drivesItself: false)
        #expect(p.parts == [.watch, .doWithMe, .whatIf, .tryOne])
        p.primary()
        for _ in 0..<5 {
            p.settle(voice)
            p.primary()
        }
        #expect(p.part == .doWithMe)
        let e = lesson.doWithMe
        // Start: the watched steps run on into the child's.
        p.primary()
        p.settle(voice)
        #expect(p.phase == .doing(2))
        p.mark(along(e.xs + 2, e.xb - 2, y: TapeDiagramExplainer.L.topY + 20))
        p.settle(voice)
        #expect(p.phase == .doing(3))
        let sub = try #require(e.cards.cards.first { $0.kind == .subtract }).rect
        p.mark(.tap(CGPoint(x: sub.midX, y: sub.midY)))
        p.settle(voice)
        #expect(p.phase == .doing(4))
        for _ in e.problem.hops {
            p.mark(.tap(CGPoint(x: e.xs + 5, y: TapeDiagramExplainer.L.lineY)))
            p.settle(voice)
        }
        #expect(p.phase == .paused(4) && p.primaryControl == .whatIf)
        p.primary()
        p.settle(voice)
        // Each goal met opens the next by itself after a beat; the last waits for Try one.
        for g in 0..<3 {
            #expect(p.phase == .whatIf(goal: g, met: false))
            p.showMe()
            p.settle(voice)
        }
        #expect(p.phase == .whatIf(goal: 2, met: true) && p.primaryControl == .tryOne)
        p.primary()
        #expect(p.phase == .tryOne && p.haptics == 3)
    }
}

// MARK: the bar graph

struct BarGraphTests {
    @Test func theTemplatesRangeAndTheOtherBars() {
        #expect((try? BarGraphProblem(0, 5)) == nil && (try? BarGraphProblem(5, 21)) == nil && (try? BarGraphProblem(7, 7)) == nil)
        for a in BarGraphProblem.values {
            for b in BarGraphProblem.values where a != b {
                let p = try! BarGraphProblem(a, b)
                #expect(p.bars[p.first] == a && p.bars[p.second] == b)
                let others = [0, 1, 2, 3].filter { $0 != p.first && $0 != p.second }.map { p.bars[$0] }
                #expect(Set(others).count == 2 && !others.contains(a) && !others.contains(b) && others.allSatisfy { BarGraphProblem.values.contains($0) })
            }
        }
        let p = try! BarGraphProblem(14, 6)
        #expect(p.word == .more && p.difference == 8 && p.longer == 0 && p.shorter == 3)
    }

    @Test func otherProblemsAreOfTheSameKind() {
        for (a, b) in [(14, 6), (6, 14), (1, 20), (20, 1), (3, 4), (10, 15)] {
            let p = try! BarGraphProblem(a, b)
            for n in [1, 2] {
                let q = p.isomorph(n)
                #expect((q.difference >= 5) == (p.difference >= 5) && q.difference != p.difference && q.small != p.small)
                #expect((q.word != p.word) == (n == 1) && q.graph == n)
            }
        }
    }

    @Test func theStepsAndWhatTheChildDoes() {
        let e = CompareFixture.graph(14, 6)
        #expect(e.guidedSteps.map(\.doable) == [false, true, true, true, true])
        #expect(e.guidedSteps.map(\.countsAloud) == [false, false, false, false, true])
    }

    @Test func watchedStepsBuildThePicture() {
        let e = CompareFixture.graph(14, 6)
        var s = e.start
        var pictures: [Scene] = []
        for k in 0..<e.steps.count {
            let (s1, motion) = e.watch(k, from: s)
            #expect(motion.end == e.picture(s1, marking: k))
            pictures.append(motion.end)
            s = s1
        }
        #expect(pictures[0].elements("grid.").count == 21 && pictures[0].words("axis.label") == "number of children")
        #expect(pictures[1].words("read.0.value") == "14" && pictures[1].words("read.3.value") == "6")
        #expect(pictures[2].elements("cell.").count == 8 && pictures[2].element("gap") != nil)
        #expect(pictures[3].equationText() == "14 − 6 = ?")
        guard case let .numberTag(total, _, _)? = pictures[4].element("gap.tag")?.kind else { Issue.record("no total"); return }
        #expect(total == "8" && pictures[4].equationText() == "14 − 6 = 8" && pictures[4].elements("count.").isEmpty)
        // Counting, each square shows its count on itself (EXP-5).
        let (_, count) = e.watch(4, from: pictures.indices.dropLast().reduce(e.start) { e.watch($1, from: $0).state })
        let midway = count.picture(3 * BarGraphExplainer.T.cell + 0.3)
        #expect(midway.elements("count.").filter(\.isVisible).count == 4 && midway.element("gap.tag")?.isVisible == false)
    }

    @Test func readingTheBarsOffTheScale() {
        let e = CompareFixture.graph(14, 6)
        let k = 1
        let s = e.start
        let axis = BarGraphExplainer.L.axisY + 19
        // The bar's end: its line drops to the scale; the number is still hers to touch.
        let end = e.read(.tap(CGPoint(x: BarGraphExplainer.x(14), y: BarGraphExplainer.rowY(0) + 18)), step: k, s)
        #expect(end.state.dropped == [0] && end.state.read.isEmpty && !end.finished)
        #expect(end.motion?.script.events.last.map { if case let .say(l, true) = $0.action { l == e.line(.lands) } else { false } } == true)
        // Another number: a kind line saying which.
        let wrong = e.read(.tap(CGPoint(x: BarGraphExplainer.x(13), y: axis)), step: k, s)
        #expect(wrong.note == .miss(e.line(.wrongNumber(13, bar: 0))) && wrong.note.map { if case let .miss(l) = $0 { l.display } else { "" } } == "That's 13. Follow the apples bar.")
        let away = e.read(.tap(CGPoint(x: 500, y: 200)), step: k, s)
        #expect(away.note == .miss(e.line(.barMissed(bar: 0))))
        // Once the line has dropped, a miss points at the number it lands on, never back at the
        // bar's end, however many misses come first.
        let landedWrong = e.read(.tap(CGPoint(x: BarGraphExplainer.x(13), y: axis)), step: k, end.state)
        #expect(landedWrong.note == .miss(e.line(.landedWrong(13))))
        let landedAway = e.read(.tap(CGPoint(x: 500, y: 200)), step: k, landedWrong.state)
        #expect(landedAway.note == .miss(e.line(.landedMissed)) && landedAway.state.dropped == [0])
        let first = e.read(.tap(CGPoint(x: BarGraphExplainer.x(14) + 5, y: axis)), step: k, end.state)
        #expect(first.state.read == [0] && !first.finished)
        #expect(first.motion?.script.events.last.map { if case let .say(l, true) = $0.action { l == e.line(.nextBar(3)) } else { false } } == true)
        // The second bar starts over: its line has not dropped.
        let secondAway = e.read(.tap(CGPoint(x: 500, y: 200)), step: k, first.state)
        #expect(secondAway.note == .miss(e.line(.barMissed(bar: 3))))
        let second = e.read(.tap(CGPoint(x: BarGraphExplainer.x(6), y: axis)), step: k, first.state)
        #expect(second.finished && second.state.read == [0, 3])
    }

    @Test func drawingOnAndCountingTheSquares() throws {
        let e = CompareFixture.graph(14, 6)
        var s = e.watch(1, from: e.start).state
        // Along the numbers between the rings is as good as along a bar.
        let drawn = e.read(along(e.xs + 3, e.xb - 3, y: BarGraphExplainer.L.axisY + 19), step: 2, s)
        #expect(drawn.finished && drawn.state.gap)
        s = e.watch(3, from: drawn.state).state
        let b = e.begin(4, s)
        #expect(b.tally == Tally(0, of: 8, op: .result) && e.picture(b.state).element("gap.tag")?.isVisible == false)
        s = b.state
        let y = e.shorterY + 18
        let away = e.read(.tap(CGPoint(x: e.xs - 40, y: y)), step: 4, s)
        #expect(away.note == .miss(e.line(.countMissed)))
        var r = e.read(.tap(e.cell(5).origin.applying(CGAffineTransform(translationX: 10, y: 10))), step: 4, s)
        #expect(r.state.counted == [5] && r.interrupts)
        #expect(e.read(.tap(CGPoint(x: e.cell(5).midX, y: y)), step: 4, r.state).motion == nil, "a square counted once")
        for k in [0, 1, 2, 3, 4, 6, 7] { r = e.read(.tap(CGPoint(x: e.cell(k).midX, y: y)), step: 4, r.state) }
        #expect(r.finished && r.state.answered)
        let motion = try #require(r.motion)
        #expect(motion.end.element("gap.tag").map { if case let .numberTag(t, _, _) = $0.kind { t == "8" } else { false } } == true)
    }

    @Test func theAddingCardJoinsTheBarsLongerFirst() throws {
        let e = CompareFixture.graph(6, 14)
        var s = e.start
        for i in 0..<3 { s = e.watch(i, from: s).state }
        s = e.begin(3, s).state
        let add = try #require(e.cards.cards.first { $0.kind == .add }).rect
        #expect(e.picture(s).words("card.add.text") == "14 + 6 = ?")
        let r = e.read(.tap(CGPoint(x: add.midX, y: add.midY)), step: 3, s)
        let motion = try #require(r.motion)
        let mid = motion.picture(3.0)
        #expect(mid.equationText("joined.sum") == "14 + 6 = 20" && mid.element("gap") != nil)
        #expect(mid.element("title")?.transform == .identity && mid.element("bar.0")?.transform != .identity)
        #expect(motion.end.element("card.add")?.opacity == Look.goneOpacity)
    }

    /// What if? on the graph: only the dragged bar moves, and a release within 2 of an exact goal
    /// snaps to it (EXP-15).
    @Test func whatIfMovesOnlyTheDraggedBar() {
        let e = CompareFixture.graph(14, 6)
        guard let w = e.whatIf else { Issue.record("no What if?"); return }
        let start = e.goal(0, w.start).state
        let y = BarGraphExplainer.rowY(0) + 10
        func letGo(at v: Int) -> DraggedBar {
            let s = e.drag(.began(CGPoint(x: BarGraphExplainer.x(14), y: y)), goal: 0, start)
            return e.drag(.ended(CGPoint(x: BarGraphExplainer.x(v), y: y)), goal: 0, s)
        }
        let snapped = e.settle(goal: 0, letGo(at: 8), showMe: false)
        #expect(snapped.state.a == 6 && snapped.met != nil, "8 is 2 from 6, so it snaps to the same length")
        let open = e.settle(goal: 0, letGo(at: 9), showMe: false)
        #expect(open.state.a == 9 && open.met == nil, "9 is 3 from 6, too far to snap")
        let picture = e.picture(whatIf: open.state)
        #expect(picture.equationText() == "9 − 6 = 3" && picture.words("read.0.value") == "9")
        for i in 1...2 {
            guard case let .shape(.rect(r, _), _)? = picture.element("bar.\(i)")?.kind else { Issue.record("no bar \(i)"); continue }
            #expect(r.width == CGFloat(e.problem.bars[i]) * BarGraphExplainer.L.unit, "bar \(i) stays where it was")
        }
        let shown = e.settle(goal: 0, open.state, showMe: true)
        #expect(shown.state.a == 6 && shown.met != nil && shown.motion != nil, "Show me slides the bar to the goal")
    }

    @MainActor @Test func playsThroughEveryPart() throws {
        let voice = RecordingVoice()
        let lesson = BarGraphExplainer.lesson(watching: try BarGraphProblem(14, 6), wording: CompareFixture.graph())
        let p = GuidedPlayer(lesson: lesson, voice: voice, labels: Fixture.guidedLabels, drivesItself: false)
        p.primary()
        for _ in 0..<5 {
            p.settle(voice)
            p.primary()
        }
        #expect(p.part == .doWithMe)
        let e = lesson.doWithMe
        // Start: step 0 is watched and runs on into the child's.
        p.primary()
        p.settle(voice)
        #expect(p.phase == .doing(1))
        for (i, v) in [(e.problem.first, e.problem.a), (e.problem.second, e.problem.b)] {
            _ = i
            p.mark(.tap(CGPoint(x: BarGraphExplainer.x(v), y: BarGraphExplainer.L.axisY + 19)))
            p.settle(voice)
        }
        #expect(p.phase == .doing(2))
        p.mark(along(e.xs, e.xb, y: e.shorterY + 18))
        p.settle(voice)
        #expect(p.phase == .doing(3))
        let sub = try #require(e.cards.cards.first { $0.kind == .subtract }).rect
        p.mark(.tap(CGPoint(x: sub.midX, y: sub.midY)))
        p.settle(voice)
        #expect(p.phase == .doing(4))
        for k in 0..<e.problem.difference {
            p.mark(.tap(CGPoint(x: e.cell(k).midX, y: e.shorterY + 18)))
            p.settle(voice)
        }
        #expect(p.phase == .paused(4))
        p.primary()
        p.settle(voice)
        for g in 0..<3 {
            #expect(p.phase == .whatIf(goal: g, met: false))
            p.showMe()
            p.settle(voice)
        }
        #expect(p.phase == .whatIf(goal: 2, met: true))
        p.primary()
        #expect(p.phase == .tryOne)
    }
}
