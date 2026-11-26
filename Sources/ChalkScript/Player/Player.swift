import CoreGraphics
import Foundation
import Observation

/// Speaks an explainer's lines (EXP-10); tests use one that records what it is given. A voice
/// that makes its audio on the device (such as Kokoro) needs time to make a line: the player
/// tells it the lines it expects to say, in the order it will say them, and waits for the first
/// line of a part before offering the control that starts it. A voice that speaks at
/// once keeps the defaults: it ignores the list and is always ready.
@MainActor
public protocol ExplainerVoice: AnyObject {
    /// Speaks `line`, cutting off nothing: the player sends one line at a time. `onFinish` is
    /// called once it has been heard to its end, and never after `stop`.
    func say(_ line: Line, onFinish: @escaping @MainActor () -> Void)
    func stop()
    /// The lines the player expects to say from now on, in the order it will say them (the
    /// main path: what a learner who does each step right hears). Replaces any earlier list.
    func expect(_ lines: [Line])
    /// Calls `then` once `line` would start at once when said: now, for a voice with nothing to
    /// make.
    func whenReady(_ line: Line, _ then: @escaping @MainActor () -> Void)
}

extension ExplainerVoice {
    public func expect(_ lines: [Line]) {}
    public func whenReady(_ line: Line, _ then: @escaping @MainActor () -> Void) { then() }
}

/// A voice that says nothing and finishes at once: narration muted. The shown line and the
/// pacing still carry the explainer (EXP-10).
@MainActor
public final class SilentVoice: ExplainerVoice {
    public init() {}
    public func say(_ line: Line, onFinish: @escaping @MainActor () -> Void) { onFinish() }
    public func stop() {}
}

/// The paced player (EXP-8). Before the first step it shows the problem and one Watch control.
/// Each step plays its motion and says its line, then stops on its finished picture and waits;
/// Next, or a tap on the drawing, plays the next step. Again replays the step it is paused on,
/// and pressed while a step plays it goes back one step, so repeated presses go back further.
/// The last step offers Watch again. The parent version can skip ahead (EXP-9): its progress
/// dots are controls, and Next, offered while a step plays, finishes that step at once. With Reduce Motion on, a playing step shows its finished picture at once and only
/// its lines take time (EXP-11).
///
/// The step clock moves only through `advance(by:)`. The player calls it itself once per frame
/// while a step plays, unless it was made with `drivesItself: false`, as tests make it.
@MainActor
@Observable
public final class ExplainerPlayer {
    public enum Phase: Equatable, Sendable {
        /// Before the first step: the Watch control.
        case ready
        case playing(Int)
        /// A step's motion and lines are done; nothing happens until the learner asks (EXP-8).
        case paused(Int)
    }

    /// The large control: what it says, or nil while a step plays in the child version (it is
    /// hidden then). The parent version offers Next while a step plays (EXP-9).
    public enum PrimaryControl: Equatable, Sendable {
        case watch, next, watchAgain
    }

    public enum Dot: Equatable, Sendable {
        case done, current, upcoming
    }

    /// The explainer, as laid out for the drawing area last given (`layOut(for:)`).
    public private(set) var explainer: any Explainer
    @ObservationIgnored private let made: any Explainer
    /// The drawing area's size the explainer was last laid out for.
    public private(set) var drawingArea: CGSize?
    /// The area the explainer is laid out for, and whether that is the area given (EXP-17); nil
    /// before the first area. A host app may show it, log it or ignore it.
    public var areaUse: AreaUse? { explainer.areaUse }
    public private(set) var phase: Phase = .ready
    /// The line shown under the drawing.
    public private(set) var caption: Line
    /// Watch is shown but waits until the voice can say the first step's line at once, so the
    /// first motion does not run ahead of its line.
    public private(set) var gettingReady = false
    @ObservationIgnored private var readyToken = 0
    /// Seconds into the playing step's motion, on its own clock (held while it waits for the
    /// voice).
    public var time: Double { runner.time }
    /// Show each step's finished picture instead of its motion (EXP-11).
    public var reduceMotion: Bool {
        get { runner.reduceMotion }
        set { runner.reduceMotion = newValue }
    }
    /// How fast the clock runs when the player drives itself; 1 is the designed pace.
    public var pace: Double {
        get { runner.pace }
        set { runner.pace = newValue }
    }

    private let runner: MotionRunner

    public init(explainer: any Explainer, voice: any ExplainerVoice, reduceMotion: Bool = false, drivesItself: Bool = true) {
        self.explainer = explainer
        self.made = explainer
        self.caption = explainer.intro
        self.runner = MotionRunner(voice: voice, drivesItself: drivesItself)
        runner.reduceMotion = reduceMotion
        runner.onCaption = { [weak self] in self?.caption = $0 }
        runner.expect(lines(from: 0))
        armWatch()
    }

