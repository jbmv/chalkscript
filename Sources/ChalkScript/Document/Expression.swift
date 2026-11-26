import Foundation

/// An expression of the explainer format (EXP-19, section 6 of the format's reference), parsed:
/// a value computed from the problem, such as `div(a, 10)`, `aO < bO` or `last(bT, whole(ten))`.
/// Expressions have no side effects and no loops, so every evaluation ends.
public struct DocumentExpression: Equatable, Sendable, CustomStringConvertible {
    /// The text as the document gives it; a number or truth value written as JSON is kept as its
    /// literal.
    public var source: String
    public var root: ExpressionNode

    public static let maxNodes = 256
    public static let maxDepth = 24

    /// Parses `source`, refusing a syntax error and an expression over the format's limits.
    public init(_ source: String) throws(ExpressionError) {
        self.source = source
        var p = ExpressionParser(source)
        root = try p.parse()
        if root.nodeCount > Self.maxNodes {
            throw ExpressionError("the expression has \(root.nodeCount) nodes, more than \(Self.maxNodes)", at: 0)
        }
        if root.depth > Self.maxDepth {
            throw ExpressionError("the expression is nested \(root.depth) deep, more than \(Self.maxDepth)", at: 0)
        }
    }

    /// A literal number or truth value, as a document writes one in JSON.
    public init(literal value: DocumentValue) {
        source = value.description
        switch value {
        case let .number(n): root = ExpressionNode(.number(n), at: 0)
        case let .truth(b): root = ExpressionNode(.truth(b), at: 0)
        case let .string(s): root = ExpressionNode(.string(s), at: 0)
        default: root = ExpressionNode(.truth(false), at: 0)
        }
    }

    public var description: String { source }
}

/// A node of a parsed expression, with the offset of its first character (for an operator, of
/// the operator), in Unicode code points from 0.
public struct ExpressionNode: Equatable, Sendable {
    public indirect enum Kind: Equatable, Sendable {
        case number(Double)
        case string(String)
        case truth(Bool)
        case name(String)
        case negate(ExpressionNode)
        case not(ExpressionNode)
        case binary(BinaryOperator, ExpressionNode, ExpressionNode)
        case conditional(ExpressionNode, ExpressionNode, ExpressionNode)
        case call(String, [ExpressionNode])
        case index(ExpressionNode, ExpressionNode)
        case member(ExpressionNode, String)
    }

    public enum BinaryOperator: String, Sendable {
        case or, and
        case equal = "==", notEqual = "!=", less = "<", lessOrEqual = "<=", greater = ">", greaterOrEqual = ">="
        case add = "+", subtract = "-", multiply = "*", divide = "/"
    }

    public var kind: Kind
    public var at: Int

    public init(_ kind: Kind, at: Int) {
        self.kind = kind
        self.at = at
    }

    public var children: [ExpressionNode] {
        switch kind {
        case .number, .string, .truth, .name: []
        case let .negate(a), let .not(a), let .member(a, _): [a]
        case let .binary(_, a, b), let .index(a, b): [a, b]
        case let .conditional(c, a, b): [c, a, b]
        case let .call(_, args): args
        }
    }

    public var nodeCount: Int { 1 + children.reduce(0) { $0 + $1.nodeCount } }
    public var depth: Int { 1 + (children.map(\.depth).max() ?? 0) }

    /// Every node of the tree, this one first.
    public func walk(_ visit: (ExpressionNode) -> Void) {
        visit(self)
        for c in children { c.walk(visit) }
    }
}

/// A syntax or evaluation error inside an expression, at an offset in Unicode code points.
public struct ExpressionError: Error, Equatable, Sendable {
    public var message: String
    public var at: Int

    public init(_ message: String, at: Int) {
        self.message = message
        self.at = at
    }
}

/// The functions of section 6.4, with how many arguments each takes.
public enum ExpressionFunction {
    public static let arity: [String: ClosedRange<Int>] = [
        "div": 2...2, "mod": 2...2, "min": 2...Int.max, "max": 2...Int.max, "abs": 1...1, "floor": 1...1,
        "round": 1...1, "str": 1...1, "first": 2...2, "last": 2...2, "slice": 3...3, "whole": 1...1,
        "start": 1...1, "end": 1...1, "split": 1...1,
    ]

