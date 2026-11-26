import Foundation
import Observation

/// A stretch of an explainer's motion with what is said during it: a step's timing and lines
/// (`StepScript`) and the picture at any moment of it, `t` seconds on its own clock. At the end of
/// its script the picture is the still picture the motion arrives at (EXP-11).
public struct Motion: Sendable {
    public var script: StepScript
    public var picture: @Sendable (Double) -> Scene
    /// When, on its clock, the picture's camera moves (EXP-18). The player never runs the clock
    /// into or through one of these while the learner's Pencil or finger is on the drawing, so the
    /// camera never moves under a mark being made.
    public var cameraMoves: [ClosedRange<Double>]

    public init(script: StepScript, cameraMoves: [ClosedRange<Double>] = [], picture: @escaping @Sendable (Double) -> Scene) {
        self.script = script
        self.picture = picture
        self.cameraMoves = cameraMoves
    }

    /// The same motion saying `line` as its caption as it begins: a camera move made while the
    /// line that introduces what it frames is said (EXP-18).
    public func saying(_ line: Line) -> Motion {
        Motion(
            script: StepScript(duration: script.duration, events: [StepEvent(0, .say(line, caption: true))] + script.events),
            cameraMoves: cameraMoves, picture: picture)
    }

    /// A motion that shows `scene` throughout and says `lines` in turn, each as the caption when
    /// `caption` is true.
    public static func still(_ scene: Scene, saying lines: [Line] = [], caption: Bool = true, duration: Double = 0) -> Motion {
        Motion(
            script: StepScript(duration: duration, events: lines.map { StepEvent(0, .say($0, caption: caption)) }),
            picture: { _ in scene })
    }

    /// The picture it ends on.
    public var end: Scene { picture(script.duration) }
}

/// Plays one `Motion` at a time on its own clock and speaks lines through the voice one at a
/// time, as both players need: the paced watch player (`ExplainerPlayer`) and the child version's
/// player (`GuidedPlayer`). The clock moves only through `advance(by:)`, which the runner calls
/// itself once a frame unless made with `drivesItself: false`, as tests make it.
@MainActor
@Observable
final class MotionRunner {
    /// Seconds into the motion, on its own clock.
    private(set) var time: Double = 0
    /// The motion playing or last played.
    private(set) var motion: Motion?
    /// Whether a motion is playing: its clock has not reached its end, or it waits for the voice.
    private(set) var running = false
    /// The clock is held at a wait for the voice (`StepEvent.Action.waitForVoice`) before its
    /// motion's end: the picture shows the moment just before the wait (`shownTime`).
    private(set) var heldForVoice = false
    /// Show each motion's end at once; only its lines take time (EXP-11).
    var reduceMotion = false {
        didSet { if reduceMotion && !oldValue { advance(by: 0) } }
    }
    /// How fast the clock runs when it drives itself; 1 is the designed pace.
    var pace: Double = 1
    /// A touch is on the drawing: the clock holds at the start of any camera move until it lifts
    /// (EXP-18), and stops in one that has begun.
    var holdsCamera = false {
        didSet { if !holdsCamera && oldValue { advance(by: 0) } }
    }
    /// Called with each line a motion shows as its caption, as it is said.
    @ObservationIgnored var onCaption: (@MainActor (Line) -> Void)?

    @ObservationIgnored private let voice: any ExplainerVoice
    @ObservationIgnored private let drivesItself: Bool
    @ObservationIgnored private var events: [StepEvent] = []
    @ObservationIgnored private var nextEvent = 0
    @ObservationIgnored private var completion: (@MainActor () -> Void)?
    @ObservationIgnored private var queue: [Line] = []
    @ObservationIgnored private var speaking = false
    @ObservationIgnored private var idleWaiters: [@MainActor () -> Void] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var advancing = false
    @ObservationIgnored private var driver: Task<Void, Never>?
    /// The motion playing is a pause (`pause`), which Reduce Motion does not shorten.
    @ObservationIgnored private var keepsTime = false

    init(voice: any ExplainerVoice, drivesItself: Bool) {
        self.voice = voice
        self.drivesItself = drivesItself
    }

    /// How far before a wait for the voice the picture holds while the clock waits there.
    static let beforeWait = 0.001

    /// The moment of the motion the picture shows: the clock's, except while it is held at a wait
    /// for the voice, when it is the moment just before. Whatever begins at the wait (a piece
    /// counted, a total, an answer) is shown with the line said after it, not while the line
    /// before is still heard, so a count's number and its piece go together however long the
    /// voice takes (EXP-10).
    var shownTime: Double { heldForVoice ? max(0, time - Self.beforeWait) : time }

    /// The picture now, or nil before any motion.
    var picture: Scene? { motion.map { $0.picture(min(shownTime, $0.script.duration)) } }

    /// Whether the voice still has lines to say.
    var voiceBusy: Bool { speaking || !queue.isEmpty }

    /// Plays `motion` from its start, replacing whatever played. With `holdForVoice` its clock
    /// waits at the start until the lines said there have been heard: a step that counts aloud
    /// says its line first and then moves (EXP-10). `then` is called once its motion and lines
    /// are done, unless it is replaced or stopped first.
    func play(_ motion: Motion, holdForVoice: Bool = false, then: (@MainActor () -> Void)? = nil) {
        play(motion, holdForVoice: holdForVoice, keepsTime: false, then: then)
    }

