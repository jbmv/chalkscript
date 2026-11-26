import CoreGraphics
import Foundation

/// An explainer played from a document (EXP-19): the watched part of an explainer document,
/// resolved for one problem's values, wording, language and playback options, and drawn with the
/// shared components (EXP-13), so that `ExplainerPlayer` and `ExplainerView` play it as they play
/// a Swift template.
///
/// The paced playback is the learner's version and the skippable one the parent's (EXP-8,
/// EXP-9). A document this player cannot draw in full is refused, naming what it does not draw
/// (section 2.3 of the format's reference: it must not draw an approximation).
public struct DocumentExplainer: Explainer {
    public let document: ExplainerDocument
    public let problem: [String: DocumentValue]
    /// The document resolved for the problem and the layout it is drawn in.
    public let resolved: ResolvedExplainer
    let area: CGSize?
    /// The area the document was laid out for and the one it was given; nil when no area was given.
    public let areaUse: AreaUse?
    let film: DocumentFilm

    /// - Parameters:
    ///   - wording: nil takes the wording the document suggests for the playback's control, or
    ///     else its first.
    ///   - locale: nil is the document's source locale.
    ///   - area: the drawing area, in points; nil is the stage. A document that declares `areas` is
    ///     laid out for the nearest declared shape that fits in it, which `areaUse` reports.
    /// - Throws: `DocumentRefusal` when the document has an error, the problem is outside its
    ///   parameters, the document is not sound for it, or it uses something this player does not
    ///   draw yet.
    public init(
        document: ExplainerDocument, problem: [String: DocumentValue], wording: String? = nil, locale: String? = nil,
        playback: DocumentPlayback = DocumentPlayback(), area: CGSize? = nil
    ) throws(DocumentRefusal) {
        let use = area.map { document.areaUse(for: $0) }
        let laidOutFor = use?.used
        let resolved = try document.resolve(problem: problem, wording: wording, locale: locale, playback: playback, area: laidOutFor)
        let r = Resolver(
            document, problem: problem, layout: resolved.layout, area: laidOutFor, wording: resolved.wording, locale: resolved.locale, playback: playback)
        do {
            film = try DocumentFilm(resolved, resolver: r)
        } catch {
            throw DocumentRefusal(findings: [DocumentFinding(.error, error.code, error.path, at: error.at, values: problem, error.message)])
        }
        self.document = document
        self.problem = problem
        self.resolved = resolved
        self.area = laidOutFor
        self.areaUse = use
    }

    public var playback: DocumentPlayback { resolved.playback }

    /// The skippable playback is played as the parent's version, the paced one as the learner's.
    public var version: ExplainerVersion { resolved.playback.control == .skippable ? .parent : .child }

    public var stepCount: Int { resolved.steps.count }

    public var intro: Line { resolved.intro?.line ?? Line(key: "", display: "", spoken: nil) }

    /// The step's line first, said as it begins; then, at each moment, the waits for the voice
    /// before the lines said there, since a wait holds for the lines begun before it (section
    /// 12.6).
    public func script(for step: Int) -> StepScript {
        let s = resolved.steps[step]
        var events: [(Double, Int, Int, StepEvent)] = []
        for (k, line) in s.lines.enumerated() where line.spoken || line.caption {
            var l = line.entry.line
            if !line.spoken { l.spoken = nil }
            let first = k == 0 && line.action == nil
            events.append((line.time, first ? 0 : 2, k, StepEvent(line.time, .say(l, caption: line.caption))))
        }
        for (k, t) in s.waits.enumerated() { events.append((t, 1, k, StepEvent(t, .waitForVoice))) }
        events.sort { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }
        return StepScript(duration: s.duration, events: events.map(\.3))
    }

    public func scene(step: Int, at t: Double) -> Scene {
        let s = resolved.steps[step]
        if t >= s.duration { return still(after: step) }
        var looks = film.carried[step]
        for track in film.tracks[step] { track.apply(at: t, to: &looks) }
        return film.scene(looks, camera: camera(step, at: t))
    }

    public func still(after step: Int) -> Scene {
        guard step >= 0 else { return film.scene(film.carried[0], camera: film.camera(film.opening)) }
        return film.scene(film.stills[step], camera: film.camera(resolved.steps[step].shot))
    }

    public func laidOutExplainer(for area: CGSize) -> any Explainer {
        (try? DocumentExplainer(
            document: document, problem: problem, wording: resolved.wording, locale: resolved.locale, playback: resolved.playback, area: area))
            ?? self
    }

    /// The shot the camera holds as step `step` begins: the one the step before played in, or
    /// the opening shot.
    func shot(before step: Int) -> String? { step > 0 ? resolved.steps[step - 1].shot : film.opening }

    /// The camera `t` seconds into step `step`: moving from the shot it held to the step's own
    /// during the lead, then holding (sections 10.4 and 12.5).
    func camera(_ step: Int, at t: Double) -> Camera? {
        guard film.cameraOn else { return nil }
        let s = resolved.steps[step]
        let to = film.camera(s.shot)
        guard s.lead > 0, let a = film.camera(shot(before: step)), let b = to else { return to }
        return Camera.between(a, b, film.cameraMove.fraction(at: t))
    }
}
