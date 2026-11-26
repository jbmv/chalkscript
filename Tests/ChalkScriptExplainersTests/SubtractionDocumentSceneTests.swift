import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

/// The subtraction document played (EXP-19) against the running `SubtractionExplainer`: at the
/// start, a quarter, the middle, three quarters and the end of every step, and at each count and
/// just after it, over the template's sample problems in the learner's and the parent's playback,
/// on the stage and laid out for a tall drawing area, the document's scene is the template's
/// within `tolerance` drawing units and opacity, element by element.
struct SubtractionDocumentSceneTests {
    static let tolerance = 1e-6
    /// A count is compared just after its moment, since the two sum their times in different
    /// orders and so differ in the last bits.
    static let timeTolerance = 1e-9

    /// The template's element ids by the document's.
    static func templateID(_ id: String) -> String {
        let parts = id.split(separator: ".").map(String.init)
        switch parts.first {
        case "cten": return parts.count == 3 ? "tag.ten.\(parts[1])" : "count.ten.\(parts[1])"
        case "cone": return parts.count == 3 ? "tag.one.\(parts[1])" : "count.one.\(parts[1])"
        case "tensLabel": return "label.tens"
        case "onesLabel": return "label.ones"
        default: return id
        }
    }

    static func explainer(_ problem: SubtractionProblem, _ wording: String, _ playback: DocumentPlayback, area: CGSize?) throws -> DocumentExplainer {
        try DocumentExplainer(
            document: SubtractionDocumentTests.document,
            problem: ["a": .number(Double(problem.minuend)), "b": .number(Double(problem.subtrahend))], wording: wording, playback: playback,
            area: area)
    }

    /// The moments compared in step `k`.
    static func moments(_ e: SubtractionExplainer, _ k: Int) -> [Double] {
        let d = e.script(for: k).duration
        var out = [0, d / 4, d / 2, 3 * d / 4, d]
        if e.steps[k] == .count {
            let lead = e.lead(k, from: e.state(after: k - 1).shot)
            for t in e.countTimes.ticks { out += [t + lead + timeTolerance, t + lead + 0.1] }
        }
        return out
    }

    /// The differences the comparison allows, each from a known cause in the template or the
    /// reference, and how many moments each was allowed at.
    enum Known: String, CaseIterable {
        /// The template draws the copies of what is left at 0.9 opacity, rising to 1 as they move,
        /// and shows them from the step's start, during the camera's move; the reference's
        /// `gather` draws them at full opacity from the action's start, after the move.
        case copies
        /// The template colours the digit a step marks from the step's start, during the camera's
        /// move; the reference moves every time but the step's line later by the camera's lead.
        case markDuringLead
        /// The template's shots frame boxes round text (the total, the labels) and the trade
        /// arrow's stroke; the reference gives a text element's bounds as its anchor point, so
        /// the camera's view differs by up to `cameraTolerance` units.
        case cameraView
    }

    static let cameraTolerance = 36.0

    /// The template's scene with the known differences from `ours` taken out, counted in `known`.
    static func allowing(_ ours: Scene, _ theirs: Scene, step: SubtractionProblem.Step, at t: Double, lead: Double, _ known: inout [Known: Int]) -> Scene {
        var out = theirs
        if let a = ours.camera, let b = theirs.camera, a.viewport == b.viewport, a.dim == b.dim, (a.focus == nil) == (b.focus == nil),
            !SceneComparison.close(a, b, tolerance),
            [a.view.minX - b.view.minX, a.view.minY - b.view.minY, a.view.width - b.view.width, a.view.height - b.view.height].allSatisfy({ abs($0) <= cameraTolerance })
        {
            out.camera = a
            known[.cameraView, default: 0] += 1
        }
        let mine = Dictionary(ours.elements.map { (templateID($0.id), $0) }, uniquingKeysWith: { a, _ in a })
        var copies = false
        var marks = false
        out.elements = out.elements.compactMap { e in
            var e = e
            if step == .count, e.id.hasPrefix("count."), e.isVisible, e.opacity < 1 {
                copies = true
                guard let m = mine[e.id], m.isVisible, m.opacity > tolerance else { return t < lead ? nil : e }
                e.opacity = m.opacity
            }
            if t < lead, case var .equation(line) = e.kind, line.mark?.progress == 0, case let .equation(m)? = mine[e.id]?.kind, m.mark == nil {
                line.mark = nil
                e.kind = .equation(line)
                marks = true
            }
            return e
        }
        if copies { known[.copies, default: 0] += 1 }
        if marks { known[.markDuringLead, default: 0] += 1 }
        return out
    }

