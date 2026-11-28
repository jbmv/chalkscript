import CoreGraphics
import Foundation

/// A resolved document's watched part as pictures (EXP-11, EXP-19): every instance it draws, each
/// step's tracks, the state each step starts from and its still, and the camera's frames. Plain
/// values, built once, so a picture at any moment is computed without evaluating the document.
struct DocumentFilm: Sendable {
    let painter: DocumentPainter
    /// Per step, its tracks, in the order their actions start.
    let tracks: [[Track]]
    /// The state before each step: index 0 is the state before the first. A step starts from
    /// the one before it, less its marks (section 12.7).
    let carried: [[InstanceLook]]
    /// Each step's still: every action at its end, marks included (section 18).
    let stills: [[InstanceLook]]
    let cameraOn: Bool
    let cameras: [String: Camera]
    let wholeCamera: Camera?
    let opening: String?
    let cameraMove: CameraMove

    func camera(_ shot: String?) -> Camera? {
        guard cameraOn else { return nil }
        return shot.flatMap { cameras[$0] } ?? wholeCamera
    }

    func scene(_ looks: [InstanceLook], camera: Camera?) -> Scene { painter.scene(looks, camera: camera) }
}

extension DocumentFilm {
    /// Builds the film of `resolved`, with `r` evaluating the document for the same problem,
    /// layout, wording, locale and playback. What this player does not draw yet is refused with
    /// a `capability` failure that names it (section 2.3: it must not draw an approximation).
    init(_ resolved: ResolvedExplainer, resolver r: Resolver) throws(EvalFailure) {
        let doc = r.doc
        let style = DocumentStyle(doc)
        let roles = DocumentRoles(colours: doc.colours, overrides: doc.overridingColours)
        // Every instance, in draw order (section 9.1): by z, then by element name in code point
        // order, then by index.
        var drawn: [(z: Double, name: [UInt32], index: Int, inst: DrawnInstance)] = []
        // What fails for one instance does not stop the others being built, so a refusal names
        // every fault the problem shows, one for each place (EXP-19).
        var failures: [EvalFailure] = []
        for name in r.root["elements"]?.object?.keys ?? [] {
            let n: Int
            do { n = try r.instanceCount(name) } catch {
                failures.append(error)
                continue
            }
            let repeated = r.root["elements"]?[name]?["repeat"] != nil
            for k in 0..<n {
                do {
                    let instance = DocumentInstance(name, repeated ? k : nil)
                    let z = try r.number(DocumentPath.join("/elements", name, "z"), locals: try r.instanceLocals(instance), default: 0, what: "z")
                    drawn.append((z, Array(name.unicodeScalars.map(\.value)), k, try Self.instance(instance, r, roles)))
                } catch { failures.append(error) }
            }
        }
        if let all = EvalFailure(collecting: failures) { throw all }
        drawn.sort { a, b in
            if a.z != b.z { return a.z < b.z }
            if a.name != b.name { return a.name.lexicographicallyPrecedes(b.name) }
            return a.index < b.index
        }
        let instances = drawn.map(\.inst)
        var index: [DocumentInstance: Int] = [:]
        for (k, i) in instances.enumerated() { index[i.instance] = k }

        // The camera's frames (section 10.3).
        cameraOn = resolved.camera
        opening = r.root["opening"]?.string
        var cams: [String: Camera] = [:]
        if resolved.camera {
            let framing = CameraFraming(r, size: resolved.size)
            func camera(_ f: CameraFraming.Frame, _ name: String?) -> Camera {
                Camera(viewport: framing.viewport, view: f.view, focus: f.region, dim: style.camera.dim, shot: name, up: f.up)
            }
            for name in r.root["shots"]?.object?.keys ?? [] {
                do { cams[name] = camera(try framing.frame(name), name) } catch { failures.append(error) }
            }
            var whole: Camera?
            do { whole = camera(try framing.frame(nil), nil) } catch { failures.append(error) }
            wholeCamera = whole
        } else {
            wholeCamera = nil
        }
        cameras = cams
        cameraMove = CameraMove(at: style.camera.at, duration: style.camera.duration, easingName: style.camera.easing,
            easing: style.easing(style.camera.easing))
        // The members of each group, in draw order, which the group draws inside its own layer.
        var groups: [Int: [Int]] = [:]
        var groupOf: [DocumentInstance: DocumentInstance] = [:]
        for (k, drawn) in instances.enumerated() {
            guard case .group = drawn.shape else { continue }
            do {
                for m in try r.members(of: drawn.instance) {
                    if let other = groupOf[m] {
                        failures.append(EvalFailure(
                            path: DocumentPath.join("/elements", drawn.instance.element, "members"),
                            message: "\(m) is a member of both \(other) and \(drawn.instance); an instance is in at most one group"))
                        continue
                    }
                    groupOf[m] = drawn.instance
                    if let at = index[m] { groups[k, default: []].append(at) }
                }
                groups[k]?.sort()
            } catch { failures.append(error) }
        }
        var painter = DocumentPainter(roles: roles, instances: instances, size: resolved.size, camera: resolved.camera)
        painter.groups = groups
        self.painter = painter

        var carried = [instances.map(\.start)]
        var stills: [[InstanceLook]] = []
        var tracks: [[Track]] = []
        for step in resolved.steps {
            let before = carried.last!
            let built = Self.tracks(step, from: before, instances: instances, index: index, style: style, roles: roles, r, failures: &failures)
            var still = before
            var next = before
            for t in built { t.apply(at: .infinity, to: &still) }
            for t in built where !t.mark { t.apply(at: .infinity, to: &next) }
            tracks.append(built)
            stills.append(still)
            carried.append(next)
            // What the step leaves for the next step's selections (section 7).
            r.applyEffects(step.actions)
        }
        if let all = EvalFailure(collecting: failures) { throw all }
        self.tracks = tracks
        self.carried = carried
        self.stills = stills
    }

