// How an explainer plugs into the player (read this first when adding one).
//
// The child version runs in parts (EXP-8, EXP-14, EXP-15): watch, do it with me, an optional
// What if?, and try one, with an optional Why? on any step (EXP-16). `GuidedPlayer` runs all of
// them; an explainer supplies only what is its own, by conforming to `GuidedExplainer` in its own
// folder in the target that holds the explainers. Nothing in Player/ or Drawing/ needs editing to
// add one.
//
// 1. A value filled with one problem (EXP-2), with a `State`: everything its picture can show,
//    including the learner's own marks. `start` is the state before the first step.
// 2. `guidedSteps`: an id per step, whether the learner can do it (`doable`), whether it counts aloud
//    (the player then says its line before it moves, EXP-10), and how the learner's Pencil is read
//    on it (`input`: marks, or drags).
// 3. `picture(_:marking:)`: the still picture of a state, with the digit a step acts on marked
//    (EXP-5). `watch(_:from:)`: a step played from a state, as a `Motion` (its `StepScript` of
//    lines and timings and the picture at any moment) and the state it ends in. The watch part
//    plays these from `start`; do it with me plays them for the steps the learner watches, and
//    Show me plays one from the state the learner's step began in.
// 4. Do it with me: `instruction(_:_:)` is said before the learner can act, while `approach(_:_:)`
//    moves the camera to the step's shot where it has one (EXP-18); `begin(_:_:)` runs as the
//    step opens (a tally, a motion such as gathering pieces to count, which the learner's marks
//    wait for); `read(_:step:_:)` is
//    called with each mark (`Mark.tap` or `Mark.stroke`, in scene units) or drag (`Drag`) and
//    returns a `Reaction`: the new state, a motion to play with any lines (a count said in
//    answer to a tap sets `interrupts`), a hint or a miss (`Note`), a `Tally`, whether a stroke
//    was kept in the drawing (`keepsStroke`; otherwise the player fades it), a haptic, and
//    whether the step is done. A miss is always a kind line; after a second the player
//    offers Show me. `MarkGeometry` reads strokes and touches against the pieces.
//    `doneLines(_:_:)` lists what the step says when the learner's marks are right, in order
//    (by default what the watched step says), so a voice that makes lines ahead makes those first.
// 5. Optional: `why(_:_:)` returns a motion played over the drawing (EXP-16); `whatIf` and its
//    functions run What if? goals on a dragged picture (EXP-15), each settled when the learner
//    lets go, snapping and Show me included; `tryOne` is the problem and line the learner tries.
// 6. The problems: the player is given three of the explainer's values, one each for watch, do
//    it with me and try one (`GuidedLesson`), which the explainer makes from the learner's problem
//    as isomorphs (EXP-3). What if? starts from the do-it-with-me problem.
//
// 7. Drawing: a picture is a `Scene` of `SceneElement`s. Use the shared components (pieces,
//    cross-outs, arrows, boxes, tags, counts) where they fit (EXP-13); where they have none (a bar,
//    a dashed part, a brace, a card, a ten frame), `.shape(Outline, Paint)` and `.words(_, Typeset)`
//    draw in palette roles (`Ink`), so the colour rules hold in light and dark (EXP-6). An
//    element's `transform` scales or moves it (a comparison's joined bars shrinking part of the
//    picture). `.ink` draws the learner's own kept line; `.hint` loops pieces a step looks at.
//
// 8. The screen (EXP-17): `question` is the problem's question, shown above the drawing in
//    portrait and at the top of the column in landscape; nil (the default) keeps it in the
//    drawing, and the question area then takes no space. `laidOut(for:)` is given the drawing
//    area's size in points and returns the explainer laid out for it, its scenes sized to suit
//    (`Scene.size`); by default the explainer is unchanged, and its 1000 by 540 stage is scaled to
//    fit and centred. The drawing area is about square or taller in both layouts.
//
// 9. The camera (EXP-18): a laid-out explainer may give its scenes a `Camera` that frames a shot
//    per step, with its shots and timings in its motion file (EXP-19). A
//    motion that moves the camera lists when in `cameraMoves`, so the player can hold it while
//    the learner's Pencil is down; marks are read in the drawing's units, through the camera.
//
// Lines are `Line`s from the explainer's wording, which the app fills;
// the package owns no strings. The player's own controls come from `GuidedLabels`.

import CoreGraphics
import Foundation

/// The parts of the child version, in order (EXP-8, EXP-14, EXP-15).
public enum GuidedPart: String, CaseIterable, Sendable {
    case watch
    case doWithMe
    case whatIf
    case tryOne
}

/// A mark the learner makes on the drawing with the Pencil or a finger (EXP-14), in scene units:
/// a touch, or a line once it is lifted. No handwriting is recognised; the explainer reads a mark
/// against what is drawn (`MarkGeometry`).
public enum Mark: Equatable, Sendable {
    case tap(CGPoint)
    case stroke([CGPoint])

