#if os(macOS)
import ChalkScript
import ChalkScriptMCP
import Foundation

/// Conversion between the engine's JSON values and the protocol's, keeping the order of keys.
enum Bridge {
    static func wire(_ value: DocJSON) -> WireJSON {
        switch value {
        case .null: return .null
        case let .bool(b): return .bool(b)
        case let .number(n): return .number(Canonical.number(n))
        case let .string(s): return .string(s)
        case let .array(a): return .array(a.map(wire))
        case let .object(o):
            var out = WireObject()
            for (k, v) in o.entries { out[k] = wire(v) }
            return .object(out)
        }
    }

    /// Nil when a number's text is not a finite double.
    static func doc(_ value: WireJSON) -> DocJSON? {
        switch value {
        case .null: return .null
        case let .bool(b): return .bool(b)
        case let .number(text):
            guard let n = Double(text), n.isFinite else { return nil }
            return .number(n)
        case let .string(s): return .string(s)
        case let .array(a):
            var out: [DocJSON] = []
            for x in a {
                guard let d = doc(x) else { return nil }
                out.append(d)
            }
            return .array(out)
        case let .object(o):
            var pairs: [(String, DocJSON)] = []
            for m in o.members {
                guard let d = doc(m.value) else { return nil }
                pairs.append((m.key, d))
            }
            return .object(DocObject(pairs))
        }
    }
}

/// The text a studio writes for a document: two-space indentation, the keys in the order the
/// document holds them, and an object or array kept on one line when it fits in `width`
/// columns, so that a file an author laid out by hand stays close to its layout after an edit.
enum DocumentText {
    static let width = 100

    static func format(_ value: DocJSON) -> String {
        var out = ""
        write(value, indent: 0, column: 0, into: &out)
        return out + "\n"
    }

    static func write(_ value: DocJSON, indent: Int, column: Int, into out: inout String) {
        let flat = compact(value)
        let isContainer: Bool
        switch value {
        case let .array(a): isContainer = !a.isEmpty
        case let .object(o): isContainer = !o.isEmpty
        default: isContainer = false
        }
        if !isContainer || column + flat.count <= width {
            out += flat
            return
        }
        let pad = String(repeating: " ", count: indent + 2)
        switch value {
        case let .array(a):
            out += "[\n"
            for (i, x) in a.enumerated() {
                out += pad
                write(x, indent: indent + 2, column: indent + 2, into: &out)
                out += i < a.count - 1 ? ",\n" : "\n"
            }
            out += String(repeating: " ", count: indent) + "]"
        case let .object(o):
            out += "{\n"
            let entries = o.entries
            for (i, e) in entries.enumerated() {
                let key = quoted(e.key) + ": "
                out += pad + key
                write(e.value, indent: indent + 2, column: indent + 2 + key.count, into: &out)
                out += i < entries.count - 1 ? ",\n" : "\n"
            }
            out += String(repeating: " ", count: indent) + "}"
        default:
            out += flat
        }
    }

    /// The value on one line, with a space after each comma and colon, and inside braces.
    static func compact(_ value: DocJSON) -> String {
        switch value {
        case .null: return "null"
        case let .bool(b): return b ? "true" : "false"
        case let .number(n): return Canonical.number(n)
        case let .string(s): return quoted(s)
        case let .array(a): return "[" + a.map(compact).joined(separator: ", ") + "]"
        case let .object(o):
            if o.isEmpty { return "{}" }
            return "{ " + o.entries.map { quoted($0.key) + ": " + compact($0.value) }.joined(separator: ", ") + " }"
        }
    }

    /// A JSON string literal: only what RFC 8259 requires is escaped, so that the document's
    /// symbols, such as × and −, stay readable.
    static func quoted(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 {
                    out += String(format: "\\u%04x", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out + "\""
    }
}

/// Where each value of a JSON text begins, by JSON Pointer: the line, from 1, so that a finding
/// can be found in the file. A text that is not JSON gives what was read before the fault.
enum LineIndex {
    static func lines(of text: String) -> [String: Int] {
        var scanner = Scanner(Array(text.utf8))
        var out: [String: Int] = [:]
        scanner.value(at: "", into: &out)
        return out
    }

    struct Scanner {
        let bytes: [UInt8]
        var i = 0
        var line = 1

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipSpace() {
            while i < bytes.count {
                switch bytes[i] {
                case 0x0A: line += 1; i += 1
                case 0x20, 0x09, 0x0D: i += 1
                default: return
                }
            }
        }

        /// Reads one value, recording where it and everything inside it begin. False on a fault.
        @discardableResult
        mutating func value(at pointer: String, into out: inout [String: Int]) -> Bool {
            skipSpace()
            guard i < bytes.count else { return false }
            out[pointer] = line
            switch bytes[i] {
            case UInt8(ascii: "{"):
                i += 1
                skipSpace()
                if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return true }
                while true {
                    skipSpace()
                    guard let key = string() else { return false }
                    skipSpace()
                    guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { return false }
                    i += 1
                    let escaped = key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
                    guard value(at: pointer + "/" + escaped, into: &out) else { return false }
                    skipSpace()
                    guard i < bytes.count else { return false }
                    if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    if bytes[i] == UInt8(ascii: "}") { i += 1; return true }
                    return false
                }
            case UInt8(ascii: "["):
                i += 1
                skipSpace()
                if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return true }
                var k = 0
                while true {
                    guard value(at: pointer + "/\(k)", into: &out) else { return false }
                    k += 1
                    skipSpace()
                    guard i < bytes.count else { return false }
                    if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    if bytes[i] == UInt8(ascii: "]") { i += 1; return true }
                    return false
                }
            case UInt8(ascii: "\""):
                return string() != nil
            default:
                // A number, true, false or null: up to the next delimiter.
                while i < bytes.count, !",]} \n\r\t".utf8.contains(bytes[i]) { i += 1 }
                return true
            }
        }

        mutating func string() -> String? {
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { return nil }
            i += 1
            let start = i
            var escaped = false
            while i < bytes.count {
                let b = bytes[i]
                if escaped {
                    escaped = false
                } else if b == UInt8(ascii: "\\") {
                    escaped = true
                } else if b == UInt8(ascii: "\"") {
                    let raw = Array(bytes[start..<i])
                    i += 1
                    // Names in a document need no escapes (section 3); decode the rare one that has.
                    if raw.contains(UInt8(ascii: "\\")),
                       let v = try? DocJSON.parse(Data([UInt8(ascii: "\"")] + raw + [UInt8(ascii: "\"")])), let s = v.string {
                        return s
                    }
                    return String(decoding: raw, as: UTF8.self)
                }
                i += 1
            }
            return nil
        }
    }
}
#endif
