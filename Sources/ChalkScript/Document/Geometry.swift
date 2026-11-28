import CoreGraphics
import CoreText
import Foundation

// Where instances are and what the camera frames (sections 8, 9 and 10 of the format's
// reference), as far as a step's timing needs it: a step's camera lead depends on whether its
// shot frames differently from the one the camera holds.

/// One entry of a shape's `points` at its place (section 9.3): a point, or an arc.
enum OutlineEntry: Equatable, Sendable {
    case point(CGPoint)
    case arc(Arc)

    var start: CGPoint {
        switch self {
        case let .point(p): p
        case let .arc(a): a.start
        }
    }

    /// The outline of `entries`: straight lines when every entry is a point, and otherwise a path
    /// in which each arc is joined to what comes before it by a straight line to its start. A closed
    /// outline closes from its last entry to its first, straight.
    static func outline(_ entries: [OutlineEntry], closed: Bool) -> Outline {
        var points: [CGPoint] = []
        for case let .point(p) in entries { points.append(p) }
        if points.count == entries.count { return .lines(points, closed: closed) }
        var segments: [Outline.Segment] = []
        for entry in entries {
            switch entry {
            case let .point(p): segments.append(segments.isEmpty ? .move(p) : .line(p))
            case let .arc(a):
                segments.append(segments.isEmpty ? .move(a.start) : .line(a.start))
                segments.append(.arc(a))
            }
        }
        if closed { segments.append(.close) }
        return .path(segments)
    }

    /// The entries of a path of moves, lines and arcs; nil when it has any other segment.
    static func entries(of segments: [Outline.Segment]) -> [OutlineEntry]? {
        var out: [OutlineEntry] = []
        for s in segments {
            switch s {
            case let .move(p), let .line(p):
                out.append(.point(p))
            case let .arc(a):
                // The move or line to the arc's start is part of the arc, not a point of its own.
                if case let .point(q)? = out.last, q == a.start { out.removeLast() }
                out.append(.arc(a))
            case .close: break
            case .quad, .curve: return nil
            }
        }
        return out
    }
}

extension Resolver {
    /// The entries of shape instance `instance`'s `points` (section 9.3): `[x, y]` points, and arcs
    /// `{"arc": [cx, cy, r], "from", "to"}` or `[cx, cy, rx, ry]`.
    func outlineEntries(_ instance: DocumentInstance, locals l: [String: DocumentValue]) throws(EvalFailure) -> [OutlineEntry] {
        let p = DocumentPath.join("/elements", instance.element)
        var out: [OutlineEntry] = []
        for (k, entry) in (root["elements"]?[instance.element]?["points"]?.array ?? []).enumerated() {
            let pk = p + "/points/\(k)"
            guard entry.object != nil else {
                out.append(.point(CGPoint(x: try number(pk + "/0", locals: l, what: "x"), y: try number(pk + "/1", locals: l, what: "y"))))
                continue
            }
            let rx = try number(pk + "/arc/2", locals: l, what: "radius")
            let arc = Arc(
                centre: CGPoint(x: try number(pk + "/arc/0", locals: l, what: "x"), y: try number(pk + "/arc/1", locals: l, what: "y")),
                rx: rx, ry: doc.expressions[pk + "/arc/3"] != nil ? try number(pk + "/arc/3", locals: l, what: "radius") : rx,
                from: try number(pk + "/from", locals: l, what: "from"), to: try number(pk + "/to", locals: l, what: "to"))
            guard abs(arc.to - arc.from) <= 360 + 1e-9 else {
                throw EvalFailure(path: pk, message: "an arc from \(Canonical.number(arc.from)) to \(Canonical.number(arc.to)) sweeps more than 360 degrees")
            }
            out.append(.arc(arc))
        }
        return out
    }

