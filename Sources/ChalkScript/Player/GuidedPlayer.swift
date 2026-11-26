import CoreGraphics
import Foundation
import Observation

/// The child version's controls and the one line the player adds itself.
public struct GuidedLabels: Sendable {
    public var watch: String
    public var start: String
    public var next: String
    public var doWithMe: String
    public var whatIf: String
    public var tryOne: String
    public var watchAgain: String
    public var again: String
    public var showMe: String
    public var why: String
    public var gotIt: String
    /// Added to a miss from the second on a step: "Or tap Show me." (EXP-14).
    public var orShowMe: Line
    /// VoiceOver's reading of the progress dots: "Step 2 of 6".
    public var progress: @Sendable (_ step: Int, _ count: Int) -> String
    /// VoiceOver's reading of a tally: "2 of 6".
    public var tally: @Sendable (_ done: Int, _ count: Int) -> String

    public init(
        watch: String, start: String, next: String, doWithMe: String, whatIf: String, tryOne: String,
        watchAgain: String, again: String, showMe: String, why: String, gotIt: String, orShowMe: Line,
        progress: @escaping @Sendable (_ step: Int, _ count: Int) -> String,
        tally: @escaping @Sendable (_ done: Int, _ count: Int) -> String
    ) {
        self.watch = watch
        self.start = start
        self.next = next
        self.doWithMe = doWithMe
        self.whatIf = whatIf
        self.tryOne = tryOne
        self.watchAgain = watchAgain
        self.again = again
        self.showMe = showMe
        self.why = why
        self.gotIt = gotIt
        self.orShowMe = orShowMe
        self.progress = progress
        self.tally = tally
    }

    /// The name of a part, as the parts strip shows it.
    public func name(_ part: GuidedPart) -> String {
        switch part {
        case .watch: watch
        case .doWithMe: doWithMe
        case .whatIf: whatIf
        case .tryOne: tryOne
        }
    }
}

/// A line of the learner's pencil, kept by the player while it is drawn or as it fades away.
public struct InkStroke: Equatable, Sendable, Identifiable {
    public var id: Int
    public var points: [CGPoint]
    /// When it began to fade, on the player's clock; nil while it is drawn.
    public var fadingSince: Double?
}

/// The child version's player (EXP-8, EXP-14, EXP-15, EXP-16): watch, do it with me, the
/// optional What if?, and try one, on a `GuidedLesson`'s three problems.
///
/// - Watch plays the steps as `ExplainerPlayer` does: Watch, then each step's motion and line,
///   paused until Next or a tap on the drawing; Again replays the paused step, or goes back one
///   while a step plays. A step that counts aloud says its line before it moves (EXP-10).
/// - Do it with me: the learner makes the marks of the last `fading` doable steps (backward
///   fading, EXP-14) and watches the rest. It runs on by itself, with no Next: a step
///   the learner watches plays straight into the next after a short beat (`beat`), and so does a
///   step the learner has done, once its line has been said. A step the learner does says its
///   instruction first, and marks made while it is said are ignored; then each mark is read by
///   the explainer. Show me plays the step as watched, and the step counts as watched. A miss is
///   a kind line; from the second on a step, it adds that Show me is there.
/// - What if? sets goals in turn on a picture the learner drags, checked when the learner lets go;
///   once one is met the picture holds while its line is said, and after a beat the next goal
///   opens by itself (EXP-15).
/// - Try one shows the third problem for the learner to try alone.
/// - Why?, where a step of watch has one, plays over the paused step; Got it returns to it as it
///   was, and Again replays the step itself (EXP-16).
///
/// The control that starts a part (Start, What if?, Try one) still waits for the learner, at the
/// end of each part. While a touch is on the drawing, and for `PalmGuard.quiet` after it lifts,
/// presses on the controls through `press(_:)` do nothing, so a resting palm presses nothing
/// (EXP-17).
///
/// The clock moves only through `advance(by:)`, which the player calls itself once a frame
/// unless made with `drivesItself: false`, as tests make it.
@MainActor
@Observable
public final class GuidedPlayer {
    public enum Phase: Equatable, Sendable {
        /// Before the first step of watch or of do it with me.
        case ready
        /// A step plays: watched, or by Show me.
        case playing(Int)
        /// A step the learner does: its instruction is said, then the learner's marks are read.
        case doing(Int)
        /// A step is done; nothing happens until the learner asks (EXP-8).
        case paused(Int)
        /// What if? goal `goal` is open, or met.
        case whatIf(goal: Int, met: Bool)
        case tryOne
    }

    /// The large control: what it says, or nil while it is hidden.
    public enum Control: Equatable, Sendable {
        case watch, start, next, doWithMe, whatIf, tryOne, watchAgain, gotIt
    }

    /// A progress dot: where it is, and whether the learner does that step.
    public struct Dot: Equatable, Sendable {
        public var state: ExplainerPlayer.Dot
        public var learnerDoes: Bool
    }

