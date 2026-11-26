import CoreGraphics
import Foundation

/// The child or the parent version of an explainer (EXP-1, EXP-9): the same template and steps,
/// with the learner's or the parent's wording. The parent can skip ahead: the progress dots are
/// controls, and Next finishes a step that is playing. The child's version is paced (EXP-8).
public enum ExplainerVersion: String, CaseIterable, Sendable {
    case child
    case parent

    /// EXP-9: the parent can jump to any step.
    public var dotsAreControls: Bool { self == .parent }

    /// EXP-9: in the parent version Next stays available while a step plays and finishes it at
    /// once; in the learner's no step is cut short (EXP-8).
    public var nextFinishesStep: Bool { self == .parent }
}

/// One line, shown under the drawing and spoken (EXP-10): a wording entry filled with the
/// step's values. `key` names the entry, the wording entry the line was filled from.
public struct Line: Equatable, Sendable {
    public var key: String
    public var display: String
    /// What the voice says; nil when the entry is visual only.
    public var spoken: String?
    /// A part of `display` set in the result colour: the answer, in the last line.
    public var emphasis: String?

    public init(key: String, display: String, spoken: String?, emphasis: String? = nil) {
        self.key = key
        self.display = display
        self.spoken = spoken
        self.emphasis = emphasis
    }

    /// Where `emphasis` is in `display`: its last occurrence, since the answer ends the line.
    public var emphasisRange: Range<String.Index>? {
        guard let emphasis, !emphasis.isEmpty else { return nil }
        return display.range(of: emphasis, options: .backwards)
    }
}

/// What happens during one step besides the drawing's motion, at times on the step's clock.
public struct StepEvent: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Speak `line`, and show it as the caption when `caption` is true. Lines queue: each is
        /// spoken after the one before it.
        case say(Line, caption: Bool)
        /// Hold the step's clock here until everything said so far has been heard, so a count
        /// is spoken in time with the piece it counts (EXP-10). While it holds, the picture is
        /// the one just before this moment: what begins here is shown once the wait is over.
        case waitForVoice
    }

    public var time: Double
    public var action: Action

    public init(_ time: Double, _ action: Action) {
        self.time = time
        self.action = action
    }
}

/// One step's timing: its motion lasts `duration` seconds of its own clock, and its events
/// happen at their times. The step is finished once the clock reaches the end and every line it
/// said has been heard.
public struct StepScript: Equatable, Sendable {
    public var duration: Double
    public var events: [StepEvent]

    public init(duration: Double, events: [StepEvent]) {
        self.duration = duration
        self.events = events.sorted { $0.time < $1.time }
    }
}

/// An explainer filled with one problem's values (EXP-2): its steps, the picture at any moment of
/// a step, and what each step says. The player plays it; nothing in it runs on its own.
public protocol Explainer: Sendable {
    var version: ExplainerVersion { get }
    var stepCount: Int { get }
    /// What the caption says before the first step, under the Watch control.
    var intro: Line { get }
    /// Step `step`'s timing and lines.
    func script(for step: Int) -> StepScript
    /// The picture `t` seconds into step `step` (0 to its duration). At 0 it is the still picture
    /// of the step before; at its duration, the step's own still picture.
    func scene(step: Int, at t: Double) -> Scene
    /// The finished picture of step `step`, as Reduce Motion shows it (EXP-11); -1 is the
    /// picture before the first step.
    func still(after step: Int) -> Scene
    /// The explainer laid out for a drawing area of `area` points (EXP-17), with its camera where
    /// it has one (EXP-18): the same problem, steps and lines. By default, itself.
    func laidOutExplainer(for area: CGSize) -> any Explainer
    /// The area this explainer was laid out for and the one it was given, or nil when it has not
    /// been laid out for an area (EXP-17). By default, nil.
    var areaUse: AreaUse? { get }
}

extension Explainer {
    public func laidOutExplainer(for area: CGSize) -> any Explainer { self }
    public var areaUse: AreaUse? { nil }
}
