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
        var doc = ExplainerDocument(json: json, findings: checker.findings, coverage: checker.coverage, expressions: checker.expressions)
        // The declaration is compared with the layouts only in a document that has no error,
        // since the layouts' `suits` are evaluated.
        if root["areas"] != nil, !checker.findings.hasErrors {
            checker.findings += doc.areaFindings()
            doc = ExplainerDocument(json: json, findings: checker.findings, coverage: checker.coverage, expressions: checker.expressions)
        }
        return DocumentReading(document: doc, findings: checker.findings)
    }

    public static func read(contentsOf url: URL, capabilities: Set<String> = ExplainerDocument.capabilities) -> DocumentReading {
        guard let data = try? Data(contentsOf: url) else {
            return DocumentReading(document: nil, findings: [.error(.json, "", "the file \(url.lastPathComponent) cannot be read")])
        }
        return read(data, capabilities: capabilities)
    }
}

/// What the player says when it refuses a document for what it does not draw (section 2.3). The
/// reader finds these from the document alone, and the film's construction says them again for what
/// only a problem's values show, so both use these words.
enum PlayerRefusal {
    static func inkRole(_ role: String) -> String { "this player does not draw the role '\(role)' yet" }
    static func hue(_ kind: String, _ role: String) -> String {
        let article = "aeiou".contains(kind.first ?? "x") ? "an" : "a"
        return "this player draws \(article) \(kind) only in an operation role or a colour of the document's named alone, not '\(role)'"
    }
    static let equation = "this player draws an equation centred and in the text role only"
    static let total = "this player draws a total centred and in the result role only"
    static let runInk = "this player draws a run's own role only in an equation, and only the result role or a colour of the document's"
    static func outlineInk(_ style: String) -> String { "this player draws a \(style) outline only in its own role" }
    static let tintNeedsRun = "this player tints only a run of a text element, not "
    static let tintHue = "this player tints only in an operation role or a colour of the document's named alone"
    static let tintEquation = "this player tints a run only in an equation"
    static let tagHue = "this player draws a tag only in an operation role or a colour of the document's named alone"
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
    /// The profile the document is made for, when the reader has it.
    var profile: ExplainerStyle?
    /// The appearances the document is made for (EXP-20); both when it declares none or declares
    /// them wrongly, which is an error.
    var madeFor: Set<Appearance> = Appearance.both
    /// The document's own colours that could be read, by name.
    var ownColours: [String: DocumentColour] = [:]
    /// The operations whose colour the document changes (EXP-6) that could be read, by role.
    var overridden: [String: DocumentColour] = [:]

    static let neutralRoles: Set<String> = ["paper", "sheet", "text", "muted", "line", "pencil", "onResult"]
    static let coreOperationRoles: Set<String> = ["result"]
    static let arithmeticRoles: Set<String> = ["subtract", "trade", "add", "multiply", "divide"]
    /// Every role the style gives, which a colour of the document's own may not be named.
    static let styleRoles: Set<String> = neutralRoles.union(coreOperationRoles).union(arithmeticRoles)
    static let pieceKinds: Set<String> = ["ten", "one", "stick", "circle"]
    static let coreKinds: Set<String> = ["text", "line", "arrow", "outline", "shape", "group"]
    static let strokedKinds: Set<String> = ["line", "arrow", "outline", "shape"]
    static let verbs: Set<String> = ["appear", "fade", "draw", "cross", "tint", "move", "gather", "look", "set", "tag", "pulse", "turn", "say", "each"]
    /// The kinds of element that have a `pivot`, which they grow and pulse about, and a `turn`, which
    /// needs the capability `drawing.turn`.
    static let turnableKinds: Set<String> = ["line", "arrow", "shape", "group"]
    /// The kinds a group may turn: those that have geometry that turns.
    static let turningMembers: Set<String> = ["line", "arrow", "shape"]
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

    /// A role named at `key`; the name when it is a role the document can use, else nil, with the
    /// finding that says why.
    @discardableResult
    func role(_ o: JSONObject, _ key: String, _ path: String) -> String? {
        guard let s = string(o, key, path) else { return nil }
        let p = DocumentPath.join(path, key)
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let base = parts[0]
        guard DocumentNames.isName(base), parts.count == 1 || (parts.count == 2 && ["fill", "ink", "soft"].contains(parts[1])) else {
            error(.schema, p, "'\(s)' is not a role")
            return nil
        }
        if parts.count == 2 && Self.neutralRoles.contains(base) {
            error(.schema, p, "'\(base)' is a neutral role, which has no \(parts[1])")
            return nil
        }
        if Self.arithmeticRoles.contains(base) { used.append(("components.arithmetic", p)) }
        if !roles.contains(base) && !Self.arithmeticRoles.contains(base) {
            error(.ref, p, "there is no role '\(base)'")
            return nil
        }
        return s
    }

    /// The roles the player draws, as the stage's inks, for the colours the document has read.
    var playerRoles: DocumentRoles { DocumentRoles(colours: ownColours) }

