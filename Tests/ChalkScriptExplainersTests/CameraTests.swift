import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

// The explainer camera (EXP-18) on subtraction laid out for the iPad mini in
// landscape. A step names a shot and the drawing eases to it with its motion file's duration and
// easing; what is out of shot is dimmed by the style's amount; touches are read through the
// camera, so a framed piece is a larger target; Reduce Motion cuts. A move runs while a line is
// said, lands before the learner is asked to act, and never moves while the learner draws.

@MainActor
struct CameraTests {
    static let area = SubtractionScreenTests.miniLandscape

    static func explainer(_ a: Int = 54, _ b: Int = 26, motion: ExplainerMotion = SubtractionExplainer.standardMotion) -> SubtractionExplainer {
        SubtractionExplainer(problem: try! SubtractionProblem(a, minus: b), version: .child, wording: Fixture.guidedWording(), motion: motion)
            .laidOut(for: area)
    }

    func step(_ e: SubtractionExplainer, _ s: SubtractionProblem.Step) -> Int { e.steps.firstIndex(of: s)! }

    // MARK: shots

    @Test func aStepEasesToItsShotWithTheMotionFilesDurationAndEasing() {
        let e = Self.explainer()
        let plan = e.frame!.plan
        let k = step(e, .short)
        let move = e.move(.short)
        #expect(move.duration == ExplainerStyle.standard.camera.duration && move.easingName == "smooth", "the style's defaults")
        let whole = plan.camera("whole")
        let ones = plan.camera("ones")
        #expect(whole != ones && ones.view.width < whole.view.width, "the ones are framed closer")
        #expect(e.scene(step: k, at: 0).camera == whole, "the step starts on the shot before it")
        for f in [0.25, 0.5, 0.75] {
            let t = move.at + move.duration * f
            #expect(e.scene(step: k, at: t).camera == Camera.between(whole, ones, move.easing(f)), "at \(f) of the move")
        }
        #expect(e.scene(step: k, at: move.end).camera?.view == ones.view, "it has landed")
        #expect(e.still(after: k).camera == ones)
        // The move comes first; the step's own motion (the digit's mark) starts once it lands.
        let early = e.scene(step: k, at: move.end - 0.01)
        guard case let .equation(eq)? = early.element("equation")?.kind else { Issue.record("no equation"); return }
        #expect((eq.mark?.progress ?? 0) == 0, "nothing else moves while the camera does")
        #expect(e.script(for: k).duration == e.ownScript(k).duration + move.end)

        // Another motion file's duration and easing, with no change to the explainer's code.
        var json = Self.bundledMotion
        json = json.replacingOccurrences(
            of: "\"short\": {\n      \"shot\": \"ones\",", with: "\"short\": {\n      \"shot\": \"ones\",\n      \"camera\": { \"duration\": 2, \"easing\": \"linear\" },")
        let slow = Self.explainer(motion: SubtractionExplainer.motion(Data(json.utf8)))
        #expect(slow.move(.short).duration == 2 && slow.move(.short).easing == .linear)
        #expect(slow.scene(step: k, at: 1).camera == Camera.between(whole, ones, 0.5), "linear, half way at 1 of 2 seconds")
        #expect(slow.script(for: k).duration == e.ownScript(k).duration + 2)
    }

    static let bundledMotion = String(decoding: ExplainerResources.data("subtraction-motion", in: ContentBundle.bundle) ?? Data(), as: UTF8.self)

