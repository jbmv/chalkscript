import CoreGraphics
import Foundation

extension ExplainerDocument {
    /// The layout a player uses for a drawing area of `area` points (section 8): the first
    /// layout other than `stage`, by name in code point order, whose `suits` is true, and
    /// otherwise `stage`. A `suits` that cannot be evaluated does not suit.
    public func layout(for area: CGSize, problem: [String: DocumentValue] = [:]) -> String {
        let names = (root["layouts"]?.object?.keys ?? []).filter { $0 != "stage" }
            .sorted { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) }
        for name in names {
            let r = Resolver(self, problem: problem, layout: name, area: area, wording: wordings.first ?? "", locale: sourceLocale, playback: DocumentPlayback())
            if case .truth(true)? = try? r.eval(DocumentPath.join("/layouts", name, "suits"), locals: r.areaLocals) { return name }
        }
        return "stage"
    }

    /// Resolves the watched part for one problem (EXP-19): the steps it has, each step's actions
    /// with their resolved targets, starts and durations, the step's duration, and every line
    /// filled in `wording` and `locale` with its shown and spoken forms.
    ///
    /// - Parameters:
    ///   - wording: the wording to fill lines from; nil takes the one `plays` suggests for the
    ///     playback's control, or else the first.
    ///   - locale: nil is the source locale. An entry the locale lacks is filled from the source
    ///     locale and listed in `fallbacks`.
    ///   - area: the drawing area, in points, from which the layout is chosen; nil is the stage.
    /// - Throws: `DocumentRefusal` when the document has an error, the problem is outside the
    ///   parameters, or the document is not sound for the problem.
    public func resolve(
        problem: [String: DocumentValue], wording: String? = nil, locale: String? = nil,
        playback: DocumentPlayback = DocumentPlayback(), area: CGSize? = nil
    ) throws(DocumentRefusal) -> ResolvedExplainer {
        if findings.hasErrors { throw DocumentRefusal(findings: findings.errors) }
        let outside = check(problem: problem)
        if !outside.isEmpty { throw DocumentRefusal(findings: outside) }
        let w = wording ?? suggestedWording(for: playback.control) ?? wordings.first ?? ""
        guard wordings.contains(w) else {
            throw DocumentRefusal(findings: [.error(.ref, DocumentPath.join("/wording", sourceLocale), "there is no wording '\(w)'")])
        }
        let loc = locale ?? sourceLocale
        guard root["wording"]?[loc] != nil else {
            throw DocumentRefusal(findings: [.error(.ref, "/wording", "there is no locale '\(loc)'")])
        }
        let layout = area.map { self.layout(for: $0, problem: problem) } ?? "stage"
        let r = Resolver(self, problem: problem, layout: layout, area: area, wording: w, locale: loc, playback: playback)
        do {
            return try r.resolve()
        } catch {
            var f = DocumentFinding(.error, error.code, error.path, at: error.at, values: problem, error.message)
            f.time = error.time
            throw DocumentRefusal(findings: [f])
        }
    }
}

/// A failure while resolving, at the JSON Pointer of what failed.
struct EvalFailure: Error {
    var path: String
    var at: Int?
    var message: String
    var code: DocumentFinding.Code = .eval
    var time: Double?
}

/// What a step has done to an instance, as far as later selections and regions need to know.
struct InstanceState {
    var crossed = false
    var ghosted = false
    /// A new place for the instance's reference point, given by a `move` with `to`.
    var place: CGPoint?
}

/// Resolves one document for one problem, layout, wording, locale and playback.
final class Resolver: EvaluationScope {
    let doc: ExplainerDocument
    let root: JSONObject
    let problem: [String: DocumentValue]
    let layout: String
    let layoutLets: JSONObject
    let area: CGSize?
    let filler: EntryFiller
    let playback: DocumentPlayback
    let wordingName: String