    /// The size, anchor and ink a text element has by style (section 9.2).
    static let textDefaults: [String: (Double, String, String)] = [
        "equation": (Components.equationSize, "middle", "text"), "total": (Components.totalSize, "middle", "result"),
        "label": (Components.labelSize, "start", "muted"), "note": (22, "middle", "muted"), "body": (26, "middle", "text"),
    ]

    /// One instance's geometry at its place and its state before the first step.
    static func instance(_ inst: DocumentInstance, _ r: Resolver, _ roles: DocumentRoles) throws(EvalFailure) -> DrawnInstance {
        let name = inst.element
        let p = DocumentPath.join("/elements", name)
        let el = r.root["elements"]?[name]?.object ?? JSONObject()
        let kind = el["kind"]?.string ?? ""
        let l = try r.instanceLocals(inst)
        func number(_ key: String, _ d: Double? = nil) throws(EvalFailure) -> Double { try r.number(p + "/" + key, locals: l, default: d, what: key) }
        func point(_ key: String) throws(EvalFailure) -> CGPoint { CGPoint(x: try number(key + "/0"), y: try number(key + "/1")) }
        func refuse(_ key: String, _ message: String) -> EvalFailure { EvalFailure(path: key.isEmpty ? p : p + "/" + key, message: message, code: .capability) }
        func role(_ key: String, fill: Bool = false) throws(EvalFailure) -> Ink? {
            guard let s = el[key]?.string else { return nil }
            guard let ink = roles.ink(s, fill: fill) else { throw refuse(key, PlayerRefusal.inkRole(s)) }
            return ink
        }
        func hue(_ key: String) throws(EvalFailure) -> Hue? {
            guard let s = el[key]?.string else { return nil }
            guard let hue = roles.hue(s) else { throw refuse(key, PlayerRefusal.hue(kind, s)) }
            return hue
        }
        let bounds = try r.bounds(inst)
        let shape: InstanceShape
        let reference: CGPoint
        var text: [TextRun] = []
        switch kind {
        case "text":
            let style = el["style"]?.string ?? "body"
            let (size0, anchor0, ink0) = Self.textDefaults[style] ?? Self.textDefaults["body"]!
            let at = try point("at")
            let size = try number("size", size0)
            let anchor = el["anchor"]?.string ?? anchor0
            let vanchor = el["vanchor"]?.string ?? "baseline"
            let ink = el["ink"]?.string ?? ink0
            if roles.ink(ink, fill: false) == nil { throw refuse("ink", PlayerRefusal.inkRole(ink)) }
            if style == "equation" && (anchor != "middle" || ink != "text") {
                throw refuse("", PlayerRefusal.equation)
            }
            if style == "total" && (anchor != "middle" || ink != "result") {
                throw refuse("", PlayerRefusal.total)
            }
            for (run, v) in el["runs"]?.object?.entries ?? [] {
                if let ri = v["ink"]?.string, style != "equation" || (ri != "result" && ri != "text" && roles.colours[ri] == nil) {
                    throw refuse("runs/\(run)/ink", PlayerRefusal.runInk)
                }
            }
            if let entry = el["text"]?.string { text = try runs(of: name, entry: entry, el: el, locals: l, r) }
            shape = .text(at: at, style: style, size: size, ink: ink, anchor: anchor, vanchor: vanchor)
            reference = at
        case "line":
            let divider = el["style"]?.string == "divider"
            let from = try point("from")
            shape = .line(from: from, to: try point("to"), divider: divider, ink: try role("ink") ?? (divider ? .line : .pencil))
            reference = from
        case "arrow":
            func end(_ key: String) throws(EvalFailure) -> CGPoint {
                if case .string = el[key] {
                    let s = try r.selection(p + "/" + key, locals: l)
                    guard s.count == 1, let one = s.instances.first else {
                        throw EvalFailure(path: p + "/" + key, message: "an arrow's \(key) selects \(s.count) instances, not one")
                    }
                    let b = try r.bounds(one.whole)
                    return CGPoint(x: b.midX, y: b.minY - 8)
                }
                return try point(key)
            }
            let from = try end("from")
            let to = try end("to")
            var points = [from, to]
            if el["y"] != nil {
                let y = try number("y")
                points = [from, CGPoint(x: from.x, y: y), CGPoint(x: to.x, y: y), to]
            }
            guard let op = try hue("ink") else { throw refuse("ink", "an arrow has no ink") }
            shape = .arrow(points, op)
            reference = from
        case "outline":
            let style = el["style"]?.string ?? "box"
            var op: Hue?
            switch style {
            case "box", "ring": op = try hue("ink")
            default:
                if el["ink"] != nil { throw refuse("ink", PlayerRefusal.outlineInk(style)) }
            }
            shape = .outline(bounds, style: style, op: op)
            reference = bounds.origin
        case "shape":
            let fill = try role("fill", fill: true)
            let stroke = try role("ink")
            let outline: Outline
            if el["points"] != nil {
                let entries = try r.outlineEntries(inst, locals: l)
                outline = OutlineEntry.outline(entries, closed: el["closed"] == .bool(true))
                reference = entries.first?.start ?? .zero
            } else if el["ellipse"] != nil {
                outline = .ellipse(bounds)
                reference = bounds.origin
            } else {
                outline = .rect(bounds, corner: CGFloat(try number("corner", 0)))
                reference = bounds.origin
            }
            shape = .shape(outline, fill: fill, stroke: stroke)
        case "group":
            var box: CGRect?
            for member in try r.members(of: inst) {
                let b = try r.bounds(member)
                box = box.map { $0.union(b) } ?? b
            }
            let members = box ?? .zero
            // A group turns only if all its members have geometry that turns.
            if el["turn"] != nil { try r.checkGroupTurns(inst, p + "/turn") }
            shape = .group(members)
            reference = CGPoint(x: members.midX, y: members.midY)
        default:
            shape = .piece(kind: kind, rect: bounds)
            reference = bounds.origin
        }
        var look = InstanceLook(
            opacity: try number("start/opacity", 1), progress: try number("start/progress", 1), position: reference, place: reference)
        look.text = text
        // The angle the instance is drawn at and the point it turns about (section 9.5).
        let turns = DocumentChecker.turnableKinds.contains(kind)
        if turns { look.turn = try number("turn", 0) }
        let pivoted = turns && el["pivot"] != nil
        let pivot = pivoted ? try point("pivot") : reference
        switch el["look"]?.string {
        case "traded": look.look = .traded
        case "counted": look.look = .counted
        default: look.look = .pencil
        }
        var drawn = DrawnInstance(
            instance: inst, shape: shape, reference: reference, bounds: bounds, fixed: el["fixed"] == .bool(true), start: look, pivot: pivot,
            pivoted: pivoted)
        if kind == "outline", el["around"] != nil { drawn.hollow = try r.selection(p + "/around", locals: l).isEmpty }
        if DocumentChecker.strokedKinds.contains(kind), el["width"] != nil {
            let width = try number("width")
            guard width > 0, width.isFinite else {
                throw EvalFailure(path: p + "/width", message: "width is \(Canonical.number(width)), not a positive number")
            }
            drawn.width = CGFloat(width)
        }
        return drawn
    }

