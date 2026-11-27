import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript

// The explainer camera (EXP-18) on `BarExplainer` given a motion file read in the test. A step
// names a shot and the drawing eases to it with the motion file's duration and easing; what is
// out of shot is dimmed by the style's amount; touches are read through the camera, so a framed
// piece is a larger target; Reduce Motion cuts. A move runs while a line is said, lands before
// the learner is asked to act, and never moves while the learner draws.

@MainActor
struct CameraTests {
    static let area = CGSize(width: 800, height: 600)

    /// Shots on the bar and on the count's number. `grow` and `slide` leave their camera to the
    /// style's defaults; `count` moves late and linearly.
    static let motionFile = """
        { "format": "explainer-motion", "version": 1, "explainer": "bar",
          "shots": { "whole": { "region": [0, 0, 1000, 540], "margin": 0 },
                     "bar": { "frame": ["bar"], "margin": 30 },
                     "count": { "region": [700, 420, 200, 120], "margin": 10 } },
          "opening": "whole",
          "steps": { "show": { "shot": "whole" },
                     "grow": { "shot": "bar" },
                     "slide": { "shot": "bar" },
                     "count": { "shot": "count", "camera": { "at": 0.2, "duration": 1, "easing": "linear" } } } }
        """

    /// The style with the dimming a camera test reads.
    static let style = ExplainerStyle.read(Data(#"{ "motion": { "camera": { "dim": 0.45 } } }"#.utf8))

    static func motion(_ json: String = motionFile, style: ExplainerStyle = style) -> ExplainerMotion {
        BarExplainer.motion(json, style: style)
    }

    static func explainer(_ json: String = motionFile, style: ExplainerStyle = style) -> BarExplainer {
        BarExplainer(length: 6, laysOut: true, motion: motion(json, style: style)).laidOut(for: area)
    }

    /// The child version of a bar, laid out for the area; do it with me, with every doable step
    /// the learner's, on the second bar. Returns the player, its voice and the second bar.
    static func player(reduceMotion: Bool = false, fading: Int = .max) -> (GuidedPlayer, RecordingVoice, BarExplainer) {
        let v = RecordingVoice()
        let lesson = BarExplainer.lesson(whatIf: false, laysOut: true, motion: motion())
        let p = GuidedPlayer(
            lesson: lesson, voice: v, labels: Fixture.guidedLabels, fading: fading, reduceMotion: reduceMotion, drivesItself: false)
        p.layOut(for: area)
        return (p, v, lesson.doWithMe.laidOut(for: area))
    }

    // MARK: shots

    @Test func aStepEasesToItsShotWithTheMotionFilesDurationAndEasing() {
        let e = Self.explainer()
        let plan = e.plan!
        let whole = plan.camera("whole")
        let bar = plan.camera("bar")
        #expect(whole != bar && bar.view.width < whole.view.width, "the bar is framed closer")
        let before = e.apply(0, e.start)
        let (after, motion) = e.watch(1, from: before)
        let move = e.motion!.steps["grow"]!.camera
        let style = Self.style.camera
        #expect(move.at == style.at && move.duration == style.duration && move.easingName == style.easing, "the style's defaults")
        #expect(motion.picture(0).camera == whole, "the step starts on the shot before it")
        for f in [0.25, 0.5, 0.75] {
            let t = move.at + move.duration * f
            #expect(motion.picture(t).camera == Camera.between(whole, bar, move.easing(f)), "at \(f) of the move")
        }
        #expect(motion.picture(move.end).camera?.view == bar.view, "it has landed")
        #expect(motion.end.camera == bar && e.picture(after, marking: 1).camera == bar)
        // The move comes first; the step's own picture changes once it lands.
        #expect(motion.picture(move.end - 0.01).element("grown") == nil, "nothing else moves while the camera does")
        #expect(motion.picture(motion.script.duration).element("grown") != nil)
        #expect(motion.script.duration == 1 + move.end)
        #expect(motion.cameraMoves == [move.at...move.end], "the player is told when the camera moves")

        // Another motion file's duration and easing, with no change to the explainer's code.
        let slowFile = Self.motionFile.replacingOccurrences(
            of: "\"count\": { \"shot\": \"count\", \"camera\": { \"at\": 0.2, \"duration\": 1, \"easing\": \"linear\" } }",
            with: "\"count\": { \"shot\": \"count\", \"camera\": { \"at\": 0, \"duration\": 2, \"easing\": \"linear\" } }")
        let slow = Self.explainer(slowFile)
        let slowMove = slow.motion!.steps["count"]!.camera
        #expect(slowMove.duration == 2 && slowMove.easing == .linear)
        let from = slow.apply(2, slow.apply(1, slow.apply(0, slow.start)))
        let counted = slow.watch(3, from: from).motion
        #expect(counted.picture(1).camera == Camera.between(plan.camera("bar"), slow.plan!.camera("count"), 0.5), "linear, half way at 1 of 2 seconds")
        #expect(counted.script.duration == 1 + 2)
    }

    @Test func whatIsOutOfShotIsDimmedByTheStylesAmount() {
        let e = Self.explainer()
        let s = e.apply(1, e.apply(0, e.start))
        var counted = s
        counted.counted = true
        let framed = e.picture(counted, marking: nil)
        guard let camera = framed.camera else { Issue.record("no camera"); return }
        #expect(camera.dim == Self.style.camera.dim)
        #expect(camera.dimming(of: framed.element("counted")!) == camera.dim, "a number far out of shot")
        #expect(camera.dimming(of: framed.element("grown")!) == camera.dim, "a piece far out of shot")
        #expect(camera.dimming(of: framed.element("label")!) == 0, "a label in shot")
        #expect(camera.dimming(of: framed.element("question")!) == 0, "what stays fixed is never dimmed")
        // The whole drawing dims nothing.
        let whole = e.picture(e.apply(0, e.start), marking: nil)
        #expect(whole.camera!.focus == nil && whole.elements.allSatisfy { whole.camera!.dimming(of: $0) == 0 })
        // Dimming fades in past the edge of the focus, so a piece just outside is dimmed less.
        let focus = camera.focus!
        let edge = SceneElement("edge", .label("edge", at: CGPoint(x: focus.maxX + Camera.feather / 2, y: focus.midY)))
        #expect(abs(camera.dimming(of: edge) - camera.dim / 2) < 1e-9)
        // A style with another amount.
        let dimmer = Self.explainer(style: ExplainerStyle.read(Data(#"{ "motion": { "camera": { "dim": 0.7 } } }"#.utf8)))
        let d = dimmer.picture(dimmer.apply(1, dimmer.apply(0, dimmer.start)), marking: nil)
        #expect(d.camera!.dimming(of: d.element("grown")!) == 0.7)
    }

    @Test func touchesMapThroughTheCameraSoAFramedPieceIsALargerTarget() {
        let e = Self.explainer()
        let whole = e.picture(e.apply(0, e.start), marking: nil)
        let framed = e.picture(e.apply(1, e.apply(0, e.start)), marking: nil)
        let small = whole.screenRect(e.end, in: Self.area)
        let large = framed.screenRect(e.end, in: Self.area)
        #expect(large.width > small.width * 1.5, "framed, the end is \(large.width) points; whole, \(small.width)")
        // A touch where the end is drawn is read on it, in either shot.
        for scene in [whole, framed] {
            let r = scene.screenRect(e.end, in: Self.area)
            let p = scene.scenePoint(CGPoint(x: r.midX, y: r.midY), in: Self.area)
            #expect(abs(p.x - e.end.midX) < 1e-6 && abs(p.y - e.end.midY) < 1e-6)
        }

        // Do it with me: a tap where the end was before the camera moved misses; a tap on the
        // end where it is shown grows the bar.
        let (p, v, d) = Self.player()
        p.jump(to: .doWithMe)
        p.jump(toStep: 1)
        p.settle(v)
        #expect(p.phase == .doing(1) && p.readsMarks)
        Self.tap(p, whole.screenRect(d.end, in: Self.area))
        #expect(p.phase == .doing(1) && p.note != nil, "the tap lands elsewhere through the camera")
        Self.tap(p, p.scene.screenRect(d.end, in: Self.area))
        #expect(Self.wait(p, v) { p.phase == .doing(2) }, "the tap on the end on screen grew the bar, and the next step opened")
    }

    @Test func withReduceMotionTheCameraCutsToEachShot() {
        let (p, v, e) = Self.player(reduceMotion: true)
        let plan = e.plan!
        p.primary()
        p.settle(v)
        p.primary()
        #expect(p.phase == .playing(1))
        #expect(p.scene.camera == plan.camera("bar"), "the shot at once, while the line is said")
        // In do it with me, the step the learner does is framed at once as its instruction is said.
        p.jump(to: .doWithMe)
        p.jump(toStep: 3)
        #expect(p.listening && p.scene.camera == plan.camera("count"))
    }

    // MARK: when the camera moves

    @Test func aCameraMoveRunsWhileItsLineIsSaid() {
        let (p, v, e) = Self.player()
        let plan = e.plan!
        let grow = e.motion!.steps["grow"]!.camera
        p.primary()
        p.settle(v)
        p.primary()
        p.advance(by: grow.duration / 2)
        #expect(v.busy && v.said.last == BarExplainer.line("watch.grow", "Watch grow."), "the step's line is being said")
        let camera = p.scene.camera!
        #expect(camera != plan.camera("whole") && camera != plan.camera("bar"), "while the camera moves")
        p.settle(v)
        #expect(p.phase == .paused(1) && p.scene.camera == plan.camera("bar"))

        // A step the learner does: the camera moves while its instruction is said.
        p.jump(to: .doWithMe)
        p.jump(toStep: 3)
        let count = e.motion!.steps["count"]!.camera
        p.advance(by: count.end / 2)
        #expect(p.listening && v.said.last == e.instruction(3, e.start))
        #expect(p.scene.camera != plan.camera("count"), "still moving as the instruction is said")
        p.settle(v)
        #expect(p.scene.camera == plan.camera("count") && p.readsMarks, "landed before the learner can act")
    }

    /// At every moment the learner can first mark, the camera has landed on the step's shot;
    /// while each of the learner's marks is made, the camera does not move.
    @Test func theCameraLandsBeforeTheLearnerActsAndNeverMovesWhileSheMarks() {
        let (p, v, e) = Self.player()
        let plan = e.plan!
        p.jump(to: .doWithMe)
        p.primary()
        // Show plays, then the beat, then the first step the learner does is introduced.
        #expect(Self.wait(p, v) { p.phase == .doing(1) && p.readsMarks }, "the learner's first step opens")
        #expect(p.scene.camera == plan.camera("bar"), "grow: framed and landed")
        Self.tap(p, p.scene.screenRect(e.end, in: Self.area))
        // Slide: dragged from the bar past x = 600 in the drawing's units.
        #expect(Self.wait(p, v) { p.phase == .doing(2) && p.readsMarks }, "the second opens")
        #expect(p.scene.camera == plan.camera("bar"), "slide: still framed")
        Self.drag(p, v, from: CGPoint(x: 130, y: 220), to: CGPoint(x: 650, y: 220))
        // Count: the camera moves to the number while the instruction is said, then the learner touches.
        #expect(Self.wait(p, v) { p.phase == .doing(3) && p.readsMarks }, "the third opens")
        #expect(p.scene.camera == plan.camera("count"), "count: framed and landed")
        Self.tap(p, p.scene.screenRect(CGRect(x: 780, y: 450, width: 40, height: 60), in: Self.area))
        #expect(Self.wait(p, v) { p.phase == .paused(3) })
    }

    @Test func aTouchRestingOnTheDrawingHoldsTheCamera() {
        let (p, v, e) = Self.player()
        let plan = e.plan!
        p.primary()
        p.settle(v)
        // The next step moves the camera from the whole drawing to the bar as it begins.
        p.primary()
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

    /// Runs the clock in frames, finishing each line as it is said, until `done`; false if it
    /// does not come.
    static func wait(_ p: GuidedPlayer, _ v: RecordingVoice, limit: Int = 5_000, until done: () -> Bool) -> Bool {
        var frames = 0
        while !done(), frames < limit {
            p.advance(by: 1.0 / 60)
            v.finish()
            frames += 1
        }
        return done()
    }

    /// Taps the middle of `screen`, a rectangle on screen.
    static func tap(_ p: GuidedPlayer, _ screen: CGRect) {
        let at = p.scene.scenePoint(CGPoint(x: screen.midX, y: screen.midY), in: area)
        p.touchBegan(at: at)
        p.touchEnded(at: at)
    }

    /// Drags from `start` to `end`, in the drawing's units, with time passing, checking the
    /// camera does not move under the drag.
    static func drag(_ p: GuidedPlayer, _ v: RecordingVoice, from start: CGPoint, to end: CGPoint) {
        let camera = p.scene.camera
        p.touchBegan(at: start)
        for step in 1...3 {
            for _ in 0..<6 {
                p.advance(by: 1.0 / 60)
                v.finish()
            }
            #expect(p.scene.camera == camera, "the camera moved while the learner dragged")
            let f = CGFloat(step) / 3
            p.touchMoved(to: CGPoint(x: start.x + (end.x - start.x) * f, y: start.y + (end.y - start.y) * f))
        }
        p.touchEnded(at: end)
    }
}
