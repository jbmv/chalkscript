#if os(macOS)
import ChalkScript
import struct ChalkScript.Scene
import CoreGraphics
import Foundation

/// What the window previews the shown document at (EXP-17): nothing, so that the document is
/// played in the pane's own area as an app would play it, or a ratio of width to height. A
/// preview changes nothing in the document.
public enum PreviewChoice: Equatable, Sendable {
    case none
    case ratio(Double)
}

/// The studio's three names for ranges of shape (EXP-17), with the ratio each is previewed at
/// and that an agent arranges for. The format has no presets: a document stores the ranges.
public enum Preset: String, CaseIterable, Identifiable, Sendable {
    case tall, square, wide

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tall: "Tall"
        case .square: "Square"
        case .wide: "Wide"
        }
    }

    /// The least and greatest ratio of width to height.
    public var range: ClosedRange<Double> {
        switch self {
        case .tall: 0.6...0.9
        case .square: 0.9...1.35
        case .wide: 1.35...2.2
        }
    }

    /// The ratio the preview shows.
    public var nominal: Double {
        switch self {
        case .tall: 0.75
        case .square: 1.1
        case .wide: 1.78
        }
    }

    /// The presets, consecutive, whose ranges together are exactly `lo` to `hi`.
    static func run(from lo: Double, to hi: Double) -> [Preset]? {
        let all = allCases
        guard let i = all.firstIndex(where: { abs($0.range.lowerBound - lo) < 1e-9 }),
              let j = all.firstIndex(where: { abs($0.range.upperBound - hi) < 1e-9 }), i <= j else { return nil }
        return Array(all[i...j])
    }
}

/// A ratio the Preview menu offers: a preset the document is made for at its nominal ratio, or a
/// custom range at the ratio midway between its ends in ln r.
public struct PreviewItem: Equatable, Sendable, Identifiable {
    public var title: String
    public var ratio: Double
    public var id: String { title }
    /// "Tall · 0.75".
    public var label: String { "\(title) · \(Shapes.text(ratio))" }
}

/// The studio's arithmetic of shapes: what the Preview menu offers, the area of a shape, and the
/// presets a document is made for.
public enum Shapes {
    /// A ratio as the studio writes it, to two decimals.
    public static func text(_ r: Double) -> String { String(format: "%.2f", r) }

    /// The area of ratio `r` whose longer side is `side`.
    static func area(ratio r: Double, longerSide side: Double) -> CGSize {
        r >= 1 ? CGSize(width: side, height: side / r) : CGSize(width: side * r, height: side)
    }

    /// The largest area of ratio `r` inside `space`. Its width is its height times `r`, so that
    /// a `suits` written as `areaW <= areaH * r` is true at an end of a range, as it is meant to be.
    static func area(ratio r: Double, inside space: CGSize) -> CGSize {
        let h = min(Double(space.height), Double(space.width) / r)
        return CGSize(width: h * r, height: h)
    }

    /// The area at which the layout of ratio `r` is chosen for a suggestion.
    static func namingArea(_ r: Double) -> CGSize { CGSize(width: 1000 * r, height: 1000) }

    /// Whether the area used is the area given, within half a point.
    static func fills(_ use: AreaUse) -> Bool {
        abs(use.used.width - use.given.width) < 0.5 && abs(use.used.height - use.given.height) < 0.5
    }

    static func ratio(_ size: CGSize) -> Double? {
        size.width > 0 && size.height > 0 ? Double(size.width / size.height) : nil
    }

