import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

/// The two tens-and-ones templates (EXP-2, EXP-5, EXP-7, EXP-9, EXP-11).
struct TensOnesProblemTests {
    /// Reading takes a number from 10 to 99, and refuses any other.
    @Test func readingTakesTwoDigitNumbers() throws {
        #expect(TensOnesReading.all().map(\.number) == Array(10...99))
        let p = try TensOnesReading(47)
        #expect(p.tens == 4 && p.ones == 7)
        for n in [9, 100, 0, -1, 5, 120] {
            #expect(!TensOnesReading.accepts(n))
            #expect(throws: TensOnesReading.RangeError.number(n)) { try TensOnesReading(n) }
        }
    }

    /// Writing takes 1 to 9 tens and 0 to 19 ones making at most 99, and refuses any
    /// other values, saying which.
    @Test func writingTakesOneToNineTensAndUpToNineteenOnes() throws {
        var count = 0
        for t in -1...11 {
            for o in -2...22 {
                let ok = (1...9).contains(t) && (0...19).contains(o) && t * 10 + o <= 99
                #expect(TensOnesWriting.accepts(tens: t, ones: o) == ok, "\(t) tens \(o) ones")
                if ok { count += 1 }
            }
        }
        #expect(TensOnesWriting.all().count == count)
        #expect(throws: TensOnesWriting.RangeError.tens(0)) { try TensOnesWriting(tens: 0, ones: 5) }
        #expect(throws: TensOnesWriting.RangeError.tens(10)) { try TensOnesWriting(tens: 10, ones: 0) }
        #expect(throws: TensOnesWriting.RangeError.ones(20)) { try TensOnesWriting(tens: 1, ones: 20) }
        #expect(throws: TensOnesWriting.RangeError.ones(-1)) { try TensOnesWriting(tens: 1, ones: -1) }
        #expect(throws: TensOnesWriting.RangeError.total(100)) { try TensOnesWriting(tens: 9, ones: 10) }
        #expect(throws: TensOnesWriting.RangeError.total(105)) { try TensOnesWriting(tens: 9, ones: 15) }
        // Ten or more ones are bundled into a ten: 3 tens and 13 ones make 43.
        let b = try TensOnesWriting(tens: 3, ones: 13)
        #expect(b.bundles && b.tens == 4 && b.ones == 3 && b.number == 43)
        let c = try TensOnesWriting(tens: 8, ones: 19)
        #expect(c.number == 99)
        #expect(try TensOnesWriting(tens: 4, ones: 7).bundles == false)
    }

    /// The steps follow the values (EXP-2): a bundle only when writing with ten
    /// or more ones; the ones step even when there are none, to say so.
    @Test func theStepsFollowTheValues() throws {
        typealias S = TensOnesQuestion.Step
        #expect(TensOnesQuestion.reading(try TensOnesReading(47)).steps == [.tens, .ones, .total])
        #expect(TensOnesQuestion.reading(try TensOnesReading(40)).steps == [.tens, .ones, .total])
        #expect(TensOnesQuestion.writing(try TensOnesWriting(tens: 4, ones: 7)).steps == [.tens, .ones, .total])
        #expect(TensOnesQuestion.writing(try TensOnesWriting(tens: 3, ones: 13)).steps == [.bundle, .tens, .ones, .total])
        #expect(TensOnesQuestion.writing(try TensOnesWriting(tens: 1, ones: 10)).steps == [.bundle, .tens, .ones, .total])
    }
}

@MainActor
struct TensOnesMotionTests {
    typealias F = PlaceValueFixture

    /// EXP-11 and EXP-2: for every question both templates accept, in both drawings and both
    /// versions, every step's motion, computed to its end, is exactly its still picture, and it
    /// starts from the picture of the step before (bar the ring, which each step draws afresh).
    @Test func everyStepEndsOnItsStillPictureAndStartsFromTheLast() {
        for q in F.all {
            for version in ExplainerVersion.allCases {
                let e = TensOnesExplainer(question: q, version: version, wording: F.wording(version))
                for k in 0..<e.stepCount {
                    let d = e.script(for: k).duration
                    #expect(d > 0, "\(q) step \(k) has no motion")
                    if e.motion(step: k, at: d).scene(e) != e.still(after: k) {
                        Issue.record("\(q) \(version) step \(k) does not end on its still")
                        return
                    }
                    if unringed(e.still(after: k - 1)) != unringed(e.scene(step: k, at: 0)) {
                        Issue.record("\(q) \(version) step \(k) jumps at its start")
                        return
                    }
                }
            }
        }
    }