    /// The short beat between one step's line and the next where do it with me and What if? run
    /// on by themselves.
    public static let beat: Double = 1.0

    /// The controls beside the drawing, pressed through `press(_:)`.
    public enum ColumnControl: String, CaseIterable, Sendable {
        case primary, again, showMe, why
    }

    public let labels: GuidedLabels
    /// The palm rule for the controls (EXP-17): fed by the touches on the drawing.
    public let palm = PalmGuard()
    /// How many of the do-it-with-me problem's doable steps the learner does, counted from the last
    /// (EXP-14). The app computes it from how many times the learner has done this explainer.
    public let fading: Int

    public private(set) var part: GuidedPart = .watch
    public private(set) var phase: Phase = .ready
    /// The line under the drawing.
    public private(set) var caption: Line
    /// The line under it while the learner does a step: a hint, or a miss.
    public private(set) var note: Line?
    public private(set) var tally: Tally?
    /// A step the learner does is saying its instruction: marks are ignored (EXP-14).
    public private(set) var listening = false
    /// Show me is offered after two misses on a step, and pulses.
    public private(set) var showMeUrged = false
    /// Why? is playing over the drawing, or has played and waits for Got it.
    public private(set) var whyShown = false
    public private(set) var whyPlaying = false
    /// The learner's pencil line being drawn, and lines fading because they were not read as marks.
    public private(set) var ink: [InkStroke] = []
    /// Bumped for each light haptic (a What if? goal met).
    public private(set) var haptics = 0
    /// The steps the learner was shown with Show me in this do it with me.
    public private(set) var shownSteps: Set<Int> = []
    /// The large control that starts a part (Watch, Start, Do it with me, What if?, Try one) is
    /// shown but waits until the voice can say the part's first line at once, so the first
    /// motion never runs ahead of its line.
    public private(set) var gettingReady = false

    /// Show each motion's end at once (EXP-11); the learner's own steps are unchanged (EXP-14).
    public var reduceMotion: Bool {
        get { runner.reduceMotion }
        set { runner.reduceMotion = newValue }
    }
    public var pace: Double {
        get { runner.pace }
        set { runner.pace = newValue }
    }

    private let lesson: any LessonEngine
    private let runner: MotionRunner
    @ObservationIgnored private let clock: @MainActor () -> Double
    private var still = Scene()
    private var whyEnd: Scene?
    /// Whether the runner's motion is the drawing's (not a Why?'s).
    private var mainMotion = false
    @ObservationIgnored private var token = 0
    @ObservationIgnored private var misses = 0
    @ObservationIgnored private var blocked = false
    @ObservationIgnored private var touch: (points: [CGPoint], began: Double)?
    @ObservationIgnored private var lastMarkAt = -Double.infinity
    @ObservationIgnored private var inkCount = 0
    @ObservationIgnored private var savedCaption: Line?
    @ObservationIgnored private var goalReady = false
    @ObservationIgnored private var locked = false
    @ObservationIgnored private var readyToken = 0
    /// The motion a step the learner does opens with (gathering pieces, framing them) is playing:
    /// the learner's marks wait for it, so the camera has landed before the learner acts (EXP-18).
    private var settling = false