    @Test func everyStepDrawsAsTheTemplateDoes() throws {
        var differences: [String] = []
        var known: [Known: Int] = [:]
        var compared = 0
        for (a, b) in Fixture.edges {
            let problem = try SubtractionProblem(a, minus: b)
            for (version, wording, playback) in SubtractionDocumentTests.playbacks {
                for area in [nil, SubtractionDocumentTests.tall] {
                    var e = Fixture.explainer(a, b, version)
                    if let area { e = e.laidOut(for: area) }
                    let d = try Self.explainer(problem, wording, playback, area: area)
                    let label = "\(a) − \(b) \(version) \(area == nil ? "stage" : "tall")"
                    #expect(d.stepCount == e.stepCount, "\(label)")
                    for k in 0..<min(d.stepCount, e.stepCount) {
                        let lead = e.lead(k, from: e.state(after: k - 1).shot)
                        for t in Self.moments(e, k) {
                            compared += 1
                            let ours = d.scene(step: k, at: t)
                            let theirs = Self.allowing(ours, e.scene(step: k, at: t), step: e.steps[k], at: t, lead: lead, &known)
                            for x in SceneComparison.differences(ours, theirs, id: Self.templateID, tolerance: Self.tolerance) {
                                differences.append("\(label) \(e.steps[k]) t=\(t): \(x)")
                            }
                        }
                        compared += 1
                        let ours = d.still(after: k)
                        let theirs = Self.allowing(ours, e.still(after: k), step: e.steps[k], at: .infinity, lead: lead, &known)
                        for x in SceneComparison.differences(ours, theirs, id: Self.templateID, tolerance: Self.tolerance) {
                            differences.append("\(label) \(e.steps[k]) still: \(x)")
                        }
                    }
                }
            }
        }
        print("compared \(compared) scenes; allowed: " + Known.allCases.map { "\($0.rawValue) at \(known[$0] ?? 0)" }.joined(separator: ", "))
        if let path = ProcessInfo.processInfo.environment["CHALK_DIFFS"] {
            try differences.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        #expect(differences.isEmpty, "\(differences.count) differences, the first: \n\(differences.prefix(40).joined(separator: "\n"))")
    }
}

/// Compares two scenes element by element, by id, within a tolerance.
enum SceneComparison {
    static func differences(_ ours: Scene, _ theirs: Scene, id: (String) -> String, tolerance tol: Double) -> [String] {
        var out: [String] = []
        if !close(ours.size, theirs.size, tol) { out.append("size \(ours.size) against \(theirs.size)") }
        switch (ours.camera, theirs.camera) {
        case (nil, nil): break
        case let (a?, b?):
            if !close(a, b, tol) { out.append("camera \(describe(a)) against \(describe(b))") }
        default: out.append("camera \(ours.camera.map(describe) ?? "none") against \(theirs.camera.map(describe) ?? "none")")
        }
        var mine: [String: SceneElement] = [:]
        // An element fainter than the tolerance is not seen.
        for e in ours.visible where e.opacity > tol { mine[id(e.id)] = e }
        var their: [String: SceneElement] = [:]
        for e in theirs.visible where e.opacity > tol { their[e.id] = e }
        for k in Set(mine.keys).union(their.keys).sorted() {
            guard let a = mine[k] else { out.append("\(k) is not drawn (template: \(their[k]!.kind), opacity \(their[k]!.opacity))"); continue }
            guard let b = their[k] else { out.append("\(k) is drawn and the template does not draw it: \(a.kind), opacity \(a.opacity)"); continue }
            if abs(a.opacity - b.opacity) > tol { out.append("\(k) opacity \(a.opacity) against \(b.opacity)") }
            if a.fixed != b.fixed { out.append("\(k) fixed \(a.fixed) against \(b.fixed)") }
            if !close(a.transform, b.transform, tol) { out.append("\(k) transform \(a.transform) against \(b.transform)") }
            if !close(a.kind, b.kind, tol) { out.append("\(k) \(a.kind) against \(b.kind)") }
        }
        return out
    }