    var cache: [String: DocumentValue] = [:]
    /// Values that failed while their dependents were being prepared; the failure is raised
    /// only where one is used.
    var failed: [String: EvalFailure] = [:]
    var evaluating: Set<String> = []
    static let maxChain = 16
    var boundsPending: Set<DocumentInstance> = []
    var varValues: [String: DocumentValue] = [:]
    var counts: [String: Int] = [:]
    var countsPending: Set<String> = []
    var locals: [[String: DocumentValue]] = []
    var state: [DocumentInstance: InstanceState] = [:]
    var nested: EvalFailure?
    var fallbacks: Set<String> = []

    // The step being resolved.
    var stepActions: [String: (action: JSONObject, path: String)] = [:]
    var resolvedActions: [String: ResolvedAction] = [:]
    var notRunning: Set<String> = []
    var timing: Set<String> = []
    /// Places given by `move` with `to` in the step being resolved, applied when it ends.
    var newPlaces: [(DocumentInstance, CGPoint)] = []

    // The style the document's timing defaults come from.
    var durations: [String: Double] = [:]
    var kindEasings: [String: String] = [:]
    var cameraAt = 0.0
    var cameraDuration = 0.0
    var cameraMargin = 12.0

    init(_ doc: ExplainerDocument, problem: [String: DocumentValue], layout: String, area: CGSize?, wording: String, locale: String, playback: DocumentPlayback) {
        self.doc = doc
        self.root = doc.root
        self.problem = problem
        self.layout = layout
        self.layoutLets = root["layouts"]?[layout]?["let"]?.object ?? JSONObject()
        self.area = area
        self.filler = EntryFiller(document: doc, locale: locale, wording: wording)
        self.playback = playback
        self.wordingName = wording
        let standard = ExplainerStyle.standard
        let motion = root["style"]?["motion"]
        for kind in MotionKind.allCases {
            if case let .number(n)? = motion?["durations"]?[kind.rawValue] { durations[kind.rawValue] = n } else { durations[kind.rawValue] = standard.durations[kind] }
            if case let .string(s)? = motion?["easings"]?[kind.rawValue] { kindEasings[kind.rawValue] = s } else { kindEasings[kind.rawValue] = standard.kindEasings[kind] }
        }
        func camera(_ key: String, _ fallback: Double) -> Double {
            if case let .number(n)? = motion?["camera"]?[key] { return n }
            return fallback
        }
        cameraAt = camera("at", standard.camera.at)
        cameraDuration = camera("duration", standard.camera.duration)
        cameraMargin = camera("margin", standard.camera.margin)
    }

    var areaLocals: [String: DocumentValue] {
        guard let area else { return [:] }
        return ["areaW": .number(Double(area.width)), "areaH": .number(Double(area.height))]
    }

    // MARK: evaluation

    /// Evaluates the expression at `path` with `extra` locals in scope.
    func eval(_ path: String, locals extra: [String: DocumentValue] = [:]) throws(EvalFailure) -> DocumentValue {
        guard let e = doc.expressions[path] else { throw EvalFailure(path: path, message: "there is no expression here") }
        locals.append(extra)
        defer { locals.removeLast() }
        do {
            return try Evaluator(scope: self).evaluate(e)
        } catch {
            if let n = nested {
                nested = nil
                throw n
            }
            throw EvalFailure(path: path, at: error.at, message: error.message)
        }
    }

    func number(_ path: String, locals: [String: DocumentValue] = [:], default d: Double? = nil, what: String) throws(EvalFailure) -> Double {
        if doc.expressions[path] == nil, let d { return d }
        let v = try eval(path, locals: locals)
        guard case let .number(n) = v else { throw EvalFailure(path: path, message: "\(what) is \(v.typeName), not a number") }
        return n
    }

    func truth(_ path: String, locals: [String: DocumentValue] = [:], default d: Bool = true) throws(EvalFailure) -> Bool {
        if doc.expressions[path] == nil { return d }
        let v = try eval(path, locals: locals)
        guard case let .truth(b) = v else { throw EvalFailure(path: path, message: "\(v) is \(v.typeName), not a truth value") }
        return b
    }

    func selection(_ path: String, locals: [String: DocumentValue] = [:]) throws(EvalFailure) -> DocumentSelection {
        let v = try eval(path, locals: locals)
        guard case let .selection(s) = v else { throw EvalFailure(path: path, message: "\(v) is \(v.typeName), not a selection") }
        return s
    }

