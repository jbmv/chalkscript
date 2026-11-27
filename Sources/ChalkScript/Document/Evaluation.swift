import Foundation

/// A value an expression computes (EXP-19, section 6.3 of the format's reference): a number (a
/// double), a truth value, a string, a selection of drawn instances, or a placement. There is no
/// conversion between them.
public enum DocumentValue: Hashable, Sendable, CustomStringConvertible {
    case number(Double)
    case truth(Bool)
    case string(String)
    case selection(DocumentSelection)
    /// Where `appear` puts its targets: `split(s)`, of `components.arithmetic`.
    case placement(DocumentPlacement)

    public var typeName: String {
        switch self {
        case .number: "a number"
        case .truth: "a truth value"
        case .string: "a string"
        case .selection: "a selection"
        case .placement: "a placement"
        }
    }

    /// The value as an integer, when it is a number with no fraction.
    public var integer: Int? {
        guard case let .number(n) = self, n.rounded(.towardZero) == n, abs(n) < 9e15 else { return nil }
        return Int(n)
    }

    public var description: String {
        switch self {
        case let .number(n): Canonical.number(n)
        case let .truth(b): b ? "true" : "false"
        case let .string(s): "'\(s)'"
        case let .selection(s): s.description
        case let .placement(p): "split(\(p.source))"
        }
    }

    /// The value as JSON, for a problem written as a document's `samples` write one.
    public var json: JSONValue {
        switch self {
        case let .number(n): .number(n)
        case let .truth(b): .bool(b)
        case let .string(s): .string(s)
        case let .selection(s): .string(s.description)
        case let .placement(p): .string("split(\(p.source))")
        }
    }

    public init?(json: JSONValue) {
        switch json {
        case let .number(n): self = .number(n)
        case let .bool(b): self = .truth(b)
        case let .string(s): self = .string(s)
        default: return nil
        }
    }
}

/// One drawn thing a selection can hold (section 7): an instance of an element, or a sub-part of
/// one, a run of a text element or the cross-out of a piece.
public struct DocumentInstance: Hashable, Sendable, CustomStringConvertible {
    public enum Part: Hashable, Sendable {
        case run(String)
        case cross
    }

    public var element: String
    /// The instance's index, from 0, for an element with `repeat`; nil for one without.
    public var index: Int?
    public var part: Part?

    public init(_ element: String, _ index: Int? = nil, part: Part? = nil) {
        self.element = element
        self.index = index
        self.part = part
    }

    /// The instance itself, without its sub-part.
    public var whole: DocumentInstance { DocumentInstance(element, index) }

    public var description: String {
        var s = element
        if let index { s += "[\(index)]" }
        switch part {
        case let .run(r): s += "." + r
        case .cross: s += ".cross"
        case nil: break
        }
        return s
    }
}

/// An ordered list of distinct instances (section 7).
public struct DocumentSelection: Hashable, Sendable, CustomStringConvertible {
    public private(set) var instances: [DocumentInstance]

    public init(_ instances: [DocumentInstance] = []) {
        var seen = Set<DocumentInstance>()
        self.instances = instances.filter { seen.insert($0).inserted }
    }

    public var count: Int { instances.count }
    public var isEmpty: Bool { instances.isEmpty }

    /// The instances of `self`, then those of `other` not already in it.
    public static func + (a: DocumentSelection, b: DocumentSelection) -> DocumentSelection {
        DocumentSelection(a.instances + b.instances)
    }

    public var description: String { "[" + instances.map(\.description).joined(separator: ", ") + "]" }
}

/// `split(s)`: the targets of an `appear` placed over the ten or stick `source`, the k-th at
/// (x + 1, y + k·h/10 + 1) of its rectangle (section 9.4).
public struct DocumentPlacement: Hashable, Sendable {
    public var source: DocumentInstance
}