    static func describe(_ c: Camera) -> String { "view \(c.view) focus \(c.focus.map { "\($0)" } ?? "none") dim \(c.dim) shot \(c.shot ?? "-")" }

    static func close(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }
    static func close(_ a: CGPoint, _ b: CGPoint, _ tol: Double) -> Bool { close(a.x, b.x, tol) && close(a.y, b.y, tol) }
    static func close(_ a: CGSize, _ b: CGSize, _ tol: Double) -> Bool { close(a.width, b.width, tol) && close(a.height, b.height, tol) }
    static func close(_ a: CGRect, _ b: CGRect, _ tol: Double) -> Bool { close(a.origin, b.origin, tol) && close(a.size, b.size, tol) }
    static func close(_ a: CGRect?, _ b: CGRect?, _ tol: Double) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (x?, y?): close(x, y, tol)
        default: false
        }
    }
    static func close(_ a: [CGPoint], _ b: [CGPoint], _ tol: Double) -> Bool { a.count == b.count && zip(a, b).allSatisfy { close($0, $1, tol) } }
    static func close(_ a: CGAffineTransform, _ b: CGAffineTransform, _ tol: Double) -> Bool {
        [a.a - b.a, a.b - b.b, a.c - b.c, a.d - b.d, a.tx - b.tx, a.ty - b.ty].allSatisfy { abs($0) <= tol }
    }
    static func close(_ a: Camera, _ b: Camera, _ tol: Double) -> Bool {
        close(a.viewport, b.viewport, tol) && close(a.view, b.view, tol) && close(a.focus, b.focus, tol) && close(a.dim, b.dim, tol)
    }

    static func close(_ a: SceneElement.Kind, _ b: SceneElement.Kind, _ tol: Double) -> Bool {
        switch (a, b) {
        case let (.ten(r, s), .ten(q, t)), let (.one(r, s), .one(q, t)), let (.stick(r, s), .stick(q, t)), let (.circle(r, s), .circle(q, t)):
            return close(r, q, tol) && s == t
        case let (.crossOut(f, t, p), .crossOut(g, u, q)):
            return close(f, g, tol) && close(t, u, tol) && close(p, q, tol)
        case let (.arrow(ps, p, op), .arrow(qs, q, oq)):
            return close(ps, qs, tol) && close(p, q, tol) && op == oq
        case let (.box(r, p, op), .box(q, s, oq)):
            return close(r, q, tol) && close(p, s, tol) && op == oq
        case let (.divider(f, t), .divider(g, u)):
            return close(f, g, tol) && close(t, u, tol)
        case let (.label(s, p), .label(t, q)):
            return s == t && close(p, q, tol)
        case let (.total(s, p, k), .total(t, q, j)):
            return s == t && close(p, q, tol) && close(k, j, tol)
        case let (.numberTag(s, r, k), .numberTag(t, q, j)):
            return s == t && close(r, q, tol) && close(k, j, tol)
        case let (.hint(r, p), .hint(q, s)):
            return close(r, q, tol) && close(p, s, tol)
        case let (.equation(x), .equation(y)):
            guard x.runs.count == y.runs.count, close(x.center, y.center, tol), close(x.size, y.size, tol) else { return false }
            guard zip(x.runs, y.runs).allSatisfy({ $0.text == $1.text && $0.role == $1.role && close($0.opacity, $1.opacity, tol) }) else { return false }
            switch (x.mark, y.mark) {
            case (nil, nil): return true
            case let (m?, n?): return m.run == n.run && m.op == n.op && close(m.progress, n.progress, tol)
            default: return false
            }
        default:
            return a == b
        }
    }
}
