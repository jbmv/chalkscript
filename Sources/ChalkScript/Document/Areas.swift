import CoreGraphics
import Foundation

extension ExplainerDocument {
    /// One entry of `areas` (section 8.2): the layout drawn in, and the least and greatest ratio
    /// of the area's width to its height.
    struct AreaEntry {
        var layout: String
        var min: Double
        var max: Double
    }

    /// The entries of `areas` as the reader accepts them; empty without a declaration or when it
    /// is malformed (which the reader reports as an error).
    var areaEntries: [AreaEntry] {
        guard case let .array(entries)? = root["areas"] else { return [] }
        return entries.compactMap { e in
            guard let layout = e["layout"]?.string, case let .array(r)? = e["ratio"], r.count == 2,
                  case let .number(lo) = r[0], case let .number(hi) = r[1] else { return nil }
            return AreaEntry(layout: layout, min: lo, max: hi)
        }
    }

    /// The ratios a reader checks for one entry (section 21, `areas`): its two ends and seven
    /// between them, evenly spaced in ln r; one ratio for an entry that declares one shape.
    static func checkedRatios(_ e: AreaEntry) -> [Double] {
        guard e.max > e.min else { return [e.min] }
        let span = log(e.max / e.min)
        return [e.min] + (1...7).map { e.min * exp(span * Double($0) / 8) } + [e.max]
    }

    /// The area of ratio `r` whose longer side is `side` points.
    static func area(ratio r: Double, longerSide side: Double) -> CGSize {
        r >= 1 ? CGSize(width: side, height: side / r) : CGSize(width: side * r, height: side)
    }

    /// The warnings section 21 gives the code `areas`, for a document that has `areas`: a
    /// declared shape at which another layout is chosen, a layout no entry names, and a `suits`
    /// that depends on the area's size. The check evaluates each sample at the ratios of
    /// `checkedRatios`, so every reader reports the same findings.
    func areaFindings() -> [DocumentFinding] {
        let entries = areaEntries
        guard !entries.isEmpty else { return [] }
        var out: [DocumentFinding] = []
        let samples: [[String: DocumentValue]] = (root["samples"]?.array ?? []).map { s in
            var values: [String: DocumentValue] = [:]
            for (k, v) in s.object?.entries ?? [] { values[k] = DocumentValue(json: v) }
            return values
        }
        func text(_ r: Double) -> String { String(format: "%.2f", r) }

        // A layout no entry names.
        let named = Set(entries.map(\.layout))
        for name in (root["layouts"]?.object?.keys ?? []).sorted() where name != "stage" && !named.contains(name) {
            out.append(.warning(.areas, DocumentPath.join("/layouts", name), "no entry of areas names this layout"))
        }

        // A declared shape at which another layout is chosen.
        for (k, e) in entries.enumerated() {
            for values in samples {
                for r in Self.checkedRatios(e) {
                    let chosen = layout(for: Self.area(ratio: r, longerSide: 1000), problem: values)
                    let allowed = entries.filter { $0.min <= r && r <= $0.max }.map(\.layout)
                    if chosen != e.layout, !allowed.contains(chosen) {
                        out.append(DocumentFinding(.warning, .areas, "/areas/\(k)", values: values,
                            "at ratio \(text(r)) the layout is \(chosen), not \(e.layout)"))
                        break
                    }
                }
            }
        }

        // A `suits` that depends on the area's size.
        var reported = Set<String>()
        for name in (root["layouts"]?.object?.keys ?? []).sorted() where name != "stage" {
            search: for values in samples {
                for e in entries {
                    for r in Self.checkedRatios(e) {
                        let large = suits(name, area: Self.area(ratio: r, longerSide: 1000), problem: values)
                        let small = suits(name, area: Self.area(ratio: r, longerSide: 500), problem: values)
                        if large != small, reported.insert(name).inserted {
                            out.append(DocumentFinding(.warning, .areas, DocumentPath.join("/layouts", name, "suits"), values: values,
                                "its value at ratio \(text(r)) depends on the area's size, which areas cannot declare"))
                            break search
                        }
                    }
                }
            }
        }
        return out
    }
}