/// What an evaluation looks names up in: the locals where the expression is evaluated, the
/// document's values for one problem, and its elements' instances in the current state.
protocol EvaluationScope {
    /// The value of `name`, or nil when the name is in no scope.
    func value(of name: String) throws(ExpressionError) -> DocumentValue?
    /// Information about element `name`, or nil when there is none.
    func element(_ name: String) -> ScopeElement?
    /// Whether `instance` is whole: not crossed out and not ghosted (section 13.2).
    func isWhole(_ instance: DocumentInstance) -> Bool
    /// `start(action)` or `end(action)` on the current step's clock.
    func time(_ function: String, of action: String, at: Int) throws(ExpressionError) -> Double
}

/// What an evaluation needs to know of an element.
struct ScopeElement {
    var kind: String
    var repeated: Bool
    /// The number of instances for this problem.
    var count: Int
    /// The runs a text element's entry has, in the wording being played.
    var runs: Set<String>
    var isPiece: Bool

    var selection: DocumentSelection {
        DocumentSelection(repeated ? (0..<count).map { DocumentInstance(name, $0) } : (count > 0 ? [DocumentInstance(name)] : []))
    }

    var name: String
}

/// Evaluates parsed expressions (section 6). Every failure is an `ExpressionError` at the offset
/// of the node that failed; a value never silently becomes 0.
struct Evaluator {
    let scope: any EvaluationScope

    func evaluate(_ e: DocumentExpression) throws(ExpressionError) -> DocumentValue {
        try evaluate(e.root)
    }

    func evaluate(_ n: ExpressionNode) throws(ExpressionError) -> DocumentValue {
        let v = try compute(n)
        if case let .number(x) = v, !x.isFinite { throw ExpressionError("the result is not finite", at: n.at) }
        return v
    }

    func number(_ n: ExpressionNode, _ what: String = "an operand") throws(ExpressionError) -> Double {
        let v = try evaluate(n)
        guard case let .number(x) = v else { throw ExpressionError("\(what) is \(v.typeName), not a number", at: n.at) }
        return x
    }

    func truth(_ n: ExpressionNode, _ what: String = "an operand") throws(ExpressionError) -> Bool {
        let v = try evaluate(n)
        guard case let .truth(b) = v else { throw ExpressionError("\(what) is \(v.typeName), not a truth value", at: n.at) }
        return b
    }

    func integer(_ n: ExpressionNode, _ what: String) throws(ExpressionError) -> Int {
        let v = try evaluate(n)
        guard let k = v.integer else { throw ExpressionError("\(what) is \(v), not an integer", at: n.at) }
        return k
    }

    func selection(_ n: ExpressionNode, _ what: String = "an operand") throws(ExpressionError) -> DocumentSelection {
        let v = try evaluate(n)
        guard case let .selection(s) = v else { throw ExpressionError("\(what) is \(v.typeName), not a selection", at: n.at) }
        return s
    }

    private func compute(_ n: ExpressionNode) throws(ExpressionError) -> DocumentValue {
        switch n.kind {
        case let .number(x): return .number(x)
        case let .string(s): return .string(s)
        case let .truth(b): return .truth(b)
        case let .name(name):
            if let v = try scope.value(of: name) { return v }
            if let el = scope.element(name) { return .selection(el.selection) }
            throw ExpressionError("unknown name '\(name)'", at: n.at)
        case let .negate(a):
            return .number(-(try number(a, "the operand of '-'")))
        case let .not(a):
            return .truth(!(try truth(a, "the operand of 'not'")))
        case let .conditional(c, a, b):
            return try truth(c, "the condition") ? try evaluate(a) : try evaluate(b)
        case let .binary(op, a, b):
            return try binary(op, a, b, at: n.at)
        case let .call(f, args):
            return try call(f, args, at: n.at)
        case let .index(base, k):
            return try index(base, k, at: n.at)
        case let .member(base, m):
            return try member(base, m, at: n.at)
        }
    }

