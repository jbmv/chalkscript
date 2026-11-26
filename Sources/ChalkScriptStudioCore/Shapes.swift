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

    /// The preset whose range holds `r`; at the end two ranges share, the one whose nominal
    /// ratio is nearer in ln r.
    public static func holding(_ r: Double) -> Preset? {
        allCases.filter { $0.range.contains(r) }.min { abs(log(r / $0.nominal)) < abs(log(r / $1.nominal)) }
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

/// One row of the Layouts sheet: a preset, ticked when the document is made for it, or a custom
/// range given by its two ratios as typed; and the layout the document is drawn in there.
public struct LayoutRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let preset: Preset?
    /// Whether the document is made for the row's shapes. A custom row is always on.
    public var isOn: Bool
    public var min: String
    public var max: String
    public var layout: String

    init(preset: Preset, isOn: Bool, layout: String) {
        id = preset.rawValue
        self.preset = preset
        self.isOn = isOn
        min = Canonical.number(preset.range.lowerBound)
        max = Canonical.number(preset.range.upperBound)
        self.layout = layout
    }

    init(customID id: String, min: String, max: String, layout: String) {
        self.id = id
        preset = nil
        isOn = true
        self.min = min
        self.max = max
        self.layout = layout
    }

    /// "Tall", or "Custom".
    public var title: String { preset?.title ?? "Custom" }

    /// The row's ratios, when they are positive numbers with the least no greater than the greatest.
    public var bounds: (lo: Double, hi: Double)? {
        guard let lo = Double(min.trimmingCharacters(in: .whitespaces)), let hi = Double(max.trimmingCharacters(in: .whitespaces)),
              lo.isFinite, hi.isFinite, lo > 0, lo <= hi else { return nil }
        return (lo, hi)
    }

    /// "Tall", or "Custom 0.45 to 0.60": the row as another row's menu names it.
    public var name: String {
        guard preset == nil else { return title }
        guard let b = bounds else { return "Custom" }
        return "Custom \(Shapes.text(b.lo)) to \(Shapes.text(b.hi))"
    }
}

/// What the Layouts sheet edits (EXP-17): which presets the document is made for, any custom
/// ranges, and for each the layout it is drawn in, either a layout of the document or a new
/// layout that starts as a copy of one. Saving it writes `areas`, the new layouts, and the
/// `suits` of each layout whose shapes changed (`Shapes.patch`).
public struct LayoutPlan: Equatable, Sendable {
    /// The three presets in order, then the custom ranges.
    public var rows: [LayoutRow]
    /// The layouts the plan makes, each mapped to the layout it starts as a copy of.
    public private(set) var copies: [String: String] = [:]
    /// `stage` and the document's layouts.
    public let layouts: [String]
    /// Whether the document declares `areas`; otherwise the plan is a suggestion.
    public let declared: Bool
    private var serial = 0

    /// The plan the document's `areas` says: each entry whose range is exactly one preset, or
    /// several presets that follow one another, ticks those presets; any other entry is a
    /// custom range. For a document without `areas`, every preset is ticked, each with the
    /// layout the document chooses at its nominal ratio for the first sample.
    public init(_ doc: ExplainerDocument) {
        layouts = Shapes.layoutNames(doc)
        let problem = doc.samples.first ?? [:]
        let entries = doc.json["areas"]?.array
        declared = entries != nil
        var presetLayout: [Preset: String] = [:]
        var customs: [LayoutRow] = []
        for (k, e) in (entries ?? []).enumerated() {
            let layout = e["layout"]?.string ?? "stage"
            let ends = e["ratio"]?.array ?? []
            func end(_ i: Int) -> Double? {
                if ends.count == 2, case let .number(n) = ends[i] { return n }
                return nil
            }
            if let lo = end(0), let hi = end(1), let run = Preset.run(from: lo, to: hi), run.allSatisfy({ presetLayout[$0] == nil }) {
                for p in run { presetLayout[p] = layout }
            } else {
                customs.append(LayoutRow(customID: "entry\(k)", min: end(0).map(Canonical.number) ?? "", max: end(1).map(Canonical.number) ?? "", layout: layout))
            }
        }
        rows = Preset.allCases.map { p in
            LayoutRow(preset: p, isOn: entries == nil || presetLayout[p] != nil,
                      layout: presetLayout[p] ?? doc.layout(for: Shapes.namingArea(p.nominal), problem: problem))
        } + customs
    }