    /// Runs `body`, turning a failure inside it into an `ExpressionError` that the evaluation in
    /// progress rethrows as the inner failure.
    func inner<T>(_ body: () throws(EvalFailure) -> T) throws(ExpressionError) -> T {
        do {
            return try body()
        } catch {
            if nested == nil { nested = error }
            throw ExpressionError(error.message, at: error.at ?? 0)
        }
    }

    func value(of name: String) throws(ExpressionError) -> DocumentValue? {
        for frame in locals.reversed() { if let v = frame[name] { return v } }
        if let v = problem[name] { return v }
        if let v = cache[name] ?? varValues[name] { return v }
        guard let path = valuePath(name) else { return nil }
        if let f = failed[name] {
            if nested == nil { nested = f }
            throw ExpressionError(f.message, at: f.at ?? 0)
        }
        guard !evaluating.contains(name) else { throw ExpressionError("'\(name)' depends on itself", at: 0) }
        // Values that name one another are evaluated in order of dependency (`prepare`); this
        // bounds what is left, such as a cycle in a document that does not conform.
        guard evaluating.count < Self.maxChain else {
            throw ExpressionError("'\(name)' is reached through more than \(Self.maxChain) values that name one another", at: 0)
        }
        prepare(name)
        evaluating.insert(name)
        defer { evaluating.remove(name) }
        let v = try inner { () throws(EvalFailure) in try self.evalIsolated(path) }
        if path.hasPrefix("/vars/") { varValues[name] = v } else { cache[name] = v }
        return v
    }

    /// The JSON Pointer of the `let` or `vars` value `name` in this layout, or nil.
    func valuePath(_ name: String) -> String? {
        if layoutLets[name] != nil { return DocumentPath.join("/layouts", layout, "let", name) }
        if root["let"]?[name] != nil { return DocumentPath.join("/let", name) }
        if root["vars"]?[name] != nil { return DocumentPath.join("/vars", name) }
        return nil
    }

    /// Evaluates the values `name` depends on, those it depends on first, so that evaluating
    /// `name` finds each already kept and a long chain of values never deepens the stack. A
    /// value that fails is kept as a failure, raised only if an evaluation actually uses it
    /// (section 5.2: values are evaluated on demand).
    func prepare(_ name: String) {
        var order: [String] = []
        var seen: Set<String> = [name]
        var stack: [(String, Bool)] = [(name, false)]
        while let (n, expanded) = stack.popLast() {
            if expanded {
                order.append(n)
                continue
            }
            stack.append((n, true))
            guard let path = valuePath(n), !evaluating.contains(n) || n == name else { continue }
            doc.expressions[path]?.root.walk { node in
                if case let .name(d) = node.kind, !seen.contains(d), cache[d] == nil, failed[d] == nil, problem[d] == nil, valuePath(d) != nil {
                    seen.insert(d)
                    stack.append((d, false))
                }
            }
        }
        for n in order where n != name && cache[n] == nil && varValues[n] == nil && failed[n] == nil && !evaluating.contains(n) {
            guard let path = valuePath(n) else { continue }
            evaluating.insert(n)
            do {
                let v = try evalIsolated(path)
                if path.hasPrefix("/vars/") { varValues[n] = v } else { cache[n] = v }
            } catch {
                failed[n] = error
            }
            evaluating.remove(n)
        }
    }

    /// Evaluates a document-level value with no locals in scope.
    func evalIsolated(_ path: String) throws(EvalFailure) -> DocumentValue {
        let saved = locals
        locals = []
        defer { locals = saved }
        return try eval(path)
    }

    func element(_ name: String) -> ScopeElement? {
        guard let el = root["elements"]?[name]?.object, let kind = el["kind"]?.string else { return nil }
        let count = (try? instanceCount(name)) ?? 0
        var runs = Set<String>()
        if kind == "text", let entry = el["text"]?.string, let (e, _, _) = filler.lookup(entry) {
            for t in DocumentChecker.entryTexts(e) { runs.formUnion(PlaceholderText(t).placeholders.map(\.run)) }
        }
        return ScopeElement(kind: kind, repeated: el["repeat"] != nil, count: count, runs: runs,
                            isPiece: DocumentChecker.pieceKinds.contains(kind), name: name)
    }