    /// Where the mark starts: the touch, or a line's first point.
    public var at: CGPoint {
        switch self {
        case let .tap(p): p
        case let .stroke(points): points.first ?? .zero
        }
    }
}

/// A drag on the drawing, for a step that moves something (a dot dragged into a ten frame) and
/// for What if?'s picture (a bar's end), in scene units.
public enum Drag: Equatable, Sendable {
    case began(CGPoint)
    case moved(CGPoint)
    case ended(CGPoint)

    public var point: CGPoint {
        switch self {
        case let .began(p), let .moved(p), let .ended(p): p
        }
    }
}

/// How the learner's Pencil is read on a step the learner does.
public enum GuidedInput: Equatable, Sendable {
    /// Taps and lines, shown in pencil as they are drawn.
    case marks
    /// Drags, which the explainer draws itself as it reads them; no pencil line is shown.
    case drag
}

/// A step as the player needs to know it.
public struct GuidedStep: Equatable, Sendable {
    /// The step's name, for tests and the explainer's own use.
    public var id: String
    /// Whether the learner can make this step's marks in do it with me (EXP-14).
    public var doable: Bool
    /// Whether the step counts aloud: the player says its first line before it moves (EXP-10).
    public var countsAloud: Bool
    public var input: GuidedInput

    public init(_ id: String, doable: Bool = false, countsAloud: Bool = false, input: GuidedInput = .marks) {
        self.id = id
        self.doable = doable
        self.countsAloud = countsAloud
        self.input = input
    }
}

/// A line under the caption while the learner does a step.
public enum Note: Equatable, Sendable {
    /// Clears the line.
    case clear
    /// Shows a line without counting it as a miss ("That's more than we need. Cross out 2 more,
    /// one at a time.").
    case hint(Line)
    /// A mark the step could not use: shown and said, kindly; after the second on a step,
    /// the player adds that Show me is there (EXP-14).
    case miss(Line)
}

/// Dots under the line counting the marks a step needs, in the colour of its action.
public struct Tally: Equatable, Sendable {
    public var done: Int
    public var of: Int
    public var op: ExplainerOperation

    public init(_ done: Int, of: Int, op: ExplainerOperation = .subtract) {
        self.done = done
        self.of = of
        self.op = op
    }
}

/// What an explainer does with a mark, a drag, or the start of a step the learner does.
public struct Reaction<State: Sendable>: Sendable {
    /// The state after it: the picture shows it once `motion` has played.
    public var state: State
    /// Played from the picture before to `state`'s, with the lines it says; nil shows `state` at
    /// once. Its last line shown as a caption becomes the step's caption.
    public var motion: Motion?
    /// Cut off what is being said before `motion`'s lines: a count said in answer to a tap, so
    /// fast taps never fall behind the voice (EXP-10).
    public var interrupts: Bool
    /// The line under the caption: nil leaves it as it is.
    public var note: Note?
    /// The marks counted so far: nil leaves the tally as it is.
    public var tally: Tally?
    /// For a stroke: it was read as a mark and is now part of the drawing (in `state`). A stroke
    /// not kept fades away.
    public var keepsStroke: Bool
    /// One light haptic, where the device has an engine for it (a goal met, EXP-15).
    public var haptic: Bool
    /// The step is done once `motion` and its lines have played.
    public var finished: Bool

    public init(
        _ state: State, motion: Motion? = nil, interrupts: Bool = false, note: Note? = nil, tally: Tally? = nil,
        keepsStroke: Bool = false, haptic: Bool = false, finished: Bool = false
    ) {
        self.state = state
        self.motion = motion
        self.interrupts = interrupts
        self.note = note
        self.tally = tally
        self.keepsStroke = keepsStroke
        self.haptic = haptic
        self.finished = finished
    }

    /// Nothing changes: a mark the step ignores.
    public static func ignored(_ state: State) -> Reaction { Reaction(state) }
}

/// Where a What if? picture settles when the learner lets go, or when Show me moves it (EXP-15).
public struct Settle<Tinker: Sendable>: Sendable {
    public var state: Tinker
    /// How the picture moves there (a snap, Show me's slide); nil shows `state` at once.
    public var motion: Motion?
    /// The goal is met: the line said about it. Nil leaves the goal open, with no failure
    /// message.
    public var met: Line?

    public init(_ state: Tinker, motion: Motion? = nil, met: Line? = nil) {
        self.state = state
        self.motion = motion
        self.met = met
    }
}

/// An explainer for the child version's parts, filled with one problem's values. See the top of
/// this file for how one plugs in.
public protocol GuidedExplainer: Sendable {
    associatedtype State: Sendable
    /// What if?'s state: the picture the learner changes. `Never` when there is no What if?.
    associatedtype Tinker: Sendable = Never

