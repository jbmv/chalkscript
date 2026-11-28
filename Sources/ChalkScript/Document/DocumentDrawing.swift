import CoreGraphics
import Foundation

// What a document draws (EXP-13, EXP-19, sections 9, 10 and 13 of the format's reference): each
// instance's geometry at its place, its state at a moment of a step, and the shared components a
// state is drawn with.

/// One run of a text element's shown text: a placeholder's run, by name, or literal text.
struct TextRun: Equatable, Sendable {
    var name: String?
    var text: String
    /// The role the run's text is drawn in, from the element's `runs`.
    var ink: String?
}

/// The geometry of one instance at its place, in the drawing's units.
enum InstanceShape: Equatable, Sendable {
    case piece(kind: String, rect: CGRect)
    case text(at: CGPoint, style: String, size: Double, ink: String, anchor: String)
    case line(from: CGPoint, to: CGPoint, divider: Bool, ink: Ink)
    case arrow([CGPoint], Hue)
    case outline(CGRect, style: String, op: Hue?)
    case shape(Outline, fill: Ink?, stroke: Ink?)

    /// What a turn moves, for the kinds that turn (section 9.5): the points of a line, arrow or
    /// shape, or the rectangle or ellipse of a shape. Nil for text, outlines and pieces.
    var turning: Turning.Geometry? {
        switch self {
        case let .line(from, to, _, _): .points([from, to])
        case let .arrow(points, _): .points(points)
        case let .shape(outline, _, _):
            switch outline {
            case let .lines(points, _): .points(points)
            case let .rect(r, _): .rect(r)
            case let .ellipse(r): .ellipse(r)
            case .path: nil
            }
        default: nil
        }
    }
}

/// One instance of an element, as it stands before the first step.
struct DrawnInstance: Sendable {
    var instance: DocumentInstance
    var shape: InstanceShape
    /// The instance's reference point at its place (section 9.1).
    var reference: CGPoint
    var bounds: CGRect
    var fixed: Bool
    var start: InstanceLook
    /// The point the instance turns, grows and pulses about, at its place: its `pivot`, or its
    /// reference point. It grows and pulses about it only when `pivoted`.
    var pivot: CGPoint
    var pivoted: Bool
    /// An outline whose `around` selects nothing for this instance of a repeated element: it is
    /// not drawn.
    var hollow = false
    /// The width of the stroke of a line, arrow, outline or shape that gives a `width` (section
    /// 9.3), in the drawing's units; nil for the renderer's own.
    var width: CGFloat?

    /// The scene element's id: the element's name, and the index of a repeated one.
    var id: String { instance.index.map { "\(instance.element).\($0)" } ?? instance.element }
    var isPiece: Bool { if case .piece = shape { true } else { false } }
}

/// The state of one instance at a moment (section 18), with the passing effects of the verbs
/// that leave nothing behind (the offset of `rise`, the scale of `grow` and `pulse`, a tag).
struct InstanceLook: Equatable, Sendable {
    struct Tint: Equatable, Sendable {
        var op: Hue
        var progress: Double
    }

    struct Tag: Equatable, Sendable {
        var text: String
        var hue: Hue
        var opacity: Double
        var scale: Double
    }

    var opacity: Double
    var progress: Double
    var position: CGPoint
    var place: CGPoint
    var look: PieceStyle = .pencil
    var crossProgress = 0.0
    var crossOpacity = 1.0
    var text: [TextRun] = []
    var runOpacity: [String: Double] = [:]
    var runTint: [String: Tint] = [:]
    var rise = 0.0
    var grow = 1.0
    var pulse = 1.0
    /// The angle the instance is drawn at, in degrees clockwise (section 18).
    var turn = 0.0
    var tag: Tag?
}

/// One instance's part in one action: what it does to the instance from `begins`, the action's
/// start, when the instance takes its start state, and from `start` for `duration`, its own
/// motion (sections 12.2 and 13).
struct Track: Sendable {
    enum Effect: Sendable {
        case appear(rise: Double, grow: Double?, place: CGPoint?, text: String?)
        case fade(from: Double, to: Double)
        case draw
        case cross(fade: Double, easing: Easing, from: Double, crossFrom: Double)
        case tint(Hue)
        case move([(Double, CGPoint)])
        case gather(from: CGPoint, to: CGPoint)
        case look(PieceStyle)
        case set(String)
        case tag(String, Hue)
        case pulse
        case turn(from: Double, to: Double)
    }