    func isWhole(_ instance: DocumentInstance) -> Bool {
        let s = state[instance.whole] ?? InstanceState()
        return !s.crossed && !s.ghosted
    }

    func time(_ function: String, of action: String, at: Int) throws(ExpressionError) -> Double {
        let a = try inner { () throws(EvalFailure) in try self.resolveTopLevel(action) }
        guard let a else { throw ExpressionError("\(function)(\(action)): \(action) does not run for this problem", at: at) }
        return function == "start" ? a.start : a.end
    }

    /// How many instances element `name` has for this problem: its `repeat`, or one, or none
    /// when its `when` is false or an outline's `around` selects nothing.
    func instanceCount(_ name: String) throws(EvalFailure) -> Int {
        if let c = counts[name] { return c }
        guard !countsPending.contains(name) else { throw EvalFailure(path: DocumentPath.join("/elements", name), message: "\(name)'s instances depend on themselves") }
        countsPending.insert(name)
        defer { countsPending.remove(name) }
        let p = DocumentPath.join("/elements", name)
        var n = 1
        if doc.expressions[p + "/repeat"] != nil {
            let v = try evalIsolated(p + "/repeat")
            guard let k = v.integer, (0...1000).contains(k) else { throw EvalFailure(path: p + "/repeat", message: "repeat is \(v), not an integer from 0 to 1000") }
            n = k
        }
        if doc.expressions[p + "/when"] != nil {
            let v = try evalIsolated(p + "/when")
            guard case let .truth(b) = v else { throw EvalFailure(path: p + "/when", message: "when is \(v.typeName), not a truth value") }
            if !b { n = 0 }
        }
        if n > 0, doc.expressions[p + "/around"] != nil {
            let s = try selection(p + "/around")
            if s.isEmpty { n = 0 }
        }
        counts[name] = n
        return n
    }

    // MARK: the watched part

