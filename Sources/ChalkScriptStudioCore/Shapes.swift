#if os(macOS)
import ChalkScript
import struct ChalkScript.Scene
import CoreGraphics
import Foundation

/// The shape of drawing area the window plays a document at (EXP-17): the shape the pane gives,
/// or a ratio of width to height chosen to preview, which changes nothing in the document.
public enum ShapeChoice: Equatable, Sendable {
    case window
    case ratio(Double)
}

/// A shape the Shape menu offers: an end or the middle of a declared range, with the layout the
/// document chooses there.
public struct PreviewShape: Equatable, Sendable, Identifiable {
    public var ratio: Double
    public var layout: String
    public var id: String { Shapes.text(ratio) }
    /// "0.90 · tall".
    public var label: String { "\(Shapes.text(ratio)) · \(layout)" }
}

/// One row of the Declare Shapes sheet: an entry of `areas` as a person edits it, its ratios as
/// typed.
public struct DeclaredRow: Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var layout: String
    public var min: String
    public var max: String

    public init(layout: String, min: String, max: String) {
        self.layout = layout
        self.min = min
        self.max = max
    }

    init(layout: String, ratio: ClosedRange<Double>) {
        self.init(layout: layout, min: Canonical.number(ratio.lowerBound), max: Canonical.number(ratio.upperBound))
    }
}

