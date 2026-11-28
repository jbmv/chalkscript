import CoreGraphics
import Foundation
import SwiftUI

/// The camera a scene is seen through (EXP-18): which region of the drawing is shown (`view`), in
/// which part of the scene (`viewport`, the scene less what stays fixed outside the camera, such
/// as the problem's question), and what is in focus (`focus`, the shot's region): anything whose
/// middle is out of focus is dimmed by `dim`. The drawing's elements are in the drawing's own
/// units; the camera maps them into the scene's, uniformly, so a framed piece is drawn larger and
/// a touch on it is read through the same mapping (`Scene.scenePoint`).
///
/// A scene without a camera is drawn as it is, scaled to fit (EXP-17).
///
/// A document's shot may turn the camera (`up`): the picture then shows the direction `up` of the
/// drawing at its top. The view and the focus are then boxes in the turned picture's frame: each
/// rectangle's middle is a point of the drawing, and its width and height are measured along the
/// turned picture's axes. Unturned, they are plain rectangles of the drawing.
public struct Camera: Equatable, Sendable {
    /// Where the camera's picture is shown, in the scene's units.
    public var viewport: CGRect
    /// The region of the drawing shown, in the drawing's units, the viewport's shape.
    public var view: CGRect
    /// The shot's region: what is in focus. Nil when the whole drawing is.
    public var focus: CGRect?
    /// How strongly what is out of focus is dimmed, 0 to 1.
    public var dim: Double
    /// The shot's name, or the shot being moved to, for tests and UI tests to read.
    public var shot: String?
    /// The direction in the drawing shown at the top of the picture, in degrees clockwise from
    /// twelve; 0 shows the drawing unturned.
    public var up: Double

    public init(viewport: CGRect, view: CGRect, focus: CGRect? = nil, dim: Double = 0, shot: String? = nil, up: Double = 0) {
        self.viewport = viewport
        self.view = view
        self.focus = focus
        self.dim = dim
        self.shot = shot
        self.up = up
    }

    /// How far the dimming fades in past the edge of the focus, in the drawing's units: an
    /// element whose middle is this far out is fully dimmed, so a shot that grows or shrinks
    /// dims and brightens pieces gradually rather than at once.
    public static let feather: CGFloat = 24

