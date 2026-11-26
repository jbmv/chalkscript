import Foundation

/// What reading a document gives (EXP-19): the document, unless it could not be read as one,
/// and every finding of section 21 that reading makes.
public struct DocumentReading: Sendable {
    public var document: ExplainerDocument?
    public var findings: [DocumentFinding]

    /// Whether the document conforms: it was read and has no error.
    public var conforms: Bool { document != nil && !findings.hasErrors }
}

extension ExplainerDocument {
    /// Reads an explainer document (EXP-19): parses it, checks its structure, names, references,
    /// capabilities, expressions and wording against the format's reference, and reports every
    /// finding with its code and JSON Pointer. It never traps on malformed input.
    ///
    /// - Parameter capabilities: the capabilities the player that will play it implements.
    public static func read(_ data: Data, capabilities: Set<String> = ExplainerDocument.capabilities) -> DocumentReading {
        let json: JSONValue
        do {
            json = try JSONValue.parse(data)
        } catch {
            return DocumentReading(document: nil, findings: [.error(.json, error.path, error.description)])
        }
        guard let root = json.object else {
            return DocumentReading(document: nil, findings: [.error(.json, "", "the document is \(json.typeName), not an object")])
        }
        guard root["format"] == .string(format) else {
            let msg = root["format"] == nil ? "format is missing" : "format is not \"\(format)\""
            return DocumentReading(document: nil, findings: [.error(.format, "/format", msg)])
        }
        guard case let .string(v)? = root["version"] else {
            return DocumentReading(document: nil, findings: [.error(.schema, "/version", root["version"] == nil ? "version is missing" : "version is not a string")])
        }
        let parts = v.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let major = Int(parts[0]), let minor = Int(parts[1]), String(major) == parts[0], String(minor) == parts[1] else {
            return DocumentReading(document: nil, findings: [.error(.schema, "/version", "version \"\(v)\" is not MAJOR.MINOR")])
        }
        guard major == readerVersion.major else {
            return DocumentReading(document: nil, findings: [.error(.version, "/version", "version \(v) is not implemented: this reader reads \(readerVersion.major).x")])
        }
        let checker = DocumentChecker(root, capabilities: capabilities)
        if minor > readerVersion.minor {
            checker.findings.append(.warning(.version, "/version", "version \(v) is newer than this reader's \(readerVersion.major).\(readerVersion.minor)"))
        }
        checker.check()
        let doc = ExplainerDocument(json: json, findings: checker.findings, coverage: checker.coverage, expressions: checker.expressions)
        return DocumentReading(document: doc, findings: checker.findings)
    }

    public static func read(contentsOf url: URL, capabilities: Set<String> = ExplainerDocument.capabilities) -> DocumentReading {
        guard let data = try? Data(contentsOf: url) else {
            return DocumentReading(document: nil, findings: [.error(.json, "", "the file \(url.lastPathComponent) cannot be read")])
        }
        return read(data, capabilities: capabilities)
    }
}

/// What a slot of the document holds where an expression may stand (section 6.1).
enum SlotType {
    case number, truth, value, selection
}

/// The names an expression at one place may use (section 6.5).
struct SlotScope {
    enum Values: Equatable {
        /// A parameter's bounds: other parameters only.
        case params
        /// `let`, `vars`, `kind` and an element's `repeat` and `when`.
        case paramsAndLets
        /// One layout's `let`: the document's values and that layout's own added names.
        case layout(String)
        /// Everywhere else: parameters, `let`, `vars` and elements.
        case all
    }

    var values: Values
    var locals: Set<String> = []
    /// The actions `start()` and `end()` may name; nil where they are not available.
    var actions: Set<String>?
    /// The layout whose `let` replaces the document's, for names a layout adds.
    var layoutNames: Set<String> = []
}

/// Where an entry is said or shown, and what is in scope there.
struct EntryUse {
    var name: String
    var path: String
    var locals: Set<String>
    var part: WordingCoverage.Part
    /// The text element showing it, whose runs may fill its placeholders.
    var element: String?
}

/// Reads one document's tree and records its findings.
final class DocumentChecker {
    let root: JSONObject
    let capabilities: Set<String>
    var findings: [DocumentFinding] = []
    var expressions: [String: DocumentExpression] = [:]
    var coverage: [WordingCoverage] = []
    var entryUses: [EntryUse] = []
    /// Capabilities used, with where.
    var used: [(capability: String, path: String)] = []

    // The names of the document, gathered before anything is checked against them.
    var params: [String: JSONObject] = [:]
    var lets: [String: JSONValue] = [:]
    var vars: Set<String> = []
    var elements: [String: JSONObject] = [:]
    var layoutAdded: [String: Set<String>] = [:]
    var parts: Set<String> = []
    var shots: Set<String> = []
    var steps: [String: JSONObject] = [:]
    var roles: Set<String> = []
    var easings: Set<String> = []
    var wordingNames: Set<String> = []

    static let neutralRoles: Set<String> = ["paper", "sheet", "text", "muted", "line", "pencil", "onResult"]
    static let coreOperationRoles: Set<String> = ["result"]
    static let arithmeticRoles: Set<String> = ["subtract", "trade", "add", "multiply", "divide"]
    static let pieceKinds: Set<String> = ["ten", "one", "stick", "circle"]
    static let coreKinds: Set<String> = ["text", "line", "arrow", "outline", "shape"]
    static let strokedKinds: Set<String> = ["line", "arrow", "outline", "shape"]
    static let verbs: Set<String> = ["appear", "fade", "draw", "cross", "tint", "move", "gather", "look", "set", "tag", "pulse", "say", "each"]
    static let instantVerbs: Set<String> = ["look", "set", "say"]

    init(_ root: JSONObject, capabilities: Set<String>) {
        self.root = root
        self.capabilities = capabilities
    }

    func error(_ code: DocumentFinding.Code, _ path: String, at: Int? = nil, _ message: String) {
        findings.append(.error(code, path, at: at, message))
    }

    func warning(_ code: DocumentFinding.Code, _ path: String, at: Int? = nil, _ message: String) {
        findings.append(.warning(code, path, at: at, message))
    }

    // MARK: structure helpers

    /// `value` as an object, reporting a wrong type, every unknown key as a warning and every
    /// missing required key as an error.
    @discardableResult
    func object(_ value: JSONValue?, _ path: String, known: [String], required: [String] = []) -> JSONObject? {
        guard let value else { return nil }
        guard case let .object(o) = value else {
            error(.schema, path, "\(last(path)) is \(value.typeName), not an object")
            return nil
        }
        for k in o.keys where !known.contains(k) {
            warning(.unknown, DocumentPath.join(path, k), "'\(k)' is not a key of \(last(path)); it is ignored")
        }
        for k in required where o[k] == nil {
            error(.schema, path, "\(last(path)) has no '\(k)', which it requires")
        }
        return o
    }

    func last(_ path: String) -> String {
        let token = path.split(separator: "/").last.map(String.init) ?? "the document"
        return token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
    }

