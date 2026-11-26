#if os(macOS)

/// A JSON value that keeps what a document's author wrote: the order of an object's keys and the
/// text of each number.
///
/// The helper forwards patches and parts of documents without reading them, so it must not reorder
/// keys or round numbers on the way through (a stored file keeps its layout from one edit to the
/// next, and `0.1` stays `0.1`).
public indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    /// A number, as the literal text of RFC 8259's grammar.
    case number(String)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    public static func int(_ value: Int) -> JSONValue { .number(String(value)) }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var object: JSONObject? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// The number as an integer, when it is one and fits.
    public var int: Int? {
        guard case .number(let text) = self else { return nil }
        if let value = Int(text) { return value }
        if let value = Double(text), value.rounded() == value, abs(value) < 9.0e15 { return Int(value) }
        return nil
    }

    public var double: Double? {
        guard case .number(let text) = self else { return nil }
        return Double(text)
    }

    public subscript(key: String) -> JSONValue? { object?[key] }
}

/// A JSON object whose members keep their order.
public struct JSONObject: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    public struct Member: Sendable, Equatable {
        public var key: String
        public var value: JSONValue
    }

    public private(set) var members: [Member] = []

    public init() {}

    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        for (key, value) in elements { self[key] = value }
    }

    public var isEmpty: Bool { members.isEmpty }
    public var keys: [String] { members.map(\.key) }

    /// Setting a key that is present replaces its value in place; setting nil removes it.
    public subscript(key: String) -> JSONValue? {
        get { members.first(where: { $0.key == key })?.value }
        set {
            let index = members.firstIndex(where: { $0.key == key })
            switch (index, newValue) {
            case (let i?, let value?): members[i].value = value
            case (let i?, nil): members.remove(at: i)
            case (nil, let value?): members.append(Member(key: key, value: value))
            case (nil, nil): break
            }
        }
    }
}

// MARK: - Parsing

public struct JSONParseError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The offset in bytes at which the text stopped being JSON.
    public let offset: Int
    public let reason: String
    public var description: String { "\(reason) at byte \(offset)" }
}

extension JSONValue {
    /// Values nested deeper than this are refused, so that hostile input cannot exhaust the stack.
    public static let maximumDepth = 256

    /// Parses one JSON text (RFC 8259) from UTF-8 bytes. A duplicate key in an object is an error.
    public static func parse(_ bytes: [UInt8]) throws(JSONParseError) -> JSONValue {
        var parser = Parser(bytes: bytes)
        parser.skipSpace()
        let value = try parser.value(depth: 0)
        parser.skipSpace()
        if parser.index != bytes.count { throw parser.failure("text after the value") }
        return value
    }

    public static func parse(_ text: String) throws(JSONParseError) -> JSONValue {
        try parse(Array(text.utf8))
    }
}