    private func binary(_ op: ExpressionNode.BinaryOperator, _ a: ExpressionNode, _ b: ExpressionNode, at: Int) throws(ExpressionError) -> DocumentValue {
        switch op {
        case .and:
            guard try truth(a, "the left of 'and'") else { return .truth(false) }
            return .truth(try truth(b, "the right of 'and'"))
        case .or:
            if try truth(a, "the left of 'or'") { return .truth(true) }
            return .truth(try truth(b, "the right of 'or'"))
        case .equal, .notEqual:
            let x = try evaluate(a)
            let y = try evaluate(b)
            switch (x, y) {
            case (.number, .number), (.truth, .truth), (.string, .string): break
            case (.selection, _), (_, .selection), (.placement, _), (_, .placement):
                throw ExpressionError("selections cannot be compared with '\(op.rawValue)'", at: at)
            default:
                throw ExpressionError("'\(op.rawValue)' compares \(x.typeName) with \(y.typeName)", at: at)
            }
            return .truth((x == y) == (op == .equal))
        case .less, .lessOrEqual, .greater, .greaterOrEqual:
            let x = try number(a, "the left of '\(op.rawValue)'")
            let y = try number(b, "the right of '\(op.rawValue)'")
            switch op {
            case .less: return .truth(x < y)
            case .lessOrEqual: return .truth(x <= y)
            case .greater: return .truth(x > y)
            default: return .truth(x >= y)
            }
        case .add:
            let x = try evaluate(a)
            let y = try evaluate(b)
            switch (x, y) {
            case let (.number(p), .number(q)): return .number(p + q)
            case let (.selection(p), .selection(q)): return .selection(p + q)
            default: throw ExpressionError("'+' adds \(x.typeName) to \(y.typeName)", at: at)
            }
        case .subtract, .multiply, .divide:
            let x = try number(a, "the left of '\(op.rawValue)'")
            let y = try number(b, "the right of '\(op.rawValue)'")
            switch op {
            case .subtract: return .number(x - y)
            case .multiply: return .number(x * y)
            default:
                if y == 0 { throw ExpressionError("division by zero", at: at) }
                return .number(x / y)
            }
        }
    }

    private func call(_ f: String, _ args: [ExpressionNode], at: Int) throws(ExpressionError) -> DocumentValue {
        guard let arity = ExpressionFunction.arity[f] else { throw ExpressionError("unknown function '\(f)'", at: at) }
        guard arity.contains(args.count) else {
            throw ExpressionError(ExpressionFunction.wrongCount(f, arity, args.count), at: at)
        }
        switch f {
        case "div", "mod":
            let a = try number(args[0], "the first argument of \(f)()")
            let b = try number(args[1], "the second argument of \(f)()")
            if b == 0 { throw ExpressionError("\(f)() by zero", at: at) }
            let q = (a / b).rounded(.down)
            return .number(f == "div" ? q : a - b * q)
        case "min", "max":
            var best = try number(args[0], "an argument of \(f)()")
            for a in args.dropFirst() {
                let x = try number(a, "an argument of \(f)()")
                best = f == "min" ? Swift.min(best, x) : Swift.max(best, x)
            }
            return .number(best)
        case "sin", "cos":
            let a = try number(args[0], "the argument of \(f)()")
            return .number(Self.trigonometric(f == "sin", degrees: a))
        case "abs": return .number(Swift.abs(try number(args[0], "the argument of abs()")))
        case "floor": return .number((try number(args[0], "the argument of floor()")).rounded(.down))
        case "round": return .number((try number(args[0], "the argument of round()")).rounded(.toNearestOrAwayFromZero))
        case "str":
            let v = try evaluate(args[0])
            if case .string = v { return v }
            guard let k = v.integer else { throw ExpressionError("str() takes an integer or a string, not \(v)", at: args[0].at) }
            return .string(String(k))
        case "first", "last":
            let k = try integer(args[0], "the count of \(f)()")
            let s = try selection(args[1], "the second argument of \(f)()")
            guard k >= 0, k <= s.count else {
                throw ExpressionError("\(f)(\(k), …) asks for \(k) of \(s.count) instance\(s.count == 1 ? "" : "s")", at: at)
            }
            return .selection(DocumentSelection(f == "first" ? Array(s.instances.prefix(k)) : Array(s.instances.suffix(k))))
        case "slice":
            let s = try selection(args[0], "the first argument of slice()")
            let start = try integer(args[1], "the start of slice()")
            let k = try integer(args[2], "the count of slice()")
            guard start >= 0, k >= 0, start + k <= s.count else {
                throw ExpressionError("slice(…, \(start), \(k)) is outside a selection of \(s.count)", at: at)
            }
            return .selection(DocumentSelection(Array(s.instances[start..<(start + k)])))
        case "whole":
            let s = try selection(args[0], "the argument of whole()")
            return .selection(DocumentSelection(s.instances.filter { $0.part == nil && scope.isWhole($0) }))
        case "start", "end":
            guard case let .name(action) = args[0].kind else {
                throw ExpressionError("\(f)() takes an action's name, not an expression", at: args[0].at)
            }
            return .number(try scope.time(f, of: action, at: at))
        case "split":
            let s = try selection(args[0], "the argument of split()")
            guard s.count == 1, let one = s.instances.first, one.part == nil,
                let el = scope.element(one.element), el.kind == "ten" || el.kind == "stick"
            else {
                throw ExpressionError("split() takes a selection of one ten or stick, not \(s)", at: at)
            }
            return .placement(DocumentPlacement(source: one))
        default:
            throw ExpressionError("unknown function '\(f)'", at: at)
        }
    }

