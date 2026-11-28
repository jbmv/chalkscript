import CoreGraphics
import CoreText
import Foundation

// Where instances are and what the camera frames (sections 8, 9 and 10 of the format's
// reference), as far as a step's timing needs it: a step's camera lead depends on whether its
// shot frames differently from the one the camera holds.

extension Resolver {
    /// The bounds of `instance` at its place (section 9.1): its `rect`; the box round the points
    /// of a line, arrow or shape; and, for a text element, the box its line of text fills as drawn.
    func bounds(_ instance: DocumentInstance) throws(EvalFailure) -> CGRect {
        let name = instance.element
        let p = DocumentPath.join("/elements", name)
        guard let el = root["elements"]?[name]?.object, let kind = el["kind"]?.string else {
            throw EvalFailure(path: p, message: "there is no element '\(name)'")
        }
        guard !boundsPending.contains(instance), boundsPending.count < Self.maxChain else {
            throw EvalFailure(path: p, message: "\(instance)'s bounds depend on themselves")
        }
        boundsPending.insert(instance)
        defer { boundsPending.remove(instance) }
        let l = try instanceLocals(instance)
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
        var b: CGRect
        let reference: CGPoint
        // What a turned instance's box is taken round, before it is turned (section 9.5).
        var turning: Turning.Geometry?
        switch kind {
        case "text":
            let at = try point("at")
            b = try textBox(el, name, at: at, locals: l)
            reference = at
        case "line":
            let from = try point("from")
            let to = try point("to")
            b = box([from, to])
            turning = .points([from, to])
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
            turning = .points(pts)
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
                turning = .points(pts)
                reference = pts.first ?? .zero
            } else {
                b = try rect(el["rect"] != nil ? "rect" : "ellipse")
                turning = el["rect"] != nil ? .rect(b) : .ellipse(b)
                reference = b.origin
            }
        default:
            b = try rect("rect")
            reference = b.origin
        }
        // A turned instance's bounds are the box round its geometry turned about its pivot, at
        // its place: the angle a `turn` has left, or else its `turn` key.
        if let turning {
            var angle = state[instance.whole]?.angle
            if angle == nil { angle = try number(p + "/turn", locals: l, default: 0, what: "turn") }
            if let angle, angle != 0 {
                let pivot = doc.expressions[p + "/pivot/0"] != nil ? try point("pivot") : reference
                b = Turning.box(of: turning, turned: angle, about: pivot)
            }
        }
        guard let place = state[instance.whole]?.place else { return b }
        return b.offsetBy(dx: place.x - reference.x, dy: place.y - reference.y)
    }

    /// The box text element `name` fills as drawn, at `at` before any verb has moved it: the line of
    /// the entry it shows before the first step, set with its bottom edge at `at` and its left,
    /// middle or right edge there by its anchor.
    func textBox(_ el: JSONObject, _ name: String, at: CGPoint, locals l: [String: DocumentValue]) throws(EvalFailure) -> CGRect {
        let p = DocumentPath.join("/elements", name)
        let style = el["style"]?.string ?? "body"
        let (size0, anchor0, _) = DocumentFilm.textDefaults[style] ?? DocumentFilm.textDefaults["body"]!
        let size = style == "total" ? Components.totalSize : try number(p + "/size", locals: l, default: size0, what: "size")
        let anchor = el["anchor"]?.string ?? anchor0
        var text = ""
        if let entry = el["text"]?.string { text = try DocumentFilm.runs(of: name, entry: entry, el: el, locals: l, self).map(\.text).joined() }
        return TextExtent.box(text, at: at, size: size, display: style != "label", anchor: anchor)
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
    /// The drawing's extent: the box round every instance seen through the camera, at its place.
    /// With the camera on, the layout's size is the shape of the picture shown, and the drawing
    /// may reach past it.
    let drawing: CGRect

    init(_ r: Resolver, size: CGSize) {
        resolver = r
        self.size = size
        let band = (try? r.number(DocumentPath.join("/layouts", r.layout, "band"), default: 0, what: "band")) ?? 0
        viewport = CGRect(x: 0, y: band, width: size.width, height: max(size.height - band, 1))
        var extent: CGRect?
        for (name, el) in r.root["elements"]?.object?.entries ?? [] where el["fixed"] != .bool(true) {
            let n = (try? r.instanceCount(name)) ?? 0
            let repeated = el["repeat"] != nil
            for k in 0..<n {
                guard let b = try? r.bounds(DocumentInstance(name, repeated ? k : nil)) else { continue }
                extent = extent.map { $0.union(b) } ?? b
            }
        }
        drawing = extent ?? CGRect(origin: .zero, size: size)
    }

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
        // A shot whose region contains the drawing's extent dims nothing.
        return framing(grown, focused: !grown.contains(drawing))
    }

    /// The region grown about its middle to the viewport's shape and, where it fits, slid to lie
    /// inside the box round the drawing's extent and the region; centred on that box where it
    /// does not fit.
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