    /// Functions a capability adds, by capability.
    public static let capability: [String: String] = ["split": "components.arithmetic"]

    public static let keywords: Set<String> = ["and", "or", "not", "true", "false"]
}

private struct ExpressionParser {
    enum Token: Equatable {
        case number(Double)
        case string(String)
        case name(String)
        case keyword(String)
        case symbol(String)
        case end
    }

    var tokens: [(Token, Int)] = []
    var k = 0
    var nesting = 0
    let length: Int
    var lexError: ExpressionError?

    init(_ source: String) {
        let s = Array(source.unicodeScalars)
        length = s.count
        var i = 0
        func isDigit(_ c: Unicode.Scalar) -> Bool { ("0"..."9").contains(c) }
        func isLetter(_ c: Unicode.Scalar) -> Bool { ("a"..."z").contains(c) || ("A"..."Z").contains(c) }
        while i < s.count {
            let c = s[i]
            if [" ", "\t", "\r", "\n"].contains(c) {
                i += 1
                continue
            }
            let start = i
            if isDigit(c) {
                while i < s.count, isDigit(s[i]) { i += 1 }
                if i + 1 < s.count, s[i] == ".", isDigit(s[i + 1]) {
                    i += 1
                    while i < s.count, isDigit(s[i]) { i += 1 }
                }
                let text = String(String.UnicodeScalarView(s[start..<i]))
                tokens.append((.number(Double(text)!), start))
            } else if isLetter(c) {
                while i < s.count, isLetter(s[i]) || isDigit(s[i]) { i += 1 }
                let word = String(String.UnicodeScalarView(s[start..<i]))
                tokens.append((ExpressionFunction.keywords.contains(word) ? .keyword(word) : .name(word), start))
            } else if c == "'" {
                i += 1
                while i < s.count, s[i] != "'" { i += 1 }
                guard i < s.count else {
                    lexError = ExpressionError("a string is not closed with '", at: start)
                    break
                }
                tokens.append((.string(String(String.UnicodeScalarView(s[(start + 1)..<i]))), start))
                i += 1
            } else {
                let two = i + 1 < s.count ? String(c) + String(s[i + 1]) : ""
                if ["==", "!=", "<=", ">="].contains(two) {
                    tokens.append((.symbol(two), start))
                    i += 2
                } else if "+-*/()[],?:.<>".unicodeScalars.contains(c) {
                    tokens.append((.symbol(String(c)), start))
                    i += 1
                } else {
                    lexError = ExpressionError("unexpected character '\(c)'", at: start)
                    break
                }
            }
        }
        tokens.append((.end, s.count))
    }

    var token: Token { tokens[k].0 }
    var offset: Int { tokens[k].1 }

    func describe(_ t: Token) -> String {
        switch t {
        case let .number(n): "the number \(Canonical.number(n))"
        case let .string(s): "the string '\(s)'"
        case let .name(n): "'\(n)'"
        case let .keyword(w): "'\(w)'"
        case let .symbol(s): "'\(s)'"
        case .end: "the end of the expression"
        }
    }

    mutating func expect(_ symbol: String) throws(ExpressionError) {
        guard token == .symbol(symbol) else {
            throw ExpressionError("expected '\(symbol)' but found \(describe(token))", at: offset)
        }
        k += 1
    }

    mutating func parse() throws(ExpressionError) -> ExpressionNode {
        if let lexError { throw lexError }
        if token == .end { throw ExpressionError("the expression is empty", at: 0) }
        let e = try conditional()
        guard token == .end else { throw ExpressionError("unexpected \(describe(token))", at: offset) }
        return e
    }

    mutating func enter() throws(ExpressionError) {
        nesting += 1
        // Parentheses add no nodes, so the parser bounds its own recursion as well.
        if nesting > 4 * DocumentExpression.maxDepth {
            throw ExpressionError("the expression is nested too deeply", at: offset)
        }
    }

    mutating func conditional() throws(ExpressionError) -> ExpressionNode {
        try enter()
        defer { nesting -= 1 }
        let c = try or()
        guard token == .symbol("?") else { return c }
        let at = offset
        k += 1
        let a = try conditional()
        try expect(":")
        let b = try conditional()
        return ExpressionNode(.conditional(c, a, b), at: at)
    }