    /// `fading` is how many doable steps the learner does; more than there are means all.
    public init<E: GuidedExplainer>(
        lesson: GuidedLesson<E>, voice: any ExplainerVoice, labels: GuidedLabels, fading: Int = .max,
        reduceMotion: Bool = false, drivesItself: Bool = true
    ) {
        self.lesson = Lesson(lesson)
        self.labels = labels
        self.fading = max(1, fading)
        self.runner = MotionRunner(voice: voice, drivesItself: drivesItself)
        let started = ContinuousClock.now
        self.clock = {
            let d = started.duration(to: .now)
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        self.caption = lesson.watch.intro(.watch)
        runner.reduceMotion = reduceMotion
        runner.onCaption = { [weak self] line in self?.caption = line }
        startPart(.watch)
    }

    // MARK: the lines ahead

    /// The lines the child version says from step `step` of `part` to the end of try one, in the
    /// order a learner who does each step right hears them; Why? panels, misses and hints are not
    /// among them.
    public func plannedLines(from part: GuidedPart, step: Int = 0) -> [Line] {
        let order = parts
        guard let i = order.firstIndex(of: part) else { return [] }
        return order[i...].enumerated().flatMap { j, p in lesson.planned(p, from: j == 0 ? step : 0, doing: doSet) }
    }

    /// The first line the large control would have said, were it pressed now, when it starts a
    /// part: nil when it starts none, or the part says nothing at first.
    var lineStartingPart: Line? {
        guard !whyShown else { return nil }
        switch phase {
        case .ready: return lesson.planned(part, from: 0, doing: doSet).first
        case let .paused(k):
            guard k == steps.count - 1 else { return nil }
            let next: GuidedPart = part == .watch ? .doWithMe : lesson.hasWhatIf ? .whatIf : .tryOne
            return lesson.planned(next, from: 0, doing: doSet).first
        case let .whatIf(g, true) where g == lesson.whatIfGoals - 1:
            return lesson.planned(.tryOne, from: 0, doing: doSet).first
        default: return nil
        }
    }

    /// Holds the large control while it starts a part whose first line is not ready yet.
    private func armControl() {
        readyToken += 1
        guard let line = lineStartingPart else {
            gettingReady = false
            return
        }
        gettingReady = true
        let my = readyToken
        runner.whenReady(line) { [weak self] in
            guard let self, self.readyToken == my else { return }
            self.gettingReady = false
        }
    }

    /// Tells the voice what follows step `step` of the part playing.
    private func expectFrom(_ step: Int) {
        runner.expect(plannedLines(from: part, step: step))
    }

    // MARK: what is shown

    /// The parts this explainer runs, in order.
    public var parts: [GuidedPart] { GuidedPart.allCases.filter { $0 != .whatIf || lesson.hasWhatIf } }

    /// The steps of the part playing (none in What if? and try one).
    public var steps: [GuidedStep] { part == .watch || part == .doWithMe ? lesson.steps(part) : [] }

    /// The problem's question, shown apart from the drawing; nil while the explainer keeps it in
    /// its drawing (EXP-17).
    public var question: Line? { lesson.question(part) }

    /// The drawing area's size the explainer was last laid out for, or nil before the screen has
    /// given one.
    public private(set) var drawingArea: CGSize?

    /// Lays the explainers out for a drawing area of `area` points (EXP-17) and shows the picture
    /// now as laid out for it. A motion already playing finishes as it was made; the next one is
    /// drawn for the new area. An explainer not laid out again is unchanged.
    public func layOut(for area: CGSize) {
        guard area.width > 0, area.height > 0, area != drawingArea else { return }
        drawingArea = area
        lesson.layOut(for: area)
        switch phase {
        case .ready: still = lesson.picture(before: 0, marking: nil)
        case let .playing(k): still = lesson.picture(before: k, marking: nil)
        case let .doing(k): still = lesson.working(marking: k)
        case let .paused(k):
            still = lesson.picture(after: k)
            if whyShown, !whyPlaying { whyEnd = lesson.why(k)?.end }
        case .whatIf: still = lesson.whatIfPicture()
        case .tryOne: still = lesson.tryOne.scene
        }
    }

    /// The picture now.
    public var scene: Scene {
        if mainMotion, runner.running, let p = runner.picture { return p }
        return still
    }

    /// What Why? draws over the drawing, while it is shown.
    public var whyScene: Scene? {
        guard whyShown else { return nil }
        if !mainMotion, runner.running, let p = runner.picture { return p }
        return whyEnd
    }

    /// The step shown, or nil.
    public var currentStep: Int? {
        switch phase {
        case let .playing(k), let .doing(k), let .paused(k): k
        default: nil
        }
    }

    /// Whether step `step` of the part playing is one the learner does.
    public func learnerDoes(_ step: Int) -> Bool { part == .doWithMe && doSet.contains(step) }

    /// The do-it-with-me steps the learner does: the last `fading` doable ones (EXP-14).
    public var doSet: Set<Int> {
        let doable = lesson.steps(.doWithMe).enumerated().filter(\.element.doable).map(\.offset)
        return Set(doable.suffix(fading))
    }

    public var dots: [Dot] {
        let now = currentStep ?? -1
        return steps.indices.map {
            Dot(state: $0 < now ? .done : $0 == now ? .current : .upcoming, learnerDoes: learnerDoes($0))
        }
    }

    public var primaryControl: Control? {
        if whyShown { return whyPlaying ? nil : .gotIt }
        switch phase {
        case .ready: return part == .watch ? .watch : .start
        case .playing, .doing: return nil
        case let .paused(k):
            // Do it with me runs on by itself between its steps.
            if k < steps.count - 1 { return part == .watch ? .next : nil }
            if part == .watch { return .doWithMe }
            return lesson.hasWhatIf ? .whatIf : .tryOne
        case let .whatIf(g, met):
            // The next goal opens by itself; only the last offers Try one.
            guard met, goalReady, g == lesson.whatIfGoals - 1 else { return nil }
            return .tryOne
        case .tryOne: return .watchAgain
        }
    }

    /// Whether the player waits to be asked to go on, as opposed to playing or reading marks.
    public var waiting: Bool { primaryControl != nil }

    public var againEnabled: Bool {
        switch phase {
        case .ready, .tryOne: false
        default: true
        }
    }

    /// Show me: always offered during a step the learner does, and while a What if? goal is open.
    public var showMeOffered: Bool {
        switch phase {
        case .doing: !blocked
        case .whatIf(_, false): !locked
        default: false
        }
    }

    /// Why?: offered while a step of watch that declares one is paused, and not while it plays
    /// (EXP-16). Do it with me runs on between its steps, so it offers none.
    public var whyOffered: Bool {
        guard !whyShown, part == .watch, case let .paused(k) = phase else { return false }
        return lesson.hasWhy(k)
    }

    /// Whether marks on the drawing are read now.
    public var readsMarks: Bool {
        guard case .doing = phase, !listening, !blocked, !settling else { return false }
        return true
    }

    // MARK: controls

    /// A control beside the drawing is pressed: it does what it does, unless the palm rule holds
    /// (EXP-17): a touch is on the drawing, one lifted less than `PalmGuard.quiet` ago, or the
    /// press began while either was so (a palm resting on the control).
    public func press(_ control: ColumnControl) {
        guard palm.accepts(control.rawValue) else { return }
        switch control {
        case .primary: primary()
        case .again: again()
        case .showMe: showMe()
        case .why: why()
        }
    }

    /// A touch on a control beside the drawing begins (its button is pressed down).
    public func pressBegan(_ control: ColumnControl) { palm.pressBegan(control.rawValue) }

    /// The large control.
    public func primary() {
        if whyShown {
            if !whyPlaying { closeWhy() }
            return
        }
        if gettingReady { return }
        switch phase {
        case .ready: run(0)
        case .playing, .doing: break
        case let .paused(k):
            if k < steps.count - 1 {
                // Do it with me goes on by itself; it has no Next.
                guard part == .watch else { return }
                return run(k + 1)
            }
            if part == .watch { return startPart(.doWithMe) }
            startPart(lesson.hasWhatIf ? .whatIf : .tryOne)
        case let .whatIf(g, met):
            guard met, goalReady, g == lesson.whatIfGoals - 1 else { return }
            startPart(.tryOne)
        case .tryOne: startPart(.watch)
        }
    }

    /// A tap on the drawing does what the large control does while it waits on a step, except
    /// just after a mark the learner made.
    public func tapDrawing() {
        guard clock() - lastMarkAt >= 0.7 else { return }
        switch phase {
        case .ready, .paused: if !whyShown { primary() }
        default: break
        }
    }

    /// Replays the paused step; while a watched step plays, goes back one (EXP-8). On a step the
    /// learner does, starts its marks again. In What if?, says the goal again. During Why?, replays
    /// the step itself (EXP-16).
    public func again() {
        if whyShown, let k = currentStep {
            closeWhy()
            return replay(k)
        }
        switch phase {
        case .ready, .tryOne: break
        case let .paused(k): replay(k)
        case let .doing(k): replay(k)
        case let .playing(k): learnerDoes(k) ? replay(k) : run(max(0, k - 1))
        case let .whatIf(g, met):
            let line = lesson.goalLine(g)
            runner.silence()
            caption = line
            guard met, goalReady else { return runner.say(line) }
            // Pressed in the beat after a goal is met: the beat waits for the line again.
            token += 1
            runner.cancelMotion()
            runner.say(line) { [weak self] in self?.openNextGoalAfterBeat(g) }
        }
    }

    /// Show me: plays the learner's step as watched; in What if?, moves the picture to the goal.
    public func showMe() {
        switch phase {
        case let .doing(k):
            shownSteps.insert(k)
            watchStep(k)
        case let .whatIf(g, false):
            guard !locked else { return }
            locked = true
            runner.silence()
            settle(g, showMe: true)
        default: break
        }
    }

    /// Plays Why? over the paused step.
    public func why() {
        guard whyOffered, case let .paused(k) = phase, let motion = lesson.why(k) else { return }
        token += 1
        savedCaption = caption
        whyShown = true
        whyPlaying = true
        whyEnd = motion.end
        mainMotion = false
        runner.stop()
        runner.play(motion) { [weak self] in self?.whyPlaying = false }
    }

    /// Goes to a part directly (for an authoring app).
    public func jump(to part: GuidedPart) {
        guard parts.contains(part) else { return }
        startPart(part)
    }

    /// Plays step `step` of the part playing directly (for an authoring app): the steps before it
    /// that have not been played are built with their watched results, and the steps after it
    /// are forgotten, so they are rebuilt from wherever it leaves off. In do it with me, a step
    /// the learner does says its instruction and waits for the learner's marks. Closes Why? if it is
    /// shown. The learner's own dots never call this (EXP-8).
    public func jump(toStep step: Int) {
        guard steps.indices.contains(step) else { return }
        if whyShown { closeWhy() }
        run(step)
    }

    /// Silences the voice and stops the clock: for when the explainer is closed.
    public func stop() {
        token += 1
        runner.stop()
    }

    // MARK: the Pencil

    /// A touch on the drawing begins, in scene units.
    public func touchBegan(at p: CGPoint) {
        touch = (points: [p], began: clock())
        palm.penDown()
        runner.holdsCamera = true
        guard readsMarks || openGoalTakesDrags else { return }
        if takesDrags {
            dragged(.began(p))
        } else {
            inkCount += 1
            ink.append(InkStroke(id: inkCount, points: [p]))
        }
    }

    public func touchMoved(to p: CGPoint) {
        guard touch != nil else { return }
        palm.penDown()
        touch?.points.append(p)
        guard readsMarks || openGoalTakesDrags else { return }
        if takesDrags {
            dragged(.moved(p))
        } else if let i = ink.lastIndex(where: { $0.fadingSince == nil }) {
            ink[i].points.append(p)
        }
    }

    public func touchEnded(at p: CGPoint) {
        // The camera may move again once the hand is off the drawing, even if the step changed
        // under it and forgot the touch.
        runner.holdsCamera = false
        guard let t = touch else { return }
        touch = nil
        palm.penUp()
        var points = t.points
        if points.last != p { points.append(p) }
        let tap = MarkGeometry.isTap(points, duration: clock() - t.began)
        let live = ink.lastIndex(where: { $0.fadingSince == nil })
        if readsMarks || openGoalTakesDrags {
            if takesDrags { return dragged(.ended(p)) }
            if let live { ink.remove(at: live) }
            mark(tap ? .tap(points[0]) : .stroke(points))
            return
        }
        if let live { ink.remove(at: live) }
        if tap { tapDrawing() }
    }

    /// The touch on the drawing was cancelled rather than lifted (a sheet over it, a system
    /// gesture): the palm rule lets go as it does for a lift, and what was being drawn is dropped.
    public func touchCancelled() {
        runner.holdsCamera = false
        guard touch != nil else { return }
        palm.penUp()
        touch = nil
        ink.removeAll { $0.fadingSince == nil }
    }

    /// A mark on the drawing, read by the step the learner is doing (EXP-14).
    public func mark(_ mark: Mark) {
        guard readsMarks, case let .doing(k) = phase else { return }
        lastMarkAt = clock()
        if runner.running && mainMotion { runner.finishNow(sayingRest: true) }
        let r = lesson.read(mark, step: k)
        if case let .stroke(points) = mark, !r.keepsStroke { fade(points) }
        apply(r, step: k)
    }

    /// A drag on the drawing: read by a step the learner does by dragging, or by an open What if?
    /// goal.
    public func dragged(_ drag: Drag) {
        if case let .whatIf(g, false) = phase {
            guard !locked else { return }
            lesson.whatIfDrag(drag, goal: g)
            still = lesson.whatIfPicture()
            if case .ended = drag { settle(g, showMe: false) }
            return
        }
        guard readsMarks, case let .doing(k) = phase, lesson.steps(part)[k].input == .drag else { return }
        if case .ended = drag { lastMarkAt = clock() }
        if runner.running && mainMotion { runner.finishNow(sayingRest: true) }
        apply(lesson.read(drag, step: k), step: k)
    }

    private var takesDrags: Bool {
        if case .whatIf = phase { return true }
        guard case let .doing(k) = phase else { return false }
        return lesson.steps(part)[k].input == .drag
    }

    private var openGoalTakesDrags: Bool {
        if case .whatIf(_, false) = phase { return !locked }
        return false
    }

    /// How strongly a pencil line shows: fully while drawn, less as it fades.
    public func opacity(of stroke: InkStroke) -> Double {
        guard let since = stroke.fadingSince else { return 1 }
        return max(0, 1 - (clock() - since) / Components.inkFade)
    }

    /// Fades a line that was not read as a mark.
    private func fade(_ points: [CGPoint]) {
        inkCount += 1
        let id = inkCount
        ink.append(InkStroke(id: id, points: points, fadingSince: clock()))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Components.inkFade))
            self?.ink.removeAll { $0.id == id }
        }
    }

    // MARK: the clock

    /// Moves the playing motion's clock on by `dt` seconds.
    public func advance(by dt: Double) { runner.advance(by: dt) }

    /// Whether the voice still has lines to say.
    public var voiceBusy: Bool { runner.voiceBusy }

    /// Whether a motion is playing.
    public var moving: Bool { runner.running }

    // MARK: parts and steps

    private func startPart(_ p: GuidedPart) {
        token += 1
        runner.stop()
        part = p
        lesson.reset(p)
        resetStep()
        whyShown = false
        whyPlaying = false
        shownSteps = p == .doWithMe ? [] : shownSteps
        mainMotion = true
        expectFrom(0)
        switch p {
        case .watch, .doWithMe:
            phase = .ready
            caption = lesson.intro(p)
            still = lesson.picture(before: 0, marking: nil)
        case .whatIf:
            lesson.whatIfReset()
            openGoal(0)
        case .tryOne:
            let t = lesson.tryOne
            phase = .tryOne
            caption = t.line
            still = t.scene
            runner.say(t.line)
        }
        armControl()
    }

    private func resetStep() {
        note = nil
        tally = nil
        listening = false
        settling = false
        showMeUrged = false
        blocked = false
        misses = 0
        ink = []
        touch = nil
    }

    private func run(_ k: Int) {
        readyToken += 1
        gettingReady = false
        expectFrom(k)
        learnerDoes(k) ? childStep(k) : watchStep(k)
    }

    private func replay(_ k: Int) { run(k) }

    private func watchStep(_ k: Int) {
        token += 1
        runner.stop()
        resetStep()
        mainMotion = true
        phase = .playing(k)
        let motion = lesson.watch(k)
        let my = token
        runner.play(motion, holdForVoice: lesson.steps(part)[k].countsAloud) { [weak self] in
            guard let self, self.token == my else { return }
            self.still = self.lesson.picture(after: k)
            self.phase = .paused(k)
            self.armControl()
            self.runOn(after: k)
        }
    }

    private func childStep(_ k: Int) {
        token += 1
        runner.stop()
        resetStep()
        mainMotion = true
        phase = .doing(k)
        listening = true
        let line = lesson.instruction(k)
        let approach = lesson.approach(k)
        still = lesson.picture(before: k, marking: k)
        caption = line
        let my = token
        let open: @MainActor () -> Void = { [weak self] in
            guard let self, self.token == my else { return }
            self.listening = false
            self.apply(self.lesson.begin(k), step: k, opening: true)
        }
        // The instruction is heard before the learner can act (EXP-14); the camera frames the step
        // while it is said, and has landed by then (EXP-18).
        if let approach {
            runner.play(approach.saying(line), then: open)
        } else {
            runner.say(line, then: open)
        }
    }

    /// Applies a reaction to step `k`. The one a step opens with (`opening`) holds the learner's
    /// marks until its motion has played, so nothing the learner draws lands while the pieces
    /// gather or the camera moves.
    private func apply(_ r: AnyReaction, step k: Int, opening: Bool = false) {
        let my = token
        if r.interrupts { runner.silence() }
        switch r.note {
        case nil: break
        case .clear: note = nil
        case let .hint(line): note = line
        case let .miss(line):
            misses += 1
            var said = line
            if misses >= 2 {
                said = Line(
                    key: line.key, display: line.display + " " + labels.orShowMe.display,
                    spoken: line.spoken.map { $0 + " " + (labels.orShowMe.spoken ?? labels.orShowMe.display) })
                showMeUrged = true
            }
            note = said
            runner.silence()
            runner.say(said)
        }
        if let t = r.tally { tally = t }
        if r.haptic { haptics += 1 }
        if r.finished { blocked = true }
        if let motion = r.motion {
            mainMotion = true
            if opening { settling = true }
            runner.play(motion) { [weak self] in
                guard let self, self.token == my else { return }
                self.settling = false
                self.still = self.lesson.working(marking: k)
                if r.finished { self.complete(k) }
            }
            return
        }
        still = lesson.working(marking: k)
        if r.finished {
            runner.whenQuiet { [weak self] in
                guard let self, self.token == my else { return }
                self.complete(k)
            }
        }
    }

    private func complete(_ k: Int) {
        lesson.commit(k)
        still = lesson.picture(after: k)
        resetStep()
        phase = .paused(k)
        armControl()
        runOn(after: k)
    }

    /// In do it with me, step `k` is done and its line said: after a beat the next step plays, or
    /// says its instruction when it is the learner's. The last step waits for the control
    /// that starts the next part. Again, a jump or Show me in the beat replaces it.
    private func runOn(after k: Int) {
        guard part == .doWithMe, k < steps.count - 1 else { return }
        let my = token
        runner.pause(Self.beat, showing: still) { [weak self] in
            guard let self, self.token == my, self.phase == .paused(k), !self.whyShown else { return }
            self.run(k + 1)
        }
    }

    // MARK: Why?

    private func closeWhy() {
        token += 1
        runner.stop()
        whyShown = false
        whyPlaying = false
        whyEnd = nil
        mainMotion = true
        if let saved = savedCaption { caption = saved }
        armControl()
    }

    // MARK: What if?

    private func openGoal(_ g: Int) {
        token += 1
        runner.stop()
        locked = false
        goalReady = false
        mainMotion = true
        let line = lesson.openGoal(g)
        phase = .whatIf(goal: g, met: false)
        caption = line
        still = lesson.whatIfPicture()
        runner.say(line)
    }

    /// Goal `g` is met and its line said: after a beat the next goal opens by itself.
    /// The last goal waits for Try one.
    private func openNextGoalAfterBeat(_ g: Int) {
        guard g < lesson.whatIfGoals - 1 else { return }
        let my = token
        runner.pause(Self.beat, showing: still) { [weak self] in
            guard let self, self.token == my, self.phase == .whatIf(goal: g, met: true) else { return }
            self.openGoal(g + 1)
        }
    }

    private func settle(_ g: Int, showMe: Bool) {
        let s = lesson.settle(goal: g, showMe: showMe)
        let my = token
        let after: @MainActor () -> Void = { [weak self] in
            guard let self, self.token == my else { return }
            self.still = self.lesson.whatIfPicture()
            guard let met = s.met else {
                self.locked = false
                return
            }
            // Met: the picture holds while its line is said, with one light haptic (EXP-15).
            self.locked = true
            self.haptics += 1
            self.phase = .whatIf(goal: g, met: true)
            self.runner.silence()
            self.caption = met
            self.runner.say(met) { [weak self] in
                guard let self, self.token == my else { return }
                self.goalReady = true
                self.armControl()
                self.openNextGoalAfterBeat(g)
            }
        }
        if let motion = s.motion {
            locked = true
            mainMotion = true
            runner.play(motion, then: after)
        } else {
            after()
        }
    }
}