    func resolve() throws(EvalFailure) -> ResolvedExplainer {
        let size = try drawingSize()
        let cameraOn = root["layouts"]?[layout]?["camera"] == .bool(true)
        for name in root["elements"]?.object?.keys ?? [] { _ = try instanceCount(name) }
        var steps: [ResolvedStep] = []
        var holding: String? = root["opening"]?.string
        let frames = cameraOn ? CameraFraming(self, size: size) : nil
        for name in doc.sequence {
            let own = root["steps"]?[name]?.object ?? JSONObject()
            if !(try truth(DocumentPath.join("/steps", name, "when"))) { continue }
            let base = own["like"]?.string
            func source(_ key: String) -> String {
                own[key] == nil && base != nil && key != "when" ? DocumentPath.join("/steps", base!) : DocumentPath.join("/steps", name)
            }
            func value(_ key: String) -> JSONValue? {
                own[key] ?? (key == "when" ? nil : base.flatMap { root["steps"]?[$0]?[key] })
            }
            let shot = value("shot")?.string ?? holding
            var lead = 0.0
            if let frames, try frames.frame(holding) != frames.frame(shot) { lead = cameraAt + cameraDuration }
            holding = shot

            // The actions, timed in their own order of dependency.
            stepActions = [:]
            resolvedActions = [:]
            notRunning = []
            newPlaces = []
            let actionsPath = source("actions") + "/actions"
            let actionObject = value("actions")?.object ?? JSONObject()
            for (k, v) in actionObject.entries { stepActions[k] = (v.object ?? JSONObject(), DocumentPath.join(actionsPath, k)) }
            // Resolved in order of dependency, so that start() and end() find what they name
            // already timed; listed in the document's order.
            for k in timingOrder(actionObject.keys) { _ = try resolveTopLevel(k) }
            let actions = actionObject.keys.compactMap { resolvedActions[$0] }

            let durationPath = source("duration") + "/duration"
            let latest = actions.map(\.end).max() ?? 0
            let timeline = try number(durationPath, default: latest, what: "duration")
            let hold = try number(source("hold") + "/hold", default: 0, what: "hold")
            if timeline < 0 { throw EvalFailure(path: durationPath, message: "duration is \(Canonical.number(timeline)), which is negative") }
            if hold < 0 { throw EvalFailure(path: source("hold") + "/hold", message: "hold is \(Canonical.number(hold)), which is negative") }
            let counted = value("counts") == .bool(true)
            let pace = counted ? playback.countPace : 1

            let sayPath = source("say") + "/say"
            let line = try fill(value("say")?.string ?? "", at: sayPath)
            var lines = [ResolvedLine(time: 0, entry: line, caption: true, spoken: line.spoken != nil, count: false, action: nil)]
            var waits: [Double] = []
            if counted && playback.counts == .spoken { waits.append(0) }
            func collect(_ a: ResolvedAction, offset: Double) {
                if a.waitsForVoice && a.verb != "each" { waits.append(offset + a.start) }
                if a.verb == "say", let text = a.text {
                    let isCount = countFlag(a.path)
                    let hidden = isCount && playback.counts == .shown
                    let caption = !hidden && captionFlag(a.path, count: isCount)
                    lines.append(ResolvedLine(time: offset + a.start, entry: text, caption: caption, spoken: !hidden && text.spoken != nil, count: isCount, action: a.path))
                }
                // An each that says a count waits so that each number is heard with its piece; a
                // count that is shown is not heard, so it does not wait (EXP-10).
                let shownCounts = playback.counts == .shown && saysCount(a.path)
                for it in a.iterations {
                    if a.waitsForVoice && !shownCounts { waits.append(offset + it.start) }
                    for x in it.actions { collect(x, offset: offset) }
                }
            }
            for a in actions { collect(a, offset: 0) }
            applyEffects(actions)

            // Paced, then moved later by the camera's lead; the step's line stays at 0.
            func shift(_ t: Double) -> Double { lead + pace * t }
            let retimed = actions.map { Self.retime($0, pace: pace, lead: lead) }
            // In time order; lines at the same moment keep the document's order.
            for k in lines.indices where k > 0 { lines[k].time = shift(lines[k].time) }
            let order = lines.indices.sorted { (a: Int, b: Int) -> Bool in
                lines[a].time != lines[b].time ? lines[a].time < lines[b].time : a < b
            }
            lines = order.map { lines[$0] }
            waits = waits.map(shift)
            let t = pace * timeline
            let h = pace * hold
            steps.append(ResolvedStep(
                name: name, shot: shot, lead: lead, timeline: t, hold: h, duration: lead + t + h, counts: counted, line: line,
                actions: retimed, lines: lines, waits: waits))
        }
        let intro = try root["intro"]?["watch"]?.string.map { name throws(EvalFailure) in try fill(name, at: "/intro/watch") }
        // Do it with me's line may be absent from a wording that plays only the watched part.
        let guided = (root["intro"]?["guided"]?.string).flatMap { try? fill($0, at: "/intro/guided") }
        return ResolvedExplainer(
            problem: problem, layout: layout, size: size, camera: cameraOn, wording: wordingName, locale: filler.locale,
            playback: playback, intro: intro, guidedIntro: guided ?? intro, steps: steps, fallbacks: fallbacks.sorted())
    }

    func countFlag(_ path: String) -> Bool { doc.json.value(at: path + "/count") == .bool(true) }

    /// Whether the `each` at `path` says a count in its `then`.
    func saysCount(_ path: String) -> Bool {
        (doc.json.value(at: path + "/then")?.object?.entries ?? []).contains { $0.value["do"] == .string("say") && $0.value["count"] == .bool(true) }
    }

    func captionFlag(_ path: String, count: Bool) -> Bool {
        if case let .bool(b)? = doc.json.value(at: path + "/caption") { return b }
        return !count
    }

    func drawingSize() throws(EvalFailure) -> CGSize {
        let p = DocumentPath.join("/layouts", layout, "size")
        guard doc.expressions[p + "/0"] != nil else { return CGSize(width: 1000, height: 540) }
        let w = try number(p + "/0", locals: areaLocals, what: "the width")
        let h = try number(p + "/1", locals: areaLocals, what: "the height")
        guard w > 0, h > 0 else { throw EvalFailure(path: p, message: "the drawing's size is not positive") }
        return CGSize(width: w, height: h)
    }

