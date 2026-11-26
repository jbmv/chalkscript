import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript

// The explainer screen (EXP-17). Its arrangement in the space it is given,
// the question apart from the drawing, the drawing area given to the explainer, and the palm
// rule. The sizes are the explainer's space in an authoring app (the screen less the status
// bar, the navigation bar, the authoring app's Jump to and its margins) on the iPad mini (744 by 1133
// points) and the 13-inch iPad Pro (1032 by 1376).

@MainActor
struct ScreenTests {
    /// The explainer's space in the authoring app on a screen of `w` by `h` points: 16-point margins,
    /// a 24-point status bar, a 50-point navigation bar and the 44-point Jump to row.
    static func space(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w - 32, height: h - 24 - 50 - 44 - 32) }

    static let screens: [(name: String, portrait: CGSize, landscape: CGSize)] = [
        ("iPad mini", space(744, 1133), space(1133, 744)),
        ("iPad Pro 13-inch", space(1032, 1376), space(1376, 1032)),
    ]

    @Test func portraitIsTopToBottomAndLandscapeHasAColumnOnTheWritingHandsSide() {
        for (name, portrait, landscape) in Self.screens {
            for hand in WritingHand.allCases {
                #expect(ScreenArrangement.choose(for: portrait, hand: hand) == .portrait, "\(name) portrait")
                guard case let .column(width, onLeft) = ScreenArrangement.choose(for: landscape, hand: hand) else {
                    Issue.record("\(name) landscape has no column")
                    continue
                }
                #expect(onLeft == (hand == .left), "\(name): the column is on the \(hand) hand's side")
                #expect(width >= ScreenArrangement.minColumn && width <= landscape.width * ScreenArrangement.maxColumnShare)
                // The drawing has the rest of the width at full height: about square or taller.
                let drawing = CGSize(width: landscape.width - width, height: landscape.height)
                #expect(drawing.width <= drawing.height * 1.15, "\(name): the drawing is \(drawing)")
            }
        }
        #expect(ScreenArrangement.choose(for: CGSize(width: 800, height: 360), hand: .right) == .scroll, "a phone in landscape scrolls")
    }

    @Test func aDrawingNotLaidOutAgainIsScaledToFitAndCentred() {
        let scene = Scene()
        #expect(scene.size == Scene.stage)
        // A tall area: the stage is as wide as the area and centred top to bottom.
        let tall = CGSize(width: 700, height: 900)
        let (s, origin) = scene.fit(in: tall)
        #expect(abs(s - 0.7) < 1e-9 && origin.x == 0 && abs(origin.y - (900 - 540 * 0.7) / 2) < 1e-9)
        // A wide area: as tall as the area and centred side to side.
        let (s2, origin2) = scene.fit(in: CGSize(width: 1400, height: 540))
        #expect(s2 == 1 && origin2 == CGPoint(x: 200, y: 0))
        // A touch in the area is read in scene units, through the same fit.
        let p = scene.scenePoint(CGPoint(x: 350, y: 450), in: tall)
        #expect(abs(p.x - 500) < 1e-9 && abs(p.y - 270) < 1e-9, "the area's centre is the stage's")
    }

    @Test func theDrawingAreaIsGivenToTheExplainer() {
        let area = CGSize(width: 680, height: 820)
        // An explainer laid out again draws for the area it is given, in every part.
        let laid = GuidedPlayer(
            lesson: BarExplainer.lesson(laysOut: true), voice: RecordingVoice(), labels: Fixture.guidedLabels, drivesItself: false)
        #expect(laid.drawingArea == nil && laid.scene.size == Scene.stage)
        laid.layOut(for: area)
        #expect(laid.drawingArea == area && laid.scene.size == area, "the picture now is drawn again for the area")
        laid.jump(toStep: 1)
        #expect(laid.scene.size == area, "and every step after it")
        laid.jump(to: .whatIf)
        #expect(laid.scene.size == area)
        // An explainer not laid out again keeps its stage, which the screen fits and centres.
        let plain = GuidedPlayer(
            lesson: BarExplainer.lesson(), voice: RecordingVoice(), labels: Fixture.guidedLabels, drivesItself: false)
        plain.layOut(for: area)
        #expect(plain.drawingArea == area && plain.scene.size == Scene.stage)
    }

    @Test func theQuestionIsShownApartOnlyWhenTheExplainerGivesIt() {
        let asks = GuidedPlayer(
            lesson: BarExplainer.lesson(asks: true), voice: RecordingVoice(), labels: Fixture.guidedLabels, drivesItself: false)
        #expect(asks.question?.display == "How long is a bar of 5?")
        asks.jump(to: .doWithMe)
        #expect(asks.question?.display == "How long is a bar of 6?", "each part asks its own problem's question")
        asks.jump(to: .tryOne)
        #expect(asks.question?.display == "How long is a bar of 7?")
        // The explainers so far keep their question in the drawing: no question area.
        let plain = GuidedPlayer(
            lesson: BarExplainer.lesson(), voice: RecordingVoice(), labels: Fixture.guidedLabels, drivesItself: false)
        #expect(plain.question == nil)
    }

    /// A palm on the column's controls while the Pencil writes presses nothing.
    @Test func aPalmTouchDuringAStrokePressesNothing() {
        final class Clock { var t = 100.0 }
        let clock = Clock()
        let v = RecordingVoice()
        let p = GuidedPlayer(lesson: BarExplainer.lesson(), voice: v, labels: Fixture.guidedLabels, drivesItself: false)
        p.palm.now = { clock.t }
        p.press(.primary)
        p.settle(v)
        #expect(p.phase == .paused(0) && p.primaryControl == .next)

        // The Pencil writes on the drawing; the palm comes down on Next, then on Again.
        p.touchBegan(at: CGPoint(x: 300, y: 300))
        p.touchMoved(to: CGPoint(x: 360, y: 320))
        for control in GuidedPlayer.ColumnControl.allCases {
            p.pressBegan(control)
            p.press(control)
        }
        #expect(p.phase == .paused(0) && !p.whyShown, "nothing was pressed while the Pencil was down")

        // Just after the Pencil lifts, the controls still ignore a touch.
        clock.t += 0.2
        p.touchEnded(at: CGPoint(x: 420, y: 340))
        clock.t += PalmGuard.quiet / 2
        p.pressBegan(.again)
        p.press(.again)
        #expect(p.phase == .paused(0), "a touch just after the stroke is the writing hand's")

        // A palm that came down during the stroke and lifts later still presses nothing.
        p.touchBegan(at: CGPoint(x: 300, y: 300))
        p.pressBegan(.primary)
        clock.t += 0.5
        p.touchEnded(at: CGPoint(x: 300, y: 380))
        clock.t += PalmGuard.quiet * 3
        p.press(.primary)
        #expect(p.phase == .paused(0), "the press began while the Pencil was down")

        // A fresh touch once the hand is clear is a press.
        p.pressBegan(.primary)
        p.press(.primary)
        #expect(p.phase == .playing(1), "a deliberate press goes on")
    }

    /// A touch on the drawing that is cancelled rather than lifted lets the controls go.
    @Test func aCancelledTouchDoesNotLeaveTheControlsHeld() {
        final class Clock { var t = 100.0 }
        let clock = Clock()
        let v = RecordingVoice()
        let p = GuidedPlayer(lesson: BarExplainer.lesson(), voice: v, labels: Fixture.guidedLabels, drivesItself: false)
        p.palm.now = { clock.t }
        p.press(.primary)
        p.settle(v)
        p.touchBegan(at: CGPoint(x: 300, y: 300))
        #expect(p.palm.holds)
        p.touchCancelled()
        #expect(p.palm.holds, "the quiet still applies after a cancel, as after a lift")
        clock.t += PalmGuard.quiet + 0.1
        #expect(!p.palm.holds, "and no longer")
        p.pressBegan(.primary)
        p.press(.primary)
        #expect(p.phase == .playing(1), "the control works after the cancelled touch")
    }

    /// A touch that never reports its end cannot hold the rule for ever.
    @Test func aTouchThatNeverEndsCannotHoldTheRuleForLong() {
        final class Clock { var t = 100.0 }
        let clock = Clock()
        let palm = PalmGuard()
        palm.now = { clock.t }
        palm.penDown()
        clock.t += PalmGuard.stuckAfter - 1
        #expect(palm.holds, "a touch that lasts holds")
        palm.penDown()
        clock.t += PalmGuard.stuckAfter - 1
        #expect(palm.holds, "a moving touch renews it")
        clock.t += 2
        #expect(!palm.holds, "a touch that has gone quiet and never ended lets go")
    }

    @Test func thePalmGuardAloneHoldsForAFingerToo() {
        final class Clock { var t = 0.0 }
        let clock = Clock()
        let palm = PalmGuard()
        palm.now = { clock.t }
        #expect(!palm.holds && palm.accepts("again"))
        palm.penDown()
        #expect(palm.holds)
        palm.pressBegan("again")
        palm.penUp()
        clock.t += PalmGuard.quiet + 0.1
        #expect(!palm.holds && !palm.accepts("again"), "voided at its start")
        palm.pressBegan("again")
        #expect(palm.accepts("again"))
    }
}