extension GuidedPlayer {
    /// The phase, the part and the picture in a compact form for UI tests: not shown and not
    /// spoken.
    public var stateSummary: String {
        let phase: String =
            switch self.phase {
            case .ready: "ready"
            case let .playing(k): "playing:\(k)"
            case let .doing(k): listening ? "listening:\(k)" : "doing:\(k)"
            case let .paused(k): "paused:\(k)"
            case let .whatIf(g, met): "whatIf:\(g)\(met ? ":met" : "")"
            case .tryOne: "tryOne"
            }
        return "phase=\(phase);part=\(part.rawValue);" + scene.summary
    }
}

// MARK: the lesson, type-erased

/// A reaction without the explainer's state, which the lesson keeps.
struct AnyReaction {
    var motion: Motion?
    var interrupts: Bool
    var note: Note?
    var tally: Tally?
    var keepsStroke: Bool
    var haptic: Bool
    var finished: Bool
}

/// What the player asks of a lesson, with the explainer's state kept inside.
@MainActor
protocol LessonEngine: AnyObject {
    var hasWhatIf: Bool { get }
    var whatIfGoals: Int { get }
    func steps(_ part: GuidedPart) -> [GuidedStep]
    func intro(_ part: GuidedPart) -> Line
    func reset(_ part: GuidedPart)
    func picture(before step: Int, marking: Int?) -> Scene
    func picture(after step: Int) -> Scene
    func watch(_ step: Int) -> Motion
    func instruction(_ step: Int) -> Line
    /// The camera's move to frame step `step` for the learner, if it moves (EXP-18); the state
    /// before the step is then the framed one.
    func approach(_ step: Int) -> Motion?
    func begin(_ step: Int) -> AnyReaction
    func read(_ mark: Mark, step: Int) -> AnyReaction
    func read(_ drag: Drag, step: Int) -> AnyReaction
    func working(marking: Int) -> Scene
    func commit(_ step: Int)
    func hasWhy(_ step: Int) -> Bool
    func why(_ step: Int) -> Motion?
    var tryOne: (line: Line, scene: Scene) { get }
    func whatIfReset()
    func openGoal(_ goal: Int) -> Line
    func goalLine(_ goal: Int) -> Line
    func whatIfPicture() -> Scene
    func whatIfDrag(_ drag: Drag, goal: Int)
    func settle(goal: Int, showMe: Bool) -> (motion: Motion?, met: Line?)
    /// The lines `part` says from step `step` on, as a learner who does the steps in `doing`
    /// right hears them, without changing what is playing.
    func planned(_ part: GuidedPart, from step: Int, doing: Set<Int>) -> [Line]
    func question(_ part: GuidedPart) -> Line?
    /// Lays the three explainers out for a drawing area of `area` points (EXP-17).
    func layOut(for area: CGSize)
}