    /// `a` with every time multiplied by `pace` and moved later by `lead`.
    static func retime(_ a: ResolvedAction, pace: Double, lead: Double) -> ResolvedAction {
        var x = a
        x.start = lead + pace * a.start
        x.end = lead + pace * a.end
        x.duration = pace * a.duration
        x.stagger = pace * a.stagger
        x.fade = pace * a.fade
        x.starts = a.starts.map { lead + pace * $0 }
        x.iterations = a.iterations.map { it in
            var y = it
            y.start = lead + pace * it.start
            y.actions = it.actions.map { retime($0, pace: pace, lead: lead) }
            return y
        }
        return x
    }

    /// Fills entry `name`, used at `path`, with the names now in scope.
    func fill(_ name: String, at path: String, runs: [String: String] = [:]) throws(EvalFailure) -> FilledEntry {
        do {
            let f = try filler.fill(name, value: { (x: String) throws(ExpressionError) -> DocumentValue? in try self.value(of: x) },
                                    evaluate: { (e: DocumentExpression) throws(ExpressionError) -> DocumentValue in try Evaluator(scope: self).evaluate(e) },
                                    runs: runs)
            if f.locale != filler.locale { fallbacks.insert(name) }
            return f
        } catch {
            if let n = nested {
                nested = nil
                throw n
            }
            throw EvalFailure(path: error.path, at: error.at, message: error.message + " (as \(path) uses it)", code: error.code)
        }
    }

    // MARK: actions

    static func kind(of verb: String) -> String? {
        switch verb {
        case "appear", "tag", "pulse": "appear"
        case "fade": "fade"
        case "draw", "cross", "tint": "draw"
        case "move", "gather": "travel"
        default: nil
        }
    }

    /// The top-level action `name` of the step being resolved, or nil when it does not run.
    func resolveTopLevel(_ name: String) throws(EvalFailure) -> ResolvedAction? {
        if let a = resolvedActions[name] { return a }
        if notRunning.contains(name) { return nil }
        guard let (o, path) = stepActions[name] else { throw EvalFailure(path: "", message: "there is no action '\(name)' in this step") }
        guard !timing.contains(name) else { throw EvalFailure(path: path + "/at", message: "\(name)'s start depends on itself") }
        guard timing.count < Self.maxChain else {
            throw EvalFailure(path: path + "/at", message: "\(name) is timed through more than \(Self.maxChain) actions that name one another")
        }
        timing.insert(name)
        defer { timing.remove(name) }
        guard let a = try resolveAction(name, o, path, iterationStart: nil, current: nil, locals: [:]) else {
            notRunning.insert(name)
            return nil
        }
        resolvedActions[name] = a
        return a
    }

