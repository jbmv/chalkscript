import Foundation
import Testing
@testable import ChalkScript

// A voice that makes its lines on the device is told the lines expected, in the order
// they will be said, and the control that starts a part waits until the part's first line is
// ready; a voice that speaks at once is always ready, so nothing waits.

/// A voice that records what it is told to expect and holds `whenReady` until the test releases
/// the line; lines finish at once.
@MainActor
final class MakingVoice: ExplainerVoice {
    var said: [Line] = []
    var expected: [[Line]] = []
    var ready: Set<String> = []
    private var waiting: [(Line, @MainActor () -> Void)] = []

    func say(_ line: Line, onFinish: @escaping @MainActor () -> Void) {
        said.append(line)
        onFinish()
    }

    func stop() {}
    func expect(_ lines: [Line]) { expected.append(lines) }

    func whenReady(_ line: Line, _ then: @escaping @MainActor () -> Void) {
        if ready.contains(line.key + (line.spoken ?? line.display)) { return then() }
        waiting.append((line, then))
    }

    /// Every line waited on so far is made.
    func release() {
        let w = waiting
        waiting = []
        for (line, then) in w {
            ready.insert(line.key + (line.spoken ?? line.display))
            then()
        }
    }

    var waitingOn: [Line] { waiting.map(\.0) }
}

@MainActor
struct VoiceReadinessTests {
    /// Runs the clock until the step pauses (lines finish at once).
    func run(_ p: GuidedPlayer) {
        for _ in 0..<20_000 {
            if case .playing = p.phase { p.advance(by: 1.0 / 60) } else { return }
        }
    }

    @Test func watchWaitsForTheFirstLineAndEachPartsControlForItsFirstLine() {
        let voice = MakingVoice()
        let p = GuidedPlayer(lesson: BarExplainer.lesson(), voice: voice, labels: Fixture.guidedLabels, drivesItself: false)
        // The whole child version is expected at once, in the order it will be said.
        let planned = p.plannedLines(from: .watch)
        #expect(voice.expected.first == planned)
        #expect(planned.count > 5)
        // Watch is shown but waits for the first step's line.
        #expect(p.primaryControl == .watch && p.gettingReady)
        #expect(voice.waitingOn == [planned[0]])
        p.primary()
        p.tapDrawing()
        #expect(p.phase == .ready, "Watch did nothing while its line was being made")
        voice.release()
        #expect(!p.gettingReady)
        p.primary()
        #expect(p.phase == .playing(0))
        #expect(voice.said.first == planned[0])
        run(p)
        // Nothing made yet: do it with me's first line must be made before its control.
        voice.ready = []
        // Next starts no part, so it never waits.
        while case let .paused(k) = p.phase, k < p.steps.count - 1 {
            #expect(!p.gettingReady)
            p.primary()
            run(p)
        }
        // Do it with me waits for do it with me's first line.
        #expect(p.primaryControl == .doWithMe && p.gettingReady)
        let doFirst = p.plannedLines(from: .doWithMe).first
        #expect(voice.waitingOn.last == doFirst)
        voice.release()
        p.primary()
        #expect(p.part == .doWithMe)
        #expect(voice.expected.last == p.plannedLines(from: .doWithMe))
    }

    @Test func aVoiceThatSpeaksAtOnceNeverHoldsAControl() {
        let p = GuidedPlayer(lesson: BarExplainer.lesson(), voice: SilentVoice(), labels: Fixture.guidedLabels, drivesItself: false)
        #expect(!p.gettingReady)
        p.primary()
        #expect(p.phase == .playing(0))
    }
}
