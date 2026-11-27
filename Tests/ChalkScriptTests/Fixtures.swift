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
/// drawing area it is given (EXP-17). With a `motion` file it gives its pictures a camera (EXP-18):
/// each step names a shot, which the drawing moves to as the step begins, before its own picture changes.
struct BarExplainer: GuidedExplainer {
    struct State: Equatable, Sendable {
        var shown = false
        var grown = false
        var counted = false
        var dragged: CGFloat?
        /// The shot the camera holds on; nil is the motion file's opening shot.
        var shot: String?
    }

    let length: Int
    var withWhatIf = true
    var asks = false
    var laysOut = false
    /// The motion file the camera reads its shots and moves from; none, no camera.
    var motion: ExplainerMotion?
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

    // MARK: the camera

    static let world = CGRect(x: 0, y: 0, width: 1000, height: 540)
    static let vocabulary = MotionVocabulary(
        steps: ["show", "grow", "slide", "count"].map { MotionVocabulary.StepValues($0, []) }, parts: ["bar"])

    /// A motion file's shots for a bar, read against `style`.
    static func motion(_ json: String, style: ExplainerStyle = .standard) -> ExplainerMotion {
        ExplainerMotion.read(Data(json.utf8), explainer: "bar", vocabulary: vocabulary, style: style)
    }

    /// The camera's plan for the drawing area. The `bar` part is where the bars are drawn, whatever
    /// their length, so every bar of a lesson has the same shots.
    var plan: CameraPlan? {
        motion.map {
            CameraPlan.resolve(
                $0, parts: ["bar": CGRect(x: 100, y: 200, width: 100, height: 100)], world: Self.world,
                viewport: CGRect(origin: .zero, size: area ?? Scene.stage))
        }
    }

    /// The shot step `step` plays in.
    func shot(_ step: Int) -> String? { motion?.steps[guidedSteps[step].id]?.shot }

    func picture(_ s: State, marking step: Int?) -> Scene { scene(s, camera: plan?.camera(s.shot)) }

    func scene(_ s: State, camera: Camera?) -> Scene {
        var out = [SceneElement("label", .label("bar \(length)", at: CGPoint(x: 100, y: 300)), opacity: s.shown ? 1 : 0)]
        if motion != nil { out.append(SceneElement("question", .text("a bar", at: CGPoint(x: 500, y: 20), style: .heading), fixed: true)) }
        if s.grown { out.append(SceneElement("grown", .total("grown", at: CGPoint(x: 500, y: 400), scale: 1))) }
        if let x = s.dragged { out.append(SceneElement("knob", .label("knob", at: CGPoint(x: x, y: 100)))) }
        if s.counted { out.append(SceneElement("counted", .total("\(length)", at: CGPoint(x: 800, y: 480), scale: 1))) }
        return Scene(elements: out, size: area ?? Scene.stage, camera: camera)
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
        if motion != nil { n.shot = shot(step) }
        return n
    }

    func watch(_ step: Int, from s: State) -> (state: State, motion: Motion) {
        let s1 = apply(step, s)
        let e = self
        let id = guidedSteps[step].id
        if let plan, let motion {
            // The camera moves first, then the step's own picture follows.
            let move = motion.steps[id]!.camera
            let moves = plan.moves(from: s.shot, to: s1.shot)
            let lead = moves ? move.end : 0
            return (s1, Motion(
                script: StepScript(duration: lead + 1, events: [StepEvent(0, .say(Self.line("watch.\(id)", "Watch \(id)."), caption: true))]),
                cameraMoves: moves ? [move.at...move.end] : [],
                picture: { t in e.scene(t >= lead + 1 ? s1 : s, camera: plan.camera(from: s.shot, to: s1.shot, move: move, at: t)) }))
        }
        return (s1, Motion(
            script: StepScript(duration: 1, events: [StepEvent(0, .say(Self.line("watch.\(id)", "Watch \(id)."), caption: true))]),
            picture: { t in t >= 1 ? e.picture(s1, marking: step) : e.picture(s, marking: step) }))
    }

    func instruction(_ step: Int, _ s: State) -> Line { Self.line("do.\(guidedSteps[step].id)", "Do \(guidedSteps[step].id).") }

    /// Frames the step the learner does, while its instruction is said.
    func approach(_ step: Int, _ s: State) -> (state: State, motion: Motion)? {
        guard let plan, let motion else { return nil }
        let move = motion.steps[guidedSteps[step].id]!.camera
        guard plan.moves(from: s.shot, to: shot(step)) else { return nil }
        var framed = s
        framed.shot = shot(step)
        let e = self, target = shot(step)
        return (framed, Motion(
            script: StepScript(duration: move.end, events: []), cameraMoves: [move.at...move.end],
            picture: { t in e.scene(s, camera: plan.camera(from: s.shot, to: target, move: move, at: t)) }))
    }

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
        if case let .ended(p) = drag, p.x >= 600 {
            if motion != nil { n.shot = shot(2) }
            return Reaction(n, finished: true)
        }
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

    static func lesson(
        _ n: Int = 5, whatIf: Bool = true, asks: Bool = false, laysOut: Bool = false, motion: ExplainerMotion? = nil
    ) -> GuidedLesson<BarExplainer> {
        func bar(_ length: Int) -> BarExplainer {
            BarExplainer(length: length, withWhatIf: whatIf, asks: asks, laysOut: laysOut, motion: motion)
        }
        return GuidedLesson(watch: bar(n), doWithMe: bar(n + 1), tryOne: bar(n + 2))
    }
}

/// A small `Explainer` for the paced player's own tests: four steps, each with a picture that
/// is a single label and one line. The last counts to three, waiting for the voice at each
/// number, and ends on a line with an emphasised answer. It is no method, only something to check.
struct SteppedExplainer: Explainer {
    var version: ExplainerVersion = .child

    static let ticks = [0.5, 1.0, 1.5]
    static let countEnd = 2.0

    var stepCount: Int { 4 }
    var intro: Line { Line(key: "stepped.intro", display: "Four steps.", spoken: "Four steps.") }

    func line(_ step: Int) -> Line {
        step == 3
            ? Line(key: "stepped.count", display: "Count.", spoken: "Count.")
            : Line(key: "stepped.\(step)", display: "Step \(step).", spoken: "Step \(step).")
    }

    func script(for step: Int) -> StepScript {
        guard step == 3 else { return StepScript(duration: 1, events: [StepEvent(0, .say(line(step), caption: true))]) }
        var events = [StepEvent(0, .say(line(3), caption: true))]
        for (i, at) in Self.ticks.enumerated() {
            events.append(StepEvent(at, .waitForVoice))
            events.append(StepEvent(at, .say(Line(key: "stepped.tick.\(i + 1)", display: "\(i + 1)", spoken: "\(i + 1)"), caption: false)))
        }
        events.append(StepEvent(Self.countEnd, .waitForVoice))
        let answer = Line(key: "stepped.answer", display: "Counted 3!", spoken: "Counted three!", emphasis: "3")
        events.append(StepEvent(Self.countEnd, .say(answer, caption: true)))
        return StepScript(duration: Self.countEnd, events: events)
    }

    func scene(step: Int, at t: Double) -> Scene {
        if t <= 0 { return still(after: step - 1) }
        if t >= script(for: step).duration { return still(after: step) }
        return Scene(elements: [SceneElement("picture", .label("during \(step)", at: CGPoint(x: 100, y: 100)), opacity: 0.5)])
    }

    func still(after step: Int) -> Scene {
        Scene(elements: [SceneElement("picture", .label("after \(step)", at: CGPoint(x: 100, y: 100)))])
    }
}