/// Turning geometry about a point (section 9.5): the angle is in degrees, clockwise on the
/// drawing, whose y grows downward.
enum Turning {
    /// What a box is taken round: the points of a line, arrow or shape, or the rectangle or the
    /// ellipse of a shape.
    enum Geometry {
        case points([CGPoint])
        case rect(CGRect)
        case ellipse(CGRect)
    }

    /// `p` turned by `degrees` about `pivot`. A multiple of 30 turns by the exact sine and cosine
    /// of section 6.4, so that a quarter turn lands on whole numbers.
    static func turn(_ p: CGPoint, by degrees: Double, about pivot: CGPoint) -> CGPoint {
        let s = Evaluator.trigonometric(true, degrees: degrees)
        let c = Evaluator.trigonometric(false, degrees: degrees)
        let dx = p.x - pivot.x
        let dy = p.y - pivot.y
        return CGPoint(x: pivot.x + dx * c - dy * s, y: pivot.y + dx * s + dy * c)
    }

    /// The turn as a transform about `pivot`; the identity when it turns nothing.
    static func transform(by degrees: Double, about pivot: CGPoint) -> CGAffineTransform {
        if degrees == 0 { return .identity }
        let s = Evaluator.trigonometric(true, degrees: degrees)
        let c = Evaluator.trigonometric(false, degrees: degrees)
        return CGAffineTransform(a: c, b: s, c: -s, d: c, tx: pivot.x - pivot.x * c + pivot.y * s, ty: pivot.y - pivot.x * s - pivot.y * c)
    }

    /// The box round `geometry` turned by `degrees` about `pivot`: round the turned points, round
    /// the turned corners of a rectangle, and, for an ellipse, round the turned ellipse itself.
    static func box(of geometry: Geometry, turned degrees: Double, about pivot: CGPoint) -> CGRect {
        func round(_ points: [CGPoint]) -> CGRect {
            let turned = points.map { turn($0, by: degrees, about: pivot) }
            let xs = turned.map(\.x)
            let ys = turned.map(\.y)
            guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
        switch geometry {
        case let .points(points):
            return round(points)
        case let .rect(r):
            return round([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)])
        case let .ellipse(r):
            // The ellipse's centre turns about the pivot; its own half-extents turn with it.
            let centre = turn(CGPoint(x: r.midX, y: r.midY), by: degrees, about: pivot)
            let s = Evaluator.trigonometric(true, degrees: degrees)
            let c = Evaluator.trigonometric(false, degrees: degrees)
            let a = r.width / 2
            let b = r.height / 2
            let hx = (a * a * c * c + b * b * s * s).squareRoot()
            let hy = (a * a * s * s + b * b * c * c).squareRoot()
            return CGRect(x: centre.x - hx, y: centre.y - hy, width: 2 * hx, height: 2 * hy)
        }
    }
}

/// The size of a line of text in the faces the stage sets it in when it is given none of its own:
/// the system's bold face for a display line and its regular face for a small one. A stage given
/// other faces draws a line a little wider or narrower than this.
enum TextExtent {
    /// The box a line of `text` fills when set with its bottom edge at `at.y` and its left, middle or
    /// right edge at `at.x`, for the anchor `start`, `middle` or `end`.
    static func box(_ text: String, at: CGPoint, size: Double, display: Bool, anchor: String) -> CGRect {
        let (width, height) = measure(text, size: size, display: display)
        let x = anchor == "start" ? at.x : anchor == "end" ? at.x - width : at.x - width / 2
        return CGRect(x: x, y: at.y - height, width: width, height: height)
    }

    static func measure(_ text: String, size: Double, display: Bool) -> (width: CGFloat, height: CGFloat) {
        guard !text.isEmpty else { return (0, 0) }
        let face = CTFontCreateUIFontForLanguage(display ? .emphasizedSystem : .system, CGFloat(size), nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): face])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return (width, ascent + descent + leading)
    }
}
