import Foundation
@testable import ChalkScript

/// The example documents beside the format's reference (EXP-19), and a small document to
/// change one key at a time.
enum DocumentFixture {
    static let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/format/examples")

    static func data(_ name: String) -> Data { (try? Data(contentsOf: examples.appendingPathComponent(name))) ?? Data() }

    static let subtraction = ExplainerDocument.read(data("subtraction.explainer")).document!
    static let equalGroups = ExplainerDocument.read(data("equal-groups.explainer")).document!

    /// A conforming document with one parameter, one text element and one step.
    static let tiny: JSONValue = try! JSONValue.parse(#"""
        {
          "format": "chalkscript-explainer", "version": "1.0", "id": "tiny", "title": "Tiny", "sourceLocale": "en-US",
          "params": { "a": { "type": "int", "min": 1, "max": 3 } },
          "let": { "twice": "a * 2" },
          "samples": [{ "a": 1 }],
          "elements": {
            "label": { "kind": "text", "at": [10, 20], "text": "label" },
            "rule": { "kind": "line", "from": [0, 0], "to": ["twice * 10", 0], "start": { "progress": 0 } }
          },
          "sequence": ["show"],
          "steps": {
            "show": { "say": "show", "actions": {
              "in": { "do": "appear", "target": "label" },
              "draw": { "do": "draw", "target": "rule", "at": "end(in)" }
            } }
          },
          "wording": { "en-US": {
            "shared": { "label": { "text": "{a}", "visual": true } },
            "plain": { "show": "This is {a}, and twice it is {twice}." }
          } }
        }
        """#)

    static func values(_ pairs: (String, Double)...) -> [String: DocumentValue] {
        Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, .number($0.1)) })
    }
}

extension JSONValue {
    /// The value with what is at `pointer` replaced by `value`, or removed when it is nil. An
    /// array index one past the end appends.
    func setting(_ pointer: String, _ value: JSONValue?) -> JSONValue {
        let tokens = pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
            .map { $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~") }
        return Self.set(self, tokens[...], value)
    }

    private static func set(_ v: JSONValue, _ tokens: ArraySlice<String>, _ value: JSONValue?) -> JSONValue {
        guard let first = tokens.first else { return value ?? .null }
        switch v {
        case var .object(o):
            if tokens.count == 1 {
                o[first] = value
            } else {
                o[first] = set(o[first] ?? .object(JSONObject()), tokens.dropFirst(), value)
            }
            return .object(o)
        case var .array(a):
            guard let i = Int(first), i <= a.count else { return v }
            if tokens.count == 1 {
                if let value { if i == a.count { a.append(value) } else { a[i] = value } } else if i < a.count { a.remove(at: i) }
            } else if i < a.count {
                a[i] = set(a[i], tokens.dropFirst(), value)
            }
            return .array(a)
        default:
            return v
        }
    }

    var data: Data { Data(Canonical.form(self).utf8) }

    /// Every JSON Pointer in the value, depth first.
    var pointers: [String] {
        var out: [String] = []
        func visit(_ v: JSONValue, _ p: String) {
            out.append(p)
            switch v {
            case let .object(o): for (k, x) in o.entries { visit(x, DocumentPath.join(p, k)) }
            case let .array(a): for (k, x) in a.enumerated() { visit(x, p + "/\(k)") }
            default: break
            }
        }
        visit(self, "")
        return out
    }
}

func read(_ json: JSONValue) -> DocumentReading { ExplainerDocument.read(json.data) }
func read(_ text: String) -> DocumentReading { ExplainerDocument.read(Data(text.utf8)) }
