import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript

/// Synthetic values shared by the engine's tests.
enum Fixture {
    static let guidedLabels = GuidedLabels(
        watch: "Watch", start: "Start", next: "Next", doWithMe: "Do it with me", whatIf: "What if?", tryOne: "Try one",
        watchAgain: "Watch again", again: "Again", showMe: "Show me", why: "Why?", gotIt: "Got it",
        orShowMe: Line(key: "explain.test.orShowMe", display: "Or tap Show me.", spoken: "Or tap Show me."),
        progress: { "Step \($0) of \($1)" }, tally: { "\($0) of \($1)" })
}

/// A voice that records each line and finishes only when the test says.
@MainActor
final class RecordingVoice: ExplainerVoice {
    var said: [Line] = []
    var stops = 0
    private var pending: [@MainActor () -> Void] = []
    var busy: Bool { !pending.isEmpty }
    /// When true, every line finishes as soon as it is said.
    var instant = false

    func say(_ line: Line, onFinish: @escaping @MainActor () -> Void) {
        #expect(pending.isEmpty, "a line was sent while another was still being said")
        said.append(line)
        if instant { onFinish() } else { pending.append(onFinish) }
    }

    func stop() {
        stops += 1
        pending = []
    }

    /// The line being said is heard to its end.
    func finish() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()()
    }
}

extension ExplainerPlayer {
    /// Runs the clock in frames until the step pauses, finishing each line as it is said.
    /// Returns the frames it took.
    @discardableResult
    func playToPause(_ voice: RecordingVoice, frame: Double = 1.0 / 60, limit: Int = 10_000) -> Int {
        var frames = 0
        while case .playing = phase, frames < limit {
            advance(by: frame)
            voice.finish()
            frames += 1
        }
        return frames
    }
}


extension GuidedPlayer {
    /// Runs the clock in frames, finishing each line as it is said, until the player waits on
    /// something other than its clock or voice: a control, or the learner's marks.
    @discardableResult
    func settle(_ voice: RecordingVoice, frame: Double = 1.0 / 60, limit: Int = 20_000) -> Int {
        var frames = 0
        while frames < limit {
            let busy: Bool =
                switch phase {
                case .playing: true
                case .doing: listening || voiceBusy || voice.busy || moving
                default: voiceBusy || voice.busy || moving
                }
            if !busy { break }
            advance(by: frame)
            voice.finish()
            frames += 1
        }
        return frames
    }
}

/// A small explainer for the player's own tests, with what subtraction does not use: a Why? on
/// its first step, What if? goals on a dragged bar, and a drag step. Its picture is a bar of
/// `length` and a label; its numbers are not a method, only something to check. With `asks` it
/// gives its question apart from the drawing, and with `laysOut` it lays its pictures out for the
/// drawing area it is given (EXP-17).
struct BarExplainer: GuidedExplainer {
    struct State: Equatable, Sendable {
        var shown = false
        var grown = false
        var counted = false
        var dragged: CGFloat?
    }

    let length: Int
    var withWhatIf = true
    var asks = false
    var laysOut = false
    /// The drawing area it was laid out for.
    var area: CGSize?

    static func line(_ key: String, _ text: String) -> Line { Line(key: "bar.\(key)", display: text, spoken: text) }

    var guidedSteps: [GuidedStep] {
        [GuidedStep("show"), GuidedStep("grow", doable: true), GuidedStep("slide", doable: true, input: .drag), GuidedStep("count", doable: true, countsAloud: true)]
    }
    var start: State { State() }
    /// Where the bar's end is touched to grow it.
    var end: CGRect { CGRect(x: 100 + CGFloat(length) * 10 - 10, y: 200, width: 20, height: 40) }

    func intro(_ part: GuidedPart) -> Line { Self.line("intro.\(part)", "A bar of \(length).") }

    func picture(_ s: State, marking step: Int?) -> Scene {
        var out = [SceneElement("label", .label("bar \(length)", at: CGPoint(x: 100, y: 300)), opacity: s.shown ? 1 : 0)]
        if s.grown { out.append(SceneElement("grown", .total("grown", at: CGPoint(x: 500, y: 400), scale: 1))) }
        if let x = s.dragged { out.append(SceneElement("knob", .label("knob", at: CGPoint(x: x, y: 100)))) }
        if s.counted { out.append(SceneElement("counted", .total("\(length)", at: CGPoint(x: 800, y: 480), scale: 1))) }
        return Scene(elements: out, size: area ?? Scene.stage)
    }

