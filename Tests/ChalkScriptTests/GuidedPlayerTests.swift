import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript

// The child version's player runs watch, do it with me (EXP-14), What if? (EXP-15)
// and try one, with Why? on a step (EXP-16), and a step that counts aloud says its line before
// it moves (EXP-10). Played on BarExplainer (Fixtures.swift), which has every optional part.

@MainActor
struct GuidedPlayerTests {
    func make(fading: Int = .max, whatIf: Bool = true) -> (GuidedPlayer, RecordingVoice) {
        let voice = RecordingVoice()
        let player = GuidedPlayer(
            lesson: BarExplainer.lesson(whatIf: whatIf), voice: voice, labels: Fixture.guidedLabels, fading: fading,
            drivesItself: false)
        return (player, voice)
    }

    /// Runs the clock and the voice until the player reaches `phase`, without finishing a line
    /// said as it gets there.
    func runOn(_ p: GuidedPlayer, _ v: RecordingVoice, to phase: GuidedPlayer.Phase, limit: Int = 20_000) {
        var frames = 0
        while p.phase != phase, frames < limit {
            v.finish()
            p.advance(by: 1.0 / 60)
            frames += 1
        }
        #expect(p.phase == phase)
    }

    /// Plays watch to its end.
    func watchAll(_ p: GuidedPlayer, _ v: RecordingVoice) {
        p.primary()
        p.settle(v)
        while case let .paused(k) = p.phase, k < p.steps.count - 1 {
            p.primary()
            p.settle(v)
        }
    }

    @Test func watchPlaysEachStepAndWaitsThenOffersDoItWithMe() {
        let (p, v) = make()
        #expect(p.part == .watch && p.phase == .ready && p.primaryControl == .watch)
        #expect(p.caption.display == "A bar of 5.")
        #expect(p.parts == [.watch, .doWithMe, .whatIf, .tryOne])
        #expect(!p.againEnabled)
        p.primary()
        #expect(p.phase == .playing(0) && p.primaryControl == nil, "the child's Next is hidden while a step plays")
        p.settle(v)
        #expect(p.phase == .paused(0) && p.primaryControl == .next)
        #expect(p.scene.element("label")?.opacity == 1)
        watchAll(p, v)
        #expect(p.phase == .paused(3) && p.primaryControl == .doWithMe)
        #expect(p.dots.allSatisfy { !$0.childDoes }, "nothing is the child's in watch")
    }

    @Test func againReplaysOrGoesBackInWatch() {
        let (p, v) = make()
        p.primary()
        p.settle(v)
        p.primary()
        #expect(p.phase == .playing(1))
        p.again()
        #expect(p.phase == .playing(0), "Again while a step plays goes back one")
        p.settle(v)
        p.again()
        #expect(p.phase == .playing(0), "Again on a paused step replays it")
    }

    @Test func aStepThatCountsAloudSaysItsLineBeforeItMoves() {
        let (p, v) = make()
        watchAll(p, v)
        p.again()  // replay the last step, which counts aloud
        #expect(p.phase == .playing(3))
        for _ in 0..<120 { p.advance(by: 1.0 / 60) }
        #expect(p.moving && p.scene.element("counted") == nil, "the clock waits at the start while the line is said")
        v.finish()
        p.settle(v)
        #expect(p.phase == .paused(3) && p.scene.element("counted") != nil)
    }

    @Test func fadingRunsBackward() {
        #expect(make(fading: 1).0.doSet == [3], "first time: only the last doable step")
        #expect(make(fading: 2).0.doSet == [2, 3])
        #expect(make().0.doSet == [1, 2, 3])
    }