    /// The bounds of `instance` at its place (section 9.1): its `rect`; the box round the points
    /// of a line, arrow or shape; and, for a text element, the box its line of text fills as drawn.
    ///
    /// With `up`, the box is in the frame of a picture turned to show the direction `up` at its top
    /// (section 10.3, `Camera.intoFrame`): round the geometry as that picture shows it, and, for a
    /// text element, which the picture keeps upright, its own box about its turned `at`.
    func bounds(_ instance: DocumentInstance, up: Double = 0) throws(EvalFailure) -> CGRect {
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
        // A group's members, whose boxes in a turned frame make the group's there.
        var groupMembers: [DocumentInstance] = []
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
                let entries = try outlineEntries(instance, locals: l)
                b = entries.isEmpty ? .zero : Turning.box(of: .entries(entries), turned: 0, about: .zero)
                turning = .entries(entries)
                reference = entries.first?.start ?? .zero
            } else {
                b = try rect(el["rect"] != nil ? "rect" : "ellipse")
                turning = el["rect"] != nil ? .rect(b) : .ellipse(b)
                reference = b.origin
            }
        case "group":
            // A group has no geometry of its own: its bounds are the box round its members' bounds, and
            // its reference point is the middle of that box.
            var u: CGRect?
            groupMembers = try members(of: instance)
            for member in groupMembers {
                let r = try bounds(member)
                u = u.map { $0.union(r) } ?? r
            }
            b = u ?? .zero
            turning = .rect(b)
            reference = CGPoint(x: b.midX, y: b.midY)
        default:
            b = try rect("rect")
            reference = b.origin
        }
        // A turned instance's bounds are the box round its geometry turned about its pivot, at
        // its place: the angle a `turn` has left, or else its `turn` key.
        let unturned = b
        var turned = 0.0
        var pivot = reference
        if let turning {
            var angle = state[instance.whole]?.angle
            if angle == nil { angle = try number(p + "/turn", locals: l, default: 0, what: "turn") }
            if let angle, angle != 0 {
                pivot = doc.expressions[p + "/pivot/0"] != nil ? try point("pivot") : reference
                b = Turning.box(of: turning, turned: angle, about: pivot)
                turned = angle
            }
        }
        let place = state[instance.whole]?.place
        if up == 0 {
            guard let place else { return b }
            return b.offsetBy(dx: place.x - reference.x, dy: place.y - reference.y)
        }
        // In a turned frame. What the instance's place moves it by, in the drawing.
        let shift = place.map { CGVector(dx: $0.x - reference.x, dy: $0.y - reference.y) } ?? CGVector(dx: 0, dy: 0)
        if kind == "text" {
            // Kept upright about its `at`, which the frame turns.
            let at = CGPoint(x: reference.x + shift.dx, y: reference.y + shift.dy)
            let q = Camera.intoFrame(at, up: up)
            return b.offsetBy(dx: shift.dx + q.x - at.x, dy: shift.dy + q.y - at.y)
        }
        if kind == "group", turned == 0 {
            var u: CGRect?
            for member in groupMembers {
                let r = try bounds(member, up: up)
                u = u.map { $0.union(r) } ?? r
            }
            // The group's own place moves its members with it.
            let moved = Camera.intoFrame(CGPoint(x: shift.dx, y: shift.dy), up: up)
            return u.map { $0.offsetBy(dx: moved.x, dy: moved.y) } ?? Camera.box(b.offsetBy(dx: shift.dx, dy: shift.dy), up: up)
        }
        // The geometry turned by its own angle less the frame's, about its pivot, and then moved to
        // where the frame shows the pivot at its place.
        let box = Turning.box(of: turning ?? .rect(unturned), turned: turned - up, about: pivot)
        let q = Camera.intoFrame(CGPoint(x: pivot.x + shift.dx, y: pivot.y + shift.dy), up: up)
        return box.offsetBy(dx: q.x - pivot.x, dy: q.y - pivot.y)
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
    /// their places; nil when it selects nothing. With `up`, in the frame of a picture turned to
    /// show `up` at its top.
    func region(ofPart name: String, up: Double = 0) throws(EvalFailure) -> CGRect? {
        let s = try selection(DocumentPath.join("/parts", name))
        var u: CGRect?
        for inst in s.instances {
            let r = try bounds(inst.whole, up: up)
            u = u.map { $0.union(r) } ?? r
        }
        return u
    }
}