    /// EXP-2: every step at the range's edges plays in the player; every number shown is the
    /// model's; the counts are said in order; everything stays on the stage.
    @Test func everyStepPlaysAtTheEdges() {
        for e in F.edges {
            let q = e.question
            let end = e.still(after: e.stepCount - 1)
            #expect(total(end) == String(q.number), "\(q)")
            #expect(numeral(end)?.text == String(format: "%d%d", q.tens, q.ones), "\(q)")
            // Every ten and every one of the number is drawn and counted; a bundle's ten ones stay as ghosts.
            #expect(pieces(end, "ten.").count == q.tens)
            #expect(pieces(end, "ten.").allSatisfy { style($0) == .counted && $0.opacity == 1 }, "\(q)")
            let ones = pieces(end, "one.")
            #expect(ones.count == q.drawnOnes)
            #expect(ones.filter { $0.opacity == Components.ghostOpacity }.count == (q.bundles ? 10 : 0))
            #expect(ones.filter { style($0) == .counted && $0.opacity == 1 }.count == q.ones)
            for el in end.visible {
                switch el.kind {
                case let .ten(r, _), let .one(r, _), let .stick(r, _), let .circle(r, _), let .box(r, _, _), let .numberTag(_, r, _):
                    #expect(r.minX >= 0 && r.maxX <= Scene.stage.width && r.minY >= 0 && r.maxY <= Scene.stage.height, "\(q) \(el.id) at \(r)")
                default: break
                }
            }
            let voice = RecordingVoice()
            let player = ExplainerPlayer(explainer: e, voice: voice, drivesItself: false)
            for k in 0..<e.stepCount {
                player.primary()
                #expect(player.phase == .playing(k))
                player.playToPause(voice)
                #expect(player.phase == .paused(k))
            }
            let ticks = voice.said.filter { $0.key.contains(".tick(") }.map(\.display)
            let expected = TensOnesExplainer.counts(q, .tens) + TensOnesExplainer.counts(q, .ones)
            #expect(ticks == expected.map(String.init), "\(q)")
            #expect(voice.said.last?.emphasisRange != nil)
            #expect(player.caption == e.line(.answer))
        }
    }

    /// EXP-5: at most two things are marked at any moment of any step.
    @Test func noMoreThanTwoThingsAreMarked() {
        for e in F.edges {
            for k in 0..<e.stepCount {
                let d = e.script(for: k).duration
                for i in 0...120 {
                    let s = e.scene(step: k, at: d * Double(i) / 120)
                    #expect(s.markedCount <= 2, "\(e.question) step \(k) marks \(s.markedCount)")
                }
            }
        }
    }

    /// Each template draws in the style the problem names: rectangles and squares
    /// labelled underneath, or sticks and circles in a chart headed Tens | Ones, in pencil.
    @Test func eachTemplateDrawsInTheProblemsStyle() {
        for (blocks, chart) in [(F.reading(47, .blocks), F.reading(47, .chart)), (F.writing(3, 13, .blocks), F.writing(3, 13, .chart))] {
            let b = blocks.still(after: blocks.stepCount - 1)
            let c = chart.still(after: chart.stepCount - 1)
            #expect(b.visible.contains { if case .ten = $0.kind { true } else { false } })
            #expect(b.visible.contains { if case .one = $0.kind { true } else { false } })
            #expect(!b.visible.contains { if case .stick = $0.kind { true } else if case .circle = $0.kind { true } else { false } })
            #expect(c.visible.contains { if case .stick = $0.kind { true } else { false } })
            #expect(c.visible.contains { if case .circle = $0.kind { true } else { false } })
            #expect(!c.visible.contains { if case .ten = $0.kind { true } else if case .one = $0.kind { true } else { false } })
            #expect(text(b, "label.tens") == "tens" && text(b, "label.ones") == "ones")
            #expect(b.element("heading.tens") == nil && b.element("rule.places") == nil)
            #expect(text(c, "heading.tens") == "Tens" && text(c, "heading.ones") == "Ones")
            #expect(c.element("rule.heading") != nil && c.element("rule.places") != nil && c.element("label.tens") == nil)
            // The tens stand left of the chart's rule and the ones right of it.
            guard case let .rule(from, _) = c.element("rule.places")?.kind else { Issue.record("no rule"); continue }
            #expect(pieces(c, "ten.").allSatisfy { frame($0).maxX < from.x })
            #expect(pieces(c, "one.").allSatisfy { frame($0).minX > from.x })
        }
        // Before anything is counted the pieces are pencil, whichever the drawing (EXP-6).
        let before = F.writing(4, 7, .chart).still(after: -1)
        #expect(pieces(before, "ten.").allSatisfy { style($0) == .pencil })
        #expect(pieces(before, "one.").allSatisfy { style($0) == .pencil })
    }