    /// The lines said from step `step` to the last, in order.
    func lines(from step: Int) -> [Line] {
        (step..<explainer.stepCount).flatMap { k in
            explainer.script(for: k).events.compactMap {
                if case let .say(line, _) = $0.action { return line }
                return nil
            }
        }
    }

    /// Holds Watch until the first step's line can be said at once.
    private func armWatch() {
        readyToken += 1
        guard let first = lines(from: 0).first else {
            gettingReady = false
            return
        }
        gettingReady = true
        let my = readyToken
        runner.whenReady(first) { [weak self] in
            guard let self, self.readyToken == my else { return }
            self.gettingReady = false
        }
    }

    /// Lays the explainer out for a drawing area of `area` points (EXP-17): an explainer drawn
    /// for that space, with its camera (EXP-18), plays on from where it is.
    public func layOut(for area: CGSize) {
        guard area.width > 0, area.height > 0, area != drawingArea else { return }
        drawingArea = area
        explainer = made.laidOutExplainer(for: area)
    }

    // MARK: what is shown

    /// The picture now.
    public var scene: Scene {
        switch phase {
        case .ready: explainer.still(after: -1)
        case let .playing(k): reduceMotion ? explainer.still(after: k) : explainer.scene(step: k, at: runner.shownTime)
        case let .paused(k): explainer.still(after: k)
        }
    }

    public var primaryControl: PrimaryControl? {
        switch phase {
        case .ready: .watch
        case .playing: explainer.version.nextFinishesStep ? .next : nil
        case let .paused(k): k == explainer.stepCount - 1 ? .watchAgain : .next
        }
    }

    /// Whether the player is waiting to be asked for the next step (before the first, or paused
    /// on a finished one), as opposed to playing one.
    public var waiting: Bool {
        if case .playing = phase { return false }
        return true
    }

    /// Again does nothing before the first step.
    public var againEnabled: Bool { phase != .ready }

    /// The step shown, or nil before the first.
    public var currentStep: Int? {
        switch phase {
        case .ready: nil
        case let .playing(k), let .paused(k): k
        }
    }

    public var dots: [Dot] {
        let now = currentStep ?? -1
        return (0..<explainer.stepCount).map { $0 < now ? .done : $0 == now ? .current : .upcoming }
    }

    /// Whether the voice still has lines to say.
    public var voiceBusy: Bool { runner.voiceBusy }

    // MARK: controls

    /// Watch, Next or Watch again. While a step plays it is ignored in the child version, so no
    /// step runs ahead (EXP-8), and in the parent version it finishes the step at once (EXP-9).
    public func primary() {
        switch phase {
        case .ready: if !gettingReady { play(0) }
        case let .playing(k): if explainer.version.nextFinishesStep { finish(k) }
        case let .paused(k): play(k == explainer.stepCount - 1 ? 0 : k + 1)
        }
    }

    /// A tap on the drawing does what Next does.
    public func tapDrawing() { primary() }

    /// Replays the paused step; while a step plays, goes back one (EXP-8).
    public func again() {
        switch phase {
        case .ready: break
        case let .paused(k): play(k)
        case let .playing(k): play(max(0, k - 1))
        }
    }

    /// Plays step `step` from the picture before it. Only the parent version's dots do this
    /// (EXP-9); the learner's are not controls, so it is ignored there.
    public func jump(to step: Int) {
        guard explainer.version.dotsAreControls, (0..<explainer.stepCount).contains(step) else { return }
        play(step)
    }

    /// Plays step `step` from the picture before it, in either version: for an authoring app that
    /// is asked to show a step, never for a learner's control (EXP-8).
    public func show(step: Int) {
        guard (0..<explainer.stepCount).contains(step) else { return }
        play(step)
    }

    /// Silences the voice and stops the clock, leaving the step's finished picture: for when
    /// the explainer is closed.
    public func stop() {
        runner.silence()
        if case .playing = phase { runner.finishNow(sayingRest: false) }
        runner.cancelMotion()
    }

    /// Ends playing step `step` at once on its finished picture, with the line it ends on as
    /// the caption; whatever it had still to say is not said (EXP-9).
    private func finish(_ step: Int) {
        runner.silence()
        if let last = runner.lastCaption { caption = last }
        runner.finishNow(sayingRest: false)
        runner.cancelMotion()
        phase = .paused(step)
    }

    // MARK: the clock

    /// Moves the playing step's clock on by `dt` seconds: fires the events it passes, holds at a
    /// wait for the voice, and pauses the step once its motion and lines are done. With Reduce
    /// Motion on, the clock runs straight to the next wait.
    public func advance(by dt: Double) { runner.advance(by: dt) }

    private func play(_ step: Int) {
        runner.silence()
        readyToken += 1
        gettingReady = false
        runner.expect(lines(from: step) + (step > 0 ? lines(from: 0) : []))
        phase = .playing(step)
        let e = explainer
        runner.play(Motion(script: e.script(for: step), picture: { e.scene(step: step, at: $0) })) { [weak self] in
            self?.phase = .paused(step)
        }
    }
}