    /// The rows the document is made for.
    public var included: [LayoutRow] { rows.filter(\.isOn) }

    /// The other rows on that are drawn in the same layout as the row `id`.
    public func sharing(_ id: String) -> [LayoutRow] {
        guard let row = rows.first(where: { $0.id == id }) else { return [] }
        return included.filter { $0.id != id && $0.layout == row.layout }
    }

    /// The layouts of the document that no row on is drawn in.
    public var unused: [String] {
        layouts.filter { name in !included.contains { $0.layout == name } }
    }

    public mutating func setOn(_ id: String, _ on: Bool) {
        guard let i = index(id) else { return }
        rows[i].isOn = on
        prune()
    }

    /// Draws the row `id` in the layout of the row `other`.
    public mutating func useSame(_ id: String, as other: String) {
        guard let i = index(id), let o = index(other) else { return }
        rows[i].layout = rows[o].layout
        prune()
    }

    /// Draws the row `id` in a layout of the document.
    public mutating func use(_ id: String, layout name: String) {
        guard let i = index(id), layouts.contains(name) else { return }
        rows[i].layout = name
        prune()
    }

    /// Gives the row `id` a layout no other row is drawn in. A row that has one keeps it;
    /// otherwise a new layout is made, named for the row, that starts as a copy of the layout
    /// the row is drawn in now.
    public mutating func useOwn(_ id: String) {
        guard let i = index(id), !sharing(id).isEmpty || !(layouts.contains(rows[i].layout) || copies[rows[i].layout] != nil) else { return }
        let source = copies[rows[i].layout] ?? (layouts.contains(rows[i].layout) ? rows[i].layout : "stage")
        let base = rows[i].preset?.rawValue ?? "custom"
        var name = base
        var k = 2
        while layouts.contains(name) || copies[name] != nil { name = "\(base)\(k)"; k += 1 }
        copies[name] = source
        rows[i].layout = name
    }

    /// Makes the new layout `name` start as a copy of the document's layout `source`.
    public mutating func setCopySource(of name: String, to source: String) {
        guard copies[name] != nil, layouts.contains(source) else { return }
        copies[name] = source
    }

    /// Adds a custom range, drawn in `stage`, and returns its id.
    @discardableResult
    public mutating func addCustom(min: String = "", max: String = "", layout: String = "stage") -> String {
        serial += 1
        let id = "added\(serial)"
        rows.append(LayoutRow(customID: id, min: min, max: max, layout: layout))
        return id
    }

    public mutating func removeCustom(_ id: String) {
        rows.removeAll { $0.id == id && $0.preset == nil }
        prune()
    }

