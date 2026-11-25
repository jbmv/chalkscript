import Foundation

// Reading the style and motion files (EXP-19). Both are JSON, decoded with Codable into a plain
// tree (`FormatValue`) and then read value by value, so that a value left out, not known to the
// format, or not readable is recorded (`FormatIssue`) and its default used, rather than the whole
// file failing. Foundation only, as the package depends on no third-party library.

/// Something noticed while reading a style or motion file: a value at `path` (keys joined with
/// dots, as `steps.trade.durations.travel`) that the file leaves out, so its default is used; a
/// key the format does not know, which is ignored; or a value that cannot be read, whose default
/// is used instead.
public struct FormatIssue: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable {
        /// Left out of the file: the default is used, as the format intends.
        case defaulted
        /// A key the format does not have, or a name it does not know (a shot, an easing, a
        /// part): ignored, and the default used where it named a value.
        case unknown
        /// Present but not readable (a colour that is not `#RRGGBB`, a negative duration).
        case invalid
    }

    public var kind: Kind
    public var path: String
    /// What was used in its place, or what is wrong, in a few words.
    public var note: String

    public init(_ kind: Kind, _ path: String, _ note: String = "") {
        self.kind = kind
        self.path = path
        self.note = note
    }

    /// Whether the file needs looking at: something unknown or unreadable, not only left to its
    /// default.
    public var isProblem: Bool { kind != .defaulted }

    public var description: String { "\(kind.rawValue) \(path)" + (note.isEmpty ? "" : ": \(note)") }
}

/// A JSON value as decoded: the tree the readers walk.
enum FormatValue: Decodable, Equatable, Sendable {
    case object([String: FormatValue])
    case array([FormatValue])
    case number(Double)
    case string(String)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([FormatValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: FormatValue].self))
        }
    }

    static func parse(_ data: Data) throws -> FormatValue { try JSONDecoder().decode(FormatValue.self, from: data) }
}

/// Reads one object of a file, recording what it finds into `log`. Each read names the key and
/// what the format expects there; `finish()` records the keys nobody read as unknown.
final class FormatReader {
    let path: String
    private let fields: [String: FormatValue]
    private let log: FormatLog
    private var read: Set<String> = []

    init(_ value: FormatValue?, path: String, log: FormatLog) {
        self.path = path
        self.log = log
        switch value {
        case let .object(f)?: fields = f
        case nil: fields = [:]
        case .some:
            fields = [:]
            log.add(.invalid, path, "not an object")
        }
    }

    func key(_ k: String) -> String { path.isEmpty ? k : "\(path).\(k)" }

    /// The keys present, in a stable order.
    var keys: [String] { fields.keys.sorted() }

    func has(_ k: String) -> Bool { fields[k] != nil }

    /// The raw value at `k`, marked as read.
    func raw(_ k: String) -> FormatValue? {
        read.insert(k)
        return fields[k]
    }

    /// The object at `k` (empty when absent: its values then all default).
    func object(_ k: String) -> FormatReader { FormatReader(raw(k), path: key(k), log: log) }

    /// A number of seconds or scene units, at least `min`; `reportDefault` records its absence.
    func number(_ k: String, min: Double = 0, max: Double = .infinity, reportDefault: Bool = true) -> Double? {
        switch raw(k) {
        case nil:
            if reportDefault { log.add(.defaulted, key(k)) }
            return nil
        case let .number(n)? where n >= min && n <= max && n.isFinite: return n
        case let v?:
            log.add(.invalid, key(k), "\(v.brief) is not a number from \(min.formatted()) to \(max.formatted())")
            return nil
        }
    }

    func string(_ k: String, reportDefault: Bool = true) -> String? {
        switch raw(k) {
        case nil:
            if reportDefault { log.add(.defaulted, key(k)) }
            return nil
        case let .string(s)?: return s
        case let v?:
            log.add(.invalid, key(k), "\(v.brief) is not text")
            return nil
        }
    }

    func strings(_ k: String) -> [String]? {
        switch raw(k) {
        case nil: return nil
        case let .array(items)?:
            var out: [String] = []
            for (i, item) in items.enumerated() {
                if case let .string(s) = item { out.append(s) } else { log.add(.invalid, "\(key(k)).\(i)", "\(item.brief) is not text") }
            }
            return out
        case let v?:
            log.add(.invalid, key(k), "\(v.brief) is not a list of names")
            return nil
        }
    }

    func numbers(_ k: String, count: Int) -> [Double]? {
        guard let v = raw(k) else { return nil }
        if case let .array(items) = v, items.count == count {
            let ns = items.compactMap { if case let .number(n) = $0, n.isFinite { n } else { nil } }
            if ns.count == count { return ns }
        }
        log.add(.invalid, key(k), "\(v.brief) is not \(count) numbers")
        return nil
    }

    /// Records every key not read as unknown.
    func finish() {
        for k in keys where !read.contains(k) { log.add(.unknown, key(k), "not part of the format; ignored") }
    }
}

/// The issues found while reading one file.
final class FormatLog {
    private(set) var issues: [FormatIssue] = []
    func add(_ kind: FormatIssue.Kind, _ path: String, _ note: String = "") { issues.append(FormatIssue(kind, path, note)) }
}

extension FormatValue {
    /// A short form for an issue's note.
    var brief: String {
        switch self {
        case let .number(n): n.formatted()
        case let .string(s): "\"\(s)\""
        case let .bool(b): String(b)
        case .null: "null"
        case .array: "a list"
        case .object: "an object"
        }
    }
}

extension RGB {
    /// A colour written `#RRGGBB`, as the style file writes them; nil for anything else.
    public init?(hexString s: String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count == 7, t.first == "#", let v = UInt32(t.dropFirst(), radix: 16) else { return nil }
        self.init(hex: v)
    }
}

/// The package's bundled files (EXP-19): the style file and each explainer's motion file.
public enum ExplainerResources {
    /// The bundled JSON file `name` (`style`, `subtraction-motion`), as it is in the package.
    public static func data(_ name: String) -> Data? {
        Bundle.module.url(forResource: name, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }
}