@MainActor
final class Lesson<E: GuidedExplainer>: LessonEngine {
    /// The lesson as made, and as laid out for the drawing area (`layOut`).
    private let made: GuidedLesson<E>
    private(set) var lesson: GuidedLesson<E>
    private var part: GuidedPart = .watch
    /// The state before each step of the part playing; step k's is `states[k]`.
    private var states: [E.State] = []
    /// The state of the step the learner is doing, as its marks change it.
    private var workingState: E.State?
    private var tinker: E.Tinker?
    private var goalLines: [Int: Line] = [:]

    init(_ lesson: GuidedLesson<E>) {
        self.made = lesson
        self.lesson = lesson
    }

    func layOut(for area: CGSize) {
        lesson = GuidedLesson(
            watch: made.watch.laidOut(for: area), doWithMe: made.doWithMe.laidOut(for: area),
            tryOne: made.tryOne.laidOut(for: area))
    }

    func question(_ part: GuidedPart) -> Line? { explainer(part).question }

    private func explainer(_ part: GuidedPart) -> E {
        switch part {
        case .watch: lesson.watch
        case .doWithMe, .whatIf: lesson.doWithMe
        case .tryOne: lesson.tryOne
        }
    }

    private var e: E { explainer(part) }

    var hasWhatIf: Bool { lesson.doWithMe.whatIf != nil }
    var whatIfGoals: Int { lesson.doWithMe.whatIf?.goals ?? 0 }

