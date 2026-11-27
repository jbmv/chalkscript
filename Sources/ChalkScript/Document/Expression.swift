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

    // These walk the tree without recursion, since a tree is measured before its size is known
    // to be within the format's limits.

    public var nodeCount: Int {
        var n = 0
        var stack = [self]
        while let x = stack.popLast() {
            n += 1
            stack += x.children
        }
        return n
    }

    public var depth: Int {
        var best = 0
        var stack = [(self, 1)]
        while let (x, d) = stack.popLast() {
            best = max(best, d)
            for c in x.children { stack.append((c, d + 1)) }
        }
        return best
    }

    /// Every node of the tree, this one first.
    public func walk(_ visit: (ExpressionNode) -> Void) {
        var stack = [self]
        while let x = stack.popLast() {
            visit(x)
            stack += x.children.reversed()
        }
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
        "start": 1...1, "end": 1...1, "split": 1...1, "sin": 1...1, "cos": 1...1,
    ]

    /// Functions added after the first draft of the format. A name is reserved (section 3) only
    /// if it was a function in the first draft, so that a document with an element or a value
    /// named `sin` keeps its meaning; a call always names a function and a bare name never does.
    public static let added: Set<String> = ["sin", "cos"]

    /// What a function's argument is, where an agent could take it for something else: the
    /// angle of `sin` and `cos` is in degrees.
    static let argument: [String: String] = ["sin": "an angle in degrees", "cos": "an angle in degrees"]

    /// The message for a call to `f` with `count` arguments, which it does not take.
    static func wrongCount(_ f: String, _ arity: ClosedRange<Int>, _ count: Int) -> String {
        let want = arity.upperBound == Int.max ? "\(arity.lowerBound) or more" : "\(arity.lowerBound)"
        let plural = arity.lowerBound == 1 && arity.upperBound == 1 ? "" : "s"
        let what = argument[f].map { ", \($0)," } ?? ""
        return "\(f)() takes \(want) argument\(plural)\(what) not \(count)"
    }

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
        if lexError == nil, tokens.count > Self.maxTokens {
            lexError = ExpressionError("the expression has more than \(Self.maxTokens) tokens", at: tokens[Self.maxTokens].1)
        }
    }

    /// More tokens than any expression within the format's limits needs.
    static let maxTokens = 2048

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
        let e = try expression(Self.conditionalLevel)
        guard token == .end else { throw ExpressionError("unexpected \(describe(token)) after a complete expression", at: offset) }
        return e
    }

    // The grammar's levels, loosest first. The parser climbs them (precedence climbing) rather
    // than calling one function per level, so that each level of nesting costs few stack frames.
    static let conditionalLevel = 1
    static let notLevel = 4
    static let comparisonLevel = 5
    static let unaryLevel = 8

    static let comparisons: [String: ExpressionNode.BinaryOperator] = [
        "==": .equal, "!=": .notEqual, "<": .less, "<=": .lessOrEqual, ">": .greater, ">=": .greaterOrEqual,
    ]

    /// The binary operator at the current token, with its level.
    var binary: (ExpressionNode.BinaryOperator, Int)? {
        switch token {
        case .keyword("or"): (.or, 2)
        case .keyword("and"): (.and, 3)
        case .symbol("+"): (.add, 6)
        case .symbol("-"): (.subtract, 6)
        case .symbol("*"): (.multiply, 7)
        case .symbol("/"): (.divide, 7)
        case let .symbol(s): Self.comparisons[s].map { ($0, Self.comparisonLevel) }
        default: nil
        }
    }

    mutating func enter() throws(ExpressionError) {
        nesting += 1
        // Parentheses add no nodes, so the parser bounds its own recursion as well.
        if nesting > 2 * DocumentExpression.maxDepth {
            throw ExpressionError("the expression is nested too deeply", at: offset)
        }
    }

    /// An expression whose operators are all at `level` or tighter.
    mutating func expression(_ level: Int) throws(ExpressionError) -> ExpressionNode {
        try enter()
        defer { nesting -= 1 }
        var left: ExpressionNode
        let at = offset
        if token == .keyword("not") {
            // not = "not" not | comparison: it cannot stand where a sum or tighter is expected.
            guard level <= Self.notLevel else { throw ExpressionError("expected a value but found 'not'", at: at) }
            k += 1
            left = ExpressionNode(.not(try expression(Self.notLevel)), at: at)
        } else if token == .symbol("-") {
            k += 1
            left = ExpressionNode(.negate(try expression(Self.unaryLevel)), at: at)
        } else {
            left = try postfix()
        }
        while true {
            if token == .symbol("?") {
                guard level <= Self.conditionalLevel else { return left }
                let q = offset
                k += 1
                let a = try expression(Self.conditionalLevel)
                try expect(":")
                let b = try expression(Self.conditionalLevel)
                left = ExpressionNode(.conditional(left, a, b), at: q)
                continue
            }
            guard let (op, opLevel) = binary, opLevel >= level, level < Self.unaryLevel else { return left }
            let o = offset
            k += 1
            let right = try expression(opLevel + 1)
            left = ExpressionNode(.binary(op, left, right), at: o)
            if opLevel == Self.comparisonLevel, let (_, next) = binary, next == Self.comparisonLevel {
                throw ExpressionError("comparisons do not chain: group them with 'and'", at: offset)
            }
        }
    }

    mutating func postfix() throws(ExpressionError) -> ExpressionNode {
        var e = try primary()
        while true {
            if token == .symbol("[") {
                let at = offset
                k += 1
                let index = try expression(Self.conditionalLevel)
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
                args.append(try expression(Self.conditionalLevel))
                while token == .symbol(",") {
                    k += 1
                    args.append(try expression(Self.conditionalLevel))
                }
            }
            try expect(")")
            return ExpressionNode(.call(n, args), at: at)
        case .symbol("("):
            k += 1
            let e = try expression(Self.conditionalLevel)
            try expect(")")
            return e
        default:
            throw ExpressionError("expected a value but found \(describe(token))", at: at)
        }
    }
}