    /// `value` as an object whose keys are names, each checked against `isKey`.
    func map(_ value: JSONValue?, _ path: String, keys: (String) -> Bool = { DocumentNames.isName($0) }, what: String = "name")
        -> [(String, JSONValue, String)]
    {
        guard let value else { return [] }
        guard case let .object(o) = value else {
            error(.schema, path, "\(last(path)) is \(value.typeName), not an object")
            return []
        }
        var out: [(String, JSONValue, String)] = []
        for (k, v) in o.entries {
            let p = DocumentPath.join(path, k)
            if !keys(k) { error(.schema, p, "'\(k)' is not a valid \(what)") }
            out.append((k, v, p))
        }
        return out
    }

    func bool(_ o: JSONObject, _ key: String, _ path: String) {
        guard let v = o[key] else { return }
        if case .bool = v { return }
        error(.schema, DocumentPath.join(path, key), "\(key) is \(v.typeName), not true or false")
    }

    func string(_ o: JSONObject, _ key: String, _ path: String) -> String? {
        guard let v = o[key] else { return nil }
        guard case let .string(s) = v else {
            error(.schema, DocumentPath.join(path, key), "\(key) is \(v.typeName), not a string")
            return nil
        }
        return s
    }

    func oneOf(_ o: JSONObject, _ key: String, _ path: String, _ allowed: [String]) -> String? {
        guard let s = string(o, key, path) else { return nil }
        if !allowed.contains(s) {
            error(.schema, DocumentPath.join(path, key), "\(key) '\(s)' is not one of \(allowed.joined(separator: ", "))")
            return nil
        }
        return s
    }

    func plainNumber(_ o: JSONObject, _ key: String, _ path: String, min: Double? = nil) {
        guard let v = o[key] else { return }
        guard case let .number(n) = v else {
            error(.schema, DocumentPath.join(path, key), "\(key) is \(v.typeName), not a number")
            return
        }
        if let min, n < min { error(.schema, DocumentPath.join(path, key), "\(key) is \(Canonical.number(n)), less than \(Canonical.number(min))") }
    }

    /// A reference by name, checked later against `names`.
    func nameRef(_ o: JSONObject, _ key: String, _ path: String, in names: Set<String>, what: String) {
        guard let s = string(o, key, path) else { return }
        if !names.contains(s) { error(.ref, DocumentPath.join(path, key), "there is no \(what) '\(s)'") }
    }

    /// A wording entry named at `path`, said or shown in `part`.
    func entry(_ o: JSONObject, _ key: String, _ path: String, part: WordingCoverage.Part, locals: Set<String> = [], element: String? = nil) {
        guard let s = string(o, key, path) else { return }
        let p = DocumentPath.join(path, key)
        guard DocumentNames.isEntryName(s) else {
            error(.schema, p, "'\(s)' is not a valid entry name")
            return
        }
        entryUses.append(EntryUse(name: s, path: p, locals: locals, part: part, element: element))
    }

    func role(_ o: JSONObject, _ key: String, _ path: String) {
        guard let s = string(o, key, path) else { return }
        let p = DocumentPath.join(path, key)
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let base = parts[0]
        guard DocumentNames.isName(base), parts.count == 1 || (parts.count == 2 && ["fill", "ink", "soft"].contains(parts[1])) else {
            error(.schema, p, "'\(s)' is not a role")
            return
        }
        if parts.count == 2 && Self.neutralRoles.contains(base) {
            error(.schema, p, "'\(base)' is a neutral role, which has no \(parts[1])")
            return
        }
        if Self.arithmeticRoles.contains(base) && !roles.contains(base) { used.append(("components.arithmetic", p)) }
        if !roles.contains(base) && !Self.arithmeticRoles.contains(base) { error(.ref, p, "there is no role '\(base)'") }
    }

    func ease(_ o: JSONObject, _ key: String, _ path: String) {
        guard let s = string(o, key, path) else { return }
        if s != "linear" && !easings.contains(s) { error(.ref, DocumentPath.join(path, key), "there is no curve '\(s)' in the style") }
    }

    // MARK: expressions

    /// The expression slot at `path`: a JSON literal of the right type, or a string parsed as an
    /// expression and checked against `scope`.
    func slot(_ value: JSONValue?, _ path: String, _ type: SlotType, _ scope: SlotScope) {
        guard let value else { return }
        let literal: DocumentValue?
        switch (value, type) {
        case let (.number(n), .number), let (.number(n), .value): literal = .number(n)
        case let (.bool(b), .truth), let (.bool(b), .value): literal = .truth(b)
        case let (.string(s), _):
            if s.isEmpty {
                error(.schema, path, "\(last(path)) is an empty string, not an expression")
                return
            }
            literal = nil
        default:
            let want = ["a number or an expression", "true, false or an expression", "a number, a truth value or an expression", "a selection"]
            let k = [SlotType.number, .truth, .value, .selection].firstIndex(of: type)!
            error(.schema, path, "\(last(path)) is \(value.typeName), not \(want[k])")
            return
        }
        if let literal {
            expressions[path] = DocumentExpression(literal: literal)
            return
        }
        guard case let .string(source) = value else { return }
        do {
            let e = try DocumentExpression(source)
            expressions[path] = e
            checkNames(e.root, path, scope)
        } catch {
            self.error(.expr, path, at: error.at, error.message)
        }
    }

    func point(_ value: JSONValue?, _ path: String, _ scope: SlotScope) {
        guard let value else { return }
        guard case let .array(a) = value, a.count == 2 else {
            error(.schema, path, "\(last(path)) is not a point [x, y]")
            return
        }
        for (k, v) in a.enumerated() { slot(v, path + "/\(k)", .number, scope) }
    }

    func rect(_ value: JSONValue?, _ path: String, _ scope: SlotScope) {
        guard let value else { return }
        guard case let .array(a) = value, a.count == 4 else {
            error(.schema, path, "\(last(path)) is not a rectangle [x, y, width, height]")
            return
        }
        for (k, v) in a.enumerated() { slot(v, path + "/\(k)", .number, scope) }
    }

    /// The document's values an expression at `scope` may name, and why another is refused.
    func refusal(_ name: String, _ scope: SlotScope) -> String? {
        if scope.locals.contains(name) { return nil }
        let isParam = params[name] != nil
        let isLet = lets[name] != nil
        let isVar = vars.contains(name)
        let isElement = elements[name] != nil
        let isLayoutAdded = layoutAdded.values.contains { $0.contains(name) } && !isLet
        switch scope.values {
        case .params:
            if isParam { return nil }
            if isLet || isVar || isElement { return "a parameter's bounds may name only other parameters, not '\(name)'" }
        case .paramsAndLets:
            if isParam || isLet { return nil }
            if isVar { return "'\(name)' is a vars value, which this value must not depend on" }
            if isElement { return "'\(name)' is an element, which this value must not name" }
            if isLayoutAdded { return "'\(name)' exists only in a layout's let, and only that layout's let may name it" }
        case let .layout(l):
            if isParam || isLet || layoutAdded[l]?.contains(name) == true { return nil }
            if isVar { return "'\(name)' is a vars value, which a let must not name" }
            if isElement { return "'\(name)' is an element, which a let must not name" }
            if isLayoutAdded { return "'\(name)' exists only in another layout's let" }
        case .all:
            if isParam || isLet || isVar || isElement { return nil }
            if isLayoutAdded { return "'\(name)' exists only in a layout's let, and only that layout's let may name it" }
        }
        if DocumentNames.reserved.contains(name) { return "'\(name)' is not in scope here" }
        return "unknown name '\(name)'" + suggestion(name, scope)
    }

