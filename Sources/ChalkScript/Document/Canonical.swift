import CryptoKit
import Foundation

/// The canonical form of a JSON value and its hash (EXP-19): the JSON Canonicalization Scheme
/// (RFC 8785), and the SHA-256 digest of its UTF-8 bytes in lowercase hexadecimal.
public enum Canonical {
    /// `value` serialised by RFC 8785: no whitespace, members sorted by their keys' UTF-16 code
    /// units, strings with only the escapes JSON requires, and numbers as ECMAScript writes them.
    public static func form(_ value: JSONValue) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    public static func hash(_ value: JSONValue) -> String {
        let digest = SHA256.hash(data: Data(form(value).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The first 12 hexadecimal digits of the hash.
    public static func shortHash(_ value: JSONValue) -> String { String(hash(value).prefix(12)) }

    static func write(_ value: JSONValue, into out: inout String) {
        switch value {
        case .null: out += "null"
        case let .bool(b): out += b ? "true" : "false"
        case let .number(n): out += number(n)
        case let .string(s): string(s, into: &out)
        case let .array(a):
            out += "["
            for (k, v) in a.enumerated() {
                if k > 0 { out += "," }
                write(v, into: &out)
            }
            out += "]"
        case let .object(o):
            out += "{"
            let keys = o.keys.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
            for (k, key) in keys.enumerated() {
                if k > 0 { out += "," }
                string(key, into: &out)
                out += ":"
                write(o[key]!, into: &out)
            }
            out += "}"
        }
    }

    static func string(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    let h = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - h.count) + h
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }

    /// `n` as ECMAScript's Number::toString writes it (ECMA-262, 6.1.6.1.20), which RFC 8785
    /// requires: the shortest digits that read back as `n`, with an exponent only below 1e-6 or
    /// from 1e21. `n` must be finite, as every number the JSON reader keeps is.
    public static func number(_ n: Double) -> String {
        if n == 0 { return "0" }
        if n < 0 { return "-" + number(-n) }
        // Swift's description gives the shortest digits that read back as `n`; only their
        // placement differs from ECMAScript's.
        let text = "\(n)"
        let parts = text.split(separator: "e", maxSplits: 1)
        var exponent = parts.count > 1 ? Int(parts[1])! : 0
        let mantissa = parts[0]
        let point = mantissa.firstIndex(of: ".")
        var digits = mantissa.replacingOccurrences(of: ".", with: "")
        let intLength = point.map { mantissa.distance(from: mantissa.startIndex, to: $0) } ?? mantissa.count
        // The value is 0.digits × 10^n, with digits stripped of zeros at both ends.
        exponent += intLength
        while digits.hasPrefix("0") {
            digits.removeFirst()
            exponent -= 1
        }
        while digits.hasSuffix("0") { digits.removeLast() }
        let k = digits.count
        let e = exponent
        if k <= e && e <= 21 { return digits + String(repeating: "0", count: e - k) }
        if 0 < e && e <= 21 {
            let cut = digits.index(digits.startIndex, offsetBy: e)
            return String(digits[..<cut]) + "." + String(digits[cut...])
        }
        if -6 < e && e <= 0 { return "0." + String(repeating: "0", count: -e) + digits }
        let sign = e - 1 < 0 ? "-" : "+"
        let first = String(digits.prefix(1))
        let rest = k == 1 ? "" : "." + String(digits.dropFirst())
        return first + rest + "e" + sign + String(abs(e - 1))
    }
}
