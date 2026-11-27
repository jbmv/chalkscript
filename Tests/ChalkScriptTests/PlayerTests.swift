import Foundation
import Testing
@testable import ChalkScript
import struct ChalkScript.Scene

/// The paced player (EXP-8, EXP-9, EXP-11), on `SteppedExplainer`: four steps, the last a count
/// that waits for the voice at each number.
@MainActor
struct PlayerTests {
    let voice = RecordingVoice()

    func player(_ version: ExplainerVersion = .child, reduceMotion: Bool = false) -> ExplainerPlayer {
        ExplainerPlayer(explainer: SteppedExplainer(version: version), voice: voice, reduceMotion: reduceMotion, drivesItself: false)
    }

    @Test func itStartsWithWatchAndTheIntroduction() {
        let p = player()
        #expect(p.phase == .ready)
        #expect(p.primaryControl == .watch)
        #expect(p.caption.display == "Four steps.")
        #expect(!p.againEnabled)
        #expect(p.dots == Array(repeating: .upcoming, count: 4))
        #expect(voice.said.isEmpty, "nothing is said before Watch")
        // No step starts until the learner asks (EXP-8).
        p.advance(by: 30)
        #expect(p.phase == .ready)
    }

    /// Each step plays its motion and says its line, then stops on its finished picture and
    /// waits; nothing runs ahead.
    @Test func eachStepPlaysAndWaits() {
        let p = player()
        p.primary()
        #expect(p.phase == .playing(0))
        #expect(p.primaryControl == nil, "the large control is hidden while a step plays")
        #expect(p.caption.display == "Step 0.")
        #expect(voice.said.map(\.display) == ["Step 0."])
        // The motion ends, but the step waits for its line to be heard.
        p.advance(by: 30)
        #expect(p.phase == .playing(0))
        voice.finish()
        #expect(p.phase == .paused(0))
        #expect(p.scene == p.explainer.still(after: 0))
        #expect(p.primaryControl == .next)
        // Paused, the clock does nothing.
        p.advance(by: 30)
        #expect(p.phase == .paused(0))
        #expect(voice.said.count == 1)
        #expect(p.dots == [.current] + Array(repeating: .upcoming, count: 3))
    }

    @Test func nextOrATapOnTheDrawingPlaysTheNextStep() {
        let p = player()
        p.primary()
        p.playToPause(voice)
        p.tapDrawing()
        #expect(p.phase == .playing(1))
        // A tap while a step plays is ignored: no step runs ahead.
        p.tapDrawing()
        p.primary()
        #expect(p.phase == .playing(1))
        p.playToPause(voice)
        p.primary()
        #expect(p.phase == .playing(2))
        #expect(p.dots == [.done, .done, .current, .upcoming])
    }

    /// Again replays the paused step; pressed while a step plays it goes back one step, so
    /// repeated presses go back further.
    @Test func againReplaysOrGoesBack() {
        let p = player()
        p.primary()
        for _ in 0..<2 {
            p.playToPause(voice)
            p.primary()
        }
        p.playToPause(voice)
        #expect(p.phase == .paused(2))
        let said = voice.said.count
        p.again()
        #expect(p.phase == .playing(2))
        #expect(p.time == 0)
        #expect(p.scene == p.explainer.scene(step: 2, at: 0), "it replays from the picture before the step")
        #expect(voice.said.count == said + 1 && voice.said.last?.display == "Step 2.", "the line is said again")
        // While it plays, Again goes back one, then another.
        p.advance(by: 0.2)
        p.again()
        #expect(p.phase == .playing(1))
        #expect(voice.stops > 0, "the line playing is cut off")
        p.again()
        #expect(p.phase == .playing(0))
        p.again()
        p.again()
        #expect(p.phase == .playing(0), "no further back than the first step")
        p.playToPause(voice)
        p.again()
        #expect(p.phase == .playing(0))
    }

    @Test func theLastStepOffersWatchAgain() {
        let p = player()
        for _ in 0..<4 {
            p.primary()
            p.playToPause(voice)
        }
        #expect(p.phase == .paused(3))
        #expect(p.primaryControl == .watchAgain)
        #expect(p.caption.display == "Counted 3!")
        #expect(p.caption.emphasisRange.map { String(p.caption.display[$0]) } == "3")
        p.primary()
        #expect(p.phase == .playing(0))
    }

    /// The learner's dots are not controls; the parent's are (EXP-9).
    @Test func onlyTheParentsDotsAreControls() {
        let child = player(.child)
        child.jump(to: 2)
        #expect(child.phase == .ready)
        let parent = player(.parent)
        parent.jump(to: 2)
        #expect(parent.phase == .playing(2))
        #expect(parent.scene == parent.explainer.scene(step: 2, at: 0))
        parent.jump(to: 9)
        #expect(parent.phase == .playing(2))
    }

