import Foundation

/// A JSON value (RFC 8259) as an explainer document holds it (EXP-19), with each object's keys in
/// the order the file gives them, so that a tool can keep the author's layout.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    public subscript(key: String) -> JSONValue? {
        if case let .object(o) = self { return o[key] }
        return nil
    }

    public var object: JSONObject? {
        if case let .object(o) = self { return o }
        return nil
    }

    public var string: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    public var array: [JSONValue]? {
        if case let .array(a) = self { return a }
        return nil
    }

    /// The JSON type's name, for a finding's message.
    public var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "a boolean"
        case .number: "a number"
        case .string: "a string"
        case .array: "an array"
        case .object: "an object"
        }
    }

    /// The value at JSON Pointer `pointer` (RFC 6901), or nil when nothing is there.
    public func value(at pointer: String) -> JSONValue? {
        if pointer.isEmpty { return self }
        guard pointer.hasPrefix("/") else { return nil }
        var v = self
        for raw in pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            let token = raw.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            switch v {
            case let .object(o):
                guard let next = o[token] else { return nil }
                v = next
            case let .array(a):
                guard let i = Int(token), a.indices.contains(i), String(i) == token else { return nil }
                v = a[i]
            default:
                return nil
            }
        }
        return v
    }
}

/// A JSON object: its members by key, and the keys in the order they were written. Two objects
/// are equal when they have the same members, in any order.
public struct JSONObject: Equatable, Sendable {
    public private(set) var keys: [String] = []
    private var members: [String: JSONValue] = [:]

    public init() {}

    public init(_ pairs: [(String, JSONValue)]) {
        for (k, v) in pairs { self[k] = v }
    }

    public subscript(key: String) -> JSONValue? {
        get { members[key] }
        set {
            if let newValue {
                if members.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if members.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }
    public var entries: [(key: String, value: JSONValue)] { keys.map { ($0, members[$0]!) } }

    public static func == (a: JSONObject, b: JSONObject) -> Bool { a.members == b.members }
}

/// Why a text is not a readable JSON document.
public struct JSONSyntaxError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String
    /// The JSON Pointer of the object at fault, for a duplicate key; otherwise empty.
    public var path: String
    public var line: Int
    public var column: Int

    public var description: String { "line \(line), column \(column): \(message)" }
}

extension JSONValue {
    /// The deepest nesting of arrays and objects a document may have; deeper input is refused
    /// rather than risking the reader's stack.
    public static let maxDepth = 128

    /// Parses `data` as one JSON text in UTF-8 without a byte order mark (EXP-19). Unlike
    /// `JSONSerialization`, it refuses a duplicate key, since parsers disagree about which
    /// value wins.
    public static func parse(_ data: Data) throws(JSONSyntaxError) -> JSONValue {
        var p = JSONParser(Array(data))
        return try p.document()
    }

    public static func parse(_ text: String) throws(JSONSyntaxError) -> JSONValue {
        try parse(Data(text.utf8))
    }
}

private struct JSONParser {
    let bytes: [UInt8]
    var i = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func fail(_ message: String, at offset: Int? = nil, path: String = "") -> JSONSyntaxError {
        let end = min(offset ?? i, bytes.count)
        var line = 1
        var column = 1
        for b in bytes[0..<end] {
            if b == 0x0A {
                line += 1
                column = 1
            } else if b & 0xC0 != 0x80 {
                column += 1
            }
        }
        return JSONSyntaxError(message: message, path: path, line: line, column: column)
    }

    mutating func document() throws(JSONSyntaxError) -> JSONValue {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { throw fail("the file starts with a byte order mark") }
        if String(validating: bytes, as: UTF8.self) == nil { throw fail("the file is not valid UTF-8", at: firstInvalidUTF8()) }
        skipSpace()
        let v = try value(path: "", depth: 1)
        skipSpace()
        if i < bytes.count { throw fail("unexpected text after the JSON value") }
        return v
    }

    func firstInvalidUTF8() -> Int {
        var lo = 0
        var hi = bytes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if String(validating: bytes[0...mid], as: UTF8.self) == nil && !endsMidSequence(mid) { hi = mid } else { lo = mid + 1 }
        }
        return lo
    }

    func endsMidSequence(_ end: Int) -> Bool {
        // A prefix that stops inside a valid multi-byte sequence is not where the fault is.
        var k = end
        var n = 0
        while k >= 0 && bytes[k] & 0xC0 == 0x80 && n < 3 {
            k -= 1
            n += 1
        }
        guard k >= 0 else { return false }
        let lead = bytes[k]
        let need = lead >= 0xF0 ? 3 : lead >= 0xE0 ? 2 : lead >= 0xC0 ? 1 : 0
        return n < need
    }

