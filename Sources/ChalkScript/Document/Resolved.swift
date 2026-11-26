import CoreGraphics
import Foundation

/// A document resolved for one problem, layout, wording, locale and playback (EXP-19): what a
/// player needs to play the watched part, without drawing. Times are on each step's clock, in
/// seconds, for a silent voice (section 12.6); a player that speaks adds the holds at `waits`.
public struct ResolvedExplainer: Sendable {
    public var problem: [String: DocumentValue]
    public var layout: String
    /// The drawing's size in its own units.
    public var size: CGSize
    /// Whether the drawing is seen through the camera.
    public var camera: Bool
    public var wording: String
    public var locale: String
    public var playback: DocumentPlayback
    /// The line said before the first step of the watched part, and before do it with me.
    public var intro: FilledEntry?
    public var guidedIntro: FilledEntry?
    /// The steps this problem has, in order.
    public var steps: [ResolvedStep]
    /// Entries the locale lacks, filled from the source locale instead (section 14.7).
    public var fallbacks: [String]

    public var stepNames: [String] { steps.map(\.name) }
}

/// One step resolved (sections 11 and 12).
public struct ResolvedStep: Sendable {
    public var name: String
    /// The shot the camera holds while the step plays.
    public var shot: String?
    /// The camera's move before the step's own timeline (section 12.5); 0 when it does not move.
    public var lead: Double
    /// The step's own timeline, from the lead: `duration`, or the latest end of its actions.
    public var timeline: Double
    public var hold: Double
    /// The step's length: lead, timeline and hold.
    public var duration: Double
    public var counts: Bool
    /// The step's line, said and shown as it begins.
    public var line: FilledEntry
    public var actions: [ResolvedAction]
    /// Every line said or shown during the step, in time order, the step's line first.
    public var lines: [ResolvedLine]
    /// The times at which the clock waits until every line begun before has been heard.
    public var waits: [Double]
}

/// One action of a step, or of an iteration of an `each`, resolved (sections 12 and 13).
public struct ResolvedAction: Sendable {
    public var name: String
    /// The JSON Pointer of the action in the document.
    public var path: String
    public var verb: String
    /// The instances it acts on, in the selection's order.
    public var targets: [DocumentInstance]
    public var start: Double
    /// How long it takes on each instance.
    public var duration: Double
    /// The seconds between one instance's start and the next.
    public var stagger: Double
    public var reverse: Bool
    /// For `cross`, the seconds the piece and its cross-out then take to fade to a ghost.
    public var fade: Double
    public var end: Double
    /// The curve its motion follows; nil for an instant verb, `say` and `each`.
    public var ease: String?
    public var mark: Bool
    public var waitsForVoice: Bool
    /// When each target starts, in the order of `targets`.
    public var starts: [Double]
    /// The text it shows or says, filled: `set`, `tag`, `appear` with text, and `say`.
    public var text: FilledEntry?
    /// The iterations of an `each`.
    public var iterations: [ResolvedIteration]
}

/// One iteration of an `each` (section 13.13).
public struct ResolvedIteration: Sendable {
    public var index: Int
    public var instance: DocumentInstance
    public var start: Double
    /// The iteration's locals: `i` and the `each`'s `let`.
    public var locals: [String: DocumentValue]
    public var actions: [ResolvedAction]
}

/// A line said or shown during a step (section 14.1).
public struct ResolvedLine: Equatable, Sendable {
    public var time: Double
    public var entry: FilledEntry
    /// Whether it is shown as the caption.
    public var caption: Bool
    /// Whether it is spoken: not a `visual` entry, and not a count when counts are shown.
    public var spoken: Bool
    /// Whether it is a count (`say` with `count: true`).
    public var count: Bool
    /// The action that says it; nil for the step's own line.
    public var action: String?
}

/// Why a document could not be resolved for a problem: it does not conform, the problem is
/// outside its parameters, or something evaluated for the problem fails (section 6.6).
public struct DocumentRefusal: Error, Sendable, CustomStringConvertible {
    public var findings: [DocumentFinding]
    public var description: String { findings.map(\.description).joined(separator: "\n") }
}