    @Test func whatIsOutOfShotIsDimmedByTheStylesAmount() {
        let e = Self.explainer()
        let ones = e.still(after: step(e, .short))
        guard let camera = ones.camera else { Issue.record("no camera"); return }
        #expect(camera.dim == ExplainerStyle.standard.camera.dim)
        #expect(camera.dimming(of: ones.element("ten.0")!) == camera.dim, "a ten far out of shot")
        #expect(camera.dimming(of: ones.element("one.0")!) == 0, "a one in shot")
        #expect(camera.dimming(of: ones.element("equation")!) == 0, "the problem is never dimmed")
        // The whole drawing dims nothing.
        let whole = e.still(after: 0)
        #expect(whole.elements.allSatisfy { whole.camera!.dimming(of: $0) == 0 })
        // A style with another amount.
        let style = ExplainerStyle.read(Data(#"{ "motion": { "camera": { "dim": 0.7 } } }"#.utf8))
        let dimmer = Self.explainer(motion: SubtractionExplainer.motion(Data(Self.bundledMotion.utf8), style: style))
        let s = dimmer.still(after: step(e, .short))
        #expect(s.camera!.dimming(of: s.element("ten.0")!) == 0.7)
    }

    @Test func touchesMapThroughTheCameraSoAFramedPieceIsALargerTarget() {
        let e = Self.explainer()
        let one = e.layout.looseOnes[0]
        let whole = e.still(after: 0)
        let framed = e.still(after: step(e, .short))
        let small = whole.screenRect(one, in: Self.area)
        let large = framed.screenRect(one, in: Self.area)
        #expect(large.width > small.width * 1.5, "framed, a one is \(large.width) points; whole, \(small.width)")
        // A touch where the one is drawn is read on the one, in either shot.
        for scene in [whole, framed] {
            let r = scene.screenRect(one, in: Self.area)
            let p = scene.scenePoint(CGPoint(x: r.midX, y: r.midY), in: Self.area)
            #expect(abs(p.x - one.midX) < 1e-6 && abs(p.y - one.midY) < 1e-6)
        }

        // Do it with me: a line drawn across where a one is shown crosses it out.
        let (p, v, d) = Self.doWithMe(fading: .max)
        let k = step(d, .takeOnes)
        p.jump(toStep: k)
        p.settle(v)
        #expect(p.phase == .doing(k) && p.readsMarks)
        let target = d.keptOnes(d.state(after: k - 1)).map(d.rect)[0]
        Self.draw(p, v, across: p.scene.screenRect(target, in: Self.area))
        #expect(p.tally?.done == 1, "the line across the one on screen crossed it out")
    }

    @Test func withReduceMotionTheCameraCutsToEachShot() {
        let e = Self.explainer()
        let v = RecordingVoice()
        let p = GuidedPlayer(
            lesson: GuidedLesson(watch: e, doWithMe: e, tryOne: e), voice: v, labels: Fixture.guidedLabels, reduceMotion: true,
            drivesItself: false)
        p.layOut(for: Self.area)
        p.primary()
        p.settle(v)
        p.primary()
        #expect(p.phase == .playing(1))
        #expect(p.scene.camera == e.frame!.plan.camera("ones"), "the shot at once, while the line is said")
        // In do it with me, the step the learner does is framed at once as its instruction is said.
        p.jump(to: .doWithMe)
        let k = step(e, .takeTens)
        p.jump(toStep: k)
        #expect(p.listening && p.scene.camera == e.frame!.plan.camera("tens"))
    }

    // MARK: when the camera moves

    @Test func aCameraMoveRunsWhileItsLineIsSaid() {
        let e = Self.explainer()
        let v = RecordingVoice()
        let p = GuidedPlayer(lesson: GuidedLesson(watch: e, doWithMe: e, tryOne: e), voice: v, labels: Fixture.guidedLabels, drivesItself: false)
        p.layOut(for: Self.area)
        p.primary()
        p.settle(v)
        p.primary()
        let k = step(e, .short)
        p.advance(by: e.move(.short).duration / 2)
        #expect(v.busy && v.said.last == e.line(.short), "the step's line is being said")
        let camera = p.scene.camera!
        #expect(camera != e.frame!.plan.camera("whole") && camera != e.frame!.plan.camera("ones"), "while the camera moves")
        p.settle(v)
        #expect(p.phase == .paused(k) && p.scene.camera == e.frame!.plan.camera("ones"))

        // A step the learner does: the camera moves while its instruction is said.
        p.jump(to: .doWithMe)
        let t = step(e, .takeTens)
        p.jump(toStep: t)
        p.advance(by: e.move(.takeTens).duration / 2)
        #expect(p.listening && v.said.last == e.instruction(t, e.state(after: t - 1)))
        #expect(p.scene.camera != e.frame!.plan.camera("tens"), "still moving as the instruction is said")
    }

    /// The child version of 54 - 26, every step of do it with me the child's: at every moment
    /// the learner can first mark, the camera has landed on the step's shot; while each of the
    /// learner's lines is drawn and while a touch rests on the drawing, the camera does not move.
    @Test func theCameraLandsBeforeTheChildActsAndNeverMovesWhileSheDraws() {
        let (p, v, e) = Self.doWithMe(fading: .max)
        let plan = e.frame!.plan
        p.primary()
        var s = e.start
        var frames = 0
        var acted: Set<SubtractionProblem.Step> = []
        while p.part == .doWithMe, frames < 40_000 {
            frames += 1
            if p.phase == .paused(e.steps.count - 1), !p.moving, !v.busy { break }
            guard case let .doing(k) = p.phase, p.readsMarks else {
                p.advance(by: 1.0 / 60)
                v.finish()
                continue
            }
            let st = e.steps[k]
            if !acted.contains(st) {
                acted.insert(st)
                // Framed, and landed, before the learner is asked to act.
                let expected = st == .count ? (e.motion.steps["count"]?.doShot ?? e.shot(st)) : e.shot(st)
                #expect(p.scene.camera == plan.camera(expected), "\(st): the camera has not landed on \(expected ?? "-")")
                if st != .show { s = e.state(after: k - 1) }
                if st == .count { s.gathered = true }
            }
            // The learner's next mark, drawn where the piece is on screen.
            let (mark, next) = Self.nextMark(e, k, s)
            s = next
            let r = p.scene.screenRect(mark, in: Self.area)
            if st == .count { Self.touch(p, v, r) } else { Self.draw(p, v, across: r) }
        }
        #expect(acted == [.trade, .takeOnes, .takeTens, .count], "the child did every step: \(acted)")
        #expect(p.phase == .paused(e.steps.count - 1) || p.part != .doWithMe)
    }

    @Test func aTouchRestingOnTheDrawingHoldsTheCamera() {
        // The learner does only the count; the steps before it play on by themselves.
        let (p, v, e) = Self.doWithMe(fading: 1)
        let plan = e.frame!.plan
        p.primary()
        // Show plays, then the beat, then the short step's move to the ones.
        var frames = 0
        while p.phase != .playing(1), frames < 5_000 {
            p.advance(by: 1.0 / 60)
            v.finish()
            frames += 1
        }
        #expect(p.phase == .playing(1))
        let before = p.scene.camera
        #expect(before == plan.camera("whole"))
        p.touchBegan(at: CGPoint(x: 300, y: 300))
        for _ in 0..<180 {
            p.advance(by: 1.0 / 60)
            v.finish()
        }
        #expect(p.scene.camera == before, "a palm on the drawing holds the camera")
        p.touchEnded(at: CGPoint(x: 300, y: 300))
        for _ in 0..<120 {
            p.advance(by: 1.0 / 60)
            v.finish()
        }
        #expect(p.scene.camera != before, "it moves once the hand lifts")
    }

    // MARK: helpers

    /// The child version on 54 - 26 (do it with me on its isomorph), laid out for the area; the
    /// player is at the start of do it with me. Returns the do-it-with-me explainer, laid out.
    static func doWithMe(fading: Int) -> (GuidedPlayer, RecordingVoice, SubtractionExplainer) {
        let lesson = SubtractionExplainer.lesson(watching: try! SubtractionProblem(54, minus: 26), wording: Fixture.guidedWording())
        let v = RecordingVoice()
        let p = GuidedPlayer(lesson: lesson, voice: v, labels: Fixture.guidedLabels, fading: fading, drivesItself: false)
        p.layOut(for: area)
        p.jump(to: .doWithMe)
        return (p, v, lesson.doWithMe.laidOut(for: area))
    }

    /// The piece the learner marks next on step `k` from `s`, and the state after it.
    static func nextMark(_ e: SubtractionExplainer, _ k: Int, _ s: SubtractionState) -> (CGRect, SubtractionState) {
        var n = s
        switch e.steps[k] {
        case .trade:
            let i = e.wholeTens(s).last!
            n.tradedTen = i
            return (e.layout.tens[i], n)
        case .takeOnes:
            let r = e.keptOnes(s)[0]
            n.onesGone.append(r)
            return (e.rect(r), n)
        case .takeTens:
            let i = e.wholeTens(s).last!
            n.tensGone.append(i)
            return (e.layout.tens[i], n)
        case .count:
            let i = (0..<e.countCount).first { !s.counted.contains($0) }!
            n.counted.insert(i)
            return (e.countRects[i], n)
        default:
            return (.zero, s)
        }
    }

    /// Draws a line across `screen` (a piece's rectangle on screen) as GuidedView passes it on:
    /// each point read through the scene shown at that moment, with time passing, checking the
    /// camera does not move under it.
    static func draw(_ p: GuidedPlayer, _ v: RecordingVoice, across screen: CGRect) {
        let points = [
            CGPoint(x: screen.minX - 8, y: screen.maxY + 8), CGPoint(x: screen.midX, y: screen.midY),
            CGPoint(x: screen.maxX + 8, y: screen.minY - 8),
        ]
        let camera = p.scene.camera
        p.touchBegan(at: p.scene.scenePoint(points[0], in: area))
        for point in points.dropFirst() {
            for _ in 0..<6 {
                p.advance(by: 1.0 / 60)
                v.finish()
            }
            #expect(p.scene.camera == camera, "the camera moved while a line was drawn")
            p.touchMoved(to: p.scene.scenePoint(point, in: area))
        }
        p.touchEnded(at: p.scene.scenePoint(points.last!, in: area))
    }

    /// Touches the middle of `screen`.
    static func touch(_ p: GuidedPlayer, _ v: RecordingVoice, _ screen: CGRect) {
        let at = p.scene.scenePoint(CGPoint(x: screen.midX, y: screen.midY), in: area)
        p.touchBegan(at: at)
        p.touchEnded(at: at)
        // A count said in answer is cut off by the next touch, as fast taps are (EXP-10).
        for _ in 0..<45 {
            p.advance(by: 1.0 / 60)
            v.finish()
        }
    }
}