    var target: Int
    var part: DocumentInstance.Part?
    var begins: Double
    var start: Double
    var duration: Double
    var easing: Easing
    var mark: Bool
    var effect: Effect

    /// Applies the track at `t` seconds on the step's clock; before `begins` it does nothing.
    func apply(at t: Double, to looks: inout [InstanceLook]) {
        guard t >= begins else { return }
        let p = progress(t, start: start, duration: duration, easing)
        var l = looks[target]
        switch effect {
        case let .appear(rise, grow, place, text):
            if case let .run(name)? = part {
                l.runOpacity[name] = p
                if let text { l.setRun(name, text) }
            } else {
                l.opacity = p
                l.rise = rise * (1 - p)
                if let grow { l.grow = mix(grow, 1, p) }
                if let place { l.position = place }
                if let text { l.text = [TextRun(name: nil, text: text)] }
            }
        case let .fade(from, to):
            let v = mix(from, to, p)
            switch part {
            case let .run(name)?: l.runOpacity[name] = v
            case .cross?: l.crossOpacity = v
            case nil: l.opacity = v
            }
        case .draw:
            l.progress = p
        case let .cross(fade, fadeEasing, from, crossFrom):
            l.crossProgress = p
            if fade > 0 {
                let q = progress(t, start: start + duration, duration: fade, fadeEasing)
                l.opacity = mix(from, Components.ghostOpacity, q)
                l.crossOpacity = mix(crossFrom, Components.ghostOpacity, q)
            }
        case let .tint(op):
            if case let .run(name)? = part { l.runTint[name] = InstanceLook.Tint(op: op, progress: p) }
        case let .move(frames):
            l.position = keyframes(frames, p)
        case let .gather(from, to):
            l.opacity = 1
            l.position = mix(from, to, p)
        case let .look(value):
            if t >= start { l.look = value }
        case let .set(text):
            guard t >= start else { break }
            if case let .run(name)? = part { l.setRun(name, text) } else { l.text = [TextRun(name: nil, text: text)] }
        case let .tag(text, hue):
            guard t >= start else { break }
            l.tag = InstanceLook.Tag(
                text: text, hue: hue, opacity: keyframes([(0, 0), (0.2, 1), (0.75, 1), (1, 0)], p), scale: keyframes([(0, 0.6), (0.2, 1), (1, 1)], p))
            if p >= 1 { l.tag = nil }
        case .pulse:
            l.pulse = keyframes([(0, 1), (0.5, 1.15), (1, 1)], p)
        case let .turn(from, to):
            l.turn = mix(from, to, p)
        }
        looks[target] = l
    }
}

extension InstanceLook {
    mutating func setRun(_ name: String, _ text: String) {
        if let k = self.text.firstIndex(where: { $0.name == name }) { self.text[k].text = text }
    }
}

/// Turns instances and their states into the shared components (EXP-13).
struct DocumentPainter: Sendable {
    let roles: DocumentRoles
    let instances: [DrawnInstance]
    let size: CGSize
    let camera: Bool

    func scene(_ looks: [InstanceLook], camera cam: Camera?) -> Scene {
        var out: [SceneElement] = []
        var tags: [SceneElement] = []
        var fixed: [SceneElement] = []
        for (k, inst) in instances.enumerated() {
            let l = looks[k]
            let isFixed = inst.fixed && camera
            var drawn = elements(inst, l)
            for j in drawn.indices { drawn[j].fixed = isFixed }
            if isFixed { fixed += drawn } else { out += drawn }
            if let tag = l.tag {
                let b = inst.bounds.offsetBy(dx: l.position.x - inst.reference.x, dy: l.position.y - inst.reference.y)
                let ten: Bool = if case let .piece(kind, _) = inst.shape { kind == "ten" || kind == "stick" } else { false }
                let card = Components.numberTag(
                    on: b, ten: ten, textWidth: TextExtent.measure(tag.text, size: Components.tagTextSize, display: true).width)
                tags.append(SceneElement(
                    inst.id + ".tag",
                    tag.hue == .result ? .numberTag(tag.text, in: card, scale: tag.scale) : .hueTag(tag.text, in: card, scale: tag.scale, hue: tag.hue),
                    opacity: tag.opacity, fixed: isFixed))
            }
        }
        return Scene(elements: out + tags + fixed, size: size, camera: camera ? cam : nil, operationColours: roles.overrides)
    }