    /// The shapes a document is made for, each as a preview: each preset the document is made
    /// for at its nominal ratio, and each custom range at its middle in ln r.
    public static func previews(_ doc: ExplainerDocument) -> [PreviewItem] {
        guard doc.declaresAreas else { return [] }
        var presets = Set<Preset>()
        var customs: [PreviewItem] = []
        for entry in doc.json["areas"]?.array ?? [] {
            let ends = entry["ratio"]?.array ?? []
            var lo: Double?, hi: Double?
            if ends.count == 2, case let .number(a) = ends[0], case let .number(b) = ends[1] { (lo, hi) = (a, b) }
            guard let lo, let hi else { continue }
            if let run = Preset.run(from: lo, to: hi), run.allSatisfy({ !presets.contains($0) }) {
                presets.formUnion(run)
            } else if lo.isFinite, hi.isFinite, lo > 0, lo <= hi {
                customs.append(PreviewItem(title: "Custom \(text(lo)) to \(text(hi))", ratio: (lo * hi).squareRoot()))
            }
        }
        return Preset.allCases.filter(presets.contains).map { PreviewItem(title: $0.title, ratio: $0.nominal) } + customs
    }

    /// A range as written in `areas`.
    struct Span: Equatable {
        var layout: String
        var lo: Double
        var hi: Double
    }

    // MARK: the presets a document is made for

    /// The presets the document is made for: those whose nominal ratio it declares. None for a
    /// document without `areas`.
    public static func madeFor(_ doc: ExplainerDocument) -> Set<Preset> {
        guard doc.declaresAreas else { return [] }
        return Set(Preset.allCases.filter { p in doc.declaredShapes.contains { $0.ratio.contains(p.nominal) } })
    }

    /// The patch that makes the document made for exactly `presets`, or nil when it already is.
    /// It writes `areas` and nothing else: each preset's range names the layout the document's
    /// own rule chooses there for its first sample, split where the rule changes layout, so no
    /// layout is made, removed or given another `suits`. A declared range that lies wholly
    /// outside the presets' ratios is kept. With no preset and no such range, `areas` is removed.
    static func ops(_ doc: ExplainerDocument, madeFor presets: Set<Preset>) -> [DocJSON]? {
        guard presets != madeFor(doc) else { return nil }
        let problem = doc.samples.first ?? [:]
        let step = 0.01
        func hundredths(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        var spans: [Span] = []
        for p in Preset.allCases where presets.contains(p) {
            let lo = p.range.lowerBound
            let count = Int(((p.range.upperBound - lo) / step).rounded())
            for i in 0..<count {
                let layout = doc.layout(for: namingArea(lo + (Double(i) + 0.5) * step), problem: problem)
                let from = hundredths(lo + Double(i) * step), to = hundredths(lo + Double(i + 1) * step)
                if let last = spans.last, last.layout == layout, abs(last.hi - from) < 1e-9 {
                    spans[spans.count - 1].hi = to
                } else {
                    spans.append(Span(layout: layout, lo: from, hi: to))
                }
            }
        }
        // The rule's own boundary may fall exactly on a range's end and choose the layout on the
        // other side there. Unless a neighbouring range names that layout at the end, the end
        // moves in by a step, so that the reader finds the declaration and the rule agree.
        for k in spans.indices {
            func settled(_ end: Double) -> Bool {
                let chosen = doc.layout(for: area(ratio: end, longerSide: 1000), problem: problem)
                return chosen == spans[k].layout || spans.contains { $0.layout == chosen && $0.lo <= end && end <= $0.hi }
            }
            if !settled(spans[k].lo) { spans[k].lo = hundredths(spans[k].lo + step) }
            if !settled(spans[k].hi) { spans[k].hi = hundredths(spans[k].hi - step) }
        }
        spans.removeAll { $0.lo > $0.hi }
        let all = Preset.tall.range.lowerBound...Preset.wide.range.upperBound
        let kept = doc.declaredShapes
            .filter { $0.ratio.upperBound < all.lowerBound || $0.ratio.lowerBound > all.upperBound }
            .map { Span(layout: $0.layout, lo: $0.ratio.lowerBound, hi: $0.ratio.upperBound) }
        spans = (spans + kept).sorted { $0.lo < $1.lo }
        let has = doc.json["areas"] != nil
        if spans.isEmpty { return has ? [op("remove", "/areas")] : nil }
        let entries = DocJSON.array(spans.map { .object(DocObject([("layout", .string($0.layout)), ("ratio", .array([.number($0.lo), .number($0.hi)]))])) })
        return [op(has ? "replace" : "add", "/areas", entries)]
    }

    private static func op(_ name: String, _ path: String, _ value: DocJSON? = nil) -> DocJSON {
        var pairs: [(String, DocJSON)] = [("op", .string(name)), ("path", .string(path))]
        if let value { pairs.append(("value", value)) }
        return .object(DocObject(pairs))
    }
}

/// A document's explainer as the window shows it (EXP-17): laid out for the largest area of the
/// previewed ratio inside the space the pane gives, or for that space itself, and in either case
/// as a conforming player lays it out, for the nearest shape the document is made for when the
/// area is not one. A preview that does not fill the space is set in the area used, centred, and
/// framed in the `line` role, so that the empty margin is seen; without a preview the drawing is
/// shown as an app shows it, with no frame.
struct ShapedExplainer: Explainer {
    /// The explainer as made, before it is laid out for an area.
    let made: DocumentExplainer
    /// The explainer as laid out for the area used.
    let shown: DocumentExplainer
    let ratio: Double?
    let use: AreaUse?