    /// Drawing units to scene units: the view fitted into the viewport, keeping its shape, and
    /// centred; turned about the view's middle so that the direction `up` points to the top.
    public var transform: CGAffineTransform {
        guard view.width > 0, view.height > 0 else { return .identity }
        let k = min(viewport.width / view.width, viewport.height / view.height)
        if up == 0 {
            let tx = viewport.midX - view.midX * k
            let ty = viewport.midY - view.midY * k
            return CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: tx, ty: ty)
        }
        // The drawing turned by -up (counter-clockwise by up), so that the direction up, which is
        // (sin up, -cos up) on a drawing whose y grows downward, is drawn pointing up.
        let s = Evaluator.trigonometric(true, degrees: up)
        let c = Evaluator.trigonometric(false, degrees: up)
        let (a, b, cc, d) = (k * c, -k * s, k * s, k * c)
        return CGAffineTransform(
            a: a, b: b, c: cc, d: d,
            tx: viewport.midX - (a * view.midX + cc * view.midY), ty: viewport.midY - (b * view.midX + d * view.midY))
    }

    /// Scene units per drawing unit.
    public var scale: CGFloat { up == 0 ? transform.a : hypot(transform.a, transform.b) }

    /// `p` in the frame of a picture turned to show `up` at its top: turned by -up about the
    /// drawing's origin, so that a box in that frame is a box as the turned picture shows it.
    public static func intoFrame(_ p: CGPoint, up: Double) -> CGPoint {
        if up == 0 { return p }
        let s = Evaluator.trigonometric(true, degrees: up)
        let c = Evaluator.trigonometric(false, degrees: up)
        return CGPoint(x: c * p.x + s * p.y, y: -s * p.x + c * p.y)
    }

    /// The point of the drawing at `q` in the frame of a picture turned to show `up` at its top.
    public static func outOfFrame(_ q: CGPoint, up: Double) -> CGPoint {
        if up == 0 { return q }
        let s = Evaluator.trigonometric(true, degrees: up)
        let c = Evaluator.trigonometric(false, degrees: up)
        return CGPoint(x: c * q.x - s * q.y, y: s * q.x + c * q.y)
    }

    /// The box round `rect`, a rectangle of the drawing, in the frame of a picture turned to show
    /// `up` at its top: round its turned corners.
    public static func box(_ rect: CGRect, up: Double) -> CGRect {
        if up == 0 { return rect }
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)].map { intoFrame($0, up: up) }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// A box in the frame of a picture turned to show `up` at its top, as the camera holds it: the
    /// same size, with its middle the point of the drawing there (see `Camera`).
    public static func held(_ box: CGRect, up: Double) -> CGRect {
        if up == 0 { return box }
        let m = outOfFrame(CGPoint(x: box.midX, y: box.midY), up: up)
        return CGRect(x: m.x - box.width / 2, y: m.y - box.height / 2, width: box.width, height: box.height)
    }

    /// How far the camera turns from showing `a` at the top to showing `b`, in degrees, positive
    /// clockwise: the shorter way round, and clockwise at exactly half a turn. The direction of a
    /// camera's turn carries no meaning, so the numbers do not choose it.
    public static func turn(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d > 180 ? d - 360 : d
    }

    /// The camera framing `shot` in `viewport`: the shot grown to the viewport's shape about its
    /// middle and, where it fits, slid inside `world` (the whole drawing), so no more empty sheet
    /// shows than must.
    public static func framing(
        _ shot: CGRect, in viewport: CGRect, world: CGRect, dim: Double, focused: Bool, name: String?
    ) -> Camera {
        var view = shot
        let aspect = viewport.width / max(viewport.height, 1)
        if view.width / max(view.height, 1) < aspect {
            let w = view.height * aspect
            view = CGRect(x: view.midX - w / 2, y: view.minY, width: w, height: view.height)
        } else {
            let h = view.width / aspect
            view = CGRect(x: view.minX, y: view.midY - h / 2, width: view.width, height: h)
        }
        let bounds = world.union(shot)
        func slide(_ lo: CGFloat, _ len: CGFloat, _ bLo: CGFloat, _ bLen: CGFloat) -> CGFloat {
            if len >= bLen { return bLo + (bLen - len) / 2 }
            return min(max(lo, bLo), bLo + bLen - len)
        }
        view.origin.x = slide(view.minX, view.width, bounds.minX, bounds.width)
        view.origin.y = slide(view.minY, view.height, bounds.minY, bounds.height)
        return Camera(viewport: viewport, view: view, focus: focused ? shot : nil, dim: dim, shot: name)
    }

    /// The camera `p` of the way from `a` to `b`: the middle of the view moves in a straight line
    /// and its size changes geometrically, so a zoom feels even all the way; its angle turns the
    /// shorter way at an even rate; the focus does the same, and the dimming fades between them.
    public static func between(_ a: Camera, _ b: Camera, _ p: Double) -> Camera {
        if p <= 0 { return a }
        if p >= 1 { return b }
        func rect(_ r0: CGRect, _ r1: CGRect) -> CGRect {
            let c = mix(CGPoint(x: r0.midX, y: r0.midY), CGPoint(x: r1.midX, y: r1.midY), p)
            let w = r0.width * pow(r1.width / r0.width, p)
            let h = r0.height * pow(r1.height / r0.height, p)
            return CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        }
        let view = rect(a.view, b.view)
        // A whole-drawing camera focuses on what it shows, so a move to or from one fades the
        // dimming in or out rather than starting it at once.
        let fa = a.focus ?? a.view
        let fb = b.focus ?? b.view
        let dimA = a.focus == nil ? 0 : a.dim
        let dimB = b.focus == nil ? 0 : b.dim
        let dim = mix(dimA, dimB, p)
        let up = a.up == b.up ? b.up : a.up + turn(from: a.up, to: b.up) * p
        return Camera(
            viewport: b.viewport, view: view, focus: dim > 0 ? rect(fa, fb) : nil, dim: dim, shot: b.shot, up: up)
    }

    /// How strongly `element` is dimmed, 0 to `dim`: by how far its middle lies out of focus, as
    /// measured in the frame of the picture, turned or not.
    public func dimming(of element: SceneElement) -> Double {
        guard dim > 0, let focus, !element.fixed, let c = element.centre else { return 0 }
        let dx: CGFloat
        let dy: CGFloat
        if up == 0 {
            dx = max(focus.minX - c.x, 0, c.x - focus.maxX)
            dy = max(focus.minY - c.y, 0, c.y - focus.maxY)
        } else {
            let q = Self.intoFrame(CGPoint(x: c.x - focus.midX, y: c.y - focus.midY), up: up)
            dx = max(abs(q.x) - focus.width / 2, 0)
            dy = max(abs(q.y) - focus.height / 2, 0)
        }
        let out = hypot(dx, dy)
        return dim * Double(min(1, out / Self.feather))
    }
}