    private func play(_ motion: Motion, holdForVoice: Bool, keepsTime: Bool, then: (@MainActor () -> Void)?) {
        cancelMotion()
        self.keepsTime = keepsTime
        var events = motion.script.events
        if holdForVoice {
            let at = events.lastIndex { $0.time <= 0 }.map { $0 + 1 } ?? 0
            events.insert(StepEvent(0, .waitForVoice), at: at)
        }
        self.motion = motion
        self.events = events
        nextEvent = 0
        time = 0
        heldForVoice = false
        completion = then
        running = true
        advance(by: 0)
        startDriver()
    }

    /// Holds `scene` still for `seconds` on the runner's clock, then calls `then`, unless it is
    /// replaced or stopped first: the short beat between one step's line and the next where the
    /// child version runs on by itself (EXP-14). It is a pause between lines, not a
    /// motion, so Reduce Motion does not shorten it.
    func pause(_ seconds: Double, showing scene: Scene, then: @escaping @MainActor () -> Void) {
        play(.still(scene, duration: seconds), holdForVoice: false, keepsTime: true, then: then)
    }

    /// Ends the playing motion at once on its end picture. With `sayingRest`, the lines it had
    /// still to say are queued; otherwise they are not said. `then` is still called.
    func finishNow(sayingRest: Bool) {
        guard running, let motion else { return }
        while nextEvent < events.count {
            if sayingRest, case let .say(line, caption) = events[nextEvent].action {
                if caption { onCaption?(line) }
                enqueue(line)
            }
            nextEvent += 1
        }
        time = motion.script.duration
        heldForVoice = false
        advance(by: 0)
    }

    /// The last line the playing motion shows as its caption, said or not.
    var lastCaption: Line? {
        for e in events.reversed() { if case let .say(line, true) = e.action { return line } }
        return nil
    }

    /// Stops the motion where it is, without calling its `then`.
    func cancelMotion() {
        driver?.cancel()
        driver = nil
        completion = nil
        running = false
        heldForVoice = false
    }

    /// Speaks `line` after whatever is queued; `then` is called once everything said so far has
    /// been heard, unless the voice is silenced first.
    func say(_ line: Line, then: (@MainActor () -> Void)? = nil) {
        enqueue(line)
        if let then { whenQuiet(then) }
    }

    /// Calls `then` once the voice has nothing left to say (at once if it has nothing now),
    /// unless it is silenced first.
    func whenQuiet(_ then: @escaping @MainActor () -> Void) {
        if voiceBusy { idleWaiters.append(then) } else { then() }
    }

    /// Cuts off what is being said and drops what is queued; nothing waiting on the voice is
    /// called.
    func silence() {
        generation += 1
        queue = []
        idleWaiters = []
        speaking = false
        voice.stop()
    }

    /// Tells the voice the lines expected from now on, in order.
    func expect(_ lines: [Line]) { voice.expect(lines) }

    /// Calls `then` once the voice can say `line` at once.
    func whenReady(_ line: Line, _ then: @escaping @MainActor () -> Void) { voice.whenReady(line, then) }

    /// Stops everything: the motion and the voice.
    func stop() {
        silence()
        cancelMotion()
    }

    // MARK: the clock

    /// Moves the clock on by `dt` seconds: fires the events it passes, holds at a wait for the
    /// voice (showing the moment just before it), and ends the motion once its clock and lines
    /// are done. With Reduce Motion on, the clock runs straight to the next wait. A count's
    /// numbers are each said at their piece, waiting at a number only while the one before is
    /// still heard: a voice that says each within the motion's pace never holds the clock.
    func advance(by dt: Double) {
        guard running, let motion, !advancing else { return }
        advancing = true
        defer { advancing = false }
        let duration = motion.script.duration
        var budget = reduceMotion && !keepsTime ? Double.infinity : max(0, dt)
        while true {
            while nextEvent < events.count, events[nextEvent].time <= time || time >= duration {
                switch events[nextEvent].action {
                case .waitForVoice:
                    if voiceBusy {
                        heldForVoice = time < duration
                        return
                    }
                    heldForVoice = false
                case let .say(line, showCaption):
                    if showCaption { onCaption?(line) }
                    enqueue(line)
                }
                nextEvent += 1
            }
            if time >= duration {
                if voiceBusy { return }
                running = false
                driver?.cancel()
                driver = nil
                let done = completion
                completion = nil
                done?()
                return
            }
            if budget <= 0 { return }
            var target = nextEvent < events.count ? min(events[nextEvent].time, duration) : duration
            if holdsCamera {
                // Not into a camera move, nor on through one already under way.
                for w in motion.cameraMoves where w.upperBound > w.lowerBound {
                    if time >= w.lowerBound && time < w.upperBound { return }
                    if w.lowerBound > time { target = min(target, w.lowerBound) }
                }
                if target <= time { return }
            }
            let move = min(budget, target - time)
            time = move >= target - time ? target : time + move
            budget -= move
        }
    }

    private func startDriver() {
        driver?.cancel()
        driver = nil
        guard drivesItself, running else { return }
        driver = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled, self.running else { return }
                let now = clock.now
                let elapsed = last.duration(to: now)
                last = now
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                self.advance(by: seconds * self.pace)
            }
        }
    }

    // MARK: the voice

    private func enqueue(_ line: Line) {
        queue.append(line)
        sayNext()
    }

    private func sayNext() {
        guard !speaking else { return }
        guard !queue.isEmpty else {
            let waiting = idleWaiters
            idleWaiters = []
            for w in waiting { w() }
            return
        }
        let line = queue.removeFirst()
        speaking = true
        let mine = generation
        voice.say(line) { [weak self] in
            guard let self, self.generation == mine else { return }
            self.speaking = false
            self.sayNext()
            self.advance(by: 0)
        }
    }
}