    mutating func or() throws(ExpressionError) -> ExpressionNode {
        var e = try and()
        while token == .keyword("or") {
            let at = offset
            k += 1
            e = ExpressionNode(.binary(.or, e, try and()), at: at)
        }
        return e
    }

    mutating func and() throws(ExpressionError) -> ExpressionNode {
        var e = try not()
        while token == .keyword("and") {
            let at = offset
            k += 1
            e = ExpressionNode(.binary(.and, e, try not()), at: at)
        }
        return e
    }

    mutating func not() throws(ExpressionError) -> ExpressionNode {
        guard token == .keyword("not") else { return try comparison() }
        let at = offset
        k += 1
        try enter()
        defer { nesting -= 1 }
        return ExpressionNode(.not(try not()), at: at)
    }

    static let comparisons: [String: ExpressionNode.BinaryOperator] = [
        "==": .equal, "!=": .notEqual, "<": .less, "<=": .lessOrEqual, ">": .greater, ">=": .greaterOrEqual,
    ]

    mutating func comparison() throws(ExpressionError) -> ExpressionNode {
        let a = try sum()
        guard case let .symbol(s) = token, let op = Self.comparisons[s] else { return a }
        let at = offset
        k += 1
        let b = try sum()
        if case let .symbol(s2) = token, Self.comparisons[s2] != nil {
            throw ExpressionError("comparisons do not chain: group them with 'and'", at: offset)
        }
        return ExpressionNode(.binary(op, a, b), at: at)
    }

    mutating func sum() throws(ExpressionError) -> ExpressionNode {
        var e = try product()
        while token == .symbol("+") || token == .symbol("-") {
            let op: ExpressionNode.BinaryOperator = token == .symbol("+") ? .add : .subtract
            let at = offset
            k += 1
            e = ExpressionNode(.binary(op, e, try product()), at: at)
        }
        return e
    }

    mutating func product() throws(ExpressionError) -> ExpressionNode {
        var e = try unary()
        while token == .symbol("*") || token == .symbol("/") {
            let op: ExpressionNode.BinaryOperator = token == .symbol("*") ? .multiply : .divide
            let at = offset
            k += 1
            e = ExpressionNode(.binary(op, e, try unary()), at: at)
        }
        return e
    }

    mutating func unary() throws(ExpressionError) -> ExpressionNode {
        guard token == .symbol("-") else { return try postfix() }
        let at = offset
        k += 1
        try enter()
        defer { nesting -= 1 }
        return ExpressionNode(.negate(try unary()), at: at)
    }

    mutating func postfix() throws(ExpressionError) -> ExpressionNode {
        var e = try primary()
        while true {
            if token == .symbol("[") {
                let at = offset
                k += 1
                let index = try conditional()
                try expect("]")
                e = ExpressionNode(.index(e, index), at: at)
            } else if token == .symbol(".") {
                let at = offset
                k += 1
                guard case let .name(m) = token else {
                    throw ExpressionError("expected a name after '.' but found \(describe(token))", at: offset)
                }
                k += 1
                e = ExpressionNode(.member(e, m), at: at)
            } else {
                return e
            }
        }
    }

    mutating func primary() throws(ExpressionError) -> ExpressionNode {
        let at = offset
        switch token {
        case let .number(n):
            k += 1
            return ExpressionNode(.number(n), at: at)
        case let .string(s):
            k += 1
            return ExpressionNode(.string(s), at: at)
        case .keyword("true"), .keyword("false"):
            let b = token == .keyword("true")
            k += 1
            return ExpressionNode(.truth(b), at: at)
        case let .name(n):
            k += 1
            guard token == .symbol("(") else { return ExpressionNode(.name(n), at: at) }
            k += 1
            var args: [ExpressionNode] = []
            if token != .symbol(")") {
                args.append(try conditional())
                while token == .symbol(",") {
                    k += 1
                    args.append(try conditional())
                }
            }
            try expect(")")
            return ExpressionNode(.call(n, args), at: at)
        case .symbol("("):
            k += 1
            let e = try conditional()
            try expect(")")
            return e
        default:
            throw ExpressionError("unexpected \(describe(token))", at: at)
        }
    }
}
