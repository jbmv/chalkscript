import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

// What subtraction asks of the explainer camera (EXP-18), laid out for the iPad mini in
// landscape: the shot each step names, the move's timing from its motion file, what is dimmed in
// each shot, and the shot the learner's steps are framed on. The camera itself (easing, dimming,
// touches through it, holding it while the learner draws, Reduce Motion) is tested in the
// engine's tests, on a synthetic explainer.

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
        // A style with another amount.
        let style = ExplainerStyle.read(Data(#"{ "motion": { "camera": { "dim": 0.7 } } }"#.utf8))
        let dimmer = Self.explainer(motion: SubtractionExplainer.motion(Data(Self.bundledMotion.utf8), style: style))
        let s = dimmer.still(after: step(e, .short))
        #expect(s.camera!.dimming(of: s.element("ten.0")!) == 0.7)
    }

    /// The child version of 54 - 26, every step of do it with me the child's: at every moment
    /// the learner can first mark, the camera has landed on the shot the step names.
    @Test func theCameraLandsOnEachStepsShotBeforeTheChildActs() {
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
    /// each point read through the scene shown at that moment, with time passing.
    static func draw(_ p: GuidedPlayer, _ v: RecordingVoice, across screen: CGRect) {
        let points = [
            CGPoint(x: screen.minX - 8, y: screen.maxY + 8), CGPoint(x: screen.midX, y: screen.midY),
            CGPoint(x: screen.maxX + 8, y: screen.minY - 8),
        ]
        p.touchBegan(at: p.scene.scenePoint(points[0], in: area))
        for point in points.dropFirst() {
            for _ in 0..<6 {
                p.advance(by: 1.0 / 60)
                v.finish()
            }
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