    /// Whether the player draws a colour as a role, for a role the document can use. A colour of
    /// the document's that could not be read is not judged here: it has a finding of its own.
    private func judged(_ role: String) -> Bool {
        let base = role.split(separator: ".").first.map(String.init) ?? role
        return Self.styleRoles.contains(base) || ownColours[base] != nil
    }

    /// Refuses, as the player would (section 2.3), a role it draws no ink for (EXP-19).
    func refuseInk(_ role: String?, fill: Bool = false, _ path: String) {
        guard let role, judged(role), playerRoles.ink(role, fill: fill) == nil else { return }
        error(.capability, path, PlayerRefusal.inkRole(role))
    }

    /// Refuses, as the player would, a role it draws as an operation role or a colour named alone only.
    func refuseHue(_ role: String?, _ path: String, _ message: (String) -> String) {
        guard let role, judged(role), playerRoles.hue(role) == nil else { return }
        error(.capability, path, message(role))
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

    /// A stroke's `width` (section 9.3): a number above 0, or an expression. An expression that
    /// gives another number is an error when the document is evaluated.
    func width(_ value: JSONValue?, _ path: String, _ scope: SlotScope) {
        guard let value else { return }
        slot(value, path, .number, scope)
        if case let .number(n) = value, !(n > 0 && n.isFinite) {
            error(.schema, path, "width is \(Canonical.number(n)), not a number above 0")
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

    /// An arc entry of a shape's `points` (section 9.3): `arc` is `[cx, cy, r]` or `[cx, cy, rx, ry]`,
    /// with `from` and `to`, and nothing else.
    func arc(_ value: JSONValue, _ path: String, _ scope: SlotScope) {
        guard case let .object(o) = value else { return }
        for k in o.keys where !["arc", "from", "to"].contains(k) {
            error(.schema, DocumentPath.join(path, k), "'\(k)' is not a key of an arc, which has arc, from and to")
        }
        for k in ["arc", "from", "to"] where o[k] == nil { error(.schema, path, "an arc has no '\(k)', which it requires") }
        if let shape = o["arc"] {
            if case let .array(a) = shape, a.count == 3 || a.count == 4 {
                for (k, v) in a.enumerated() { slot(v, path + "/arc/\(k)", .number, scope) }
            } else {
                error(.schema, path + "/arc", "arc is not [cx, cy, r] or [cx, cy, rx, ry]")
            }
        }
        slot(o["from"], path + "/from", .number, scope)
        slot(o["to"], path + "/to", .number, scope)
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
        // Optimal string alignment: an edit, or two neighbouring letters swapped, counts 1.
        var d = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in stride(from: 1, through: x.count, by: 1) {
            for j in stride(from: 1, through: y.count, by: 1) {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[x.count][y.count]
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
                error(.expr, path, at: n.at, ExpressionFunction.wrongCount(f, arity, args.count))
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
            "appearances", "areas", "layouts", "elements", "parts", "shots", "opening", "intro", "sequence", "steps", "try", "whatIf", "style", "plays",
            "wording", "extensions", "profile", "colours",
        ], required: ["format", "version", "id", "title", "sourceLocale", "params", "samples", "elements", "sequence", "steps", "wording"])
        gatherNames()
        checkHeader()
        checkProfile()
        checkAppearances()
        checkColours()
        checkParams()
        checkValues()
        checkLayouts()
        checkAreas()
        checkElements()
        checkPartsAndShots()
        checkSteps()
        checkInteraction()
        checkStyle()
        checkWording()
        checkCapabilities()
        checkSamples()
        checkColourSeen()
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
        for (k, _) in root["colours"]?.object?.entries ?? [] where DocumentNames.isName(k) && !Self.styleRoles.contains(k) { roles.insert(k) }
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

    /// The declaration of the areas the document is made for (section 8.2): its structure and
    /// the layouts it names. What it says about the layouts' `suits` is checked once the
    /// document has been read (`ExplainerDocument.areaFindings`).
    func checkAreas() {
        guard let value = root["areas"] else { return }
        guard case let .array(entries) = value, !entries.isEmpty else {
            error(.schema, "/areas", "areas is not a non-empty array of entries")
            return
        }
        let layouts = Set(root["layouts"]?.object?.keys ?? []).union(["stage"])
        for (k, e) in entries.enumerated() {
            let p = "/areas/\(k)"
            guard let o = object(e, p, known: ["layout", "ratio"], required: ["layout", "ratio"]) else { continue }
            nameRef(o, "layout", p, in: layouts, what: "layout")
            guard let ratio = o["ratio"] else { continue }
            let rp = p + "/ratio"
            guard case let .array(bounds) = ratio, bounds.count == 2 else {
                error(.schema, rp, "ratio is not [min, max], two numbers")
                continue
            }
            var numbers: [Double] = []
            for (i, b) in bounds.enumerated() {
                guard case let .number(n) = b else {
                    error(.schema, "\(rp)/\(i)", "the \(i == 0 ? "least" : "greatest") ratio is \(b.typeName), not a number")
                    continue
                }
                if n <= 0 { error(.schema, "\(rp)/\(i)", "the \(i == 0 ? "least" : "greatest") ratio is \(Canonical.number(n)), not more than 0") }
                numbers.append(n)
            }
            if numbers.count == 2, numbers[0] > 0, numbers[0] > numbers[1] {
                error(.schema, rp, "the least ratio \(Canonical.number(numbers[0])) is more than the greatest \(Canonical.number(numbers[1]))")
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
            let common = ["kind", "repeat", "when", "z", "fixed", "start", "let"]
            let byKind: [String: (known: [String], required: [String])] = [
                "text": (["at", "text", "runs", "style", "ink", "size", "anchor", "vanchor"], ["at"]),
                "line": (["from", "to", "style", "ink", "width", "turn", "pivot"], ["from", "to"]),
                "arrow": (["from", "to", "y", "ink", "width", "turn", "pivot"], ["from", "to", "ink"]),
                "outline": (["rect", "around", "pad", "style", "ink", "width"], ["style"]),
                "shape": (["rect", "corner", "ellipse", "points", "closed", "fill", "ink", "width", "turn", "pivot"], []),
                "group": (["members", "turn", "pivot"], ["members"]),
                "ten": (["rect", "look"], ["rect"]), "one": (["rect", "look"], ["rect"]),
                "stick": (["rect", "look"], ["rect"]), "circle": (["rect", "look"], ["rect"]),
            ]
            guard let spec = byKind[kind] else {
                error(.schema, p + "/kind", "'\(kind)' is not an element kind")
                continue
            }
            if Self.pieceKinds.contains(kind) { used.append(("components.arithmetic", p + "/kind")) }
            object(.object(el), p, known: common + spec.known, required: spec.required)
            // Text, outlines and pieces do not turn: a numeral stays upright and a piece's drawing is
            // fixed, so a `turn` or `pivot` on one is an error, not a key to ignore.
            if !Self.turnableKinds.contains(kind) {
                for key in ["turn", "pivot"] where el[key] != nil {
                    error(.schema, DocumentPath.join(p, key), "'\(key)' is for a line, arrow, shape or group, and \(name) is a \(kind)")
                }
            }
            let fixedScope = SlotScope(values: .paramsAndLets)
            // The element's own `let` names are locals of every key but `repeat` and `when`, which
            // fix how many instances there are and so cannot depend on one.
            let letNames = Set(el["let"]?.object?.keys ?? [])
            var scope = SlotScope(values: .all, locals: el["repeat"] != nil ? ["i"] : [])
            if el["let"] != nil { checkElementLet(el, p, scope) }
            scope.locals.formUnion(letNames)
            slot(el["repeat"], p + "/repeat", .number, fixedScope)
            slot(el["when"], p + "/when", .truth, fixedScope)
            slot(el["z"], p + "/z", .number, scope)
            if Self.turnableKinds.contains(kind) {
                slot(el["turn"], p + "/turn", .number, scope)
                point(el["pivot"], p + "/pivot", scope)
                if el["turn"] != nil { used.append(("drawing.turn", p + "/turn")) }
            }
            bool(el, "fixed", p)
            if Self.strokedKinds.contains(kind) { width(el["width"], p + "/width", scope) }
            if let start = object(el["start"], p + "/start", known: kind == "group" ? ["opacity"] : ["opacity", "progress"]) {
                slot(start["opacity"], p + "/start/opacity", .number, scope)
                slot(start["progress"], p + "/start/progress", .number, scope)
            }
            switch kind {
            case "text":
                point(el["at"], p + "/at", scope)
                entry(el, "text", p, part: .watch, locals: scope.locals, element: name)
                let style = oneOf(el, "style", p, ["equation", "total", "label", "note", "body"])
                let styleName = el["style"] == nil ? "body" : style
                for (run, v, rp) in map(el["runs"], p + "/runs") {
                    guard let r = object(v, rp, known: ["ink", "text"]) else { continue }
                    if let ri = role(r, "ink", rp), judged(ri), styleName != "equation" || (ri != "result" && ri != "text" && ownColours[ri] == nil) {
                        error(.capability, DocumentPath.join(rp, "ink"), PlayerRefusal.runInk)
                    }
                    entry(r, "text", rp, part: .watch, locals: scope.locals)
                    if !runs(of: name).contains(run) { error(.ref, rp, "\(name)'s entry has no placeholder {\(run)}") }
                }
                slot(el["size"], p + "/size", .number, scope)
                let anchor = oneOf(el, "anchor", p, ["start", "middle", "end"])
                _ = oneOf(el, "vanchor", p, ["baseline", "middle"])
                let ink = role(el, "ink", p)
                refuseInk(ink, p + "/ink")
                // What the player draws of a style, by the style's own anchor and ink where the element gives none.
                if let styleName, let (_, anchor0, ink0) = DocumentFilm.textDefaults[styleName],
                    let anchorNow = el["anchor"] == nil ? anchor0 : anchor, let inkNow = el["ink"] == nil ? ink0 : ink
                {
                    if styleName == "equation" && (anchorNow != "middle" || inkNow != "text") { error(.capability, p, PlayerRefusal.equation) }
                    if styleName == "total" && (anchorNow != "middle" || inkNow != "result") { error(.capability, p, PlayerRefusal.total) }
                }
            case "group":
                slot(el["members"], p + "/members", .selection, scope)
                // A group's members are the same for every state of the film, which `whole` is not.
                expressions[p + "/members"]?.root.walk { node in
                    if case let .call(f, _) = node.kind, f == "whole" {
                        error(.schema, p + "/members", "a group's members do not depend on the state, so they must not use whole()")
                    }
                }
            case "line":
                point(el["from"], p + "/from", scope)
                point(el["to"], p + "/to", scope)
                _ = oneOf(el, "style", p, ["rule", "divider"])
                refuseInk(role(el, "ink", p), p + "/ink")
            case "arrow":
                for key in ["from", "to"] {
                    if case .string = el[key] { slot(el[key], p + "/" + key, .selection, scope) } else { point(el[key], p + "/" + key, scope) }
                }
                slot(el["y"], p + "/y", .number, scope)
                refuseHue(role(el, "ink", p), p + "/ink") { PlayerRefusal.hue("arrow", $0) }
            case "outline":
                if el["rect"] == nil && el["around"] == nil { error(.schema, p, "an outline has rect or around") }
                if el["rect"] != nil && el["around"] != nil { error(.schema, p, "an outline has rect or around, not both") }
                rect(el["rect"], p + "/rect", scope)
                slot(el["around"], p + "/around", .selection, scope)
                slot(el["pad"], p + "/pad", .number, scope)
                let style = oneOf(el, "style", p, ["box", "ring", "hint", "target"])
                let ink = role(el, "ink", p)
                switch style {
                case "box", "ring": refuseHue(ink, p + "/ink") { PlayerRefusal.hue("outline", $0) }
                case let other?: if el["ink"] != nil { error(.capability, p + "/ink", PlayerRefusal.outlineInk(other)) }
                case nil: break
                }
                if (style == "box" || style == "ring") && el["ink"] == nil { error(.schema, p, "a \(style!) outline has no 'ink', which it requires") }
            case "shape":
                let geometry = ["rect", "ellipse", "points"].filter { el[$0] != nil }
                if geometry.count != 1 { error(.schema, p, "a shape has exactly one of rect, ellipse and points") }
                rect(el["rect"], p + "/rect", scope)
                rect(el["ellipse"], p + "/ellipse", scope)
                slot(el["corner"], p + "/corner", .number, scope)
                if let pts = el["points"] {
                    if case let .array(a) = pts {
                        for (k, x) in a.enumerated() {
                            if case .object = x { arc(x, p + "/points/\(k)", scope) } else { point(x, p + "/points/\(k)", scope) }
                        }
                    } else {
                        error(.schema, p + "/points", "points is not an array of points")
                    }
                }
                bool(el, "closed", p)
                refuseInk(role(el, "fill", p), fill: true, p + "/fill")
                refuseInk(role(el, "ink", p), p + "/ink")
                if el["fill"] == nil && el["ink"] == nil { error(.schema, p, "a shape has at least one of fill and ink") }
            default:
                rect(el["rect"], p + "/rect", scope)
                _ = oneOf(el, "look", p, ["pencil", "traded", "counted"])
            }
        }
    }

    /// An element's `let` (section 9.1): names for values computed for each instance, with `i`
    /// in scope when the element repeats. A name must not be any other name of the first
    /// namespace, so that a reader that does not know the key reports each use as an unknown
    /// name and never reads a document value of the same name.
    func checkElementLet(_ el: JSONObject, _ p: String, _ scope: SlotScope) {
        let names = Set(el["let"]?.object?.keys ?? [])
        var graph: [String: Set<String>] = [:]
        for (name, x, lp) in map(el["let"], p + "/let") {
            if DocumentNames.reserved.contains(name) {
                error(.schema, lp, "'\(name)' is reserved and cannot name a local")
            } else if params[name] != nil || lets[name] != nil || vars.contains(name) || elements[name] != nil {
                error(.schema, lp, "'\(name)' is already a name of the document; an element's let must not reuse a parameter, let, vars value or element")
            }
            var inner = scope
            inner.locals.formUnion(names)
            slot(x, lp, .value, inner)
            graph[name] = dependencies(lp).intersection(names)
        }
        reportCycle(graph, what: "the element's let values") { DocumentPath.join(p, "let", $0) }
    }

    func checkPartsAndShots() {
        for (_, v, p) in map(root["parts"], "/parts") { slot(v, p, .selection, SlotScope(values: .all)) }
        for (_, v, p) in map(root["shots"], "/shots") {
            guard let o = object(v, p, known: ["frame", "region", "margin", "up"]) else { continue }
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
            slot(o["up"], p + "/up", .number, SlotScope(values: .all))
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
    func action(_ value: JSONValue, _ p: String, scope: SlotScope, inner: Bool, part: WordingCoverage.Part) {
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
            "appear": ["rise", "grow", "place", "text", "from"], "fade": ["to"], "draw": [], "cross": ["fade"], "tint": ["ink"],
            "move": ["to", "via"], "gather": ["from"], "look": ["value"], "set": ["text"], "tag": ["text", "ink"], "pulse": [], "turn": ["to"],
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
            if case .string = o["from"] { slot(o["from"], p + "/from", .selection, perInstance) } else { point(o["from"], p + "/from", perInstance) }
            if o["from"] != nil && o["rise"] != nil { error(.schema, p, "an appear has from or rise, not both") }
            entry(o, "text", p, part: part, locals: plain.locals)
        case "fade":
            if o["to"] != .string("ghost") { slot(o["to"], p + "/to", .number, perInstance) }
        case "cross":
            slot(o["fade"], p + "/fade", .number, plain)
        case "tint":
            refuseHue(role(o, "ink", p), p) { _ in PlayerRefusal.tintHue }
            checkTintTarget(o["target"], p, scope: plain)
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
        case "turn":
            slot(o["to"], p + "/to", .number, perInstance)
            used.append(("drawing.turn", p + "/do"))
        case "look":
            _ = oneOf(o, "value", p, ["pencil", "traded", "counted"])
        case "set", "tag":
            entry(o, "text", p, part: part, locals: plain.locals)
            if verb == "tag" { refuseHue(role(o, "ink", p), p) { _ in PlayerRefusal.tagHue } }
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

    /// What a `tint` can be told of its target before any problem: a bare element that does not
    /// repeat is no run, and a run of a text element that is not an equation is not tinted. Any
    /// other target is judged when it is evaluated.
    func checkTintTarget(_ target: JSONValue?, _ path: String, scope: SlotScope) {
        guard let e = expressions[path + "/target"] else { return }
        func element(_ n: ExpressionNode) -> String? {
            if case let .index(base, _) = n.kind { return element(base) }
            guard case let .name(name) = n.kind, !scope.locals.contains(name), elements[name] != nil else { return nil }
            return name
        }
        switch e.root.kind {
        case let .name(name) where !scope.locals.contains(name):
            if let el = elements[name], el["repeat"] == nil, el["kind"]?.string != nil {
                error(.capability, path, PlayerRefusal.tintNeedsRun + name)
            }
        case let .member(base, run):
            if let name = element(base), let el = elements[name], el["kind"] == .string("text"), run != "cross",
                (el["style"] == nil ? "body" : el["style"]?.string).map({ $0 != "equation" }) == true
            {
                error(.capability, path, PlayerRefusal.tintEquation)
            }
        default: break
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
        guard let style = object(root["style"], "/style", known: ["palette", "overrides", "easings", "motion"]) else { return }
        if style["palette"] != nil {
            error(.schema, "/style/palette", "a document does not give a palette; name its own colours under colours")
        }
        checkOverrides(style["overrides"])
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
            error(.capability, path, "this uses the capability '\(cap)', and the document's requires does not list it")
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
            // A sample is checked against parameters that can themselves be read.
            if findings.contains(where: { $0.severity == .error && $0.path.hasPrefix("/params") }) { continue }
            for f in ProblemCheck.check(values, params: root["params"]?.object ?? JSONObject(), expressions: expressions) {
                findings.append(DocumentFinding(.error, .range, f.path.isEmpty ? p : DocumentPath.join(p, f.path), values: values, f.message))
            }
        }
    }
}

// MARK: profiles and colours (EXP-20)

/// A role a document draws with, in the form it is drawn in.
struct DrawnRole: Hashable {
    var base: String
    /// `fill`, `ink` or `soft`.
    var form: String
}

extension DocumentChecker {
    /// The profile the document declares, which defaults to `open`. An unknown one is a `ref`
    /// error, so a player never draws a document under a profile it does not have.
    func checkProfile() {
        guard let v = root["profile"] else {
            profile = ExplainerStyle.profiles[ExplainerStyle.defaultProfile]
            return
        }
        guard case let .string(id) = v else {
            error(.schema, "/profile", "profile is \(v.typeName), not a string")
            return
        }
        if let p = ExplainerStyle.profiles[id] {
            profile = p
        } else {
            let known = ExplainerStyle.profiles.keys.sorted().joined(separator: ", ")
            error(.ref, "/profile", "there is no profile '\(id)'; this reader has \(known)")
        }
    }

    var profileID: String { root["profile"]?.string ?? ExplainerStyle.defaultProfile }

    /// The appearances the document is made for, as an array of unique names from `light` and
    /// `dark` (section 16.6).
    func checkAppearances() {
        guard let v = root["appearances"] else { return }
        guard case let .array(entries) = v, !entries.isEmpty else {
            error(.schema, "/appearances", "appearances is not a non-empty array of light and dark")
            return
        }
        var declared: Set<Appearance> = []
        var sound = true
        for (k, e) in entries.enumerated() {
            let p = "/appearances/\(k)"
            guard case let .string(name) = e else {
                error(.schema, p, "an appearance is \(e.typeName), not light or dark")
                sound = false
                continue
            }
            guard let a = Appearance(rawValue: name) else {
                error(.schema, p, "'\(name)' is not an appearance; the appearances are light and dark")
                sound = false
                continue
            }
            if !declared.insert(a).inserted {
                error(.schema, p, "\(name) is listed more than once")
                sound = false
            }
        }
        if sound { madeFor = declared }
    }

    /// The document's own colours: each gives a value for each appearance the document is made
    /// for, or names one of its profile's suggested colours, and says what tells its marks apart
    /// without colour.
    func checkColours() {
        for (name, v, p) in map(root["colours"], "/colours") {
            if Self.styleRoles.contains(name) {
                error(.schema, p, "'\(name)' is a role of the style; a colour of the document's own has another name")
                continue
            }
            guard let o = object(v, p, known: ["light", "dark", "suggested", "cue"]) else { continue }
            if let cue = string(o, "cue", p), cue.trimmingCharacters(in: .whitespaces).isEmpty {
                warning(.colour, p, "\(name) has no cue. Say what tells its marks apart without colour, such as length, width or place.")
            } else if o["cue"] == nil {
                warning(.colour, p, "\(name) has no cue. Say what tells its marks apart without colour, such as length, width or place.")
            }
            let values = o["light"] != nil || o["dark"] != nil
            if values && o["suggested"] != nil {
                error(.schema, p, "\(name) gives values or a suggested colour, not both")
                continue
            }
            if !values && o["suggested"] == nil {
                error(.schema, p, "\(name) gives a value for each appearance the document is made for, or the name of a suggested colour")
                continue
            }
            if values {
                var read: [String: RGB] = [:]
                for k in ["light", "dark"] {
                    guard let s = string(o, k, p) else {
                        if o[k] == nil, madeFor.contains(Appearance(rawValue: k)!) {
                            error(.schema, p, "\(name) has no \(k) value, and the document is made for \(k)")
                        }
                        continue
                    }
                    if Self.isColour(s), let c = RGB(hexString: s) { read[k] = c } else {
                        error(.schema, DocumentPath.join(p, k), "'\(s)' is not a colour #RRGGBB")
                    }
                }
                if read["light"] != nil || read["dark"] != nil { ownColours[name] = DocumentColour(name: name, light: read["light"], dark: read["dark"]) }
            } else if let s = string(o, "suggested", p), let profile {
                if let l = profile.light.suggested[s], let d = profile.dark.suggested[s] {
                    ownColours[name] = DocumentColour(name: name, light: l, dark: d)
                } else {
                    let offered = profile.light.suggested.keys.sorted()
                    let list = offered.isEmpty ? "offers no suggested colours" : "offers \(offered.joined(separator: ", "))"
                    error(.ref, DocumentPath.join(p, "suggested"), "the profile '\(profileID)' has no suggested colour '\(s)'; it \(list)")
                }
            }
        }
    }

    /// The operations whose colour the document changes (section 16.7), each with a value for
    /// each appearance the document is made for. A profile that fixes the operations has the
    /// request of the person who asked, and each change is reported as a warning, so that whoever
    /// checks the document is told of it; a profile that fixes no colour takes the change as it is.
    func checkOverrides(_ value: JSONValue?) {
        guard let value else { return }
        let base = "/style/overrides"
        // A profile the reader does not have is already an error, and says nothing of what it fixes.
        guard let fixes = profile?.profile else { return }
        let explained = fixes.overrides == .explained
        let changeable = ExplainerOperation.allCases.map(\.rawValue).filter { !explained || fixes.fixed[$0] != nil }
        for (name, v, p) in map(value, base, keys: { _ in true }) {
            guard changeable.contains(name) else {
                let what = explained ? "a colour the \(fixes.id) profile fixes" : "an operation"
                error(.schema, p, "'\(name)' is not \(what); an override changes one of \(changeable.joined(separator: ", "))")
                continue
            }
            guard let o = object(v, p, known: ["light", "dark", "asked"]) else { continue }
            if explained {
                if o["asked"] == nil {
                    error(.schema, p, "the override of \(name) has no 'asked', which it requires: the request of the person who asked for the change")
                } else if let asked = string(o, "asked", p), asked.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    error(.schema, DocumentPath.join(p, "asked"), "asked is empty; it holds the request of the person who asked for the change")
                }
            } else if o["asked"] != nil {
                _ = string(o, "asked", p)
            }
            var read: [String: RGB] = [:]
            for k in ["light", "dark"] {
                guard let s = string(o, k, p) else {
                    if o[k] == nil, madeFor.contains(Appearance(rawValue: k)!) {
                        error(.schema, p, "the override of \(name) has no \(k) value, and the document is made for \(k)")
                    }
                    continue
                }
                if Self.isColour(s), let c = RGB(hexString: s) { read[k] = c } else {
                    error(.schema, DocumentPath.join(p, k), "'\(s)' is not a colour #RRGGBB")
                }
            }
            if read["light"] != nil || read["dark"] != nil { overridden[name] = DocumentColour(name: name, light: read["light"], dark: read["dark"]) }
            guard explained else { continue }
            let meaning = fixes.fixed[name] ?? name
            warning(.override, p, "This explainer changes the colour for \(meaning) (\(name)). \(OperationOverride.reason) An app that plays the explainer may show the standard colour instead.")
        }
    }

    // MARK: what is drawn

    /// The role `s` as drawn in a key that gives `defaultForm`.
    private func drawn(_ s: String, form defaultForm: String, into out: inout Set<DrawnRole>) {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let base = parts.first, DocumentNames.isName(base) else { return }
        out.insert(DrawnRole(base: base, form: parts.count == 2 ? parts[1] : defaultForm))
    }

    /// The roles the document draws with, by what its elements and actions name and by the roles
    /// the format gives by default (section 9).
    func drawnRoles() -> Set<DrawnRole> {
        var out = Set<DrawnRole>()
        let textDefaults = ["equation": "text", "total": "result", "label": "muted", "note": "muted", "body": "text"]
        for (_, el) in elements {
            let ink = el["ink"]?.string
            switch el["kind"]?.string {
            case "text":
                drawn(ink ?? textDefaults[el["style"]?.string ?? "body"] ?? "text", form: "ink", into: &out)
                for (_, run) in el["runs"]?.object?.entries ?? [] { if let r = run["ink"]?.string { drawn(r, form: "ink", into: &out) } }
            case "line": drawn(ink ?? (el["style"]?.string == "divider" ? "line" : "pencil"), form: "ink", into: &out)
            case "arrow": if let ink { drawn(ink, form: "ink", into: &out) }
            case "outline":
                switch el["style"]?.string ?? "box" {
                case "hint": drawn("muted", form: "ink", into: &out)
                case "target": drawn("result", form: "fill", into: &out)
                default: if let ink { drawn(ink, form: "ink", into: &out) }
                }
            case "shape":
                if let f = el["fill"]?.string { drawn(f, form: "fill", into: &out) }
                if let ink { drawn(ink, form: "ink", into: &out) }
            default: drawn("pencil", form: "ink", into: &out)
            }
        }
        func walk(_ actions: JSONValue?) {
            for (_, a) in actions?.object?.entries ?? [] {
                switch a["do"]?.string {
                case "tint": if let r = a["ink"]?.string { drawn(r, form: "ink", into: &out) }
                case "tag": drawn(a["ink"]?.string ?? "result", form: "ink", into: &out)
                case "cross": drawn("subtract", form: "ink", into: &out)
                case "look":
                    if a["value"] == .string("traded") { drawn("trade", form: "ink", into: &out) }
                    if a["value"] == .string("counted") { drawn("result", form: "ink", into: &out) }
                case "each": walk(a["then"])
                default: break
                }
            }
        }
        for (_, s) in steps {
            walk(s["actions"])
            walk(s["why"]?["actions"])
            if let act = s["act"] {
                if let r = act["ink"]?.string { drawn(r, form: "ink", into: &out) }
                if let r = act["tally"]?.string { drawn(r, form: "ink", into: &out) }
                if case .object = act["then"] { walk(.object(JSONObject([("then", act["then"]!)]))) }
            }
        }
        return out
    }

    /// The value of a role drawn, in one appearance, or nil for a role that is not a colour drawn
    /// on the sheet.
    private func value(_ role: DrawnRole, dark: Bool) -> RGB? {
        let palette = ExplainerStyle.standard.palette(dark: dark)
        if let own = ownColours[role.base] ?? overridden[role.base] { return own.value(dark: dark) }
        switch role.base {
        case "text": return palette.ink
        case "muted": return palette.muted
        case "line": return palette.line
        case "pencil": return palette.pencil
        default:
            guard let op = ExplainerOperation(rawValue: role.base) else { return nil }
            return role.form == "fill" ? palette.colors(op).fill : palette.colors(op).ink
        }
    }

    // MARK: what is seen

    /// Reports, as warnings, a colour a person may not see or tell from another: an ink under 3:1
    /// with the sheet or on its own soft form, two colours drawn together under 20 apart with
    /// normal vision or a simulated deficiency, and, in the maths profile, a colour close to an
    /// operation's. The colours judged are the document's own and those it gives an operation in
    /// place of the style's (section 16.7). None stops the document playing.
    func checkColourSeen() {
        // An operation role is not a name a colour of the document's own may have, so the two do not meet.
        let given = ownColours.merging(overridden) { own, _ in own }
        guard !given.isEmpty else { return }
        func pathOf(_ name: String) -> String { DocumentPath.join(overridden[name] != nil ? "/style/overrides" : "/colours", name) }
        let used = drawnRoles()
        let names = given.keys.sorted()
        func appearance(_ dark: Bool) -> String { dark ? "dark" : "light" }
        // The checks are made in each appearance the document is made for, and in no other.
        let checked = [false, true].filter { madeFor.contains($0 ? .dark : .light) }
        // The appearances in which a colour is too faint to see, which its other checks leave out.
        var faint: Set<String> = []
        for name in names {
            let c = given[name]!
            let path = pathOf(name)
            for dark in checked {
                guard let ink = c.value(dark: dark) else { continue }
                let sheet = ExplainerStyle.standard.palette(dark: dark).sheet
                let k = ColourChecks.contrasts(ink, sheet: sheet, dark: dark)
                guard k.sheet < ColourChecks.minimumContrast || k.soft < ColourChecks.minimumContrast else { continue }
                faint.insert(name + (dark ? "/dark" : "/light"))
                let refs = used.compactMap { value($0, dark: dark) }.filter { $0 != ink }
                let near = ColourChecks.nearestPassing(to: ink, sheet: sheet, dark: dark, apart: refs)
                let remedy = near.map { " The nearest colour that is easy to see is \($0.hex)." } ?? " No colour near it shows beside the others in the document; choose another."
                if k.sheet < ColourChecks.minimumContrast {
                    let how = dark ? "very dark" : "very pale"
                    warning(.colour, path, "\(name) (\(ink.hex)) is \(how) on the \(appearance(dark)) sheet (\(ratio(k.sheet)):1; thin lines and text need 3:1), so what is drawn in it will be hard to see.\(remedy)")
                } else {
                    warning(.colour, path, "text in \(name) (\(ink.hex)) on its own tint is hard to read on the \(appearance(dark)) sheet (\(ratio(k.soft)):1, under 3:1).\(remedy)")
                }
            }
        }

        // Pairs drawn together: each colour of the document's own with every other colour drawn.
        let drawnNames = names.filter { n in used.contains { $0.base == n } }
        // A colour is compared once however many forms of it are drawn (text as ink and as fill is
        // one colour), taking the closest of its forms in each appearance.
        var others: [(label: String, roles: [DrawnRole])] = []
        for r in used.sorted(by: { ($0.base, $0.form) < ($1.base, $1.form) }) where r.form != "soft" && given[r.base] == nil {
            guard value(r, dark: false) != nil else { continue }
            if let i = others.firstIndex(where: { $0.label == r.base }) { others[i].roles.append(r) } else { others.append((r.base, [r])) }
        }
        for (k, name) in drawnNames.enumerated() {
            let path = pathOf(name)
            var candidates: [(label: String, roles: [DrawnRole])] = others
            for later in drawnNames[(k + 1)...] { candidates.append((later, [DrawnRole(base: later, form: "ink")])) }
            for other in candidates {
                var worst: (distance: Double, dark: Bool, seenWith: ColourVision, a: RGB, b: RGB)?
                for dark in checked {
                    if faint.contains(name + (dark ? "/dark" : "/light")) || faint.contains(other.label + (dark ? "/dark" : "/light")) { continue }
                    guard let a = value(DrawnRole(base: name, form: "ink"), dark: dark) else { continue }
                    for role in other.roles {
                        guard let b = value(role, dark: dark) else { continue }
                        let w = ColourVision.worst(a, b)
                        if w.distance < (worst?.distance ?? .infinity) { worst = (w.distance, dark, w.seenWith, a, b) }
                    }
                }
                guard let w = worst, w.distance < ColourChecks.minimumDistance else { continue }
                let measured = "in \(appearance(w.dark)), \(name) \(w.a.hex) and \(other.label) \(w.b.hex) are \(ratio(w.distance)) apart with \(w.seenWith == .normal ? "normal vision" : w.seenWith.description); under 20"
                if w.seenWith == .normal {
                    warning(.colour, path, "\(name) and \(other.label) look alike (\(measured)).")
                } else {
                    warning(.colour, path, "\(name) and \(other.label) may look like one colour to some colour-blind viewers (\(measured)).")
                }
            }
        }

        // In the maths profile, a colour near an operation's may be read as that operation.
        guard profileID == "maths" else { return }
        for name in drawnNames {
            let path = pathOf(name)
            // An operation whose colour the document changes no longer has the colour every
            // explainer uses, and an operation is not compared with itself.
            for op in ExplainerOperation.allCases where overridden[op.rawValue] == nil {
                var worst: (distance: Double, dark: Bool, a: RGB, b: RGB)?
                for dark in checked {
                    let palette = ExplainerStyle.standard.palette(dark: dark)
                    guard let a = value(DrawnRole(base: name, form: "ink"), dark: dark) else { continue }
                    for b in [palette.colors(op).ink, palette.colors(op).fill] {
                        let d = ColourVision.normal.distance(a, b)
                        if d < (worst?.distance ?? .infinity) { worst = (d, dark, a, b) }
                    }
                }
                guard let w = worst, w.distance < ColourChecks.minimumDistance else { continue }
                warning(.colour, path, "\(name) (\(w.a.hex)) looks like the colour every maths explainer uses for \(profile?.profile?.fixed[op.rawValue] ?? op.rawValue), so a learner may read it as that (in \(appearance(w.dark)), \(ratio(w.distance)) apart from \(op.rawValue) with normal vision; under 20).")
            }
        }
    }

    private func ratio(_ x: Double) -> String { String(format: "%.1f", x) }
}