    mutating func skipSpace() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    mutating func value(path: String, depth: Int) throws(JSONSyntaxError) -> JSONValue {
        guard i < bytes.count else { throw fail("the text ends where a value was expected") }
        switch bytes[i] {
        case UInt8(ascii: "{"): return try object(path: path, depth: depth)
        case UInt8(ascii: "["): return try array(path: path, depth: depth)
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try number())
        default: throw fail("unexpected character where a value was expected")
        }
    }

    mutating func literal(_ word: String) throws(JSONSyntaxError) {
        let w = Array(word.utf8)
        guard bytes.count - i >= w.count, Array(bytes[i..<i + w.count]) == w else { throw fail("unexpected word") }
        i += w.count
    }

    mutating func object(path: String, depth: Int) throws(JSONSyntaxError) -> JSONValue {
        if depth > JSONValue.maxDepth { throw fail("the document is nested more than \(JSONValue.maxDepth) deep") }
        i += 1
        var o = JSONObject()
        skipSpace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") {
            i += 1
            return .object(o)
        }
        while true {
            skipSpace()
            guard i < bytes.count else { throw fail("the text ends inside an object") }
            guard bytes[i] == UInt8(ascii: "\"") else { throw fail("expected a key in double quotes") }
            let keyAt = i
            let key = try string()
            if o[key] != nil { throw fail("duplicate key \"\(key)\"", at: keyAt, path: path) }
            skipSpace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw fail("expected ':' after a key") }
            i += 1
            skipSpace()
            o[key] = try value(path: path + "/" + DocumentPath.escape(key), depth: depth + 1)
            skipSpace()
            guard i < bytes.count else { throw fail("the text ends inside an object") }
            if bytes[i] == UInt8(ascii: ",") {
                i += 1
                continue
            }
            if bytes[i] == UInt8(ascii: "}") {
                i += 1
                return .object(o)
            }
            throw fail("expected ',' or '}' in an object")
        }
    }

    mutating func array(path: String, depth: Int) throws(JSONSyntaxError) -> JSONValue {
        if depth > JSONValue.maxDepth { throw fail("the document is nested more than \(JSONValue.maxDepth) deep") }
        i += 1
        var a: [JSONValue] = []
        skipSpace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "]") {
            i += 1
            return .array(a)
        }
        while true {
            skipSpace()
            a.append(try value(path: path + "/\(a.count)", depth: depth + 1))
            skipSpace()
            guard i < bytes.count else { throw fail("the text ends inside an array") }
            if bytes[i] == UInt8(ascii: ",") {
                i += 1
                continue
            }
            if bytes[i] == UInt8(ascii: "]") {
                i += 1
                return .array(a)
            }
            throw fail("expected ',' or ']' in an array")
        }
    }

    mutating func string() throws(JSONSyntaxError) -> String {
        i += 1
        var out: [UInt8] = []
        while true {
            guard i < bytes.count else { throw fail("the text ends inside a string") }
            let b = bytes[i]
            if b == UInt8(ascii: "\"") {
                i += 1
                return String(decoding: out, as: UTF8.self)
            }
            if b < 0x20 { throw fail("a control character inside a string must be escaped") }
            if b != UInt8(ascii: "\\") {
                out.append(b)
                i += 1
                continue
            }
            i += 1
            guard i < bytes.count else { throw fail("the text ends inside a string") }
            let e = bytes[i]
            i += 1
            switch e {
            case UInt8(ascii: "\""): out.append(0x22)
            case UInt8(ascii: "\\"): out.append(0x5C)
            case UInt8(ascii: "/"): out.append(0x2F)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "f"): out.append(0x0C)
            case UInt8(ascii: "n"): out.append(0x0A)
            case UInt8(ascii: "r"): out.append(0x0D)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "u"):
                var unit = try hex4()
                if (0xD800..<0xDC00).contains(unit) {
                    guard bytes.count - i >= 6, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") else {
                        throw fail("an unpaired surrogate in a string")
                    }
                    i += 2
                    let low = try hex4()
                    guard (0xDC00..<0xE000).contains(low) else { throw fail("an unpaired surrogate in a string") }
                    unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                } else if (0xDC00..<0xE000).contains(unit) {
                    throw fail("an unpaired surrogate in a string")
                }
                out.append(contentsOf: Array(String(Character(Unicode.Scalar(unit)!)).utf8))
            default:
                throw fail("an unknown escape in a string")
            }
        }
    }

    mutating func hex4() throws(JSONSyntaxError) -> UInt32 {
        guard bytes.count - i >= 4 else { throw fail("a \\u escape needs four hexadecimal digits") }
        var v: UInt32 = 0
        for _ in 0..<4 {
            let b = bytes[i]
            let d: UInt32
            switch b {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): d = UInt32(b - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): d = UInt32(b - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): d = UInt32(b - UInt8(ascii: "A") + 10)
            default: throw fail("a \\u escape needs four hexadecimal digits")
            }
            v = v * 16 + d
            i += 1
        }
        return v
    }

    mutating func number() throws(JSONSyntaxError) -> Double {
        let start = i
        func digit() -> Bool { i < bytes.count && (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[i]) }
        if bytes[i] == UInt8(ascii: "-") { i += 1 }
        guard digit() else { throw fail("a number needs a digit") }
        if bytes[i] == UInt8(ascii: "0") {
            i += 1
            if digit() { throw fail("a number must not start with 0") }
        } else {
            while digit() { i += 1 }
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
            i += 1
            guard digit() else { throw fail("a number needs a digit after '.'") }
            while digit() { i += 1 }
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            i += 1
            if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
            guard digit() else { throw fail("a number needs a digit in its exponent") }
            while digit() { i += 1 }
        }
        let text = String(decoding: bytes[start..<i], as: UTF8.self)
        guard let v = Double(text), v.isFinite else { throw fail("the number \(text) is too large", at: start) }
        return v
    }
}

/// JSON Pointers (RFC 6901), as findings give them.
public enum DocumentPath {
    public static func escape(_ token: String) -> String {
        token.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }

    public static func join(_ path: String, _ tokens: String...) -> String {
        tokens.reduce(path) { $0 + "/" + escape($1) }
    }
}