    /// The plan that makes the document made for ratio `r`, drawn in `layout`, and how a button
    /// names it: the preset that holds `r`, when it is off and overlaps no custom range, or
    /// otherwise the nearest end of the nearest range moved to `r`, rounded outward to two
    /// decimals. Nil when no row is on, or `r` is already inside a range.
    public func adding(ratio r: Double, layout: String) -> (plan: LayoutPlan, label: String)? {
        guard r > 0, r.isFinite else { return nil }
        let on = included.compactMap { row in row.bounds.map { (row: row, lo: $0.lo, hi: $0.hi) } }
        guard !on.isEmpty, !on.contains(where: { $0.lo <= r && r <= $0.hi }) else { return nil }
        var next = self
        if let p = Preset.holding(r), let i = next.index(p.rawValue), !rows[i].isOn,
           !on.contains(where: { $0.row.preset == nil && $0.lo < p.range.upperBound && p.range.lowerBound < $0.hi }) {
            next.rows[i].isOn = true
            next.rows[i].layout = layout
            return (next, "Add \(p.title)")
        }
        var best: (id: String, end: Double)?
        for x in on {
            for end in [x.lo, x.hi] {
                guard let b = best else { best = (x.row.id, end); continue }
                let d = abs(log(r / end)), db = abs(log(r / b.end))
                if d < db || (d == db && end > b.end) { best = (x.row.id, end) }
            }
        }
        guard let best, let i = next.index(best.id), let b = next.rows[i].bounds else { return nil }
        let lower = r < b.lo
        var value = (r * 100).rounded() / 100
        if lower && value > r { value -= 0.01 }
        if !lower && value < r { value += 0.01 }
        value = (value * 100).rounded() / 100
        let lo = lower ? value : b.lo, hi = lower ? b.hi : value
        if next.rows[i].preset == nil {
            next.rows[i].min = Canonical.number(lo)
            next.rows[i].max = Canonical.number(hi)
        } else {
            // A preset's range is fixed, so the widened range is a custom one.
            next.rows[i].isOn = false
            next.addCustom(min: Canonical.number(lo), max: Canonical.number(hi), layout: rows[i].layout)
        }
        return (next, "Add \(Shapes.text(r))")
    }

    private func index(_ id: String) -> Int? { rows.firstIndex { $0.id == id } }

    /// Forgets a new layout no row on is drawn in; a row that is off and was drawn in it is
    /// drawn in the layout it was a copy of.
    private mutating func prune() {
        for (name, source) in copies where !included.contains(where: { $0.layout == name }) {
            copies[name] = nil
            for i in rows.indices where rows[i].layout == name { rows[i].layout = source }
        }
    }
}

/// Why the Layouts sheet cannot be saved, in one sentence for a person.
public struct ShapeError: Error, Equatable {
    public var message: String
    init(_ message: String) { self.message = message }
}