    func suggestion(_ name: String, _ scope: SlotScope) -> String {
        let pool = Array(params.keys) + Array(lets.keys) + Array(vars) + Array(elements.keys) + Array(scope.locals)
        if let near = pool.sorted().first(where: { $0.lowercased() == name.lowercased() || editDistance($0, name) == 1 }) {
            return " (did you mean '\(near)'?)"
        }
        return ""
    }

    func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a)
        let y = Array(b)
        if abs(x.count - y.count) > 1 { return 2 }
        var prev = Array(0...y.count)
        for i in x.indices {
            var row = [i + 1] + Array(repeating: 0, count: y.count)
            for j in y.indices {
                row[j + 1] = min(prev[j + 1] + 1, row[j] + 1, prev[j] + (x[i] == y[j] ? 0 : 1))
            }
            prev = row
        }
        return prev[y.count]
    }

    func checkNames(_ n: ExpressionNode, _ path: String, _ scope: SlotScope) {
        switch n.kind {
        case let .name(name):
            if let why = refusal(name, scope) { error(.expr, path, at: n.at, why) }
        case let .call(f, args):
            guard let arity = ExpressionFunction.arity[f] else {
                error(.expr, path, at: n.at, "unknown function '\(f)'")
                for a in args { checkNames(a, path, scope) }
                return
            }
            if !arity.contains(args.count) {
                let want = arity.upperBound == Int.max ? "\(arity.lowerBound) or more" : "\(arity.lowerBound)"
                error(.expr, path, at: n.at, "\(f)() takes \(want) argument\(arity.lowerBound == 1 && arity.upperBound == 1 ? "" : "s"), not \(args.count)")
            }
            if let cap = ExpressionFunction.capability[f] { used.append((cap, path)) }
            if f == "start" || f == "end" {
                guard let actions = scope.actions else {
                    error(.expr, path, at: n.at, "\(f)() is available only in an action's at, outside an each's then")
                    return
                }
                guard args.count == 1, case let .name(a) = args[0].kind else {
                    if let a = args.first { error(.expr, path, at: a.at, "\(f)() takes an action's name, not an expression") }
                    return
                }
                if !actions.contains(a) { error(.ref, path, at: args[0].at, "there is no action '\(a)' in this step") }
                return
            }
            for a in args { checkNames(a, path, scope) }
        case let .member(base, m):
            checkNames(base, path, scope)
            if case let .name(e) = base.kind, !scope.locals.contains(e), let el = elements[e], case let .string(kind)? = el["kind"] {
                if m == "cross" {
                    if !Self.pieceKinds.contains(kind) { error(.ref, path, at: n.at, "\(e) is not a piece, so it has no cross-out") }
                } else if kind != "text" {
                    error(.ref, path, at: n.at, "\(e) is not a text element, so it has no run '\(m)'")
                } else if !runs(of: e).contains(m) {
                    error(.ref, path, at: n.at, "\(e) has no run '\(m)': its entry has no placeholder {\(m)}")
                }
            }
        default:
            for c in n.children { checkNames(c, path, scope) }
        }
    }

    /// The names `n` refers to as values, for finding cycles.
    func dependencies(_ path: String) -> Set<String> {
        guard let e = expressions[path] else { return [] }
        var out = Set<String>()
        func visit(_ n: ExpressionNode) {
            switch n.kind {
            case let .name(x): out.insert(x)
            case let .call(f, args): if f != "start" && f != "end" { args.forEach(visit) }
            default: n.children.forEach(visit)
            }
        }
        visit(e.root)
        return out
    }

    /// The actions an action's `at` names through `start()` and `end()`.
    func timeDependencies(_ path: String) -> Set<String> {
        guard let e = expressions[path] else { return [] }
        var out = Set<String>()
        e.root.walk { n in
            if case let .call(f, args) = n.kind, f == "start" || f == "end", args.count == 1, case let .name(a) = args[0].kind {
                out.insert(a)
            }
        }
        return out
    }

    /// Reports the first cycle in `graph` (name to the names it depends on), at `path(name)`.
    func reportCycle(_ graph: [String: Set<String>], what: String, path: (String) -> String) {
        var state: [String: Int] = [:]
        var stack: [String] = []
        var reported = false
        func visit(_ v: String) {
            if reported { return }
            state[v] = 1
            stack.append(v)
            for w in (graph[v] ?? []).sorted() where graph[w] != nil {
                if state[w] == 1 {
                    let cycle = stack[stack.firstIndex(of: w)!...] + [w]
                    error(.expr, path(w), "\(what) form a cycle: \(cycle.joined(separator: " → "))")
                    reported = true
                    return
                }
                if state[w] == nil { visit(w) }
                if reported { return }
            }
            stack.removeLast()
            state[v] = 2
        }
        for v in graph.keys.sorted() where state[v] == nil { visit(v) }
    }

    /// The runs of text element `e`: the placeholders of its entry in every locale and section.
    func runs(of e: String) -> Set<String> {
        guard let entry = elements[e]?["text"]?.string else { return [] }
        var out = Set<String>()
        for (_, loc) in root["wording"]?.object?.entries ?? [] {
            for (_, section) in loc.object?.entries ?? [] {
                guard let v = section[entry] else { continue }
                for t in texts(of: v) { out.formUnion(PlaceholderText(t.text).placeholders.map(\.run)) }
            }
        }
        return out
    }

    /// Every text of an entry, with the key it is under: `text`, `spoken`, each form and each case.
    func texts(of entry: JSONValue) -> [(key: String, text: String)] {
        switch entry {
        case let .string(s): return [("", s)]
        case let .object(o):
            var out: [(String, String)] = []
            for k in ["text", "spoken"] { if let s = o[k]?.string { out.append((k, s)) } }
            for (k, v) in o["forms"]?.object?.entries ?? [] { if let s = v.string { out.append(("forms/" + k, s)) } }
            for (k, v) in o["cases"]?.object?.entries ?? [] { if let s = v.string { out.append(("cases/" + DocumentPath.escape(k), s)) } }
            return out
        default: return []
        }
    }

    // MARK: the document

    func check() {
        object(.object(root), "", known: [
            "format", "version", "requires", "id", "title", "about", "sourceLocale", "params", "let", "vars", "samples", "kind",
            "layouts", "elements", "parts", "shots", "opening", "intro", "sequence", "steps", "try", "whatIf", "style", "plays",
            "wording", "extensions",
        ], required: ["format", "version", "id", "title", "sourceLocale", "params", "samples", "elements", "sequence", "steps", "wording"])
        gatherNames()
        checkHeader()
        checkParams()
        checkValues()
        checkLayouts()
        checkElements()
        checkPartsAndShots()
        checkSteps()
        checkInteraction()
        checkStyle()
        checkWording()
        checkCapabilities()
        checkSamples()
    }

    func gatherNames() {
        for (k, v, _) in map(root["params"], "/params") { if let o = v.object { params[k] = o } else { params[k] = JSONObject() } }
        for (k, v, _) in map(root["let"], "/let") { lets[k] = v }
        for (k, _, _) in map(root["vars"], "/vars") { vars.insert(k) }
        for (k, v, p) in map(root["elements"], "/elements") {
            if let o = v.object { elements[k] = o } else { error(.schema, p, "element \(k) is \(v.typeName), not an object") }
        }
        if let layouts = root["layouts"]?.object {
            for (name, l) in layouts.entries {
                let added = Set((l["let"]?.object?.keys ?? []).filter { lets[$0] == nil })
                layoutAdded[name] = added
            }
        }
        parts = Set(root["parts"]?.object?.keys ?? [])
        shots = Set(root["shots"]?.object?.keys ?? [])
        for (k, v) in root["steps"]?.object?.entries ?? [] { steps[k] = v.object ?? JSONObject() }
        roles = Self.neutralRoles.union(Self.coreOperationRoles)
        if capabilities.contains("components.arithmetic") || (root["requires"]?.array ?? []).contains(.string("components.arithmetic")) {
            roles.formUnion(Self.arithmeticRoles)
        }
        for mode in ["light", "dark"] {
            for (k, v) in root["style"]?["palette"]?[mode]?.object?.entries ?? [] where v.object != nil { roles.insert(k) }
        }
        easings = Set(ExplainerStyle.standard.easings.keys).union(root["style"]?["easings"]?.object?.keys ?? [])
        for (_, loc) in root["wording"]?.object?.entries ?? [] {
            for k in loc.object?.keys ?? [] where k != "shared" { wordingNames.insert(k) }
        }

        // The first namespace: parameters, let, vars and elements are distinct, and none is reserved.
        var seen: [String: String] = [:]
        let groups: [(String, [String])] = [
            ("params", root["params"]?.object?.keys ?? []), ("let", root["let"]?.object?.keys ?? []),
            ("vars", root["vars"]?.object?.keys ?? []), ("elements", root["elements"]?.object?.keys ?? []),
        ]
        for (group, names) in groups {
            for n in names {
                let p = DocumentPath.join("/" + group, n)
                if DocumentNames.reserved.contains(n) { error(.schema, p, "'\(n)' is reserved and cannot name a value or an element") }
                if let other = seen[n] { error(.schema, p, "'\(n)' is already a name in \(other); parameters, let, vars and elements share one namespace") }
                seen[n] = group
            }
        }
        for (layout, added) in layoutAdded {
            for n in added.sorted() {
                let p = DocumentPath.join("/layouts", layout, "let", n)
                if DocumentNames.reserved.contains(n) { error(.schema, p, "'\(n)' is reserved and cannot name a value") }
                if let other = seen[n] { error(.schema, p, "'\(n)' is already a name in \(other)") }
            }
        }
    }

    func checkHeader() {
        if let reqs = root["requires"] {
            if case let .array(a) = reqs {
                var seen = Set<String>()
                for (k, v) in a.enumerated() {
                    let p = "/requires/\(k)"
                    guard case let .string(s) = v else {
                        error(.schema, p, "a capability is \(v.typeName), not a string")
                        continue
                    }
                    if !DocumentNames.isCapability(s) { error(.schema, p, "'\(s)' is not a capability name") }
                    if !seen.insert(s).inserted { error(.schema, p, "'\(s)' is listed twice") }
                    if !capabilities.contains(s) { error(.capability, p, "the capability '\(s)' is not implemented") }
                }
            } else {
                error(.schema, "/requires", "requires is \(reqs.typeName), not an array")
            }
        }
        if let id = string(root, "id", ""), !DocumentNames.isID(id) { error(.schema, "/id", "id '\(id)' does not match ^[a-z][a-z0-9-]{0,63}$") }
        if let t = string(root, "title", ""), t.isEmpty { error(.schema, "/title", "title is empty") }
        if let a = root["about"], a.object == nil { error(.schema, "/about", "about is \(a.typeName), not an object") }
        if let l = string(root, "sourceLocale", "") {
            if !DocumentNames.isLocale(l) { error(.schema, "/sourceLocale", "'\(l)' is not a BCP 47 language tag") }
            if root["wording"]?[l] == nil, root["wording"]?.object != nil { error(.ref, "/sourceLocale", "wording has no locale '\(l)'") }
        }
        _ = map(root["extensions"], "/extensions", keys: DocumentNames.isExtensionKey, what: "extension key (vendor.feature)")
    }

    func checkParams() {
        var graph: [String: Set<String>] = [:]
        for (name, v, p) in map(root["params"], "/params") {
            guard let o = v.object else {
                error(.schema, p, "parameter \(name) is \(v.typeName), not an object")
                continue
            }
            let type = o["type"]?.string
            switch type {
            case "int", "number":
                object(v, p, known: ["type", "min", "max"], required: ["min", "max"])
                slot(o["min"], p + "/min", .number, SlotScope(values: .params))
                slot(o["max"], p + "/max", .number, SlotScope(values: .params))
                graph[name] = dependencies(p + "/min").union(dependencies(p + "/max"))
            case "bool":
                object(v, p, known: ["type"])
            case "choice":
                object(v, p, known: ["type", "values"], required: ["values"])
                if let vals = o["values"] {
                    if case let .array(a) = vals, !a.isEmpty {
                        for (k, x) in a.enumerated() {
                            switch x {
                            case .string, .number: if a[..<k].contains(x) { error(.schema, p + "/values/\(k)", "a choice's values are distinct") }
                            default: error(.schema, p + "/values/\(k)", "a choice's value is \(x.typeName), not a string or a number")
                            }
                        }
                    } else {
                        error(.schema, p + "/values", "values is not a non-empty array")
                    }
                }
            case nil:
                object(v, p, known: ["type", "min", "max", "values"], required: ["type"])
            default:
                error(.schema, p + "/type", "type '\(type!)' is not int, number, bool or choice")
            }
        }
        reportCycle(graph, what: "the parameters' bounds") { "/params/\($0)" }
    }

    func checkValues() {
        var graph: [String: Set<String>] = [:]
        for (name, v, p) in map(root["let"], "/let") {
            slot(v, p, .value, SlotScope(values: .paramsAndLets))
            graph[name] = dependencies(p)
        }
        reportCycle(graph, what: "the let values") { "/let/\($0)" }
        for (_, v, p) in map(root["vars"], "/vars") { slot(v, p, .value, SlotScope(values: .paramsAndLets)) }
        if let kind = object(root["kind"], "/kind", known: ["search", "same", "differ", "near"]) {
            for (name, v, p) in map(kind["search"], "/kind/search") {
                if params[name] == nil { error(.ref, p, "there is no parameter '\(name)'") }
                guard case let .array(a) = v, a.count == 2 else {
                    error(.schema, p, "a search range is not [min, max]")
                    continue
                }
                slot(a[0], p + "/0", .number, SlotScope(values: .params))
                slot(a[1], p + "/1", .number, SlotScope(values: .params))
            }
            for key in ["same", "differ"] {
                guard let list = kind[key] else { continue }
                guard case let .array(a) = list else {
                    error(.schema, "/kind/" + key, "\(key) is not an array")
                    continue
                }
                for (k, x) in a.enumerated() { slot(x, "/kind/\(key)/\(k)", key == "same" ? .truth : .value, SlotScope(values: .paramsAndLets)) }
            }
            for (name, v, p) in map(kind["near"], "/kind/near") {
                if params[name] == nil && lets[name] == nil { error(.ref, p, "there is no parameter or let '\(name)'") }
                if case let .number(n) = v, n >= 0 { continue }
                error(.schema, p, "a near distance is not a number of at least 0")
            }
            let types = params.values.compactMap { $0["type"]?.string }
            if types.contains("number") { error(.schema, "/kind", "kind may be used only when every parameter is int, bool or choice") }
        }
    }

    func checkLayouts() {
        for (name, v, p) in map(root["layouts"], "/layouts") {
            let required = name == "stage" ? [] : ["suits", "size"]
            guard let o = object(v, p, known: ["size", "suits", "camera", "band", "let"], required: required) else { continue }
            if name == "stage", o["suits"] != nil { warning(.unknown, p + "/suits", "the stage is the default layout and has no suits") }
            let area = SlotScope(values: .all, locals: ["areaW", "areaH"])
            slot(o["suits"], p + "/suits", .truth, area)
            point(o["size"], p + "/size", area)
            bool(o, "camera", p)
            slot(o["band"], p + "/band", .number, SlotScope(values: .paramsAndLets))
            var graph: [String: Set<String>] = [:]
            for (k, _) in lets { graph[k] = dependencies("/let/" + k) }
            for (k, x, lp) in map(o["let"], p + "/let") {
                slot(x, lp, .value, SlotScope(values: .layout(name)))
                graph[k] = dependencies(lp)
            }
            reportCycle(graph, what: "layout \(name)'s let values") { k in
                o["let"]?[k] != nil ? DocumentPath.join(p, "let", k) : "/let/" + k
            }
        }
    }

    func checkElements() {
        for (name, el) in elements.sorted(by: { $0.key < $1.key }) {
            let p = DocumentPath.join("/elements", name)
            guard let kind = string(el, "kind", p) else {
                if el["kind"] == nil { error(.schema, p, "element \(name) has no 'kind', which it requires") }
                continue
            }
            let common = ["kind", "repeat", "when", "z", "fixed", "start"]
            let byKind: [String: (known: [String], required: [String])] = [
                "text": (["at", "text", "runs", "style", "ink", "size", "anchor"], ["at"]),
                "line": (["from", "to", "style", "ink"], ["from", "to"]),
                "arrow": (["from", "to", "y", "ink"], ["from", "to", "ink"]),
                "outline": (["rect", "around", "pad", "style", "ink"], ["style"]),
                "shape": (["rect", "corner", "ellipse", "points", "closed", "fill", "ink"], []),
                "ten": (["rect", "look"], ["rect"]), "one": (["rect", "look"], ["rect"]),
                "stick": (["rect", "look"], ["rect"]), "circle": (["rect", "look"], ["rect"]),
            ]
            guard let spec = byKind[kind] else {
                error(.schema, p + "/kind", "'\(kind)' is not an element kind")
                continue
            }
            if Self.pieceKinds.contains(kind) { used.append(("components.arithmetic", p + "/kind")) }
            object(.object(el), p, known: common + spec.known, required: spec.required)
            let fixedScope = SlotScope(values: .paramsAndLets)
            let scope = SlotScope(values: .all, locals: el["repeat"] != nil ? ["i"] : [])
            slot(el["repeat"], p + "/repeat", .number, fixedScope)
            slot(el["when"], p + "/when", .truth, fixedScope)
            slot(el["z"], p + "/z", .number, scope)
            bool(el, "fixed", p)
            if let start = object(el["start"], p + "/start", known: ["opacity", "progress"]) {
                slot(start["opacity"], p + "/start/opacity", .number, scope)
                slot(start["progress"], p + "/start/progress", .number, scope)
            }
            switch kind {
            case "text":
                point(el["at"], p + "/at", scope)
                entry(el, "text", p, part: .watch, locals: scope.locals, element: name)
                for (run, v, rp) in map(el["runs"], p + "/runs") {
                    guard let r = object(v, rp, known: ["ink", "text"]) else { continue }
                    role(r, "ink", rp)
                    entry(r, "text", rp, part: .watch, locals: scope.locals)
                    if !runs(of: name).contains(run) { error(.ref, rp, "\(name)'s entry has no placeholder {\(run)}") }
                }
                _ = oneOf(el, "style", p, ["equation", "total", "label", "note", "body"])
                role(el, "ink", p)
                slot(el["size"], p + "/size", .number, scope)
                _ = oneOf(el, "anchor", p, ["start", "middle", "end"])
            case "line":
                point(el["from"], p + "/from", scope)
                point(el["to"], p + "/to", scope)
                _ = oneOf(el, "style", p, ["rule", "divider"])
                role(el, "ink", p)
            case "arrow":
                for key in ["from", "to"] {
                    if case .string = el[key] { slot(el[key], p + "/" + key, .selection, scope) } else { point(el[key], p + "/" + key, scope) }
                }
                slot(el["y"], p + "/y", .number, scope)
                role(el, "ink", p)
            case "outline":
                if el["rect"] == nil && el["around"] == nil { error(.schema, p, "an outline has rect or around") }
                if el["rect"] != nil && el["around"] != nil { error(.schema, p, "an outline has rect or around, not both") }
                rect(el["rect"], p + "/rect", scope)
                slot(el["around"], p + "/around", .selection, scope)
                slot(el["pad"], p + "/pad", .number, scope)
                let style = oneOf(el, "style", p, ["box", "ring", "hint", "target"])
                role(el, "ink", p)
                if (style == "box" || style == "ring") && el["ink"] == nil { error(.schema, p, "a \(style!) outline has no 'ink', which it requires") }
            case "shape":
                let geometry = ["rect", "ellipse", "points"].filter { el[$0] != nil }
                if geometry.count != 1 { error(.schema, p, "a shape has exactly one of rect, ellipse and points") }
                rect(el["rect"], p + "/rect", scope)
                rect(el["ellipse"], p + "/ellipse", scope)
                slot(el["corner"], p + "/corner", .number, scope)
                if let pts = el["points"] {
                    if case let .array(a) = pts {
                        for (k, x) in a.enumerated() { point(x, p + "/points/\(k)", scope) }
                    } else {
                        error(.schema, p + "/points", "points is not an array of points")
                    }
                }
                bool(el, "closed", p)
                role(el, "fill", p)
                role(el, "ink", p)
                if el["fill"] == nil && el["ink"] == nil { error(.schema, p, "a shape has at least one of fill and ink") }
            default:
                rect(el["rect"], p + "/rect", scope)
                _ = oneOf(el, "look", p, ["pencil", "traded", "counted"])
            }
        }
    }

    func checkPartsAndShots() {
        for (_, v, p) in map(root["parts"], "/parts") { slot(v, p, .selection, SlotScope(values: .all)) }
        for (_, v, p) in map(root["shots"], "/shots") {
            guard let o = object(v, p, known: ["frame", "region", "margin"]) else { continue }
            if let f = o["frame"] {
                if case let .array(a) = f {
                    for (k, x) in a.enumerated() {
                        if case let .string(s) = x {
                            if !parts.contains(s) { error(.ref, p + "/frame/\(k)", "there is no part '\(s)'") }
                        } else {
                            error(.schema, p + "/frame/\(k)", "a part name is \(x.typeName), not a string")
                        }
                    }
                } else {
                    error(.schema, p + "/frame", "frame is not an array of part names")
                }
            }
            rect(o["region"], p + "/region", SlotScope(values: .all))
            slot(o["margin"], p + "/margin", .number, SlotScope(values: .all))
        }
        nameRef(root, "opening", "", in: shots, what: "shot")
    }

    /// The step `name` with `like` applied (section 11): every key of the named step except
    /// `when`, replaced by the step's own.
    func effectiveStep(_ name: String) -> JSONObject {
        guard let s = steps[name] else { return JSONObject() }
        guard let like = s["like"]?.string, let base = steps[like] else { return s }
        var out = base
        out["when"] = nil
        out["like"] = nil
        for (k, v) in s.entries { out[k] = v }
        return out
    }

    func checkSteps() {
        let seq = root["sequence"]
        var inSequence = Set<String>()
        if let seq {
            if case let .array(a) = seq, !a.isEmpty {
                for (k, x) in a.enumerated() {
                    let p = "/sequence/\(k)"
                    guard case let .string(s) = x else {
                        error(.schema, p, "a step name is \(x.typeName), not a string")
                        continue
                    }
                    if !inSequence.insert(s).inserted { error(.schema, p, "step '\(s)' is in the sequence twice") }
                    if steps[s] == nil { error(.ref, p, "there is no step '\(s)'") }
                }
            } else {
                error(.schema, "/sequence", "sequence is not a non-empty array of step names")
            }
        }
        if let st = root["steps"], st.object == nil { error(.schema, "/steps", "steps is \(st.typeName), not an object") }
        for (name, v, p) in map(root["steps"], "/steps") {
            if seq != nil && !inSequence.contains(name) { error(.ref, p, "step '\(name)' is not in the sequence") }
            guard let s = object(v, p, known: ["when", "shot", "doShot", "say", "actions", "duration", "hold", "counts", "like", "act", "why"])
            else { continue }
            if let like = string(s, "like", p) {
                if steps[like] == nil {
                    error(.ref, p + "/like", "there is no step '\(like)'")
                } else if steps[like]?["like"] != nil {
                    error(.schema, p + "/like", "step '\(like)' itself has like")
                }
            }
            let eff = effectiveStep(name)
            let actionNames = Set(eff["actions"]?.object?.keys ?? [])
            let scope = SlotScope(values: .all)
            slot(s["when"], p + "/when", .truth, scope)
            nameRef(s, "shot", p, in: shots, what: "shot")
            nameRef(s, "doShot", p, in: shots, what: "shot")
            if eff["say"] == nil { error(.schema, p, "step \(name) has no 'say', here or through like") }
            entry(s, "say", p, part: .watch)
            slot(s["duration"], p + "/duration", .number, scope)
            slot(s["hold"], p + "/hold", .number, scope)
            bool(s, "counts", p)
            actions(s["actions"], p + "/actions", names: actionNames, part: .watch)
            if let why = object(s["why"], p + "/why", known: ["say", "actions", "hold"], required: ["say"]) {
                entry(why, "say", p + "/why", part: .guided)
                actions(why["actions"], p + "/why/actions", names: Set(why["actions"]?.object?.keys ?? []), part: .guided)
                slot(why["hold"], p + "/why/hold", .number, scope)
            }
        }
    }

    /// A step's actions. `names` are the actions of the step as played (after `like`).
    func actions(_ value: JSONValue?, _ path: String, names: Set<String>, part: WordingCoverage.Part) {
        var graph: [String: Set<String>] = [:]
        for (name, v, p) in map(value, path) {
            action(v, p, scope: SlotScope(values: .all, actions: names), inner: false, part: part)
            graph[name] = timeDependencies(p + "/at")
        }
        reportCycle(graph, what: "the actions' start() and end()") { DocumentPath.join(path, $0, "at") }
    }

    /// One action. `inner` is true for an action in an `each`'s `then` or an `act`'s `then`.
    func action(_ value: JSONValue, _ p: String, scope: SlotScope, inner: Bool, part: WordingCoverage.Part, hasTarget: Bool = false) {
        guard let o = value.object else {
            error(.schema, p, "\(last(p)) is \(value.typeName), not an action")
            return
        }
        guard let verb = o["do"]?.string else {
            if o["do"] == nil { error(.schema, p, "\(last(p)) has no 'do', which it requires") } else { _ = string(o, "do", p) }
            return
        }
        guard Self.verbs.contains(verb) else {
            error(.schema, p + "/do", "'\(verb)' is not a verb")
            return
        }
        if inner && verb == "each" {
            error(.schema, p + "/do", "an each's then must not hold an each")
            return
        }
        let timing = ["dur", "each", "reverse", "ease"]
        var known = ["do", "target", "at", "when", "mark"] + (inner ? [] : ["wait"])
        let params: [String: [String]] = [
            "appear": ["rise", "grow", "place", "text"], "fade": ["to"], "draw": [], "cross": ["fade"], "tint": ["ink"],
            "move": ["to", "via"], "gather": ["from"], "look": ["value"], "set": ["text"], "tag": ["text"], "pulse": [],
            "say": ["line", "count", "caption"], "each": ["gap", "let", "then"],
        ]
        known += params[verb]!
        if !Self.instantVerbs.contains(verb) && verb != "each" { known += timing }
        if verb == "say" { known.removeAll { $0 == "target" } }
        let required: [String: [String]] = [
            "fade": ["to"], "tint": ["ink"], "gather": ["from"], "look": ["value"], "set": ["text"], "tag": ["text"],
            "say": ["line"], "each": ["target", "gap", "then"],
        ]
        object(value, p, known: known, required: required[verb] ?? [])
        let atScope = inner ? SlotScope(values: .all, locals: scope.locals) : scope
        var plain = scope
        plain.actions = nil
        var perInstance = plain
        perInstance.locals.insert("i")
        slot(o["target"], p + "/target", .selection, plain)
        slot(o["at"], p + "/at", .number, atScope)
        slot(o["when"], p + "/when", .truth, plain)
        slot(o["dur"], p + "/dur", .number, plain)
        slot(o["each"], p + "/each", .number, plain)
        bool(o, "reverse", p)
        bool(o, "mark", p)
        ease(o, "ease", p)
        if !inner, let w = o["wait"], w != .string("voice") { error(.schema, p + "/wait", "wait is \"voice\" or absent") }
        switch verb {
        case "appear":
            slot(o["rise"], p + "/rise", .number, perInstance)
            slot(o["grow"], p + "/grow", .number, perInstance)
            slot(o["place"], p + "/place", .value, plain)
            entry(o, "text", p, part: part, locals: plain.locals)
        case "fade":
            if o["to"] != .string("ghost") { slot(o["to"], p + "/to", .number, perInstance) }
        case "cross":
            slot(o["fade"], p + "/fade", .number, plain)
        case "tint":
            role(o, "ink", p)
        case "move":
            point(o["to"], p + "/to", perInstance)
            if let via = o["via"] {
                guard case let .array(frames) = via, !frames.isEmpty else {
                    error(.schema, p + "/via", "via is not a non-empty array of [offset, x, y]")
                    break
                }
                var last = 0.0
                var keyScope = perInstance
                keyScope.locals.formUnion(["x0", "y0"])
                for (k, f) in frames.enumerated() {
                    let fp = p + "/via/\(k)"
                    guard case let .array(a) = f, a.count == 3, case let .number(off) = a[0] else {
                        error(.schema, fp, "a keyframe is not [offset, x, y] with a number offset")
                        continue
                    }
                    if !(off > last && off < 1) { error(.schema, fp + "/0", "keyframe offsets are strictly between 0 and 1, in increasing order") }
                    last = off
                    slot(a[1], fp + "/1", .number, keyScope)
                    slot(a[2], fp + "/2", .number, keyScope)
                }
            }
        case "gather":
            slot(o["from"], p + "/from", .selection, plain)
        case "look":
            _ = oneOf(o, "value", p, ["pencil", "traded", "counted"])
        case "set", "tag":
            entry(o, "text", p, part: part, locals: plain.locals)
        case "say":
            entry(o, "line", p, part: part, locals: plain.locals)
            bool(o, "count", p)
            bool(o, "caption", p)
        case "each":
            var local = plain
            local.locals.insert("i")
            slot(o["gap"], p + "/gap", .number, local)
            var graph: [String: Set<String>] = [:]
            let letNames = Set(o["let"]?.object?.keys ?? [])
            for (name, x, lp) in map(o["let"], p + "/let") {
                if DocumentNames.reserved.contains(name) && name != "n" { error(.schema, lp, "'\(name)' is reserved and cannot name a local") }
                if params[name] != nil || lets[name] != nil || vars.contains(name) || elements[name] != nil {
                    error(.schema, lp, "'\(name)' is already a name of the document")
                }
                var ls = local
                ls.locals.formUnion(letNames)
                slot(x, lp, .value, ls)
                graph[name] = dependencies(lp).intersection(letNames)
            }
            reportCycle(graph, what: "the each's let values") { DocumentPath.join(p, "let", $0) }
            local.locals.formUnion(letNames)
            for (_, x, tp) in map(o["then"], p + "/then") {
                action(x, tp, scope: local, inner: true, part: part)
            }
        default:
            break
        }
    }

    func checkInteraction() {
        for (name, s) in steps.sorted(by: { $0.key < $1.key }) {
            let p = DocumentPath.join("/steps", name)
            guard let actObject = s["act"] else { continue }
            guard let act = object(actObject, p + "/act", known: [
                "input", "say", "targets", "need", "many", "order", "bind", "keep", "ink", "tally", "pad", "begin", "then", "done",
                "interrupts", "misses",
            ], required: ["input", "targets"]) else { continue }
            let ap = p + "/act"
            let eff = effectiveStep(name)
            let actionNames = Set(eff["actions"]?.object?.keys ?? [])
            let scope = SlotScope(values: .all)
            _ = oneOf(act, "input", ap, ["stroke", "tap"])
            entry(act, "say", ap, part: .guided)
            slot(act["targets"], ap + "/targets", .selection, scope)
            slot(act["need"], ap + "/need", .number, scope)
            for k in ["many", "keep", "interrupts"] { bool(act, k, ap) }
            if let order = act["order"] {
                if case let .array(a) = order, !a.isEmpty {
                    for (k, x) in a.enumerated() { slot(x, ap + "/order/\(k)", .selection, scope) }
                } else {
                    error(.schema, ap + "/order", "order is not a non-empty array of selections")
                }
            }
            nameRef(act, "bind", ap, in: vars, what: "vars value")
            role(act, "ink", ap)
            role(act, "tally", ap)
            slot(act["pad"], ap + "/pad", .number, scope)
            nameRef(act, "begin", ap, in: actionNames, what: "action in this step")
            if let then = act["then"] {
                switch then {
                case let .string(t):
                    if t != "watch" && !actionNames.contains(t) { error(.ref, ap + "/then", "there is no action '\(t)' in this step") }
                case .object:
                    action(then, ap + "/then", scope: SlotScope(values: .all), inner: true, part: .guided)
                default:
                    error(.schema, ap + "/then", "then is \(then.typeName), not \"watch\", an action's name or an action")
                }
            }
            if let done = act["done"] {
                switch done {
                case .string: entry(act, "done", ap, part: .guided)
                case let .array(a) where !a.isEmpty:
                    for (k, x) in a.enumerated() {
                        if case let .string(n) = x {
                            if !actionNames.contains(n) { error(.ref, ap + "/done/\(k)", "there is no action '\(n)' in this step") }
                        } else {
                            error(.schema, ap + "/done/\(k)", "an action's name is \(x.typeName), not a string")
                        }
                    }
                default:
                    error(.schema, ap + "/done", "done is an entry's name or a non-empty array of action names")
                }
            }
            let missKinds: Set<String> = ["tap", "stroke", "nothing", "tooMany", "order"]
            for (key, x, mp) in map(act["misses"], ap + "/misses", keys: { !$0.isEmpty }, what: "miss") {
                if !missKinds.contains(key) {
                    // Any other key is a selection.
                    do {
                        let e = try DocumentExpression(key)
                        expressions[mp] = e
                        checkNames(e.root, mp, scope)
                    } catch {
                        self.error(.expr, mp, at: error.at, error.message)
                    }
                }
                guard case let .string(line) = x else {
                    error(.schema, mp, "a miss's line is \(x.typeName), not an entry's name")
                    continue
                }
                entryUses.append(EntryUse(name: line, path: mp, locals: key == "tooMany" ? ["left"] : [], part: .guided))
            }
        }
        if let t = object(root["try"], "/try", known: ["question", "say", "note"], required: ["question", "say"]) {
            entry(t, "question", "/try", part: .tryOne)
            entry(t, "say", "/try", part: .tryOne)
            entry(t, "note", "/try", part: .tryOne)
        }
        if let i = object(root["intro"], "/intro", known: ["watch", "guided"], required: ["watch"]) {
            entry(i, "watch", "/intro", part: .watch)
            entry(i, "guided", "/intro", part: .guided)
        }
        if let w = object(root["whatIf"], "/whatIf", known: ["say", "handle", "bind", "range", "axis", "per", "snap", "goals", "done"],
                          required: ["say", "handle", "bind", "range", "axis", "per", "goals"]) {
            let scope = SlotScope(values: .all)
            entry(w, "say", "/whatIf", part: .whatIf)
            slot(w["handle"], "/whatIf/handle", .selection, scope)
            nameRef(w, "bind", "/whatIf", in: vars, what: "vars value")
            if let r = w["range"] {
                if case let .array(a) = r, a.count == 2 {
                    slot(a[0], "/whatIf/range/0", .number, scope)
                    slot(a[1], "/whatIf/range/1", .number, scope)
                } else {
                    error(.schema, "/whatIf/range", "range is not [min, max]")
                }
            }
            _ = oneOf(w, "axis", "/whatIf", ["x", "y"])
            slot(w["per"], "/whatIf/per", .number, scope)
            slot(w["snap"], "/whatIf/snap", .number, scope)
            if let goals = w["goals"] {
                if case let .array(a) = goals, !a.isEmpty {
                    for (k, g) in a.enumerated() {
                        let gp = "/whatIf/goals/\(k)"
                        guard let go = object(g, gp, known: ["when", "say", "show"], required: ["when", "say", "show"]) else { continue }
                        slot(go["when"], gp + "/when", .truth, scope)
                        entry(go, "say", gp, part: .whatIf)
                        slot(go["show"], gp + "/show", .value, scope)
                    }
                } else {
                    error(.schema, "/whatIf/goals", "goals is not a non-empty array")
                }
            }
            entry(w, "done", "/whatIf", part: .whatIf)
        }
        if let plays = object(root["plays"], "/plays", known: ["paced", "skippable"]) {
            nameRef(plays, "paced", "/plays", in: wordingNames, what: "wording")
            nameRef(plays, "skippable", "/plays", in: wordingNames, what: "wording")
        }
    }

    func checkStyle() {
        guard let style = object(root["style"], "/style", known: ["palette", "easings", "motion"]) else { return }
        if let palette = object(style["palette"], "/style/palette", known: ["light", "dark"]) {
            for mode in ["light", "dark"] {
                for (role, v, p) in map(palette[mode], "/style/palette/" + mode) {
                    switch v {
                    case let .string(c):
                        if !Self.isColour(c) { error(.schema, p, "'\(c)' is not a colour #RRGGBB") }
                        if !Self.neutralRoles.contains(role) { error(.schema, p, "'\(role)' is not a neutral role; an operation role has fill, ink and soft") }
                    case let .object(o):
                        object(v, p, known: ["fill", "ink", "soft"], required: ["fill", "ink", "soft"])
                        for k in ["fill", "ink", "soft"] {
                            if let c = o[k]?.string, !Self.isColour(c) { error(.schema, p + "/" + k, "'\(c)' is not a colour #RRGGBB") }
                        }
                        let other = mode == "light" ? "dark" : "light"
                        let defined = Self.coreOperationRoles.union(Self.arithmeticRoles).contains(role)
                        if !defined && palette[other]?[role]?.object == nil {
                            error(.schema, p, "a new operation role is given in both palette.light and palette.dark")
                        }
                    default:
                        error(.schema, p, "a role's colour is \(v.typeName), not #RRGGBB or {fill, ink, soft}")
                    }
                }
            }
        }
        for (name, v, p) in map(style["easings"], "/style/easings") {
            if name == "linear" { error(.schema, p, "linear cannot be redefined") }
            guard case let .array(a) = v, a.count == 4, a.allSatisfy({ if case .number = $0 { true } else { false } }) else {
                error(.schema, p, "a curve is [x1, y1, x2, y2] of numbers")
                continue
            }
            for k in [0, 2] {
                if case let .number(x) = a[k], !(0...1).contains(x) { error(.schema, p + "/\(k)", "a curve's x is from 0 to 1") }
            }
        }
        if let motion = object(style["motion"], "/style/motion", known: ["durations", "easings", "camera"]) {
            if let d = object(motion["durations"], "/style/motion/durations", known: ["appear", "draw", "fade", "travel", "lag", "hold"]) {
                for k in d.keys { plainNumber(d, k, "/style/motion/durations", min: 0) }
            }
            if let e = object(motion["easings"], "/style/motion/easings", known: ["appear", "draw", "fade", "travel"]) {
                for k in e.keys { ease(e, k, "/style/motion/easings") }
            }
            if let c = object(motion["camera"], "/style/motion/camera", known: ["at", "duration", "easing", "margin", "dim"]) {
                for k in ["at", "duration", "margin", "dim"] { plainNumber(c, k, "/style/motion/camera", min: 0) }
                ease(c, "easing", "/style/motion/camera")
            }
        }
    }

    static func isColour(_ s: String) -> Bool {
        let u = Array(s.unicodeScalars)
        return u.count == 7 && u[0] == "#" && u.dropFirst().allSatisfy { $0.properties.isASCIIHexDigit }
    }

    func checkCapabilities() {
        let declared = Set(root["requires"]?.array?.compactMap(\.string) ?? [])
        var reported = Set<String>()
        for (cap, path) in used where !declared.contains(cap) && !reported.contains(cap) {
            reported.insert(cap)
            error(.capability, path, "this uses the capability '\(cap)', which requires does not list")
        }
    }

    func checkSamples() {
        guard let samples = root["samples"] else { return }
        guard case let .array(a) = samples, !a.isEmpty else {
            error(.schema, "/samples", "samples is not a non-empty array of problems")
            return
        }
        for (k, s) in a.enumerated() {
            let p = "/samples/\(k)"
            if a[..<k].contains(s) { error(.schema, p, "this sample is given twice") }
            guard let o = s.object else {
                error(.schema, p, "a sample is \(s.typeName), not an object")
                continue
            }
            var values: [String: DocumentValue] = [:]
            for (key, v) in o.entries {
                guard let value = DocumentValue(json: v) else {
                    error(.schema, DocumentPath.join(p, key), "a problem's value is \(v.typeName), not a number, truth value or string")
                    continue
                }
                values[key] = value
            }
            guard expressions.keys.contains(where: { $0.hasPrefix("/params/") }) || params.values.allSatisfy({ $0["min"] == nil }) else { continue }
            if findings.contains(where: { $0.severity == .error && $0.path.hasPrefix("/params") }) { continue }
            for f in ProblemCheck.check(values, params: root["params"]?.object ?? JSONObject(), expressions: expressions) {
                findings.append(DocumentFinding(.error, .range, f.path.isEmpty ? p : DocumentPath.join(p, f.path), values: values, f.message))
            }
        }
    }
}