/// How the camera frames each shot in a layout with `camera: true` (section 10.3).
struct CameraFraming {
    /// What a shot shows: the view of the drawing, and the region outside which elements are
    /// dimmed (nil when nothing is), and the direction shown at the top, from 0 to 360. Turned, the
    /// view and the region are boxes in the turned picture's frame, held as `Camera` holds them.
    struct Frame: Equatable {
        var view: CGRect
        var region: CGRect?
        var up: Double = 0
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
        var up = try resolver.number(p + "/up", default: 0, what: "up").truncatingRemainder(dividingBy: 360)
        if up < 0 { up += 360 }
        if up != 0 { return try turnedFrame(spec, p, up: up) }
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

    /// A shot that turns the picture to show `up` at its top (section 10.3): framed as an unturned
    /// shot is, with its region and the drawing's extent taken as boxes in the turned picture's
    /// frame, so the view slides along the picture's own edges.
    func turnedFrame(_ spec: JSONObject, _ p: String, up: Double) throws(EvalFailure) -> Frame {
        var region: CGRect?
        for part in spec["frame"]?.array?.compactMap(\.string) ?? [] {
            if let r = try resolver.region(ofPart: part, up: up) { region = region.map { $0.union(r) } ?? r }
        }
        if resolver.doc.expressions[p + "/region/0"] != nil {
            let r = CGRect(
                x: try resolver.number(p + "/region/0", what: "x"), y: try resolver.number(p + "/region/1", what: "y"),
                width: try resolver.number(p + "/region/2", what: "width"), height: try resolver.number(p + "/region/3", what: "height"))
            let turned = Camera.box(r, up: up)
            region = region.map { $0.union(turned) } ?? turned
        }
        let extent = turnedExtent(up)
        let f: Frame
        if let r = region {
            let margin = try resolver.number(p + "/margin", default: resolver.cameraMargin, what: "margin")
            let grown = r.insetBy(dx: -margin, dy: -margin)
            f = framing(grown, within: extent, focused: !grown.contains(extent))
        } else {
            f = framing(extent, within: extent, focused: false)
        }
        return Frame(view: Camera.held(f.view, up: up), region: f.region.map { Camera.held($0, up: up) }, up: up)
    }

    /// The drawing's extent in the frame of a picture turned to show `up` at its top: the box round
    /// the bounds of every instance that is not fixed, at its place, as that picture shows them.
    func turnedExtent(_ up: Double) -> CGRect {
        var extent: CGRect?
        for (name, el) in resolver.root["elements"]?.object?.entries ?? [] where el["fixed"] != .bool(true) {
            let n = (try? resolver.instanceCount(name)) ?? 0
            let repeated = el["repeat"] != nil
            for k in 0..<n {
                guard let b = try? resolver.bounds(DocumentInstance(name, repeated ? k : nil), up: up) else { continue }
                extent = extent.map { $0.union(b) } ?? b
            }
        }
        return extent ?? Camera.box(drawing, up: up)
    }

    /// The region grown about its middle to the viewport's shape and, where it fits, slid to lie
    /// inside the box round the drawing's extent and the region; centred on that box where it
    /// does not fit.
    func framing(_ region: CGRect, focused: Bool) -> Frame { framing(region, within: drawing, focused: focused) }

    /// `framing(_:focused:)` with `extent` for the drawing's extent: the box round it in a turned
    /// picture's frame, where every box here is in that frame.
    func framing(_ region: CGRect, within extent: CGRect, focused: Bool) -> Frame {
        var view = region
        let aspect = viewport.width / viewport.height
        if view.width / max(view.height, 1e-9) < aspect {
            let w = view.height * aspect
            view = CGRect(x: view.midX - w / 2, y: view.minY, width: w, height: view.height)
        } else {
            let h = view.width / aspect
            view = CGRect(x: view.minX, y: view.midY - h / 2, width: view.width, height: h)
        }
        let bounds = extent.union(region)
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
        /// The points and arcs of a shape's outline.
        case entries([OutlineEntry])
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
        case let .entries(entries):
            var u: CGRect?
            for entry in entries {
                let r: CGRect =
                    switch entry {
                    case let .point(p): CGRect(origin: degrees == 0 ? p : turn(p, by: degrees, about: pivot), size: .zero)
                    case let .arc(a): a.box(turned: degrees, about: pivot)
                    }
                u = u.map { $0.union(r) } ?? r
            }
            return u ?? .zero
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
