import Foundation

// The problem (EXP-2, section 5 of the format's reference): checking one against the
// parameters, and enumerating the problem space.

/// Checks a problem against a document's parameters.
enum ProblemCheck {
    struct Problem {
        var path: String
        var message: String
    }

    /// Scope for evaluating a parameter's bounds: the other parameters' values.
    struct BoundsScope: EvaluationScope {
        var values: [String: DocumentValue]
        func value(of name: String) throws(ExpressionError) -> DocumentValue? { values[name] }
        func element(_ name: String) -> ScopeElement? { nil }
        func isWhole(_ instance: DocumentInstance) -> Bool { true }
        func time(_ function: String, of action: String, at: Int) throws(ExpressionError) -> Double {
            throw ExpressionError("\(function)() is not available here", at: at)
        }
    }

    /// The problems with `values`: a missing, extra, mistyped or out-of-range value (section 5.1).
    static func check(_ values: [String: DocumentValue], params: JSONObject, expressions: [String: DocumentExpression]) -> [Problem] {
        var out: [Problem] = []
        for key in values.keys.sorted() where params[key] == nil {
            out.append(Problem(path: DocumentPath.escape(key), message: "there is no parameter '\(key)'"))
        }
        let eval = Evaluator(scope: BoundsScope(values: values))
        for (name, p) in params.entries {
            guard let v = values[name] else {
                out.append(Problem(path: "", message: "the problem gives no value for '\(name)'"))
                continue
            }
            let type = p["type"]?.string ?? ""
            switch (type, v) {
            case ("int", .number), ("number", .number):
                guard case let .number(x) = v else { break }
                if type == "int" && v.integer == nil {
                    out.append(Problem(path: name, message: "\(name) is \(v), not an integer"))
                    continue
                }
                for (key, lower) in [("min", true), ("max", false)] {
                    let path = DocumentPath.join("/params", name, key)
                    guard let e = expressions[path] else { continue }
                    let bound: DocumentValue
                    do { bound = try eval.evaluate(e) } catch {
                        out.append(Problem(path: name, message: "\(name)'s \(key) cannot be evaluated: \(error.message)"))
                        continue
                    }
                    guard case let .number(b) = bound else {
                        out.append(Problem(path: name, message: "\(name)'s \(key) is \(bound.typeName), not a number"))
                        continue
                    }
                    if lower ? x < b : x > b {
                        out.append(Problem(path: name, message: "\(name) is \(v), \(lower ? "below its min" : "above its max") \(Canonical.number(b))"))
                    }
                }
            case ("bool", .truth):
                break
            case ("choice", _):
                let allowed = p["values"]?.array?.compactMap { DocumentValue(json: $0) } ?? []
                if !allowed.contains(v) { out.append(Problem(path: name, message: "\(name) is \(v), which is not one of its values")) }
            default:
                out.append(Problem(path: name, message: "\(name) is \(v.typeName), not a value of type \(type)"))
            }
        }
        return out
    }
}

extension ExplainerDocument {
    /// The parameters in parameter order (section 5.1): each after every parameter its bounds
    /// name, and otherwise by name in code point order.
    public var parameterOrder: [String] {
        let names = parameterNames
        var deps: [String: Set<String>] = [:]
        for n in names {
            var d = Set<String>()
            for key in ["min", "max"] {
                expressions[DocumentPath.join("/params", n, key)]?.root.walk { if case let .name(x) = $0.kind { d.insert(x) } }
            }
            deps[n] = d.intersection(names)
        }
        var out: [String] = []
        var left = Set(names)
        while !left.isEmpty {
            let ready = left.filter { deps[$0]!.isSubset(of: Set(out)) }
            guard let next = ready.min(by: { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) })
            else {
                // A cycle among the bounds, which reading reports; the rest by name.
                out += left.sorted()
                break
            }
            out.append(next)
            left.remove(next)
        }
        return out
    }

    /// Checks a problem against the parameters, giving a `range` finding for each value that is
    /// missing, extra, mistyped or out of range.
    public func check(problem values: [String: DocumentValue]) -> [DocumentFinding] {
        ProblemCheck.check(values, params: root["params"]?.object ?? JSONObject(), expressions: expressions).map {
            DocumentFinding(.error, .range, DocumentPath.join("/params", $0.path), values: values, $0.message)
        }
    }

    /// Every problem the parameters allow, in parameter order (section 5.1); nil when a `number`
    /// parameter makes the space infinite, or when it would hold more than `limit` problems.
    public func problemSpace(limit: Int = 1_000_000) -> [[String: DocumentValue]]? {
        let order = parameterOrder
        let params = root["params"]?.object ?? JSONObject()
        var out: [[String: DocumentValue]] = []
        var current: [String: DocumentValue] = [:]
        var overflow = false
        func values(of name: String) -> [DocumentValue]? {
            guard let p = params[name]?.object else { return nil }
            switch p["type"]?.string {
            case "bool": return [.truth(false), .truth(true)]
            case "choice": return p["values"]?.array?.compactMap { DocumentValue(json: $0) }
            case "int":
                let eval = Evaluator(scope: ProblemCheck.BoundsScope(values: current))
                guard let lo = expressions[DocumentPath.join("/params", name, "min")].flatMap({ try? eval.evaluate($0) }),
                    let hi = expressions[DocumentPath.join("/params", name, "max")].flatMap({ try? eval.evaluate($0) }),
                    case let .number(a) = lo, case let .number(b) = hi
                else { return nil }
                let from = Int(a.rounded(.up))
                let to = Int(b.rounded(.down))
                return from <= to ? (from...to).map { .number(Double($0)) } : []
            default: return nil
            }
        }
        func visit(_ k: Int) -> Bool {
            if k == order.count {
                out.append(current)
                if out.count > limit { overflow = true }
                return !overflow
            }
            guard let vs = values(of: order[k]) else { return false }
            for v in vs {
                current[order[k]] = v
                if !visit(k + 1) { return false }
            }
            current[order[k]] = nil
            return true
        }
        guard visit(0), !overflow else { return nil }
        return out
    }
}
