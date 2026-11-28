import CoreGraphics
import Foundation
import Testing
import struct ChalkScript.Scene
@testable import ChalkScript

// An action that ends as the clock holds for the voice is drawn finished for the whole hold
// (EXP-10, EXP-19): the picture held at a wait shows the moment just before it, so that what
// begins there is not yet shown, and what ends there must still be complete.

@MainActor
struct HoldTests {
    /// A document with a step that says a line of eight words at 0, runs `first` (which ends at 1 s)
    /// and then draws `rule` as an action that waits for the voice, at 1 s.
    func explainer(first: String) throws -> DocumentExplainer {
        var doc = DocumentFixture.tiny
        doc = doc.setting("/elements/ray", try JSONValue.parse(
            #"{"kind": "arrow", "from": [0, 50], "to": [100, 50], "ink": "result", "start": {"progress": 0}}"#))
        doc = doc.setting("/steps/show/actions", try JSONValue.parse(#"""
            {
              "first": \#(first),
              "later": {"do": "draw", "target": "rule", "at": "end(first)", "dur": 0.5, "wait": "voice"}
            }
            """#))
        let d = try #require(ExplainerDocument.read(doc.data).document)
        #expect(d.conforms, "\(d.findings)")
        return try DocumentExplainer(document: d, problem: DocumentFixture.values(("a", 1)))
    }

    /// Plays step 0 on the stand-in voice, which takes time, until the clock reaches the wait at 1 s
    /// and has held there for a moment, and returns the player.
    func held(_ e: DocumentExplainer) throws -> ExplainerPlayer {
        let p = ExplainerPlayer(explainer: e, voice: EstimatedVoice(), drivesItself: false)
        p.show(step: 0)
        while p.time < 1 { p.advance(by: 0.01) }
        #expect(p.voiceBusy, "the line is still being said")
        p.advance(by: 0.3)
        #expect(p.time == 1, "the clock holds at the first action's end while the line is heard")
        return p
    }

    @Test func aDrawnArrowThatEndsAtAHoldIsCompleteWithItsHeadForTheWholeHold() throws {
        let e = try explainer(first: #"{"do": "draw", "target": "ray", "at": 0, "dur": 1}"#)
        let p = try held(e)
        guard case let .arrow(_, progress, _)? = p.scene.element("ray")?.kind else {
            Issue.record("the ray is drawn as an arrow")
            return
        }
        #expect(progress == 1, "the stage draws an arrow's head at progress 1")
    }

    @Test(arguments: [
        #"{"do": "draw", "target": "ray", "at": 0, "dur": 1}"#,
        #"{"do": "appear", "target": "label", "at": 0, "dur": 1, "rise": 20}"#,
        #"{"do": "fade", "target": "label", "to": 0.5, "at": 0, "dur": 1}"#,
        #"{"do": "move", "target": "label", "to": [300, 200], "at": 0, "dur": 1}"#,
        #"{"do": "draw", "target": "ray", "at": 0.5, "dur": 0.5, "ease": "linear"}"#,
    ])
    func everyVerbIsFinishedWhereItEndsAtAHold(first: String) throws {
        let e = try explainer(first: first)
        let p = try held(e)
        #expect(p.scene == e.scene(step: 0, at: 1), "the held picture is the picture at the hold's start: \(first)")
    }

    @Test func anActionThatBeginsAtTheHoldIsNotYetShown() throws {
        let e = try explainer(first: #"{"do": "draw", "target": "ray", "at": 0, "dur": 1}"#)
        let p = try held(e)
        guard case let .shape(_, paint)? = p.scene.element("rule")?.kind else {
            Issue.record("the rule is drawn as a shape")
            return
        }
        #expect(paint.progress == 0, "what begins at the wait is shown with the line said after it")
    }

    @Test func anActionStillBeingDrawnJustBeforeTheHoldIsNotFinished() throws {
        let e = try explainer(first: #"{"do": "draw", "target": "ray", "at": 0, "dur": 1}"#)
        guard case let .arrow(_, progress, _)? = e.scene(step: 0, at: 0.9).element("ray")?.kind else {
            Issue.record("the ray is drawn as an arrow")
            return
        }
        #expect(progress < 1)
    }

    @Test func theCameraHasLandedWhereItsMoveEndsAtAHold() throws {
        let e = try DocumentExplainer(
            document: DocumentFixture.subtraction, problem: DocumentFixture.values(("a", 54), ("b", 26)), wording: "everyday",
            area: CGSize(width: 660, height: 760))
        let lead = e.resolved.steps[1].lead
        #expect(lead > 0)
        let held = Motion.wait(heldAt: lead - Motion.beforeWait, in: [0.4, lead])
        #expect(held == lead)
        #expect(e.camera(1, at: lead - Motion.beforeWait, holdingAt: held) == e.camera(1, at: lead))
        // Played through, without a hold there, the camera is still short of it a moment before.
        #expect(e.camera(1, at: lead - Motion.beforeWait) != e.camera(1, at: lead))
    }
}

@MainActor
struct HeldMomentTests {
    @Test func aMomentIsHeldOnlyWhenItIsTheMomentJustBeforeAWait() {
        #expect(Motion.wait(heldAt: 1 - Motion.beforeWait, in: [0.5, 1, 2]) == 1)
        #expect(Motion.wait(heldAt: 1, in: [0.5, 1, 2]) == nil)
        #expect(Motion.wait(heldAt: 1.5, in: []) == nil)
    }
}