private struct Parser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    func failure(_ reason: String) -> JSONParseError { JSONParseError(offset: index, reason: reason) }

    var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    mutating func skipSpace() {
        while let byte = peek, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { index += 1 }
    }

    mutating func expect(_ literal: String, _ value: JSONValue) throws(JSONParseError) -> JSONValue {
        for byte in literal.utf8 {
            guard peek == byte else { throw failure("expected \(literal)") }
            index += 1
        }
        return value
    }

    mutating func value(depth: Int) throws(JSONParseError) -> JSONValue {
        guard depth < JSONValue.maximumDepth else { throw failure("nested too deeply") }
        guard let byte = peek else { throw failure("expected a value") }
        switch byte {
        case UInt8(ascii: "{"): return try object(depth: depth)
        case UInt8(ascii: "["): return try array(depth: depth)
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): return try expect("true", .bool(true))
        case UInt8(ascii: "f"): return try expect("false", .bool(false))
        case UInt8(ascii: "n"): return try expect("null", .null)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try number()
        default: throw failure("expected a value")
        }
    }

    mutating func object(depth: Int) throws(JSONParseError) -> JSONValue {
        index += 1
        var result = JSONObject()
        skipSpace()
        if peek == UInt8(ascii: "}") {
            index += 1
            return .object(result)
        }
        while true {
            skipSpace()
            guard peek == UInt8(ascii: "\"") else { throw failure("expected a key") }
            let keyStart = index
            let key = try string()
            if result[key] != nil { throw JSONParseError(offset: keyStart, reason: "duplicate key '\(key)'") }
            skipSpace()
            guard peek == UInt8(ascii: ":") else { throw failure("expected ':'") }
            index += 1
            skipSpace()
            result[key] = try value(depth: depth + 1)
            skipSpace()
            switch peek {
            case UInt8(ascii: ","): index += 1
            case UInt8(ascii: "}"):
                index += 1
                return .object(result)
            default: throw failure("expected ',' or '}'")
            }
        }
    }

    mutating func array(depth: Int) throws(JSONParseError) -> JSONValue {
        index += 1
        var result: [JSONValue] = []
        skipSpace()
        if peek == UInt8(ascii: "]") {
            index += 1
            return .array(result)
        }
        while true {
            skipSpace()
            result.append(try value(depth: depth + 1))
            skipSpace()
            switch peek {
            case UInt8(ascii: ","): index += 1
            case UInt8(ascii: "]"):
                index += 1
                return .array(result)
            default: throw failure("expected ',' or ']'")
            }
        }
    }

    mutating func digits() -> Int {
        let start = index
        while let byte = peek, byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") { index += 1 }
        return index - start
    }

    mutating func number() throws(JSONParseError) -> JSONValue {
        let start = index
        if peek == UInt8(ascii: "-") { index += 1 }
        if peek == UInt8(ascii: "0") {
            index += 1
        } else if digits() == 0 {
            throw failure("expected a digit")
        }
        if peek == UInt8(ascii: ".") {
            index += 1
            if digits() == 0 { throw failure("expected a digit after '.'") }
        }
        if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
            index += 1
            if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") { index += 1 }
            if digits() == 0 { throw failure("expected a digit in the exponent") }
        }
        return .number(String(decoding: bytes[start..<index], as: UTF8.self))
    }

    mutating func hex4() throws(JSONParseError) -> UInt32 {
        guard index + 4 <= bytes.count else { throw failure("expected four hexadecimal digits") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
            default: throw failure("expected a hexadecimal digit")
            }
            value = value * 16 + UInt32(digit)
            index += 1
        }
        return value
    }

    mutating func string() throws(JSONParseError) -> String {
        index += 1
        var out: [UInt8] = []
        while true {
            guard let byte = peek else { throw failure("unterminated string") }
            switch byte {
            case UInt8(ascii: "\""):
                index += 1
                guard let text = String(validating: out, as: UTF8.self) else {
                    throw failure("a string is not valid UTF-8")
                }
                return text
            case UInt8(ascii: "\\"):
                index += 1
                guard let escape = peek else { throw failure("unterminated string") }
                index += 1
                switch escape {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try hex4()
                    if (0xD800...0xDBFF).contains(scalar) {
                        guard peek == UInt8(ascii: "\\"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "u")
                        else { throw failure("a lone surrogate") }
                        index += 2
                        let low = try hex4()
                        guard (0xDC00...0xDFFF).contains(low) else { throw failure("a lone surrogate") }
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    } else if (0xDC00...0xDFFF).contains(scalar) {
                        throw failure("a lone surrogate")
                    }
                    guard let unicode = Unicode.Scalar(scalar) else { throw failure("an invalid escape") }
                    out.append(contentsOf: Array(String(Character(unicode)).utf8))
                default: throw failure("an invalid escape")
                }
            case 0x00..<0x20:
                throw failure("a control character in a string")
            default:
                out.append(byte)
                index += 1
            }
        }
    }
}

// MARK: - Writing

extension JSONValue {
    /// The value as compact JSON on one line: a newline inside a string is written as `\n`, so the
    /// text can be sent as one line of the stdio framing.
    public var serialized: String {
        var out = ""
        write(to: &out)
        return out
    }

    func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let value): out += value ? "true" : "false"
        case .number(let text): out += text
        case .string(let text): JSONValue.writeString(text, to: &out)
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                item.write(to: &out)
            }
            out += "]"
        case .object(let object):
            out += "{"
            for (i, member) in object.members.enumerated() {
                if i > 0 { out += "," }
                JSONValue.writeString(member.key, to: &out)
                out += ":"
                member.value.write(to: &out)
            }
            out += "}"
        }
    }

    static func writeString(_ text: String, to out: inout String) {
        out += "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case let s where s.value < 0x20 || s == "\u{2028}" || s == "\u{2029}":
                let hex = String(s.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}

#endif