    /// `rect` scaled by `s` about its middle.
    static func scaled(_ r: CGRect, _ s: Double) -> CGRect {
        if s == 1 { return r }
        return r.insetBy(dx: r.width * (1 - s) / 2, dy: r.height * (1 - s) / 2)
    }

    /// A scale by `s` about `c`.
    static func scale(_ s: Double, about c: CGPoint) -> CGAffineTransform {
        if s == 1 { return .identity }
        return CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: s, y: s).translatedBy(x: -c.x, y: -c.y)
    }

    func elements(_ inst: DrawnInstance, _ l: InstanceLook) -> [SceneElement] {
        let d = CGVector(dx: l.position.x - inst.reference.x, dy: l.position.y - inst.reference.y + l.rise)
        func moved(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.dx, y: p.y + d.dy) }
        let scale = l.grow * l.pulse
        // A turned instance is drawn through a turn about its pivot, which moves with it. It grows
        // and pulses about its pivot when it has one, and otherwise about the middle of its turned
        // geometry.
        let pivot = moved(inst.pivot)
        let spin = Turning.transform(by: l.turn, about: pivot)
        var box = inst.bounds.offsetBy(dx: d.dx, dy: d.dy)
        if let geometry = inst.shape.turning, l.turn != inst.start.turn || inst.pivoted {
            box = Turning.box(of: geometry, turned: l.turn, about: inst.pivot).offsetBy(dx: d.dx, dy: d.dy)
        }
        var centre = inst.pivoted ? pivot : CGPoint(x: box.midX, y: box.midY)
        // A text element grows and pulses about the middle of the text it shows now, which a verb may
        // have set, and not of the text it showed before the first step.
        if scale != 1, case let .text(at, style, size, _, anchor) = inst.shape {
            let shown = TextExtent.box(
                l.text.map(\.text).joined(), at: moved(at), size: style == "total" ? Components.totalSize : size, display: style != "label",
                anchor: anchor)
            centre = CGPoint(x: shown.midX, y: shown.midY)
        }
        let around = Self.scale(scale, about: centre)
        let turned = spin.concatenating(around)
        switch inst.shape {
        case let .piece(kind, rect):
            // A piece is a rectangle the stage draws as it is, so its scale is its rectangle's.
            let r = Self.scaled(rect.offsetBy(dx: d.dx, dy: d.dy), scale)
            let k: SceneElement.Kind =
                switch kind {
                case "ten": .ten(r, l.look)
                case "stick": .stick(r, l.look)
                case "circle": .circle(r, l.look)
                default: .one(r, l.look)
                }
            let pad = kind == "ten" || kind == "stick" ? Components.tenCrossPad : Components.oneCrossPad
            let x = Components.crossOut(over: r, pad: pad)
            return [
                SceneElement(inst.id, k, opacity: l.opacity),
                SceneElement(inst.id + ".cross", .crossOut(from: x.from, to: x.to, progress: l.crossProgress),
                    opacity: l.opacity > 0 ? l.crossOpacity : 0),
            ]
        case let .text(at, style, size, ink, anchor):
            let runs = l.text.filter { !$0.text.isEmpty }
            let text = runs.map(\.text).joined()
            let a = moved(at)
            switch style {
            case "equation":
                var eqRuns: [EquationLine.Run] = []
                var mark: EquationLine.Mark?
                for r in runs {
                    if let name = r.name, let tint = l.runTint[name] {
                        mark = EquationLine.Mark(run: eqRuns.count, op: tint.op, progress: tint.progress)
                    }
                    let role: EquationLine.Role =
                        switch r.ink {
                        case nil, "text": .plain
                        case "result": .answer
                        default: roles.hue(r.ink!).map { .hue($0) } ?? .plain
                        }
                    eqRuns.append(EquationLine.Run(r.text, role, opacity: r.name.flatMap { l.runOpacity[$0] } ?? 1))
                }
                return [SceneElement(inst.id, .equation(EquationLine(runs: eqRuns, mark: mark, center: a, size: size)), opacity: l.opacity,
                    transform: around)]
            case "total":
                return [SceneElement(inst.id, .total(text, at: a, scale: 1), opacity: text.isEmpty ? 0 : l.opacity, transform: around)]
            default:
                if style == "label" && ink == "muted" && anchor == "start" && size == Components.labelSize {
                    return [SceneElement(inst.id, .label(text, at: a), opacity: l.opacity, transform: around)]
                }
                let set = Typeset(
                    at: a, size: size, ink: roles.ink(ink, fill: false) ?? .text, display: style != "label",
                    anchor: anchor == "start" ? .leading : anchor == "end" ? .trailing : .center)
                return [SceneElement(inst.id, .words(text, set), opacity: l.opacity, transform: around)]
            }
        case let .line(from, to, divider, ink):
            let f = moved(from)
            let t = moved(to)
            if divider && ink == .line && l.progress >= 1 && inst.width == nil {
                return [SceneElement(inst.id, .divider(from: f, to: t), opacity: l.opacity, transform: turned)]
            }
            let paint = Paint(
                stroke: ink, width: inst.width ?? (divider ? Components.dividerWidth : Components.pencilWidth),
                dash: divider ? Components.dividerDash : [], progress: l.progress)
            return [SceneElement(inst.id, .shape(.lines([f, t]), paint), opacity: l.opacity, transform: turned)]
        case let .arrow(points, op):
            return [SceneElement(inst.id, .arrow(points: points.map(moved), progress: l.progress, op: op), opacity: l.opacity, transform: turned,
                strokeWidth: inst.width)]
        case let .outline(rect, style, op):
            if inst.hollow { return [] }
            let r = rect.offsetBy(dx: d.dx, dy: d.dy)
            let k: SceneElement.Kind =
                switch style {
                case "hint": .hint(r, progress: l.progress)
                case "target":
                    .shape(.rect(r, corner: Components.targetCorner),
                        Paint(stroke: .fill(.result), width: inst.width ?? Components.targetWidth, dash: Components.targetDash, progress: l.progress))
                default: .box(r, progress: l.progress, op: op ?? .result)
                }
            return [SceneElement(inst.id, k, opacity: l.opacity, transform: around, strokeWidth: inst.width)]
        case let .shape(outline, fill, stroke):
            let shift = CGAffineTransform(translationX: d.dx, y: d.dy)
            return [SceneElement(inst.id, .shape(outline, Paint(fill: fill, stroke: stroke, width: inst.width ?? Components.pencilWidth, progress: l.progress)), opacity: l.opacity,
                transform: shift.concatenating(turned))]
        }
    }
}