    /// The sine or cosine of an angle in degrees (section 6.4): the angle is reduced modulo 360
    /// first, and the value is exactly 0, 0.5, -0.5, 1 or -1 at the multiples of 30 where it is
    /// those; elsewhere it is the platform's.
    static func trigonometric(_ sine: Bool, degrees: Double) -> Double {
        let r = degrees - 360 * (degrees / 360).rounded(.down)
        // The sine at each multiple of 30 from 0 to 330, where it is exact; nil where it is not.
        let exact: [Double?] = [0, 0.5, nil, 1, nil, 0.5, 0, -0.5, nil, -1, nil, -0.5]
        if r.truncatingRemainder(dividingBy: 30) == 0 {
            let k = Int(r / 30) % 12
            if let v = exact[sine ? k : (k + 3) % 12] { return v }
        }
        let radians = r * Double.pi / 180
        return sine ? Foundation.sin(radians) : Foundation.cos(radians)
    }

    private func index(_ base: ExpressionNode, _ k: ExpressionNode, at: Int) throws(ExpressionError) -> DocumentValue {
        let s = try selection(base, "what is indexed")
        let i = try integer(k, "the index")
        let families = Set(s.instances.map(\.element))
        if case let .name(name) = base.kind, let el = scope.element(name), !el.repeated {
            throw ExpressionError("\(name) has no repeat, so it cannot be indexed", at: at)
        }
        guard families.count <= 1, s.instances.allSatisfy({ $0.part == nil && $0.index != nil }) else {
            throw ExpressionError("only one element's instances can be indexed, not \(s)", at: at)
        }
        guard let hit = s.instances.first(where: { $0.index == i }) else {
            let name: String
            if case let .name(n) = base.kind { name = n } else { name = families.first ?? "an empty selection" }
            let total = families.first.flatMap { scope.element($0)?.count }
            throw ExpressionError("\(name)[\(i)] is outside \(name)" + (total.map { " (\($0) instance\($0 == 1 ? "" : "s"))" } ?? ""), at: at)
        }
        return .selection(DocumentSelection([hit]))
    }

    private func member(_ base: ExpressionNode, _ m: String, at: Int) throws(ExpressionError) -> DocumentValue {
        let s = try selection(base, "what '.\(m)' is taken of")
        var out: [DocumentInstance] = []
        for inst in s.instances {
            guard inst.part == nil, let el = scope.element(inst.element) else {
                throw ExpressionError("\(inst) has no sub-part '\(m)'", at: at)
            }
            if m == "cross" {
                guard el.isPiece else { throw ExpressionError("\(inst) is not a piece, so it has no cross-out", at: at) }
                out.append(DocumentInstance(inst.element, inst.index, part: .cross))
            } else {
                guard el.kind == "text", el.runs.contains(m) else {
                    throw ExpressionError("\(inst.element) has no run '\(m)'", at: at)
                }
                out.append(DocumentInstance(inst.element, inst.index, part: .run(m)))
            }
        }
        return .selection(DocumentSelection(out))
    }
}