    var question: Line? { asks ? Self.line("question", "How long is a bar of \(length)?") : nil }

    func laidOut(for area: CGSize) -> BarExplainer {
        guard laysOut else { return self }
        var out = self
        out.area = area
        return out
    }

    func apply(_ step: Int, _ s: State) -> State {
        var n = s
        switch step {
        case 0: n.shown = true
        case 1: n.grown = true
        case 2: n.dragged = 600
        default: n.counted = true
        }
        return n
    }

    func watch(_ step: Int, from s: State) -> (state: State, motion: Motion) {
        let s1 = apply(step, s)
        let e = self
        let id = guidedSteps[step].id
        return (s1, Motion(
            script: StepScript(duration: 1, events: [StepEvent(0, .say(Self.line("watch.\(id)", "Watch \(id)."), caption: true))]),
            picture: { t in t >= 1 ? e.picture(s1, marking: step) : e.picture(s, marking: step) }))
    }

    func instruction(_ step: Int, _ s: State) -> Line { Self.line("do.\(guidedSteps[step].id)", "Do \(guidedSteps[step].id).") }

    func begin(_ step: Int, _ s: State) -> Reaction<State> {
        step == 1 ? Reaction(s, tally: Tally(0, of: 1)) : .ignored(s)
    }

    func read(_ mark: Mark, step: Int, _ s: State) -> Reaction<State> {
        switch step {
        case 1:
            guard case let .tap(p) = mark, end.contains(p) else { return Reaction(s, note: .miss(Self.line("miss", "Touch the end of the bar."))) }
            return Reaction(apply(1, s), tally: Tally(1, of: 1), finished: true)
        case 3:
            return Reaction(apply(3, s), motion: .still(picture(apply(3, s), marking: 3), saying: [Self.line("counted", "Counted.")]), finished: true)
        default: return .ignored(s)
        }
    }

    func read(_ drag: Drag, step: Int, _ s: State) -> Reaction<State> {
        var n = s
        n.dragged = drag.point.x
        if case let .ended(p) = drag, p.x >= 600 { return Reaction(n, finished: true) }
        return Reaction(n)
    }

    func why(_ step: Int, _ s: State) -> Motion? {
        guard step == 0 else { return nil }
        let scene = Scene(elements: [SceneElement("why", .text("why", at: CGPoint(x: 500, y: 100), style: .heading))])
        return .still(scene, saying: [Self.line("why", "Because.")], duration: 0.5)
    }

    // What if?: drag the bar's end; make it exactly 10 (snapping within 2), then longer than 15.
    var whatIf: (start: Int, goals: Int)? { withWhatIf ? (length, 2) : nil }

    func goal(_ goal: Int, _ state: Int) -> (line: Line, state: Int) {
        (goal == 0 ? Self.line("goal.0", "Make it 10.") : Self.line("goal.1", "Make it longer than 15."), state)
    }

    func picture(whatIf state: Int) -> Scene {
        Scene(elements: [SceneElement("bar", .total("\(state)", at: CGPoint(x: 500, y: 300), scale: 1))], size: area ?? Scene.stage)
    }

    func drag(_ drag: Drag, goal: Int, _ state: Int) -> Int { max(1, min(20, Int((drag.point.x / 10).rounded()))) }

    func settle(goal: Int, _ state: Int, showMe: Bool) -> Settle<Int> {
        let target = goal == 0 ? 10 : 18
        let glide = Motion.still(picture(whatIf: target), duration: 0.3)
        if showMe { return Settle(target, motion: glide, met: Self.line("met.\(goal)", "Yes!")) }
        if goal == 0 {
            if state == 10 { return Settle(state, met: Self.line("met.0", "Yes!")) }
            if abs(state - 10) <= 2 { return Settle(10, motion: glide, met: Self.line("met.0", "Yes!")) }
            return Settle(state)
        }
        return state > 15 ? Settle(state, met: Self.line("met.1", "Yes!")) : Settle(state)
    }

    var tryOne: (line: Line, scene: Scene) { (Self.line("try", "Try a bar of \(length)."), Scene()) }

    static func lesson(_ n: Int = 5, whatIf: Bool = true, asks: Bool = false, laysOut: Bool = false) -> GuidedLesson<BarExplainer> {
        func bar(_ length: Int) -> BarExplainer { BarExplainer(length: length, withWhatIf: whatIf, asks: asks, laysOut: laysOut) }
        return GuidedLesson(watch: bar(n), doWithMe: bar(n + 1), tryOne: bar(n + 2))
    }
}