    func steps(_ part: GuidedPart) -> [GuidedStep] { explainer(part).guidedSteps }
    func intro(_ part: GuidedPart) -> Line { explainer(part).intro(part) }

    func reset(_ part: GuidedPart) {
        self.part = part
        states = [explainer(part).start]
        workingState = nil
    }

    /// The state before step `k`, building the steps before it with their watched results
    /// where they have not been played.
    private func state(before k: Int) -> E.State {
        while states.count <= k {
            let i = states.count - 1
            states.append(e.watch(i, from: states[i]).state)
        }
        return states[k]
    }

    func picture(before step: Int, marking: Int?) -> Scene { e.picture(state(before: step), marking: marking) }
    func picture(after step: Int) -> Scene { e.picture(state(before: step + 1), marking: step) }

    func watch(_ step: Int) -> Motion {
        let (s1, motion) = e.watch(step, from: state(before: step))
        states = Array(states.prefix(step + 1)) + [s1]
        // A step the learner was doing and left (by Show me or a jump) leaves no marks behind.
        workingState = nil
        return motion
    }

    func instruction(_ step: Int) -> Line { e.instruction(step, state(before: step)) }

    func approach(_ step: Int) -> Motion? {
        guard let (s1, motion) = e.approach(step, state(before: step)) else { return nil }
        states = Array(states.prefix(step)) + [s1]
        workingState = nil
        return motion
    }