    /// The runs of the entry a text element shows (section 9.2): each placeholder a run, named
    /// by the placeholder or by its phrase entry, and the literal text between them.
    static func runs(of element: String, entry name: String, el: JSONObject, locals: [String: DocumentValue], _ r: Resolver) throws(EvalFailure) -> [TextRun] {
        let p = DocumentPath.join("/elements", element)
        // The entry is filled with the instance's own locals: its `i` and its element's `let`.
        r.locals.append(locals)
        defer { r.locals.removeLast() }
        guard let (entry, _, _) = r.filler.lookup(name) else {
            throw EvalFailure(path: p + "/text", message: "there is no entry '\(name)'", code: .ref)
        }
        let source: String? = entry.string ?? entry["text"]?.string
        guard let source else {
            // A forms or select entry is shown whole, as one run.
            return [TextRun(name: nil, text: try r.fill(name, at: p + "/text").shown)]
        }
        let runs = el["runs"]?.object ?? JSONObject()
        var out: [TextRun] = []
        for piece in PlaceholderText(source).pieces {
            switch piece {
            case let .literal(s, _):
                out.append(TextRun(name: nil, text: s))
            case let .placeholder(ph):
                let run = ph.run
                let ink = runs[run]?["ink"]?.string
                if let t = runs[run]?["text"]?.string {
                    out.append(TextRun(name: run, text: try r.fill(t, at: DocumentPath.join(p, "runs", run, "text")).shown, ink: ink))
                    continue
                }
                let shown: String
                do {
                    let v = try r.value(of: ph.name)
                    if let phrase = ph.entry {
                        let f = try r.filler.fill(
                            phrase, value: { (x: String) throws(ExpressionError) -> DocumentValue? in try r.value(of: x) },
                            evaluate: { (e: DocumentExpression) throws(ExpressionError) -> DocumentValue in try Evaluator(scope: r).evaluate(e) }, n: v)
                        shown = f.shown
                    } else {
                        guard let v, let s = EntryFiller.shown(v) else {
                            throw EvalFailure(path: p + "/text", message: "{\(ph.name)} cannot be shown in \(element)")
                        }
                        shown = s
                    }
                } catch let e as ExpressionError {
                    throw r.nested ?? EvalFailure(path: p + "/text", at: e.at, message: e.message)
                } catch let e as EntryFiller.Failure {
                    throw EvalFailure(path: e.path, at: e.at, message: e.message, code: e.code)
                } catch let e as EvalFailure {
                    throw e
                } catch {
                    throw EvalFailure(path: p + "/text", message: "\(error)")
                }
                out.append(TextRun(name: run, text: shown, ink: ink))
            }
        }
        return out
    }

