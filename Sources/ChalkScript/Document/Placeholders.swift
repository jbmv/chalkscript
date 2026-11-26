import Foundation

/// A placeholder in an entry's text (section 14.2): `{name}`, filled with a value, or
/// `{entry:name}`, a phrase filled from another entry with `n` set to the value of `name`.
struct Placeholder: Equatable {
    var name: String
    /// The phrase entry, for `{entry:name}`.
    var entry: String?
    /// Offsets in Unicode code points of `{` and of the character after `}`.
    var start: Int
    var end: Int

    /// The run a text element showing the entry has for this placeholder (section 9.2).
    var run: String { entry ?? name }
}

/// An entry's text split into literal text and placeholders.
struct PlaceholderText {
    enum Piece: Equatable {
        case literal(String, at: Int)
        case placeholder(Placeholder)
    }

    var pieces: [Piece] = []
    /// A malformed brace or placeholder, at its offset.
    var problems: [(String, Int)] = []

    var placeholders: [Placeholder] {
        pieces.compactMap { if case let .placeholder(p) = $0 { p } else { nil } }
    }

    init(_ text: String) {
        let s = Array(text.unicodeScalars)
        var literal = ""
        var literalStart = 0
        var i = 0
        func flush() {
            if !literal.isEmpty { pieces.append(.literal(literal, at: literalStart)) }
            literal = ""
        }
        while i < s.count {
            let c = s[i]
            if c == "}" {
                problems.append(("a '}' with no '{' before it", i))
                i += 1
                continue
            }
            if c != "{" {
                if literal.isEmpty { literalStart = i }
                literal.unicodeScalars.append(c)
                i += 1
                continue
            }
            guard let close = s[i...].firstIndex(of: "}") else {
                problems.append(("a '{' is not closed", i))
                break
            }
            let inner = String(String.UnicodeScalarView(s[(i + 1)..<close]))
            let parts = inner.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let ok: Bool
            if parts.count == 1 {
                ok = DocumentNames.isName(parts[0], allowingLocals: true)
            } else if parts.count == 2 {
                ok = DocumentNames.isEntryName(parts[0]) && DocumentNames.isName(parts[1], allowingLocals: true)
            } else {
                ok = false
            }
            if ok {
                flush()
                pieces.append(.placeholder(Placeholder(
                    name: parts.count == 1 ? parts[0] : parts[1], entry: parts.count == 2 ? parts[0] : nil, start: i, end: close + 1)))
            } else {
                problems.append(("'{\(inner)}' is not a placeholder: it is {name} or {entry:name}", i))
            }
            i = close + 1
        }
        flush()
    }
}

/// The patterns names follow (section 3).
enum DocumentNames {
    /// Element, step, action, part, shot, layout, parameter, `let`, `vars` and section names.
    static func isName(_ s: String, allowingLocals: Bool = false) -> Bool {
        let u = Array(s.unicodeScalars)
        guard let first = u.first, ("a"..."z").contains(first), u.count <= 48 || allowingLocals else { return false }
        return u.allSatisfy { ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
    }

    /// Wording entry names, such as `do.trade`.
    static func isEntryName(_ s: String) -> Bool {
        guard s.unicodeScalars.count <= 64, !s.isEmpty else { return false }
        return s.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { isName(String($0), allowingLocals: true) }
    }

    /// Two or more lowercase dot-separated words, such as `components.arithmetic`.
    static func isCapability(_ s: String) -> Bool {
        let words = s.split(separator: ".", omittingEmptySubsequences: false)
        return words.count >= 2 && words.allSatisfy { w in
            guard let f = w.unicodeScalars.first, ("a"..."z").contains(f) else { return false }
            return w.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
        }
    }

    static func isID(_ s: String) -> Bool {
        let u = Array(s.unicodeScalars)
        guard let f = u.first, ("a"..."z").contains(f), u.count <= 64 else { return false }
        return u.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// A BCP 47 tag, as far as the schema checks one.
    static func isLocale(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard let lang = parts.first, (2...3).contains(lang.count), lang.unicodeScalars.allSatisfy({ $0.properties.isAlphabetic && $0.isASCII })
        else { return false }
        return parts.dropFirst().allSatisfy { p in
            (1...8).contains(p.count) && p.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) }
        }
    }

    static func isExtensionKey(_ s: String) -> Bool {
        guard let dot = s.firstIndex(of: ".") else { return false }
        let vendor = s[..<dot]
        let rest = s[s.index(after: dot)...]
        return !vendor.isEmpty && vendor.unicodeScalars.allSatisfy { ("a"..."z").contains($0) } && !rest.isEmpty
            && rest.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-" }
    }

    /// Names that must not name a parameter, a `let`, a `vars` value, an element or a local
    /// (section 3).
    static let reserved: Set<String> = ExpressionFunction.keywords.union(ExpressionFunction.arity.keys)
        .union(["i", "x0", "y0", "left", "areaW", "areaH", "n"])
}