/// The studio's arithmetic of shapes: what the Preview menu offers, the area of a shape, and the
/// patch that writes a plan of layouts.
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

    /// What the Preview menu offers between None and Test Ratio: each preset the document is made
    /// for at its nominal ratio, and each custom range at its middle in ln r.
    public static func previews(_ doc: ExplainerDocument) -> [PreviewItem] {
        guard doc.declaresAreas else { return [] }
        return LayoutPlan(doc).included.compactMap { row in
            if let p = row.preset { return PreviewItem(title: p.title, ratio: p.nominal) }
            guard let b = row.bounds else { return nil }
            return PreviewItem(title: row.name, ratio: (b.lo * b.hi).squareRoot())
        }
    }

    /// The names a range may be drawn in: `stage` and the document's other layouts.
    public static func layoutNames(_ doc: ExplainerDocument) -> [String] {
        ["stage"] + (doc.json["layouts"]?.object?.keys ?? []).filter { $0 != "stage" }.sorted()
    }

    /// A range the plan declares, as written in `areas`.
    struct Span: Equatable {
        var layout: String
        var lo: Double
        var hi: Double
    }

    /// The ranges of the plan's rows on, in increasing order, a range that meets or overlaps
    /// the next in the same layout joined to it. Throws a sentence for a person when a custom
    /// range is not two positive numbers, least first, or two ranges in different layouts
    /// overlap.
    static func ranges(_ plan: LayoutPlan) throws(ShapeError) -> [Span] {
        var out: [Span] = []
        for row in plan.included {
            guard let b = row.bounds else {
                guard let lo = Double(row.min.trimmingCharacters(in: .whitespaces)), let hi = Double(row.max.trimmingCharacters(in: .whitespaces)),
                      lo.isFinite, hi.isFinite else {
                    throw ShapeError("A custom range needs a number in each of its fields.")
                }
                if lo <= 0 || hi <= 0 { throw ShapeError("A custom range has a ratio that is not greater than 0.") }
                throw ShapeError("A custom range has its least ratio greater than its greatest.")
            }
            out.append(Span(layout: row.layout, lo: b.lo, hi: b.hi))
        }
        return try joined(out)
    }

    /// The entries of the document's `areas`, joined as `ranges` joins a plan's.
    static func ranges(_ doc: ExplainerDocument) -> [Span] {
        let entries = doc.declaredShapes.map { Span(layout: $0.layout, lo: $0.ratio.lowerBound, hi: $0.ratio.upperBound) }
        return (try? joined(entries)) ?? entries.sorted { $0.lo < $1.lo }
    }

    private static func joined(_ ranges: [Span]) throws(ShapeError) -> [Span] {
        var out: [Span] = []
        for r in ranges.sorted(by: { ($0.lo, $0.hi) < ($1.lo, $1.hi) }) {
            if let last = out.last, r.lo <= last.hi {
                if r.layout == last.layout {
                    out[out.count - 1].hi = Swift.max(last.hi, r.hi)
                    continue
                }
                if r.lo < last.hi {
                    throw ShapeError("The ranges \(text(last.lo)) to \(text(last.hi)) and \(text(r.lo)) to \(text(r.hi)) overlap and have different layouts; ranges may meet at an end.")
                }
            }
            out.append(r)
        }
        return out
    }

    /// The part of the ratio axis in which each layout other than `stage` is to be chosen, for
    /// ranges in increasing order that do not overlap: each range up to where the next begins
    /// when they meet, and otherwise up to a ratio in the gap, near its middle in ln r, so that
    /// no declared shape lies on a boundary that rounding could move. The lowest range reaches
    /// down without bound and the highest up. Each part is a run of lower and upper bounds, nil
    /// for none.
    static func regions(_ ranges: [Span]) -> [String: [(lo: Double?, hi: Double?)]] {
        var bounds: [Double] = []
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            bounds.append(a.hi == b.lo ? a.hi : between(a.hi, b.lo))
        }
        var out: [String: [(lo: Double?, hi: Double?)]] = [:]
        var k = 0
        while k < ranges.count {
            var j = k
            while j + 1 < ranges.count, ranges[j + 1].layout == ranges[k].layout { j += 1 }
            let lo = k == 0 ? nil : bounds[k - 1]
            let hi = j == ranges.count - 1 ? nil : bounds[j]
            out[ranges[k].layout, default: []].append((lo, hi))
            k = j + 1
        }
        out["stage"] = nil
        return out
    }

    /// A ratio strictly between `a` and `b`, with as few decimals as it can have, near their
    /// middle in ln r.
    static func between(_ a: Double, _ b: Double) -> Double {
        let middle = (a * b).squareRoot()
        for d in 2...6 {
            let scale = pow(10, Double(d))
            let v = (middle * scale).rounded() / scale
            if a < v && v < b { return v }
        }
        return middle
    }

    /// A `suits` true in exactly `parts` of the ratio axis.
    static func suits(_ parts: [(lo: Double?, hi: Double?)]) -> String {
        let terms = parts.map { part in
            [part.lo.map { "areaW >= areaH * \(Canonical.number($0))" }, part.hi.map { "areaW <= areaH * \(Canonical.number($0))" }].compactMap { $0 }
        }
        if terms.contains(where: \.isEmpty) { return "true" }
        if terms.count == 1 { return terms[0].joined(separator: " and ") }
        return terms.map { $0.count == 1 ? $0[0] : "(" + $0.joined(separator: " and ") + ")" }.joined(separator: " or ")
    }

    /// The patch that makes the document what `plan` says, or nil when the plan is the one the
    /// document's `areas` gives (`original`) or changes nothing. It writes `areas`, adds each new layout
    /// as a copy of its source, and writes the `suits` of each layout whose part of the ratio
    /// axis changed, so that the layout chosen at every declared shape is the one its range
    /// names; when another layout's `suits` would still disagree, it writes every layout's.
    /// Throws a sentence for a person when a range cannot be written, when a layout of the
    /// document would be drawn at no shape, or when the result would have an `areas` warning
    /// the document does not have.
    static func patch(_ doc: ExplainerDocument, plan: LayoutPlan, original: LayoutPlan) throws(ShapeError) -> [DocJSON]? {
        // A document without `areas` opens on a suggestion, which saving declares.
        if plan == original, doc.declaresAreas { return nil }
        let wanted = try ranges(plan)
        guard !wanted.isEmpty else {
            return doc.json["areas"] == nil ? nil : [op("remove", "/areas")]
        }
        let before = ranges(doc)
        let named = Set(wanted.map(\.layout))
        for name in Set(before.map(\.layout)).subtracting(named).sorted() where name != "stage" {
            throw ShapeError("The layout \(name) would be drawn at no shape. Choose it for a shape; the sheet does not remove a layout.")
        }

        let entries = DocJSON.array(wanted.map { .object(DocObject([("layout", .string($0.layout)), ("ratio", .array([.number($0.lo), .number($0.hi)]))])) })
        let parts = regions(wanted)
        let old = doc.declaresAreas ? regions(before) : [:]
        func same(_ a: [(lo: Double?, hi: Double?)]?, _ b: [(lo: Double?, hi: Double?)]?) -> Bool {
            guard let a, let b, a.count == b.count else { return a == nil && b == nil }
            return zip(a, b).allSatisfy { $0.lo == $1.lo && $0.hi == $1.hi }
        }
        let layouts = doc.json["layouts"]?.object
        let made = plan.copies.filter { named.contains($0.key) }
        let existing = parts.keys.filter { made[$0] == nil }
        let changed = existing.filter { !same(parts[$0], old[$0]) }

        func ops(rewriting rewrite: [String]) -> [DocJSON] {
            var ops: [DocJSON] = []
            let areas = doc.json["areas"]
            if areas != entries { ops.append(op(areas == nil ? "add" : "replace", "/areas", entries)) }
            if layouts == nil, !made.isEmpty { ops.append(op("add", "/layouts", .object(DocObject()))) }
            for name in rewrite.sorted() {
                let path = DocumentPath.join("/layouts", name, "suits")
                let value = DocJSON.string(suits(parts[name] ?? []))
                let current = layouts?[name]?["suits"]
                if current != value { ops.append(op(current == nil ? "add" : "replace", path, value)) }
            }
            for (name, source) in made.sorted(by: { $0.key < $1.key }) {
                var copy = DocObject([("suits", .string(suits(parts[name] ?? [])))])
                let from = layouts?[source]?.object ?? DocObject()
                for (k, v) in from.entries where k != "suits" { copy[k] = v }
                if copy["size"] == nil { copy["size"] = .array([.number(Double(Scene.stage.width)), .number(Double(Scene.stage.height))]) }
                ops.append(op("add", DocumentPath.join("/layouts", name), .object(copy)))
            }
            return ops
        }

        let warnings = Set(doc.findings.filter { $0.code == .areas }.map(\.message))
        func added(_ ops: [DocJSON]) -> [DocumentFinding]? {
            let result = doc.patch(base: doc.shortHash, ops: ops)
            // A refusal is the patch engine's to report, with its findings.
            guard result.applied else { return nil }
            return result.document.findings.filter { $0.code == .areas && !warnings.contains($0.message) }
        }
        var attempt = ops(rewriting: changed)
        if let new = added(attempt), !new.isEmpty, changed.count < existing.count {
            attempt = ops(rewriting: existing)
        }
        if let new = added(attempt), let first = new.first {
            throw ShapeError("The layouts' suits cannot be made to agree with these ranges: \(first.message) (\(first.path)).")
        }
        return attempt.isEmpty ? nil : attempt
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
