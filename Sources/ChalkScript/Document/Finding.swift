import Foundation

/// Something a reader found in an explainer document, or found when evaluating it for a
/// problem (EXP-19, section 21 of the format's reference). A document with an error is not
/// played.
public struct DocumentFinding: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }

    public enum Code: String, Sendable, CaseIterable {
        /// Not JSON, not an object, or a duplicate key.
        case json
        /// `format` is missing or is not `chalkscript-explainer`.
        case format
        /// A major version not implemented, or a newer minor version.
        case version
        /// A required capability not implemented, or one used and not required.
        case capability
        /// A missing key, a value of the wrong type, an unknown verb, kind or input, or a name
        /// that does not match its pattern.
        case schema
        /// A key the format does not define.
        case unknown
        /// A reference to a step, action, element, part, shot, layout, entry or `vars` value
        /// that does not exist.
        case ref
        /// A syntax error, unknown name, unknown function, wrong arguments, or a cycle.
        case expr
        /// A placeholder that cannot be filled, a typed numeral, a spoken form that cannot be
        /// derived, or an entry in both `shared` and a wording.
        case wording
        /// An evaluation error for a problem.
        case eval
        /// A problem outside the parameters' ranges.
        case range
        /// A declaration of the areas the document is made for that disagrees with its layouts.
        case areas
        /// A patch refused.
        case patch
    }

    public var severity: Severity
    public var code: Code
    /// A JSON Pointer to the value at fault.
    public var path: String
    /// The offset in Unicode code points, from 0, inside an expression or an entry's text.
    public var at: Int?
    /// The problem's values, for a finding made by evaluating the document.
    public var values: [String: DocumentValue]?
    /// The time on the step's clock, for a finding at a moment of a step.
    public var time: Double?
    public var message: String

    public init(
        _ severity: Severity, _ code: Code, _ path: String, at: Int? = nil, values: [String: DocumentValue]? = nil,
        time: Double? = nil, _ message: String
    ) {
        self.severity = severity
        self.code = code
        self.path = path
        self.at = at
        self.values = values
        self.time = time
        self.message = message
    }

    public static func error(_ code: Code, _ path: String, at: Int? = nil, _ message: String) -> DocumentFinding {
        DocumentFinding(.error, code, path, at: at, message)
    }

    public static func warning(_ code: Code, _ path: String, at: Int? = nil, _ message: String) -> DocumentFinding {
        DocumentFinding(.warning, code, path, at: at, message)
    }

    /// The finding on one line, as section 21 writes it:
    /// `error eval /steps/takeTens/actions/cross/target {a: 20, b: 11}: ten[2] is outside ten`.
    public var description: String {
        var s = "\(severity.rawValue) \(code.rawValue) \(path.isEmpty ? "/" : path)"
        if let at { s += " @\(at)" }
        if let values {
            s += " {" + values.keys.sorted().map { "\($0): \(values[$0]!)" }.joined(separator: ", ") + "}"
        }
        if let time { s += " t=\(Canonical.number(time))" }
        return s + ": " + message
    }
}

extension Array where Element == DocumentFinding {
    public var errors: [DocumentFinding] { filter { $0.severity == .error } }
    public var warnings: [DocumentFinding] { filter { $0.severity == .warning } }
    public var hasErrors: Bool { contains { $0.severity == .error } }
}