    /// With Reduce Motion on, each step shows its finished picture at once, and only its lines
    /// take time (EXP-11).
    @Test func reduceMotionShowsTheStillPictures() {
        let p = player(reduceMotion: true)
        p.primary()
        for k in 0..<4 {
            #expect(p.phase == .playing(k))
            #expect(p.scene == p.explainer.still(after: k), "step \(k) shows its still at once")
            // No time passes, only the lines are heard.
            var guardCount = 0
            while case .playing = p.phase, guardCount < 100 {
                voice.finish()
                p.advance(by: 0)
                #expect(p.scene == p.explainer.still(after: k))
                guardCount += 1
            }
            #expect(p.phase == .paused(k))
            #expect(p.scene == p.explainer.still(after: k))
            if k < 3 { p.primary() }
        }
        // The same lines are said as with motion.
        let moving = RecordingVoice()
        let q = ExplainerPlayer(explainer: SteppedExplainer(), voice: moving, drivesItself: false)
        for _ in 0..<4 {
            q.primary()
            q.playToPause(moving)
        }
        #expect(voice.said == moving.said)
    }

    /// With narration muted the pacing still holds: each step plays and waits (EXP-10).
    @Test func mutedNarrationKeepsThePacing() {
        let p = ExplainerPlayer(explainer: SteppedExplainer(), voice: SilentVoice(), drivesItself: false)
        p.primary()
        p.advance(by: 0.5)
        #expect(p.phase == .playing(0))
        p.advance(by: 30)
        #expect(p.phase == .paused(0))
        #expect(p.caption.display == "Step 0.")
    }

    /// Lines never overlap: each is sent once the one before it has been heard.
    @Test func linesAreSaidOneAtATime() {
        let p = player()
        for _ in 0..<4 {
            p.primary()
            // RecordingVoice fails the test if a line is sent while another is being said.
            p.playToPause(voice, frame: 0.25)
        }
        // One line for each of the first three steps; the count says its line, three numbers and its last line.
        #expect(voice.said.count == 3 + 1 + 3 + 1)
    }

    /// The count waits for each word, so the pieces are counted in time with the voice.
    @Test func theCountHoldsForTheVoice() {
        let p = player()
        for _ in 0..<3 {
            p.primary()
            p.playToPause(voice)
        }
        p.primary()
        #expect(p.phase == .playing(3))
        let ticks = SteppedExplainer.ticks
        // The step's line is still being said: the clock holds at the first count.
        p.advance(by: 30)
        #expect(p.time == ticks[0])
        voice.finish()
        #expect(voice.said.last?.display == "1")
        p.advance(by: 30)
        #expect(p.time == ticks[1], "the next count waits for the first to be heard")
    }

    /// In the parent version Next is offered while a step plays and finishes it at
    /// once, on its finished picture and its last line, silencing what it was saying (EXP-9).
    @Test func theParentsNextFinishesAPlayingStep() {
        let p = player(.parent)
        p.primary()
        #expect(p.phase == .playing(0))
        #expect(p.primaryControl == .next, "the parent's Next is offered while a step plays")
        #expect(!p.waiting)
        p.advance(by: 0.1)
        let stops = voice.stops
        p.primary()
        #expect(p.phase == .paused(0), "Next finishes the step at once")
        #expect(p.scene == p.explainer.still(after: 0))
        #expect(voice.stops > stops, "what the step was saying is cut off")
        #expect(p.waiting)
        // Paused, Next plays the next step, as in the child version.
        p.primary()
        #expect(p.phase == .playing(1))
        // A tap on the drawing does what Next does.
        p.tapDrawing()
        #expect(p.phase == .paused(1))
        // The count, finished at once, ends on its last line, which is the caption, and the
        // numbers and lines it had still to say are not said.
        p.jump(to: 3)
        #expect(p.phase == .playing(3))
        let said = voice.said.count
        p.primary()
        #expect(p.phase == .paused(3))
        #expect(p.scene == p.explainer.still(after: 3))
        #expect(p.caption.display == "Counted 3!")
        #expect(voice.said.count == said)
        #expect(p.primaryControl == .watchAgain)
        // Nothing is left running: the clock does nothing more.
        p.advance(by: 30)
        voice.finish()
        #expect(p.phase == .paused(3))
    }

    /// The child version keeps its pacing: Next is hidden while a step plays (EXP-8).
    @Test func theChildsNextIsHiddenWhileAStepPlays() {
        let p = player(.child)
        p.primary()
        #expect(p.primaryControl == nil)
        p.primary()
        #expect(p.phase == .playing(0))
    }

    /// The parent's dots jump to any step, forward or back, while one plays or is
    /// paused (EXP-9).
    @Test func theParentsDotsJumpToAnyStep() {
        let p = player(.parent)
        for target in [3, 1, 2, 0, 1] {
            p.jump(to: target)
            #expect(p.phase == .playing(target))
            #expect(p.scene == p.explainer.scene(step: target, at: 0), "step \(target) starts from the picture before it")
            if target.isMultiple(of: 2) { p.playToPause(voice) }
        }
        p.playToPause(voice)
        #expect(p.phase == .paused(1))
        #expect(p.scene == p.explainer.still(after: 1))
    }

    @Test func stopSilencesAndShowsTheFinishedPicture() {
        let p = player()
        p.primary()
        p.advance(by: 0.1)
        p.stop()
        #expect(p.phase == .paused(0))
        #expect(voice.stops > 0)
        p.advance(by: 10)
        #expect(p.phase == .paused(0))
    }
}
