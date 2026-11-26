import CoreGraphics
import Foundation

/// The drawing area an explainer was laid out for, and the one it was given (EXP-17): a host app
/// may show it, log it or ignore it. They differ when a document declares the shapes of area it
/// is made for and the area given is not one of them; the explainer is then laid out for the
/// largest area of the nearest declared shape that fits in the one given, centred in it.
public struct AreaUse: Equatable, Sendable {
    /// The area the player was given.
    public var given: CGSize
    /// The area the explainer was laid out for.
    public var used: CGSize

    public init(given: CGSize, used: CGSize) {
        self.given = given
        self.used = used
    }

    /// Whether the area used is the area given.
    public var isGiven: Bool { used == given }
}

/// One declared range of shapes (section 8.2 of the format's reference).
public struct DeclaredShape: Equatable, Sendable {
    /// The layout the document is drawn in at these shapes.
    public var layout: String
    /// The least and greatest ratio of the area's width to its height.
    public var ratio: ClosedRange<Double>
}

extension ExplainerDocument {
    /// The ranges of shape the document declares in `areas`; empty for a document without it.
    public var declaredShapes: [DeclaredShape] {
        areaEntries.compactMap { e in e.min <= e.max ? DeclaredShape(layout: e.layout, ratio: e.min...e.max) : nil }
    }

    /// Whether the document declares `areas`.
    public var declaresAreas: Bool { !areaEntries.isEmpty }

    /// Whether a drawing area of this size has a declared shape. A document without `areas`
    /// declares nothing, so no area is among its shapes.
    public func declares(_ area: CGSize) -> Bool {
        guard area.width > 0, area.height > 0 else { return false }
        return declares(ratio: Double(area.width / area.height))
    }

    /// Whether `ratio` of width to height is a declared shape.
    public func declares(ratio r: Double) -> Bool {
        areaEntries.contains { $0.min <= r && r <= $0.max }
    }

    /// Whether every ratio from `low` to `high` is declared: the ranges, taken together, cover
    /// the interval with no gap.
    public func declares(ratiosFrom low: Double, to high: Double) -> Bool {
        guard low <= high else { return false }
        var reach = low
        var covered = false
        for e in areaEntries.sorted(by: { $0.min < $1.min }) {
            guard e.min <= reach else { break }
            if e.max >= reach {
                reach = e.max
                covered = true
            }
        }
        return covered && reach >= high
    }

    /// The area the document is laid out for when a player is given `area` (section 8.2): the
    /// area itself without `areas` or at a declared shape; otherwise the largest area of the
    /// nearest declared shape that fits in it.
    public func areaUse(for area: CGSize) -> AreaUse {
        let given = AreaUse(given: area, used: area)
        let entries = areaEntries.filter { $0.min <= $0.max && $0.min > 0 }
        guard !entries.isEmpty, area.width > 0, area.height > 0 else { return given }
        let w = Double(area.width), h = Double(area.height)
        let r = w / h
        if entries.contains(where: { $0.min <= r && r <= $0.max }) { return given }
        // The nearest end of any range by |ln r - ln r'|; the greater when two are equally near.
        var best: Double?
        for end in entries.flatMap({ [$0.min, $0.max] }) {
            guard let b = best else { best = end; continue }
            let d = abs(log(r) - log(end)), db = abs(log(r) - log(b))
            if d < db || (d == db && end > b) { best = end }
        }
        guard let target = best else { return given }
        let used = target < r ? CGSize(width: h * target, height: h) : CGSize(width: w, height: w / target)
        return AreaUse(given: area, used: used)
    }
}