    /// The steps, in order (named so as not to clash with an explainer's own `steps`).
    var guidedSteps: [GuidedStep] { get }
    var start: State { get }
    /// What the caption says before the first step of watch or of do it with me.
    func intro(_ part: GuidedPart) -> Line
    /// The still picture of `state`, with the digit step `marking` acts on marked (EXP-5).
    func picture(_ state: State, marking step: Int?) -> Scene
    /// Step `step` played from `state`: its motion and lines, and the state it ends in.
    func watch(_ step: Int, from state: State) -> (state: State, motion: Motion)

    // MARK: do it with me (EXP-14)

    /// What the learner is asked to do on step `step`; it is said before the learner can act.
    func instruction(_ step: Int, _ state: State) -> Line
    /// Frames step `step` for the learner before they are asked to act (EXP-18): the camera's move
    /// from `state` to the step's shot, played while the instruction is said, and the state it
    /// leaves (the same, framed). Nil when the camera stays where it is.
    func approach(_ step: Int, _ state: State) -> (state: State, motion: Motion)?
    /// The step opens for the learner's marks, once its instruction has been said.
    func begin(_ step: Int, _ state: State) -> Reaction<State>
    func read(_ mark: Mark, step: Int, _ state: State) -> Reaction<State>
    func read(_ drag: Drag, step: Int, _ state: State) -> Reaction<State>
    /// The lines step `step` says, after its instruction and what `begin` says, when the learner's
    /// marks are right, in order: the main path, which a voice that makes its lines on the
    /// device makes first. By default the lines the watched step says.
    func doneLines(_ step: Int, _ state: State) -> [Line]

    // MARK: Why? (EXP-16)

    /// The Why? of step `step` paused on `state`, played over the drawing; nil for none.
    func why(_ step: Int, _ state: State) -> Motion?

    // MARK: What if? (EXP-15)

    /// What if?'s first picture and its number of goals; nil when the explainer has none.
    var whatIf: (start: Tinker, goals: Int)? { get }
    /// Goal `goal` opens on `state`: its line, and the state it starts from (a goal may note
    /// something about the picture as it opens).
    func goal(_ goal: Int, _ state: Tinker) -> (line: Line, state: Tinker)
    func picture(whatIf state: Tinker) -> Scene
    /// The learner drags while goal `goal` is open: the picture follows at once.
    func drag(_ drag: Drag, goal: Int, _ state: Tinker) -> Tinker
    /// The learner lets go (`showMe` false), or taps Show me (true): where the picture settles and
    /// whether the goal is met. Show me always meets it.
    func settle(goal: Int, _ state: Tinker, showMe: Bool) -> Settle<Tinker>

    // MARK: try one

    /// The problem the learner tries alone, and the line said with it.
    var tryOne: (line: Line, scene: Scene) { get }

    // MARK: the screen (EXP-17)

    /// The problem's question, shown apart from the drawing; nil while the explainer keeps it in
    /// its drawing.
    var question: Line? { get }
    /// The explainer laid out for a drawing area of `area` points: the same problem and steps,
    /// with pictures drawn for that space. By default, itself.
    func laidOut(for area: CGSize) -> Self
}

extension GuidedExplainer {
    public func begin(_ step: Int, _ state: State) -> Reaction<State> { .ignored(state) }
    public func approach(_ step: Int, _ state: State) -> (state: State, motion: Motion)? { nil }
    public func read(_ mark: Mark, step: Int, _ state: State) -> Reaction<State> { .ignored(state) }
    public func read(_ drag: Drag, step: Int, _ state: State) -> Reaction<State> { .ignored(state) }
    public func why(_ step: Int, _ state: State) -> Motion? { nil }
    public func doneLines(_ step: Int, _ state: State) -> [Line] { watch(step, from: state).motion.said }
    public var question: Line? { nil }
    public func laidOut(for area: CGSize) -> Self { self }
}

extension Motion {
    /// The lines it says, in order.
    public var said: [Line] {
        script.events.compactMap {
            if case let .say(line, _) = $0.action { return line }
            return nil
        }
    }
}

extension GuidedExplainer where Tinker == Never {
    public var whatIf: (start: Never, goals: Int)? { nil }
    public func goal(_ goal: Int, _ state: Never) -> (line: Line, state: Never) { switch state {} }
    public func picture(whatIf state: Never) -> Scene { switch state {} }
    public func drag(_ drag: Drag, goal: Int, _ state: Never) -> Never { switch state {} }
    public func settle(goal: Int, _ state: Never, showMe: Bool) -> Settle<Never> { switch state {} }
}

/// The three problems of a child version (EXP-3, EXP-14): the method watched on one, done with
/// the learner on a second, and tried alone on a third, all of the same kind and none the learner's
/// own.
public struct GuidedLesson<E: GuidedExplainer>: Sendable {
    public var watch: E
    public var doWithMe: E
    public var tryOne: E

    public init(watch: E, doWithMe: E, tryOne: E) {
        self.watch = watch
        self.doWithMe = doWithMe
        self.tryOne = tryOne
    }
}