    private func erase(_ r: Reaction<E.State>) -> AnyReaction {
        workingState = r.state
        return AnyReaction(
            motion: r.motion, interrupts: r.interrupts, note: r.note, tally: r.tally, keepsStroke: r.keepsStroke,
            haptic: r.haptic, finished: r.finished)
    }

    func begin(_ step: Int) -> AnyReaction {
        let s0 = state(before: step)
        states = Array(states.prefix(step + 1))
        return erase(e.begin(step, s0))
    }

    func read(_ mark: Mark, step: Int) -> AnyReaction {
        erase(e.read(mark, step: step, workingState ?? state(before: step)))
    }

    func read(_ drag: Drag, step: Int) -> AnyReaction {
        erase(e.read(drag, step: step, workingState ?? state(before: step)))
    }

    func working(marking: Int) -> Scene { e.picture(workingState ?? state(before: marking), marking: marking) }

    func commit(_ step: Int) {
        let s = workingState ?? state(before: step)
        states = Array(states.prefix(step + 1)) + [s]
        workingState = nil
    }

    func hasWhy(_ step: Int) -> Bool { why(step) != nil }
    func why(_ step: Int) -> Motion? { e.why(step, state(before: step + 1)) }

    var tryOne: (line: Line, scene: Scene) { lesson.tryOne.tryOne }

