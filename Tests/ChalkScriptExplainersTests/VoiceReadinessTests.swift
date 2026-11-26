import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

// What the voice is told about the subtraction explainer's lines (see the engine's readiness tests).

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
struct SubtractionVoiceReadinessTests {
    /// The main path of do it with me: a step the child does says its instruction, then what
    /// the child's right marks bring; Show me's lines are not expected for it.
    @Test func doItWithMeExpectsTheInstructionThenTheChildsLines() throws {
        let problem = try SubtractionProblem(54, minus: 26)
        let lesson = SubtractionExplainer.lesson(watching: problem, wording: Fixture.guidedWording())
        let p = GuidedPlayer(lesson: lesson, voice: SilentVoice(), labels: Fixture.guidedLabels, drivesItself: false)
        let d = lesson.doWithMe
        let lines = p.plannedLines(from: .doWithMe)
        let texts = lines.map { $0.spoken ?? $0.display }
        let count = d.steps.firstIndex(of: .count)!
        let state = d.guidedSteps.indices.prefix(count).reduce(d.start) { s, k in d.watch(k, from: s).state }
        let instruction = d.instruction(count, state)
        let i = try #require(lines.firstIndex(of: instruction))
        // Each piece counted, tens first, then the join and the answer.
        let after = Array(texts[(i + 1)...])
        let tens = d.problem.differenceTens
        let ticks = (1...(tens + d.problem.differenceOnes)).map { n in
            d.line(.tick(n <= tens ? n * 10 : n - tens)).spoken ?? ""
        }
        #expect(Array(after.prefix(ticks.count)) == ticks, "\(after)")
        #expect(lines.last == lesson.tryOne.tryOne.line)
    }

    @Test func thePacedPlayersWatchWaitsForTheFirstLine() {
        let voice = MakingVoice()
        let p = ExplainerPlayer(explainer: Fixture.explainer(54, 26), voice: voice, drivesItself: false)
        #expect(p.gettingReady)
        p.primary()
        #expect(p.phase == .ready)
        voice.release()
        p.primary()
        #expect(p.phase == .playing(0))
        #expect(voice.expected.first?.first == voice.said.first)
    }
}