    init(_ made: DocumentExplainer, ratio: Double?) {
        self.made = made
        self.shown = made
        self.ratio = ratio
        self.use = nil
    }

    private init(made: DocumentExplainer, shown: DocumentExplainer, ratio: Double?, use: AreaUse) {
        self.made = made
        self.shown = shown
        self.ratio = ratio
        self.use = use
    }

    var version: ExplainerVersion { shown.version }
    var stepCount: Int { shown.stepCount }
    var intro: Line { shown.intro }
    var areaUse: AreaUse? { use }
    /// The document's own, so that the player draws it only in an appearance it is made for (EXP-20).
    var appearances: Set<Appearance> { made.appearances }
    func script(for step: Int) -> StepScript { shown.script(for: step) }
    func scene(step: Int, at t: Double) -> Scene { framed(shown.scene(step: step, at: t)) }
    func still(after step: Int) -> Scene { framed(shown.still(after: step)) }

    func laidOutExplainer(for area: CGSize) -> any Explainer {
        let target = ratio.map { Shapes.area(ratio: $0, inside: area) } ?? area
        let laid = made.laidOutExplainer(for: target) as? DocumentExplainer ?? made
        let used = laid.areaUse?.used ?? target
        return ShapedExplainer(made: made, shown: laid, ratio: ratio, use: AreaUse(given: area, used: used))
    }

    /// Whether the picture is drawn as it is, unframed: without a preview, or where the area
    /// used fills the space.
    var fillsSpace: Bool { ratio == nil || use.map(Shapes.fills) ?? true }

    /// `scene` widened to the area used's shape, with its picture centred in it as the stage
    /// would fit it there, and a frame of one point round it.
    func framed(_ scene: Scene) -> Scene {
        guard !fillsSpace, let use, let r = Shapes.ratio(use.used), scene.size.width > 0, scene.size.height > 0 else { return scene }
        let s = scene.size
        let size = Double(s.width / s.height) < r ? CGSize(width: s.height * r, height: s.height) : CGSize(width: s.width, height: s.width / r)
        let dx = (size.width - s.width) / 2, dy = (size.height - s.height) / 2
        let shift = CGAffineTransform(translationX: dx, y: dy)
        var out = scene
        out.size = size
        // Under a camera, what is not fixed is placed by the camera's viewport, which moves; the
        // rest is in the scene's own units and moves itself.
        out.elements = scene.elements.map { e in
            guard scene.camera == nil || e.fixed else { return e }
            var moved = e
            moved.transform = e.transform.concatenating(shift)
            return moved
        }
        if let camera = scene.camera { out.camera?.viewport = camera.viewport.offsetBy(dx: dx, dy: dy) }
        let width = size.width / max(use.used.width, 1)
        let edge = CGRect(origin: .zero, size: size).insetBy(dx: width / 2, dy: width / 2)
        out.elements.append(SceneElement("studio.areaFrame", .shape(.rect(edge), Paint(stroke: .line, width: width)), fixed: true))
        return out
    }
}
#endif