/// The studio's arithmetic of declared shapes: the shapes it previews, the area of a shape, and
/// the patches that change a declaration.
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

    /// The area the layout at ratio `r` is named for in the menu and the suggestion.
    static func namingArea(_ r: Double) -> CGSize { CGSize(width: 1000 * r, height: 1000) }

    /// Whether the area used is the area given, within half a point.
    static func fills(_ use: AreaUse) -> Bool {
        abs(use.used.width - use.given.width) < 0.5 && abs(use.used.height - use.given.height) < 0.5
    }

    static func ratio(_ size: CGSize) -> Double? {
        size.width > 0 && size.height > 0 ? Double(size.width / size.height) : nil
    }

    /// The shapes previewed for a document that declares `areas`: each range's two ends and the
    /// ratio midway between them in ln r, in increasing order, a shape shared by two ranges listed
    /// once. Empty for a document without a declaration.
    public static func previews(_ doc: ExplainerDocument, problem: [String: DocumentValue]) -> [PreviewShape] {
        var ratios: [Double] = []
        for shape in doc.declaredShapes {
            let lo = shape.ratio.lowerBound, hi = shape.ratio.upperBound
            ratios += [lo, (lo * hi).squareRoot(), hi]
        }
        var seen = Set<String>()
        return ratios.sorted().compactMap { r in
            guard seen.insert(text(r)).inserted else { return nil }
            return PreviewShape(ratio: r, layout: doc.layout(for: namingArea(r), problem: problem))
        }
    }

    /// The names a declared range may name: `stage` and the document's other layouts.
    public static func layoutNames(_ doc: ExplainerDocument) -> [String] {
        ["stage"] + (doc.json["layouts"]?.object?.keys ?? []).filter { $0 != "stage" }.sorted()
    }

    /// The rows the Declare Shapes sheet starts from: the document's entries or, for a document
    /// without a declaration, a suggestion. The suggestion evaluates the layout rule for the
    /// first sample at ratios from 0.5 to 2.5 in steps of 0.05, and proposes one range for each
    /// run of ratios at which the same layout is chosen.
    public static func rows(_ doc: ExplainerDocument) -> [DeclaredRow] {
        if let entries = doc.json["areas"]?.array {
            return entries.map { e in
                let r = e["ratio"]?.array ?? []
                func end(_ k: Int) -> String {
                    if r.indices.contains(k), case let .number(n) = r[k] { return Canonical.number(n) }
                    return ""
                }
                return DeclaredRow(layout: e["layout"]?.string ?? "stage", min: end(0), max: end(1))
            }
        }
        return suggestion(doc).map { DeclaredRow(layout: $0.layout, ratio: $0.lo...$0.hi) }
    }

    static func suggestion(_ doc: ExplainerDocument) -> [(layout: String, lo: Double, hi: Double)] {
        let problem = doc.samples.first ?? [:]
        var runs: [(layout: String, lo: Double, hi: Double)] = []
        for k in 10...50 {
            let r = Double(k) / 20
            let chosen = doc.layout(for: namingArea(r), problem: problem)
            if let last = runs.last, last.layout == chosen {
                runs[runs.count - 1].hi = r
            } else {
                runs.append((chosen, r, r))
            }
        }
        return runs
    }

    /// The one-operation patch that makes the document's declaration `rows`: `add` for a document
    /// without one, `remove` for no rows, and otherwise `replace`. Nil when nothing changes.
    /// Throws a sentence for a person when a row's ratios are not positive numbers with the least
    /// no greater than the greatest.
    static func patch(_ doc: ExplainerDocument, rows: [DeclaredRow]) throws(ShapeError) -> [DocJSON]? {
        var entries: [DocJSON] = []
        for (k, row) in rows.enumerated() {
            let place = rows.count == 1 ? "The range" : "Range \(k + 1)"
            guard let lo = Double(row.min.trimmingCharacters(in: .whitespaces)),
                  let hi = Double(row.max.trimmingCharacters(in: .whitespaces)), lo.isFinite, hi.isFinite else {
                throw ShapeError("\(place) needs a number in each of its fields.")
            }
            guard lo > 0, hi > 0 else { throw ShapeError("\(place) has a ratio that is not greater than 0.") }
            guard lo <= hi else { throw ShapeError("\(place) has its least ratio greater than its greatest.") }
            entries.append(.object(DocObject([("layout", .string(row.layout)), ("ratio", .array([.number(lo), .number(hi)]))])))
        }
        let old = doc.json["areas"]
        if entries.isEmpty {
            return old == nil ? nil : [op("remove", "/areas")]
        }
        let value = DocJSON.array(entries)
        if old == value { return nil }
        return [op(old == nil ? "add" : "replace", "/areas", value)]
    }

    /// The patch that declares the shape `r` by moving the nearest end of the nearest range to
    /// it, rounded outward to two decimals so that `r` is inside. Nil for a document without a
    /// declaration, or when `r` is already declared.
    static func declaring(_ doc: ExplainerDocument, ratio r: Double) -> [DocJSON]? {
        guard r > 0, r.isFinite, !doc.declares(ratio: r), let entries = doc.json["areas"]?.array else { return nil }
        var best: (entry: Int, ratio: Double)?
        for (k, e) in entries.enumerated() {
            guard let ends = e["ratio"]?.array, ends.count == 2 else { continue }
            for end in ends {
                guard case let .number(n) = end, n > 0 else { continue }
                guard let b = best else { best = (k, n); continue }
                let d = abs(log(r) - log(n)), db = abs(log(r) - log(b.ratio))
                if d < db || (d == db && n > b.ratio) { best = (k, n) }
            }
        }
        guard let best else { return nil }
        // r is outside the nearest range, so the end to move is the lower one when r is below it.
        guard case let .number(lo)? = entries[best.entry]["ratio"]?.array?.first else { return nil }
        let lower = r < lo
        var value = (r * 100).rounded() / 100
        if lower && value > r { value -= 0.01 }
        if !lower && value < r { value += 0.01 }
        return [op("replace", "/areas/\(best.entry)/ratio/\(lower ? 0 : 1)", .number((value * 100).rounded() / 100))]
    }

    private static func op(_ name: String, _ path: String, _ value: DocJSON? = nil) -> DocJSON {
        var pairs: [(String, DocJSON)] = [("op", .string(name)), ("path", .string(path))]
        if let value { pairs.append(("value", value)) }
        return .object(DocObject(pairs))
    }
}

/// Why a declaration typed in the sheet cannot be written, in one sentence for a person.
public struct ShapeError: Error, Equatable {
    public var message: String
    init(_ message: String) { self.message = message }
}

/// A document's explainer as the window shows it at a shape (EXP-17): laid out for the largest
/// area of the chosen ratio inside the space the pane gives, or for that space itself, and in
/// either case as a conforming player lays it out, for the nearest declared shape when the
/// shape is not declared. Where the area used is not the whole space, the picture is set in the
/// area used, centred, and framed in the `line` role, so that the empty margin is seen.
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
    func script(for step: Int) -> StepScript { shown.script(for: step) }
    func scene(step: Int, at t: Double) -> Scene { framed(shown.scene(step: step, at: t)) }
    func still(after step: Int) -> Scene { framed(shown.still(after: step)) }

    func laidOutExplainer(for area: CGSize) -> any Explainer {
        let target = ratio.map { Shapes.area(ratio: $0, inside: area) } ?? area
        let laid = made.laidOutExplainer(for: target) as? DocumentExplainer ?? made
        let used = laid.areaUse?.used ?? target
        return ShapedExplainer(made: made, shown: laid, ratio: ratio, use: AreaUse(given: area, used: used))
    }

    var fillsSpace: Bool { use.map(Shapes.fills) ?? true }

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