    /// Reading 47, step for step.
    @Test func fortySevenIsHowManyTensAndOnes() {
        let e = F.reading(47)
        let L = e.layout
        // The number written with its digits together, printed; nothing drawn yet.
        let ready = e.still(after: -1)
        #expect(numeral(ready)?.text == "47")
        #expect(numeral(ready)?.digits.map(\.centerX) == [312, 378])
        #expect(numeral(ready)?.digits.allSatisfy { $0.role == .printed && $0.slot == nil } == true)
        #expect(numeral(ready)?.ring == nil)
        #expect(pieces(ready, "ten.").isEmpty && pieces(ready, "one.").isEmpty)
        #expect(total(ready) == nil)
        // tens: the ring goes round the 4 as the line is said, with "tens" under it, before any ten.
        let ringing = e.scene(step: 0, at: 0.3)
        #expect((numeral(ringing)?.ring?.progress ?? 0) > 0 && numeral(ringing)?.ring?.digit == 0)
        #expect(pieces(ringing, "ten.").isEmpty)
        let times = e.placeTimes(.tens)
        #expect(times.ticks.first == TensOnesExplainer.T.lead)
        // Each ten drops in, shows its count on itself, and keeps the counted fill.
        let first = e.scene(step: 0, at: times.ticks[0] + 0.15)
        #expect(tag(first, "tag.ten.0")?.text == "10")
        #expect(tag(first, "tag.ten.0").map { abs($0.rect.midX - L.tens[0].midX) < 0.001 && abs($0.rect.midY - L.tens[0].midY) < 0.001 } == true,
            "the count is on the ten itself")
        #expect(style(first.element("ten.0")!) == .counted)
        #expect(first.element("ten.1")!.opacity == 0)
        #expect(total(first) == "10")
        let third = e.scene(step: 0, at: times.ticks[2] + 0.15)
        #expect(tag(third, "tag.ten.2")?.text == "30" && total(third) == "30")
        #expect(third.element("tag.ten.0")!.opacity == 0, "a count shows only while its piece is counted")
        #expect(style(third.element("ten.0")!) == .counted, "a counted ten keeps its fill")
        let tens = e.still(after: 0)
        #expect(numeral(tens)?.ring?.digit == 0 && numeral(tens)?.ring?.word == "tens" && numeral(tens)?.ring?.progress == 1)
        #expect(total(tens) == "40")
        #expect(tens.elements("tag.").allSatisfy { $0.opacity == 0 })
        // ones: the ring moves to the 7; the total runs "40 + 1" … "40 + 7".
        let ones = e.placeTimes(.ones)
        #expect(e.scene(step: 1, at: 0.1).element("numeral").flatMap { el -> Int? in
            if case let .numeral(n) = el.kind { n.ring?.digit } else { nil }
        } == 1)
        #expect(total(e.scene(step: 1, at: 0.1)) == "40")
        #expect(total(e.scene(step: 1, at: ones.ticks[0] + 0.05)) == "40 + 1")
        #expect(tag(e.scene(step: 1, at: ones.ticks[6] + 0.1), "tag.one.6")?.text == "7")
        let afterOnes = e.still(after: 1)
        #expect(total(afterOnes) == "40 + 7")
        #expect(numeral(afterOnes)?.ring?.word == "ones")
        #expect(pieces(afterOnes, "one.").allSatisfy { style($0) == .counted })
        // total: "40 + 7" becomes 47, and stays under it.
        let tt = TensOnesExplainer.TotalTimes(e.question)
        #expect(total(e.scene(step: 2, at: tt.join - 0.01)) == "40 + 7")
        #expect(total(e.scene(step: 2, at: tt.join + 0.01)) == "47")
        let end = e.still(after: 2)
        #expect(total(end) == "47" && text(end, "worked") == "40 + 7")
        #expect(numeral(end)?.ring == nil, "nothing is ringed as the number is put together")
        // The lines.
        let says = (0..<3).flatMap { k in e.script(for: k).events.compactMap { ev -> String? in
            if case let .say(line, _) = ev.action { return line.display }
            return nil
        } }
        #expect(says == ["The 4 is in the tens place. It means 4 tens.", "10", "20", "30", "40",
            "The 7 is in the ones place. It means 7 ones.", "1", "2", "3", "4", "5", "6", "7",
            "Put them together.", "40 plus 7 is 47.", "47 is 4 tens and 7 ones!"])
        #expect(e.intro.display == "47. Let's find its tens and ones!")
    }

    /// No ones when the ones digit is 0: none drawn or counted, and the line says so.
    @Test func noOnesWhenTheOnesDigitIsZero() {
        for e in [F.reading(40), F.reading(40, .chart), F.writing(4, 0)] {
            for k in -1..<e.stepCount {
                #expect(pieces(e.still(after: k), "one.").isEmpty, "\(e.question) step \(k)")
            }
            #expect(e.placeTimes(.ones).ticks.isEmpty)
            #expect(total(e.still(after: 1)) == "40", "\(e.question): no '40 + 0'")
            let end = e.still(after: 2)
            #expect(total(end) == "40" && end.element("worked")!.opacity == 0)
            #expect(e.line(.ones).display.contains("no ones"))
            let total = e.script(for: 2).events.compactMap { ev -> String? in
                if case let .say(line, _) = ev.action { return line.display }
                return nil
            }
            #expect(total == ["Put them together.", "40.", e.line(.answer).display])
        }
        // Writing: the 0 is still written in the ones place.
        let w = F.writing(4, 0)
        #expect(numeral(w.still(after: 1))?.text == "40")
        #expect(numeral(w.still(after: 1))?.digits[1].role == .answer)
    }

    /// The ring is centred on the digit as drawn: on its ink, which sits off the middle of the
    /// box the face reserves for it, and not on that box.
    @Test func theRingIsCentredOnTheDigitsInk() throws {
        let face = ExplainerFonts.systemFace(CGFloat(Components.numeralSize))
        for n in [47, 10, 11, 74, 88, 19] {
            let e = F.reading(n)
            for (k, place) in [(0, 0), (1, 1)] {
                let numeral = try #require(numeral(e.still(after: k)))
                let ring = try #require(numeral.ring)
                #expect(ring.digit == place)
                let centre = try #require(Components.ringCentre(numeral, face: face))
                let digit = numeral.digits[place]
                let ink = Components.glyphs(digit.text, centerX: digit.centerX, baseline: numeral.baseline, face: face).ink
                #expect(!ink.isEmpty)
                #expect(abs(centre.x - ink.midX) < 0.001 && abs(centre.y - ink.midY) < 0.001, "\(n): ring at \(centre), ink \(ink)")
                // The ring goes round the whole digit.
                #expect(Components.ring(at: centre).insetBy(dx: -1, dy: -1).contains(ink), "\(n): ring \(Components.ring(at: centre)) ink \(ink)")
            }
        }
        // Writing: the place to write in is ringed on its slot.
        let w = F.writing(4, 7)
        let numeral = try #require(numeral(w.scene(step: 0, at: 0.3)))
        let slot = try #require(numeral.digits[0].slot)
        #expect(Components.ringCentre(numeral, face: face) == CGPoint(x: slot.midX, y: slot.midY))
        #expect(numeral.digits.map(\.text) == ["?", "?"] && numeral.digits.allSatisfy { $0.role == .unknown })
    }

    /// Writing 4 tens and 7 ones: the tens counted, then 4 written in its slot and said; the
    /// ones the same; and the line says what they make.
    @Test func fourTensAndSevenOnesMakeFortySeven() {
        let e = F.writing(4, 7)
        let ready = e.still(after: -1)
        #expect(pieces(ready, "ten.").count == 4 && pieces(ready, "one.").count == 7, "the pieces are drawn from the start")
        #expect(e.intro.display == "What number do these make? Let's see!")
        let times = e.placeTimes(.tens)
        let w = times.write!
        #expect(numeral(e.scene(step: 0, at: w - 0.01))?.digits[0].text == "?")
        let writing = e.scene(step: 0, at: w + 0.2)
        #expect(numeral(writing)?.digits[0].text == "4" && numeral(writing)?.digits[0].role == .answer)
        #expect((numeral(writing)?.digits[0].opacity ?? 1) < 1, "the digit is written in, not shown at once")
        let said = e.script(for: 0).events.compactMap { ev -> (Double, String)? in
            if case let .say(line, false) = ev.action, !line.key.contains("tick") { return (ev.time, line.display) }
            return nil
        }
        #expect(said.map(\.1) == ["4 tens."])
        #expect(said[0].0 >= w + TensOnesExplainer.T.write, "said once written")
        #expect(numeral(e.still(after: 1))?.text == "47")
        #expect(e.line(.answer).display == "4 tens and 7 ones make 47!")
    }

    /// 3 tens and 13 ones: ten ones are boxed, sent along an arrow into a new ten in
    /// the trade colour, and left as ghosts; the other three stand clear of the box.
    @Test func thirteenOnesAreBundledIntoATen() {
        for drawing in PlaceValueDrawing.allCases {
            let e = F.writing(3, 13, drawing)
            let L = e.layout
            #expect(e.steps == [.bundle, .tens, .ones, .total])
            // The ones past the first ten stand clear of the box.
            #expect(L.ones[10...].allSatisfy { $0.minX > L.box.maxX + 10 }, "\(drawing)")
            #expect(L.ones[..<10].allSatisfy { L.box.contains($0) })
            let ready = e.still(after: -1)
            #expect(pieces(ready, "ten.").count == 3, "the new ten is not there before the bundle")
            #expect(ready.element("box")!.isVisible == false && ready.element("arrow")!.isVisible == false)
            #expect(e.line(.bundle).display == "We have 13 ones. Ten ones make a ten!")
            let b = TensOnesExplainer.BundleTimes()
            // The box is drawn first, then the arrow from it to the new ten.
            let boxing = e.scene(step: 0, at: 0.35)
            #expect(progressOf(boxing, "box") > 0 && progressOf(boxing, "box") < 1 && progressOf(boxing, "arrow") == 0)
            let arrowing = e.scene(step: 0, at: b.arrow + 0.4)
            #expect(progressOf(arrowing, "box") == 1 && progressOf(arrowing, "arrow") > 0 && progressOf(arrowing, "arrow") < 1)
            guard case let .arrow(points, _, op) = arrowing.element("arrow")!.kind, case let .box(_, _, boxOp) = arrowing.element("box")!.kind else {
                Issue.record("no arrow or box")
                continue
            }
            #expect(op == .trade && boxOp == .trade)
            let newTen = L.tens[3]
            #expect(points.first!.x == L.box.midX && points.last!.x == newTen.midX && points.last!.y < newTen.minY)
            // Copies of the ten ones, in the trade colour, rise to the arrow, follow it and stack into the new ten.
            let top = L.arrowY - Components.oneSide / 2
            for i in [0, 5, 9] {
                let start = b.travelStart(i)
                let path = (0...1500).map { frame(e.scene(step: 0, at: start + TensOnesExplainer.T.travel * Double($0) / 1500).element("copy.\(i)")!) }
                #expect(path.first!.origin == L.ones[i].origin)
                #expect(path.contains { abs($0.minY - top) < 0.5 && abs($0.midX - L.box.midX) < 0.5 }, "copy \(i) rises to the arrow over the box")
                #expect(path.contains { abs($0.minY - top) < 0.5 && abs($0.midX - newTen.midX) < 0.5 }, "copy \(i) follows the arrow to the new ten")
                #expect(path.last!.origin == L.intoTen(i), "copy \(i) ends in the new ten")
                #expect(newTen.insetBy(dx: -2, dy: -2).contains(path.last!), "copy \(i) is inside the new ten")
                #expect(style(e.scene(step: 0, at: start + 0.5).element("copy.\(i)")!) == .traded)
            }
            #expect(b.travelStart(0) < b.travelStart(9), "one after another")
            // The new ten appears in the trade colour; the ten ones are ghosts, never erased.
            let bundled = e.still(after: 0)
            #expect(style(bundled.element("ten.3")!) == .traded && bundled.element("ten.3")!.opacity == 1)
            #expect((0..<10).allSatisfy { bundled.element("one.\($0)")!.opacity == Components.ghostOpacity })
            #expect((10..<13).allSatisfy { bundled.element("one.\($0)")!.opacity == 1 })
            #expect(bundled.elements("copy.").allSatisfy { !$0.isVisible })
            #expect(progressOf(bundled, "box") == 1 && progressOf(bundled, "arrow") == 1)
            // Then four tens are counted and three ones, and 43 is written.
            #expect(TensOnesExplainer.counts(e.question, .tens) == [10, 20, 30, 40])
            #expect(TensOnesExplainer.counts(e.question, .ones) == [1, 2, 3])
            let oneTimes = e.placeTimes(.ones)
            let firstOne = e.scene(step: 2, at: oneTimes.ticks[0] + 0.1)
            #expect(style(firstOne.element("one.10")!) == .counted && style(firstOne.element("one.0")!) == .pencil,
                "the ones counted are the ones left, not the ghosts")
            #expect(tag(firstOne, "tag.one.0").map { abs($0.rect.midX - L.ones[10].midX) < 0.001 } == true)
            let end = e.still(after: 3)
            #expect(total(end) == "43" && numeral(end)?.text == "43")
            #expect(style(end.element("ten.3")!) == .counted, "the new ten is counted with the others")
            #expect(e.line(.answer).display == "4 tens and 3 ones make 43!")
        }
    }

    /// The parent version plays the same steps; its dots skip ahead, Next finishes a
    /// step at once; its counts are shown and not said, at most half the learner's time.
    @Test func theParentVersionSkipsAheadAndCountsFaster() {
        for (child, parent) in [(F.reading(47), F.reading(47, .blocks, .parent)), (F.writing(3, 13), F.writing(3, 13, .blocks, .parent)),
            (F.reading(99, .chart), F.reading(99, .chart, .parent))]
        {
            #expect(parent.steps == child.steps)
            for s in [TensOnesQuestion.Step.tens, .ones] {
                let (c, p) = (child.placeTimes(s), parent.placeTimes(s))
                #expect(p.countEnd - TensOnesExplainer.T.lead <= (c.countEnd - TensOnesExplainer.T.lead) / 2 + 1e-9)
                let k = parent.steps.firstIndex(of: s)!
                let says = parent.script(for: k).events.filter { if case let .say(line, _) = $0.action { line.key.contains("tick") } else { false } }
                #expect(says.isEmpty, "the parent's counts are not said")
                #expect(parent.motion(step: k, at: parent.script(for: k).duration).scene(parent) == parent.still(after: k))
            }
            // The dots jump to any step; Next finishes the step playing, on its last line.
            let voice = RecordingVoice()
            let player = ExplainerPlayer(explainer: parent, voice: voice, drivesItself: false)
            player.jump(to: parent.stepCount - 1)
            #expect(player.phase == .playing(parent.stepCount - 1))
            player.primary()
            #expect(player.phase == .paused(parent.stepCount - 1))
            #expect(player.caption == parent.line(.answer))
            #expect(player.scene == parent.still(after: parent.stepCount - 1))
            // The learner's dots are not controls.
            let childPlayer = ExplainerPlayer(explainer: child, voice: RecordingVoice(), drivesItself: false)
            childPlayer.jump(to: 1)
            #expect(childPlayer.phase == .ready)
        }
    }

    // MARK: reading a scene

    private func unringed(_ s: Scene) -> Scene {
        var s = s
        for i in s.elements.indices {
            if case var .numeral(n) = s.elements[i].kind {
                n.ring = nil
                s.elements[i].kind = .numeral(n)
            }
        }
        return Scene(elements: s.visible)
    }

    private func pieces(_ s: Scene, _ prefix: String) -> [SceneElement] { s.visible.filter { $0.id.hasPrefix(prefix) } }

    private func frame(_ e: SceneElement) -> CGRect {
        switch e.kind {
        case let .ten(r, _), let .one(r, _), let .stick(r, _), let .circle(r, _): r
        default: .null
        }
    }

    private func style(_ e: SceneElement) -> PieceStyle? {
        switch e.kind {
        case let .ten(_, s), let .one(_, s), let .stick(_, s), let .circle(_, s): s
        default: nil
        }
    }

    private func numeral(_ s: Scene) -> Numeral? {
        if case let .numeral(n) = s.element("numeral")?.kind { return n }
        return nil
    }

    private func total(_ s: Scene) -> String? {
        guard let e = s.element("total"), e.isVisible, case let .total(text, _, _) = e.kind else { return nil }
        return text
    }

    private func text(_ s: Scene, _ id: String) -> String? {
        guard let e = s.element(id), e.isVisible, case let .text(text, _, _) = e.kind else { return nil }
        return text
    }

    private func tag(_ s: Scene, _ id: String) -> (text: String, rect: CGRect)? {
        guard let e = s.element(id), e.isVisible, case let .numberTag(text, rect, _) = e.kind else { return nil }
        return (text, rect)
    }

    private func progressOf(_ s: Scene, _ id: String) -> Double {
        switch s.element(id)?.kind {
        case let .box(_, p, _), let .arrow(_, p, _): p
        default: -1
        }
    }
}