    func whatIfReset() {
        tinker = lesson.doWithMe.whatIf?.start
        goalLines = [:]
    }

    func openGoal(_ goal: Int) -> Line {
        guard let t = tinker else { preconditionFailure("What if? opened on an explainer without one") }
        let (line, s) = lesson.doWithMe.goal(goal, t)
        tinker = s
        goalLines[goal] = line
        return line
    }

    func goalLine(_ goal: Int) -> Line { goalLines[goal] ?? openGoal(goal) }

    func whatIfPicture() -> Scene { tinker.map { lesson.doWithMe.picture(whatIf: $0) } ?? Scene() }

    func whatIfDrag(_ drag: Drag, goal: Int) {
        guard let t = tinker else { return }
        tinker = lesson.doWithMe.drag(drag, goal: goal, t)
    }

    func settle(goal: Int, showMe: Bool) -> (motion: Motion?, met: Line?) {
        guard let t = tinker else { return (nil, nil) }
        let s = lesson.doWithMe.settle(goal: goal, t, showMe: showMe)
        tinker = s.state
        return (s.motion, s.met)
    }

    func planned(_ part: GuidedPart, from step: Int, doing: Set<Int>) -> [Line] {
        let e = explainer(part)
        switch part {
        case .watch, .doWithMe:
            let steps = e.guidedSteps
            guard step < steps.count else { return [] }
            // The state before `step`: what is playing, or the part's watched steps from its start.
            var s = e.start
            if part == self.part, step < states.count {
                s = states[step]
            } else {
                for k in 0..<step { s = e.watch(k, from: s).state }
            }
            var out: [Line] = []
            for k in step..<steps.count {
                let (next, motion) = e.watch(k, from: s)
                if part == .doWithMe, doing.contains(k) {
                    out.append(e.instruction(k, s))
                    out += e.begin(k, s).motion?.said ?? []
                    out += e.doneLines(k, s)
                } else {
                    out += motion.said
                }
                s = next
            }
            return out
        case .whatIf:
            guard let w = lesson.doWithMe.whatIf else { return [] }
            var t = w.start
            var out: [Line] = []
            for g in 0..<w.goals {
                let (line, s) = lesson.doWithMe.goal(g, t)
                let settled = lesson.doWithMe.settle(goal: g, s, showMe: true)
                if g >= step {
                    out.append(line)
                    out += settled.motion?.said ?? []
                    if let met = settled.met { out.append(met) }
                }
                t = settled.state
            }
            return out
        case .tryOne:
            return [lesson.tryOne.tryOne.line]
        }
    }
}