/// Roles as a document names them (section 16.1), as the stage's inks: the style's own, and the
/// colours the document names for itself (EXP-20).
struct DocumentRoles: Sendable {
    var colours: [String: DocumentColour] = [:]
    /// The operations the document draws in a colour of its choosing (EXP-6), which every scene
    /// of its film carries to the stage.
    var overrides: [ExplainerOperation: DocumentColour] = [:]

    /// The ink of role `name`: a hue named alone is its `ink` for a stroke or text and its `fill`
    /// for a fill. Nil for a role the stage has no ink for (`paper`, `onResult`).
    func ink(_ name: String, fill: Bool) -> Ink? {
        let parts = name.split(separator: ".").map(String.init)
        switch parts[0] {
        case "text": return .text
        case "muted": return .muted
        case "line": return .line
        case "pencil": return .pencil
        case "sheet": return .sheet
        default:
            guard let hue = hue(parts[0]) else { return nil }
            switch parts.count == 2 ? parts[1] : (fill ? "fill" : "ink") {
            case "fill": return .fill(hue)
            case "soft": return .soft(hue)
            default: return .ink(hue)
            }
        }
    }

    /// The hue of role `name` named alone: an operation, or a colour the document names, or nil.
    func hue(_ name: String) -> Hue? {
        if let op = ExplainerOperation(rawValue: name) { return .operation(op) }
        return colours[name].map { .document($0) }
    }
}