    /// One action. Inside an `each`, `iterationStart` is the iteration's start, `current` its
    /// instance and `locals` its `i` and `let`.
    func resolveAction(
        _ name: String, _ o: JSONObject, _ path: String, iterationStart: Double?, current: DocumentInstance?, locals: [String: DocumentValue]
    ) throws(EvalFailure) -> ResolvedAction? {
        // The iteration's locals are in scope for the lines the action fills, too.
        self.locals.append(locals)
        defer { self.locals.removeLast() }
        guard try truth(path + "/when", locals: locals) else { return nil }
        let verb = o["do"]?.string ?? ""
        let at = try number(path + "/at", locals: locals, default: 0, what: "at")
        if at < 0 { throw EvalFailure(path: path + "/at", message: "at is \(Canonical.number(at)), which is negative") }
        let start = (iterationStart ?? 0) + at
        var targets: [DocumentInstance] = []
        let hasTarget = doc.expressions[path + "/target"] != nil
        if hasTarget {
            targets = try selection(path + "/target", locals: locals).instances
        } else if let current, verb != "say" {
            targets = [current]
        }
        try checkTargets(verb, targets, path)
        let kind = Self.kind(of: verb)
        let dur = kind == nil ? 0 : try number(path + "/dur", locals: locals, default: durations[kind!] ?? 0, what: "dur")
        let each = try number(path + "/each", locals: locals, default: 0, what: "each")
        let fade = verb == "cross" ? try number(path + "/fade", locals: locals, default: 0, what: "fade") : 0
        for (v, k) in [(dur, "dur"), (each, "each"), (fade, "fade")] where v < 0 {
            throw EvalFailure(path: path + "/" + k, message: "\(k) is \(Canonical.number(v)), which is negative")
        }
        let reverse = o["reverse"] == .bool(true)
        let n = targets.count
        var end: Double
        if (hasTarget || current != nil) && verb != "say" {
            end = n == 0 ? start : start + Double(n - 1) * each + dur + fade
        } else {
            end = start + dur
        }
        let starts = (0..<n).map { k in start + Double(reverse ? n - 1 - k : k) * each }
        var text: FilledEntry?
        var iterations: [ResolvedIteration] = []
        switch verb {
        case "say":
            text = try fill(o["line"]?.string ?? "", at: path + "/line")
        case "set", "tag":
            text = try fill(o["text"]?.string ?? "", at: path + "/text")
        case "appear":
            if let t = o["text"]?.string { text = try fill(t, at: path + "/text") }
            if doc.expressions[path + "/place"] != nil {
                let v = try eval(path + "/place", locals: locals)
                guard case .placement = v else { throw EvalFailure(path: path + "/place", message: "place is \(v.typeName), not a placement") }
                if n != 10 || !targets.allSatisfy({ element($0.element)?.kind == "one" && $0.part == nil }) {
                    throw EvalFailure(path: path + "/place", message: "split() places ten ones, and the targets are \(n) instance\(n == 1 ? "" : "s")")
                }
            }
        case "fade":
            if o["to"] != .string("ghost") {
                for (k, t) in targets.enumerated() {
                    let to = try number(path + "/to", locals: locals.merging(["i": .number(Double(k))]) { $1 }, what: "to")
                    if !(0...1).contains(to) { throw EvalFailure(path: path + "/to", message: "to is \(Canonical.number(to)), not from 0 to 1") }
                    if to < Components.ghostOpacity - 1e-12, t.part == nil, element(t.element)?.isPiece == true {
                        throw EvalFailure(path: path + "/to", message: "\(t) is a piece, which is never faded below a ghost")
                    }
                }
            }
        case "gather":
            let from = try selection(path + "/from", locals: locals)
            if from.count != n {
                throw EvalFailure(path: path + "/from", message: "gather moves \(n) target\(n == 1 ? "" : "s") from \(from.count) instance\(from.count == 1 ? "" : "s"); they must be as many")
            }
        case "move":
            if doc.expressions[path + "/to/0"] != nil {
                for (k, t) in targets.enumerated() {
                    let l = locals.merging(["i": .number(Double(k))]) { $1 }
                    let x = try number(path + "/to/0", locals: l, what: "x")
                    let y = try number(path + "/to/1", locals: l, what: "y")
                    newPlaces.append((t.whole, CGPoint(x: x, y: y)))
                }
            }
        case "each":
            let saved = locals
            var t = start
            var latest = start
            let letObject = o["let"]?.object ?? JSONObject()
            for (k, inst) in targets.enumerated() {
                var l = saved
                l["i"] = .number(Double(k))
                for key in letOrder(letObject, path) {
                    l[key] = try eval(DocumentPath.join(path, "let", key), locals: l)
                }
                let gap = try number(path + "/gap", locals: l, what: "gap")
                if gap < 0 { throw EvalFailure(path: path + "/gap", message: "gap is \(Canonical.number(gap)), which is negative") }
                var inner: [ResolvedAction] = []
                for (key, v) in o["then"]?.object?.entries ?? [] {
                    let ip = DocumentPath.join(path, "then", key)
                    if let a = try resolveAction(key, v.object ?? JSONObject(), ip, iterationStart: t, current: inst, locals: l) {
                        inner.append(a)
                        latest = max(latest, a.end)
                    }
                }
                iterations.append(ResolvedIteration(index: k, instance: inst, start: t, locals: l, actions: inner))
                t += gap
            }
            end = max(t, latest)
        default:
            break
        }
        let ease: String? = kind == nil ? nil : (o["ease"]?.string ?? kindEasings[kind!])
        return ResolvedAction(
            name: name, path: path, verb: verb, targets: targets, start: start, duration: dur, stagger: each, reverse: reverse, fade: fade,
            end: end, ease: ease, mark: o["mark"] == .bool(true), waitsForVoice: o["wait"] == .string("voice"), starts: starts, text: text,
            iterations: iterations)
    }