/// The camera an explainer laid out for its drawing area plans with (EXP-18): its shots resolved
/// to regions of the drawing, the viewport they are shown in, the whole drawing, and the dimming.
public struct CameraPlan: Equatable, Sendable {
    public var viewport: CGRect
    public var world: CGRect
    public var shots: [String: CGRect]
    public var opening: String?
    public var dim: Double

    public init(viewport: CGRect, world: CGRect, shots: [String: CGRect], opening: String?, dim: Double) {
        self.viewport = viewport
        self.world = world
        self.shots = shots
        self.opening = opening
        self.dim = dim
    }

    /// Resolves `motion`'s shots against `parts`, the regions of the explainer's drawing by name,
    /// for this problem: each shot frames the union of its parts and its region, with its margin.
    /// A shot whose parts this problem does not draw (no trade, nothing left to count) frames the
    /// whole drawing.
    public static func resolve(
        _ motion: ExplainerMotion, parts: [String: CGRect], world: CGRect, viewport: CGRect
    ) -> CameraPlan {
        var shots: [String: CGRect] = [:]
        for (name, spec) in motion.shots {
            var r = spec.frame.compactMap { parts[$0] }.reduce(spec.region) { ($0 ?? $1).union($1) }
            if let region = r { r = region.insetBy(dx: -spec.margin, dy: -spec.margin) }
            shots[name] = r ?? world
        }
        return CameraPlan(viewport: viewport, world: world, shots: shots, opening: motion.opening, dim: motion.dim)
    }

    /// The camera holding on shot `name`; nil holds on the opening shot, and with no opening shot
    /// the whole drawing is shown with nothing dimmed.
    public func camera(_ name: String?) -> Camera {
        let n = name ?? opening
        guard let n, let region = shots[n] else {
            return Camera.framing(world, in: viewport, world: world, dim: dim, focused: false, name: n)
        }
        // A shot that takes in the whole drawing dims nothing.
        let focused = !region.contains(world)
        return Camera.framing(region, in: viewport, world: world, dim: dim, focused: focused, name: n)
    }

    /// The camera `t` seconds into a step that moves from shot `from` to shot `to` by `move`.
    public func camera(from: String?, to: String?, move: CameraMove, at t: Double) -> Camera {
        let a = camera(from)
        let b = camera(to)
        if a == b { return b }
        return Camera.between(a, b, move.fraction(at: t))
    }

    /// Whether moving from `from` to `to` moves the camera at all.
    public func moves(from: String?, to: String?) -> Bool { camera(from) != camera(to) }
}

extension SceneElement {
    /// Where the element is in its own units, as far as the camera needs to know (its middle, for
    /// dimming): the rectangle or the points it is drawn through, moved by its transform; nil for
    /// the few kinds with no fixed extent here (the problem, a written number).
    public var bounds: CGRect? {
        func box(_ points: [CGPoint]) -> CGRect? {
            guard let first = points.first else { return nil }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        }
        let r: CGRect?
        switch kind {
        case let .ten(rect, _), let .one(rect, _), let .stick(rect, _), let .circle(rect, _), let .numberTag(_, rect, _), let .hueTag(_, rect, _, _),
            let .box(rect, _, _), let .hint(rect, _), let .target(rect):
            r = rect
        case let .crossOut(from, to, _), let .divider(from, to), let .rule(from, to): r = box([from, to])
        case let .arrow(points, _, _), let .ink(points, _): r = box(points)
        case let .label(_, at), let .count(_, at), let .total(_, at, _), let .text(_, at, _): r = CGRect(origin: at, size: .zero)
        case let .words(_, set): r = CGRect(origin: set.at, size: .zero)
        case let .shape(outline, _): r = StageDrawing.path(outline).boundingRect
        case let .group(children):
            var u: CGRect?
            for b in children.compactMap(\.bounds) { u = u.map { $0.union(b) } ?? b }
            r = u
        case .equation, .numeral: r = nil
        }
        return r.map { transform == .identity ? $0 : $0.applying(transform) }
    }

    /// The middle of `bounds`.
    public var centre: CGPoint? { bounds.map { CGPoint(x: $0.midX, y: $0.midY) } }
}

extension Scene {
    /// Drawing units to points in a drawing area of `area` points: through the camera, when
    /// there is one, and the scene's fit (EXP-17, EXP-18).
    public func drawingTransform(in area: CGSize) -> CGAffineTransform {
        let (s, o) = fit(in: area)
        let base = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: o.x, ty: o.y)
        guard let camera else { return base }
        return camera.transform.concatenating(base)
    }

    /// Where `rect`, in the drawing's units, is on screen in a drawing area of `area` points.
    public func screenRect(_ rect: CGRect, in area: CGSize) -> CGRect { rect.applying(drawingTransform(in: area)) }
}