    @Test func doItWithMeWaitsForTheInstructionThenReadsMarks() {
        let (p, v) = make(fading: 3)
        watchAll(p, v)
        p.primary()
        #expect(p.part == .doWithMe && p.phase == .ready && p.primaryControl == .start)
        #expect(p.dots.map(\.childDoes) == [false, true, true, true])
        p.primary()
        runOn(p, v, to: .paused(0))  // step 0 is watched
        // No Next in do it with me: a beat, then the next step by itself; Again stays.
        #expect(p.primaryControl == nil && p.againEnabled && !p.whyOffered)
        p.primary()
        p.tapDrawing()
        #expect(p.phase == .paused(0), "nothing skips the beat")
        for _ in 0..<Int(GuidedPlayer.beat * 60) - 3 { p.advance(by: 1.0 / 60) }
        #expect(p.phase == .paused(0), "the beat lasts \(GuidedPlayer.beat) s")
        runOn(p, v, to: .doing(1))
        #expect(p.listening)
        #expect(p.showMeOffered, "Show me is on screen during a step the child does")
        let bar = BarExplainer(length: 6)
        // A mark made while the instruction is said is ignored (EXP-14).
        p.mark(.tap(CGPoint(x: bar.end.midX, y: bar.end.midY)))
        #expect(p.phase == .doing(1) && p.scene.element("grown") == nil)
        v.finish()
        #expect(!p.listening && p.readsMarks && p.tally == Tally(0, of: 1))
        // A miss: a kind line, said; the second adds Show me and makes it pulse.
        p.mark(.tap(CGPoint(x: 900, y: 500)))
        #expect(p.note?.display == "Touch the end of the bar." && !p.showMeUrged)
        #expect(v.said.last?.display == "Touch the end of the bar.")
        p.mark(.stroke([CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)]))
        #expect(p.note?.display == "Touch the end of the bar. Or tap Show me." && p.showMeUrged)
        // The mark the step wants: the step is done, and after a beat the explainer goes on by
        // itself to the next step.
        p.mark(.tap(CGPoint(x: bar.end.midX, y: bar.end.midY)))
        runOn(p, v, to: .paused(1))
        #expect(p.scene.element("grown") != nil && p.primaryControl == nil)
        #expect(p.note == nil && p.tally == nil && !p.showMeOffered)
        runOn(p, v, to: .doing(2))
    }

    @Test func againInTheBeatReplaysTheStepAndWatchKeepsNext() {
        let (p, v) = make(fading: 1)
        p.primary()
        p.settle(v)
        #expect(p.phase == .paused(0) && p.primaryControl == .next, "watch keeps Next (EXP-8)")
        p.advance(by: 5)
        #expect(p.phase == .paused(0), "and waits for it")
        p.jump(to: .doWithMe)
        p.primary()
        runOn(p, v, to: .paused(0))
        p.again()
        #expect(p.phase == .playing(0), "Again in the beat replays the step")
        runOn(p, v, to: .paused(0))
        runOn(p, v, to: .playing(1))
    }

    @Test func theBeatHoldsWithReduceMotion() {
        let (p, v) = make(fading: 1)
        p.reduceMotion = true
        p.jump(to: .doWithMe)
        p.primary()
        runOn(p, v, to: .paused(0))
        p.advance(by: GuidedPlayer.beat / 2)
        #expect(p.phase == .paused(0), "a pause between lines, not a motion: Reduce Motion keeps it")
        p.advance(by: GuidedPlayer.beat)
        #expect(p.phase == .playing(1))
    }

    @Test func touchesAreReadAsTapsOrStrokes() {
        let (p, v) = make(fading: 3)
        watchAll(p, v)
        p.primary()
        p.primary()
        p.settle(v)
        p.primary()
        v.finish()
        // A line drawn across the drawing is a stroke: not the touch the step wants, so a miss, and
        // the line fades.
        p.touchBegan(at: CGPoint(x: 100, y: 100))
        p.touchMoved(to: CGPoint(x: 160, y: 120))
        #expect(p.ink.count == 1 && p.ink[0].fadingSince == nil, "the line shows as it is drawn")
        p.touchEnded(at: CGPoint(x: 200, y: 140))
        #expect(p.note != nil)
        #expect(p.ink.count == 1 && p.ink[0].fadingSince != nil, "a line not read as a mark fades")
        let end = BarExplainer(length: 6).end
        p.touchBegan(at: CGPoint(x: end.midX, y: end.midY))
        p.touchEnded(at: CGPoint(x: end.midX + 2, y: end.midY))
        p.settle(v)
        #expect(p.phase == .doing(2), "done, and on by itself to the next step")
    }

    @Test func aDragStepReadsDrags() {
        let (p, v) = make(fading: 2)
        watchAll(p, v)
        p.primary()
        p.primary()
        p.settle(v)
        p.primary()
        p.settle(v)
        p.primary()
        #expect(p.phase == .doing(2))
        v.finish()
        p.touchBegan(at: CGPoint(x: 300, y: 100))
        p.touchMoved(to: CGPoint(x: 400, y: 100))
        #expect(p.ink.isEmpty, "a drag shows no pencil line")
        guard case let .label(_, at) = p.scene.element("knob")?.kind else { Issue.record("the knob does not follow"); return }
        #expect(at.x == 400)
        p.touchEnded(at: CGPoint(x: 650, y: 100))
        p.settle(v)
        #expect(p.phase == .doing(3), "done, and on by itself to the next step")
    }

    @Test func showMePlaysTheStepAsWatched() {
        let (p, v) = make(fading: 1)
        watchAll(p, v)
        p.primary()
        for _ in 0..<3 {
            p.primary()
            p.settle(v)
        }
        p.primary()
        #expect(p.phase == .doing(3))
        p.showMe()
        #expect(p.phase == .playing(3) && p.shownSteps == [3])
        p.settle(v)
        #expect(p.phase == .paused(3) && p.scene.element("counted") != nil)
        #expect(p.primaryControl == .whatIf)
        // Again on a step the child does starts its marks again.
        p.again()
        #expect(p.phase == .doing(3) && p.listening)
    }

    @Test func whyPlaysOverThePausedStepAndGotItReturnsToIt() {
        let (p, v) = make()
        #expect(!p.whyOffered)
        p.primary()
        #expect(!p.whyOffered, "not while the step plays")
        p.settle(v)
        #expect(p.whyOffered, "offered while a step that has one is paused")
        let caption = p.caption
        let scene = p.scene
        let dots = p.dots
        p.why()
        #expect(p.whyShown && p.primaryControl == nil && !p.whyOffered)
        #expect(p.whyScene?.element("why") != nil)
        #expect(p.scene == scene && p.dots == dots, "Why? is not a step: the drawing and dots stay")
        p.settle(v)
        #expect(p.primaryControl == .gotIt && p.caption.display == "Because.")
        p.primary()
        #expect(!p.whyShown && p.caption == caption && p.scene == scene && p.phase == .paused(0))
        #expect(p.primaryControl == .next)
        // A step without one offers none.
        p.primary()
        p.settle(v)
        #expect(!p.whyOffered)
    }

    @Test func againDuringWhyReplaysTheStep() {
        let (p, v) = make()
        p.primary()
        p.settle(v)
        p.why()
        p.again()
        #expect(!p.whyShown && p.phase == .playing(0))
    }

    /// Plays to What if?, the child doing nothing but Show me.
    func toWhatIf(_ p: GuidedPlayer, _ v: RecordingVoice) {
        watchAll(p, v)
        p.primary()
        p.primary()
        p.settle(v)
        for k in 1...3 {
            #expect(p.phase == .doing(k))
            p.showMe()
            p.settle(v)
        }
        #expect(p.primaryControl == .whatIf)
        p.primary()
    }

    @Test func whatIfChecksEachGoalWhenTheChildLetsGo() {
        let (p, v) = make()
        toWhatIf(p, v)
        #expect(p.part == .whatIf && p.phase == .whatIf(goal: 0, met: false))
        #expect(p.caption.display == "Make it 10." && p.showMeOffered && p.primaryControl == nil)
        #expect(p.dots.isEmpty)
        // Dragging changes the picture at once; nothing is checked until the child lets go.
        p.touchBegan(at: CGPoint(x: 60, y: 300))
        p.touchMoved(to: CGPoint(x: 100, y: 300))
        guard case let .total(shown, _, _) = p.scene.element("bar")?.kind else { Issue.record("no bar"); return }
        #expect(shown == "10" && p.phase == .whatIf(goal: 0, met: false), "checked only on letting go")
        p.touchMoved(to: CGPoint(x: 130, y: 300))
        p.touchEnded(at: CGPoint(x: 130, y: 300))
        #expect(p.phase == .whatIf(goal: 0, met: false), "13 is not 10: no failure, the goal stays open")
        #expect(p.note == nil && p.haptics == 0)
        // Within 2 of an exact goal, it snaps.
        p.touchBegan(at: CGPoint(x: 90, y: 300))
        p.touchEnded(at: CGPoint(x: 90, y: 300))
        p.settle(v, limit: 30)
        #expect(p.phase == .whatIf(goal: 0, met: true) && p.haptics == 1)
        guard case .total("10", _, _) = p.scene.element("bar")?.kind else { Issue.record("did not snap to 10"); return }
        // Once met, the picture holds.
        p.touchBegan(at: CGPoint(x: 190, y: 300))
        p.touchEnded(at: CGPoint(x: 190, y: 300))
        guard case .total("10", _, _) = p.scene.element("bar")?.kind else { Issue.record("moved after the goal was met"); return }
        #expect(p.primaryControl == nil, "no Next: the next goal opens by itself")
        p.settle(v)
        #expect(p.phase == .whatIf(goal: 1, met: false), "after the line about the goal and a beat")
        #expect(p.caption.display == "Make it longer than 15.")
        // Show me moves the picture to the goal, which then counts as met.
        p.showMe()
        p.settle(v)
        #expect(p.phase == .whatIf(goal: 1, met: true) && p.haptics == 2)
        #expect(p.primaryControl == .tryOne)
        p.primary()
        #expect(p.part == .tryOne && p.phase == .tryOne && p.caption.display == "Try a bar of 7.")
        #expect(p.primaryControl == .watchAgain && !p.againEnabled)
        p.primary()
        #expect(p.part == .watch && p.phase == .ready)
    }

    @Test func withoutWhatIfDoItWithMeGoesOnToTryOne() {
        let (p, v) = make(fading: 1, whatIf: false)
        #expect(p.parts == [.watch, .doWithMe, .tryOne])
        watchAll(p, v)
        p.primary()
        for _ in 0..<4 {
            p.primary()
            p.settle(v)
        }
        #expect(p.phase == .doing(3))
        p.showMe()
        p.settle(v)
        #expect(p.primaryControl == .tryOne)
    }

    // A preview app jumps to any part and any step.

    @Test func aStepJumpInWatchBuildsTheStepsBeforeItAndForgetsThoseAfter() {
        let (p, v) = make()
        p.jump(toStep: 2)
        #expect(p.phase == .playing(2) && p.currentStep == 2)
        #expect(p.dots.map(\.state) == [.done, .done, .current, .upcoming])
        p.settle(v)
        #expect(p.phase == .paused(2) && p.primaryControl == .next)
        #expect(p.scene.element("label")?.opacity == 1, "step 0 was built with its watched result")
        #expect(p.scene.element("grown") != nil && p.scene.element("knob") != nil)
        #expect(p.scene.element("counted") == nil)
        // Back to step 1: what step 2 did is forgotten.
        p.jump(toStep: 1)
        p.settle(v)
        #expect(p.phase == .paused(1) && p.scene.element("grown") != nil && p.scene.element("knob") == nil)
        // Forward again, past a step that was forgotten, to the last.
        p.jump(toStep: 3)
        p.settle(v)
        #expect(p.phase == .paused(3) && p.scene.element("knob") != nil && p.scene.element("counted") != nil)
        #expect(p.primaryControl == .doWithMe)
        p.jump(toStep: 4)
        #expect(p.phase == .paused(3), "a step the part does not have is ignored")
    }

    @Test func aStepJumpInDoItWithMeWaitsForTheChildsMarks() {
        let (p, v) = make(fading: 3)
        p.jump(to: .doWithMe)
        #expect(p.part == .doWithMe && p.phase == .ready)
        p.jump(toStep: 3)
        #expect(p.phase == .doing(3) && p.listening && !p.readsMarks, "the child's step says its instruction first")
        #expect(p.caption.display == "Do count.")
        #expect(p.scene.element("grown") != nil && p.scene.element("knob") != nil, "the steps before it have their default marks")
        #expect(p.scene.element("counted") == nil)
        v.finish()
        #expect(p.readsMarks)
        p.mark(.tap(CGPoint(x: 500, y: 300)))
        p.settle(v)
        #expect(p.phase == .paused(3) && p.scene.element("counted") != nil)
        // A step the child does, jumped back to: the child's marks again, on the picture before it.
        p.jump(toStep: 1)
        #expect(p.phase == .doing(1) && p.scene.element("grown") == nil)
        v.finish()
        #expect(p.tally == Tally(0, of: 1))
        // A watched step plays as watched.
        p.jump(toStep: 0)
        #expect(p.phase == .playing(0) && !p.readsMarks && p.tally == nil)
    }

    @Test func aPartJumpStartsThePartAndAStepJumpClosesWhy() {
        let (p, v) = make()
        p.primary()
        p.settle(v)
        p.why()
        #expect(p.whyShown)
        p.jump(toStep: 2)
        #expect(!p.whyShown && p.whyScene == nil && p.phase == .playing(2))
        p.jump(to: .tryOne)
        #expect(p.part == .tryOne && p.phase == .tryOne && p.caption.display == "Try a bar of 7.")
        #expect(p.steps.isEmpty && p.dots.isEmpty)
        p.jump(toStep: 0)
        #expect(p.phase == .tryOne, "try one has no steps to jump to")
        p.jump(to: .whatIf)
        #expect(p.part == .whatIf && p.phase == .whatIf(goal: 0, met: false) && p.caption.display == "Make it 10.")
        p.jump(to: .watch)
        #expect(p.part == .watch && p.phase == .ready && p.primaryControl == .watch)
        let (q, _) = make(whatIf: false)
        q.jump(to: .whatIf)
        #expect(q.part == .watch, "an explainer without What if? cannot be jumped to it")
    }

    @Test func reduceMotionShowsEachWatchedStepsEndAtOnce() {
        let (p, v) = make()
        p.reduceMotion = true
        p.primary()
        #expect(p.phase == .playing(0), "its line still takes time")
        v.finish()
        #expect(p.phase == .paused(0))
    }
}