    /// The step's actions, each after those its `at` names through `start()` and `end()`.
    func timingOrder(_ names: [String]) -> [String] {
        var order: [String] = []
        var seen = Set<String>()
        for root in names where !seen.contains(root) {
            seen.insert(root)
            var stack: [(String, Bool)] = [(root, false)]
            while let (n, expanded) = stack.popLast() {
                if expanded {
                    order.append(n)
                    continue
                }
                stack.append((n, true))
                guard let path = stepActions[n]?.path else { continue }
                doc.expressions[path + "/at"]?.root.walk { node in
                    if case let .call(f, args) = node.kind, f == "start" || f == "end", case let .name(d)? = args.first?.kind,
                        stepActions[d] != nil, !seen.contains(d)
                    {
                        seen.insert(d)
                        stack.append((d, false))
                    }
                }
            }
        }
        return order
    }

    /// An `each`'s `let` names in an order of dependency.
    func letOrder(_ lets: JSONObject, _ path: String) -> [String] {
        var out: [String] = []
        var left = lets.keys
        while !left.isEmpty {
            let before = left.count
            for k in left {
                var deps = Set<String>()
                doc.expressions[DocumentPath.join(path, "let", k)]?.root.walk { if case let .name(x) = $0.kind { deps.insert(x) } }
                if deps.intersection(Set(left)).subtracting([k]).isEmpty {
                    out.append(k)
                    left.removeAll { $0 == k }
                }
            }
            if left.count == before { return out + left }
        }
        return out
    }

    func checkTargets(_ verb: String, _ targets: [DocumentInstance], _ path: String) throws(EvalFailure) {
        for t in targets {
            guard let el = element(t.element) else { continue }
            let ok: Bool
            switch verb {
            case "cross", "look": ok = el.isPiece && t.part == nil
            case "draw": ok = DocumentChecker.strokedKinds.contains(el.kind) && t.part == nil
            case "tint", "set": ok = t.part == nil ? (verb == "tint" || el.kind == "text") : { if case .run = t.part { true } else { false } }()
            case "move", "gather", "tag", "pulse": ok = t.part == nil
            default: ok = true
            }
            if !ok { throw EvalFailure(path: path + "/target", message: "\(verb) cannot act on \(t)") }
        }
    }

    /// What the step's actions leave for the next step's selections: crossed-out and ghosted
    /// pieces, and new places. A mark is undone as the next step begins, so it leaves nothing.
    func applyEffects(_ actions: [ResolvedAction]) {
        for a in actions where !a.mark {
            switch a.verb {
            case "cross":
                for t in a.targets where t.part == nil {
                    state[t, default: InstanceState()].crossed = true
                    if a.fade > 0 { state[t, default: InstanceState()].ghosted = true }
                }
            case "fade":
                let ghost = doc.json.value(at: a.path + "/to") == .string("ghost")
                for t in a.targets where t.part == nil { state[t, default: InstanceState()].ghosted = ghost }
            default:
                break
            }
            for it in a.iterations { applyEffects(it.actions) }
        }
        for (t, p) in newPlaces { state[t, default: InstanceState()].place = p }
        newPlaces = []
    }
}

extension DocumentChecker {
    static func entryTexts(_ entry: JSONValue) -> [String] {
        switch entry {
        case let .string(s): return [s]
        case let .object(o):
            var out = ["text", "spoken"].compactMap { o[$0]?.string }
            out += (o["forms"]?.object?.entries ?? []).compactMap { $0.value.string }
            out += (o["cases"]?.object?.entries ?? []).compactMap { $0.value.string }
            return out
        default: return []
        }
    }
}
