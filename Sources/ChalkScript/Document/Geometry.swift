import CoreGraphics
import Foundation

// Where instances are and what the camera frames (sections 8, 9 and 10 of the format's
// reference), as far as a step's timing needs it: a step's camera lead depends on whether its
// shot frames differently from the one the camera holds.

extension Resolver {
    /// The bounds of `instance` at its place (section 9.1): its `rect`; the box round the points
    /// of a line, arrow or shape; and, for a text element, the point `at` with no size.
    func bounds(_ instance: DocumentInstance) throws(EvalFailure) -> CGRect {
        let name = instance.element
        let p = DocumentPath.join("/elements", name)
        guard let el = root["elements"]?[name]?.object, let kind = el["kind"]?.string else {
            throw EvalFailure(path: p, message: "there is no element '\(name)'")
        }
        let l: [String: DocumentValue] = instance.index.map { ["i": .number(Double($0))] } ?? [:]
        func point(_ key: String) throws(EvalFailure) -> CGPoint {
            CGPoint(x: try number(p + "/\(key)/0", locals: l, what: "x"), y: try number(p + "/\(key)/1", locals: l, what: "y"))
        }
        func rect(_ key: String) throws(EvalFailure) -> CGRect {
            CGRect(x: try number(p + "/\(key)/0", locals: l, what: "x"), y: try number(p + "/\(key)/1", locals: l, what: "y"),
                   width: try number(p + "/\(key)/2", locals: l, what: "width"), height: try number(p + "/\(key)/3", locals: l, what: "height"))
        }
        func box(_ points: [CGPoint]) -> CGRect {
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        /// An arrow's end: a point, or 8 units above the middle of the top edge of one instance.
        func end(_ key: String) throws(EvalFailure) -> CGPoint {
            if doc.expressions[p + "/" + key] != nil {
                let s = try selection(p + "/" + key, locals: l)
                guard s.count == 1, let one = s.instances.first else {
                    throw EvalFailure(path: p + "/" + key, message: "an arrow's \(key) selects \(s.count) instances, not one")
                }
                let b = try bounds(one)
                return CGPoint(x: b.midX, y: b.minY - 8)
            }
            return try point(key)
        }
        let b: CGRect
        let reference: CGPoint
        switch kind {
        case "text":
            let at = try point("at")
            b = CGRect(origin: at, size: .zero)
            reference = at
        case "line":
            let from = try point("from")
            b = box([from, try point("to")])
            reference = from
        case "arrow":
            let from = try end("from")
            let to = try end("to")
            var pts = [from, to]
            if doc.expressions[p + "/y"] != nil {
                let y = try number(p + "/y", locals: l, what: "y")
                pts += [CGPoint(x: from.x, y: y), CGPoint(x: to.x, y: y)]
            }
            b = box(pts)
            reference = from
        case "outline":
            if doc.expressions[p + "/around"] != nil {
                let s = try selection(p + "/around", locals: l)
                var u: CGRect?
                for inst in s.instances {
                    let r = try bounds(inst.whole)
                    u = u.map { $0.union(r) } ?? r
                }
                let pad = try number(p + "/pad", locals: l, default: el["style"]?.string == "hint" ? 12 : 0, what: "pad")
                let r = (u ?? .zero).insetBy(dx: -pad, dy: -pad)
                b = r
                reference = r.origin
            } else {
                b = try rect("rect")
                reference = b.origin
            }
        case "shape":
            if el["points"] != nil {
                let n = el["points"]?.array?.count ?? 0
                var pts: [CGPoint] = []
                for k in 0..<n { pts.append(try point("points/\(k)")) }
                b = pts.isEmpty ? .zero : box(pts)
                reference = pts.first ?? .zero
            } else {
                b = try rect(el["rect"] != nil ? "rect" : "ellipse")
                reference = b.origin
            }
        default:
            b = try rect("rect")
            reference = b.origin
        }
        guard let place = state[instance.whole]?.place else { return b }
        return b.offsetBy(dx: place.x - reference.x, dy: place.y - reference.y)
    }

    /// The region of part `name` (section 10.1): the box round the bounds of its instances at
    /// their places; nil when it selects nothing.
    func region(ofPart name: String) throws(EvalFailure) -> CGRect? {
        let s = try selection(DocumentPath.join("/parts", name))
        var u: CGRect?
        for inst in s.instances {
            let r = try bounds(inst.whole)
            u = u.map { $0.union(r) } ?? r
        }
        return u
    }
}

/// How the camera frames each shot in a layout with `camera: true` (section 10.3).
struct CameraFraming {
    /// What a shot shows: the view of the drawing, and the region outside which elements are
    /// dimmed (nil when nothing is).
    struct Frame: Equatable {
        var view: CGRect
        var region: CGRect?
    }

    let resolver: Resolver
    let size: CGSize
    let viewport: CGRect

    init(_ r: Resolver, size: CGSize) {
        resolver = r
        self.size = size
        let band = (try? r.number(DocumentPath.join("/layouts", r.layout, "band"), default: 0, what: "band")) ?? 0
        viewport = CGRect(x: 0, y: band, width: size.width, height: max(size.height - band, 1))
    }

    var drawing: CGRect { CGRect(origin: .zero, size: size) }

    func frame(_ shot: String?) throws(EvalFailure) -> Frame {
        guard let shot, let spec = resolver.root["shots"]?[shot]?.object else { return framing(drawing, focused: false) }
        let p = DocumentPath.join("/shots", shot)
        var region: CGRect?
        for part in spec["frame"]?.array?.compactMap(\.string) ?? [] {
            if let r = try resolver.region(ofPart: part) { region = region.map { $0.union(r) } ?? r }
        }
        if resolver.doc.expressions[p + "/region/0"] != nil {
            let r = CGRect(
                x: try resolver.number(p + "/region/0", what: "x"), y: try resolver.number(p + "/region/1", what: "y"),
                width: try resolver.number(p + "/region/2", what: "width"), height: try resolver.number(p + "/region/3", what: "height"))
            region = region.map { $0.union(r) } ?? r
        }
        guard let r = region else { return framing(drawing, focused: false) }
        let margin = try resolver.number(p + "/margin", default: resolver.cameraMargin, what: "margin")
        let grown = r.insetBy(dx: -margin, dy: -margin)
        // A shot whose region contains the whole drawing dims nothing.
        return framing(grown, focused: !grown.contains(drawing))
    }

    /// The region grown about its middle to the viewport's shape and, where it fits, slid to lie
    /// inside the box round the drawing and the region.
    func framing(_ region: CGRect, focused: Bool) -> Frame {
        var view = region
        let aspect = viewport.width / viewport.height
        if view.width / max(view.height, 1e-9) < aspect {
            let w = view.height * aspect
            view = CGRect(x: view.midX - w / 2, y: view.minY, width: w, height: view.height)
        } else {
            let h = view.width / aspect
            view = CGRect(x: view.minX, y: view.midY - h / 2, width: view.width, height: h)
        }
        let bounds = drawing.union(region)
        func slide(_ lo: CGFloat, _ len: CGFloat, _ bLo: CGFloat, _ bLen: CGFloat) -> CGFloat {
            if len >= bLen { return bLo + (bLen - len) / 2 }
            return min(max(lo, bLo), bLo + bLen - len)
        }
        view.origin.x = slide(view.minX, view.width, bounds.minX, bounds.width)
        view.origin.y = slide(view.minY, view.height, bounds.minY, bounds.height)
        return Frame(view: view, region: focused ? region : nil)
    }
}