    /// The point an `appear` comes from (section 13.1): its `from` as a point, or the middle of the
    /// bounds of the one instance it selects; nil without a `from`.
    static func origin(of a: ResolvedAction, _ p: String, locals: [String: DocumentValue], _ r: Resolver) throws(EvalFailure) -> CGPoint? {
        guard a.verb == "appear" else { return nil }
        if r.doc.expressions[p + "/from"] != nil {
            let s = try r.selection(p + "/from", locals: locals)
            guard s.count == 1, let one = s.instances.first else {
                throw EvalFailure(path: p + "/from", message: "from selects \(s.count) instances, not one")
            }
            let b = try r.bounds(one.whole)
            return CGPoint(x: b.midX, y: b.midY)
        }
        if r.doc.expressions[p + "/from/0"] != nil {
            return CGPoint(x: try r.number(p + "/from/0", locals: locals, what: "x"), y: try r.number(p + "/from/1", locals: locals, what: "y"))
        }
        return nil
    }

    /// A step's tracks, built in the order its actions start, each reading the state it starts
    /// from (the position a `move` sets out from, the opacity a `fade` starts at).
    static func tracks(
        _ step: ResolvedStep, from before: [InstanceLook], instances: [DrawnInstance], index: [DocumentInstance: Int], style: DocumentStyle,
        roles: DocumentRoles, _ r: Resolver, failures: inout [EvalFailure]
    ) -> [Track] {
        var flat: [(action: ResolvedAction, locals: [String: DocumentValue], inEach: Bool)] = []
        for a in step.actions {
            flat.append((a, [:], false))
            for it in a.iterations { for x in it.actions { flat.append((x, it.locals, true)) } }
        }
        let order = flat.indices.sorted { flat[$0].action.start != flat[$1].action.start ? flat[$0].action.start < flat[$1].action.start : $0 < $1 }
        var out: [Track] = []
        func state(at t: Double) -> [InstanceLook] {
            var s = before
            for track in out { track.apply(at: t, to: &s) }
            return s
        }
        // An action that fails leaves no track, and the others are still built.
        func build(_ k: Int) throws(EvalFailure) {
            let (a, locals, inEach) = flat[k]
            let p = a.path
            func refuse(_ message: String) -> EvalFailure { EvalFailure(path: p, message: message, code: .capability) }
            if a.verb == "say" || a.verb == "each" { return }
            let easing = style.easing(a.ease ?? "linear")
            let o = r.doc.json.value(at: p)?.object ?? JSONObject()
            var placement: [CGPoint]?
            if a.verb == "appear", r.doc.expressions[p + "/place"] != nil, case let .placement(pl) = try r.eval(p + "/place", locals: locals) {
                let rect = try r.bounds(pl.source.whole)
                placement = (0..<a.targets.count).map { CGPoint(x: rect.minX + 1, y: rect.minY + CGFloat($0) * rect.height / 10 + 1) }
            }
            var gatherFrom: [DocumentInstance] = []
            if a.verb == "gather" { gatherFrom = try r.selection(p + "/from", locals: locals).instances }
            for (j, target) in a.targets.enumerated() {
                guard let at = index[target.whole] else { continue }
                let l = Resolver.perInstance(locals, j, inEach: inEach)
                let start = a.starts[j]
                let effect: Track.Effect
                switch a.verb {
                case "appear":
                    let rise = try r.number(p + "/rise", locals: l, default: 0, what: "rise")
                    let grow = r.doc.expressions[p + "/grow"] != nil ? try r.number(p + "/grow", locals: l, what: "grow") : nil
                    var entrance: Track.Entrance?
                    if target.part == nil, let origin = try Self.origin(of: a, p, locals: l, r) {
                        // The instance starts with its pivot, or the middle of its bounds, at the point, and
                        // is carried to its place in a straight line as it grows.
                        let inst = instances[at]
                        let base = state(at: start)[at].position
                        let moved = CGVector(dx: base.x - inst.reference.x, dy: base.y - inst.reference.y)
                        let centre = inst.pivoted ? inst.pivot : CGPoint(x: inst.bounds.midX, y: inst.bounds.midY)
                        entrance = Track.Entrance(
                            base: base, offset: CGVector(dx: origin.x - (centre.x + moved.dx), dy: origin.y - (centre.y + moved.dy)))
                    }
                    effect = .appear(rise: rise, grow: grow, place: placement?[j], text: a.text?.shown, entrance: entrance)
                case "fade":
                    let to = o["to"] == .string("ghost") ? Components.ghostOpacity : try r.number(p + "/to", locals: l, what: "to")
                    let now = state(at: start)[at]
                    let from: Double =
                        switch target.part {
                        case let .run(name)?: now.runOpacity[name] ?? 1
                        case .cross?: now.crossOpacity
                        case nil: now.opacity
                        }
                    effect = .fade(from: from, to: to)
                case "draw":
                    effect = .draw
                case "cross":
                    let now = state(at: start)[at]
                    effect = .cross(fade: a.fade, easing: style.easing(style.kindEasing("fade")), from: now.opacity, crossFrom: now.crossOpacity)
                case "tint":
                    guard case .run? = target.part else { throw refuse(PlayerRefusal.tintNeedsRun + "\(target)") }
                    guard let role = o["ink"]?.string, let op = roles.hue(role) else {
                        throw refuse(PlayerRefusal.tintHue)
                    }
                    if case let .text(_, style, _, _, _, _) = instances[at].shape, style != "equation" {
                        throw refuse(PlayerRefusal.tintEquation)
                    }
                    effect = .tint(op)
                case "move":
                    let now = state(at: start)[at]
                    let x0 = now.position
                    var dest = now.place
                    if r.doc.expressions[p + "/to/0"] != nil {
                        dest = CGPoint(x: try r.number(p + "/to/0", locals: l, what: "x"), y: try r.number(p + "/to/1", locals: l, what: "y"))
                    }
                    var frames: [(Double, CGPoint)] = [(0, x0)]
                    let keys = l.merging(["x0": .number(Double(x0.x)), "y0": .number(Double(x0.y))]) { $1 }
                    for (f, v) in (o["via"]?.array ?? []).enumerated() {
                        let fp = p + "/via/\(f)"
                        guard case let .number(offset)? = v.array?.first else { continue }
                        frames.append((offset,
                            CGPoint(x: try r.number(fp + "/1", locals: keys, what: "x"), y: try r.number(fp + "/2", locals: keys, what: "y"))))
                    }
                    frames.append((1, dest))
                    effect = .move(frames)
                    if dest != now.place {
                        // `to` becomes the instance's place, for what selects and frames it later.
                        r.state[target.whole, default: InstanceState()].place = dest
                    }
                case "gather":
                    guard j < gatherFrom.count, let source = index[gatherFrom[j].whole] else { continue }
                    let now = state(at: a.start)
                    effect = .gather(from: now[source].position, to: now[at].place)
                case "look":
                    let value: PieceStyle =
                        switch o["value"]?.string {
                        case "traded": .traded
                        case "counted": .counted
                        default: .pencil
                        }
                    effect = .look(value)
                case "set":
                    effect = .set(a.text?.shown ?? "")
                case "tag":
                    guard let hue = o["ink"]?.string.map({ roles.hue($0) }) ?? .some(.result) else {
                        throw refuse(PlayerRefusal.tagHue)
                    }
                    effect = .tag(a.text?.shown ?? "", hue)
                case "pulse":
                    effect = .pulse
                case "turn":
                    let now = state(at: start)[at]
                    // Without `to`, back to the place's angle: the last `to` a step left, or the
                    // element's own `turn`.
                    var dest = r.state[target.whole]?.angle ?? instances[at].start.turn
                    if r.doc.expressions[p + "/to"] != nil {
                        dest = try r.number(p + "/to", locals: l, what: "to")
                        if !a.mark { r.newAngles.append((target.whole, dest, start)) }
                    }
                    effect = .turn(from: now.turn, to: dest)
                default:
                    throw refuse("this player does not draw the verb '\(a.verb)' yet")
                }
                out.append(Track(
                    target: at, part: target.part, begins: a.start, start: start, duration: a.duration, easing: easing, mark: a.mark, effect: effect))
            }
        }
        for k in order {
            do { try build(k) } catch { failures.append(error) }
        }
        return out
    }
}

/// The style a document's timing and camera come from: the standard style with the document's
/// own `style` over it (section 16.3).
struct DocumentStyle {
    let root: JSONObject
    let camera: CameraDefaults

    init(_ doc: ExplainerDocument) {
        root = doc.root["style"]?.object ?? JSONObject()
        var c = ExplainerStyle.standard.camera
        let cam = root["motion"]?["camera"]
        if case let .number(n)? = cam?["at"] { c.at = n }
        if case let .number(n)? = cam?["duration"] { c.duration = n }
        if case let .string(s)? = cam?["easing"] { c.easing = s }
        if case let .number(n)? = cam?["margin"] { c.margin = n }
        if case let .number(n)? = cam?["dim"] { c.dim = n }
        camera = c
    }

    /// The curve called `name`: the document's, then the standard style's.
    func easing(_ name: String) -> Easing {
        if name == "linear" { return .linear }
        let a = (root["easings"]?[name]?.array ?? []).compactMap { v -> Double? in if case let .number(n) = v { n } else { nil } }
        if a.count == 4 { return .cubic(a[0], a[1], a[2], a[3]) }
        return ExplainerStyle.standard.easing(named: name) ?? .linear
    }

    /// The default curve's name for a kind of verb.
    func kindEasing(_ kind: String) -> String {
        root["motion"]?["easings"]?[kind]?.string ?? MotionKind(rawValue: kind).flatMap { ExplainerStyle.standard.kindEasings[$0] } ?? "linear"
    }
}
