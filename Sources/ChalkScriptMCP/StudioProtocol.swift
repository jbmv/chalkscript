#if os(macOS)

/// The names and numbers of the protocol between the helper and the studio app, which
/// `docs/studio/helper-protocol.md` defines.
public enum Studio {
    /// The protocol's version, which `hello` carries. Adding an optional key or a method does not
    /// change it; changing what an existing key or method means does.
    public static let protocolVersion = 1

    public enum Method {
        public static let hello = "hello"
        public static let list = "documents.list"
        public static let read = "document.read"
        public static let patch = "document.patch"
        public static let check = "document.check"
        public static let show = "step.show"
        public static let guide = "guide.read"
        public static let create = "document.create"
    }

    /// Error codes the studio answers with, beside JSON-RPC's own.
    public enum ErrorCode {
        public static let unsupportedProtocol = 1
        public static let noProject = 2
        public static let noDocument = 3
        public static let noValue = 4
        public static let noStep = 5
        public static let failed = 6
    }

    /// JSON-RPC's codes, which both ends use with their usual meanings.
    public enum RPCError {
        public static let parse = -32700
        public static let invalidRequest = -32600
        public static let methodNotFound = -32601
        public static let invalidParams = -32602
        public static let internalError = -32603
    }
}

/// A name and version, as `hello` and MCP's `clientInfo` and `serverInfo` carry them.
public struct Implementation: Sendable, Equatable {
    public var name: String
    public var version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }

    public init?(json: JSONValue?) {
        guard let name = json?["name"]?.string else { return nil }
        self.init(name: name, version: json?["version"]?.string ?? "")
    }

    public var json: JSONValue { .object(["name": .string(name), "version": .string(version)]) }
}

/// A reader's or validator's finding, with the fields of the format reference's section 21.
public struct Finding: Sendable, Equatable {
    public var severity: String
    public var code: String
    /// A JSON Pointer to the value at fault.
    public var path: String
    /// The offset in Unicode code points within an expression or an entry's text.
    public var at: Int?
    /// The problem's values, for a finding made by evaluating the document.
    public var values: JSONObject?
    /// Seconds on the step's clock, for a finding at a moment of a step.
    public var time: Double?
    public var message: String

    public init(severity: String, code: String, path: String, at: Int? = nil, values: JSONObject? = nil,
                time: Double? = nil, message: String) {
        self.severity = severity
        self.code = code
        self.path = path
        self.at = at
        self.values = values
        self.time = time
        self.message = message
    }

    public init?(json: JSONValue) {
        guard let severity = json["severity"]?.string, let code = json["code"]?.string,
              let message = json["message"]?.string else { return nil }
        self.init(severity: severity, code: code, path: json["path"]?.string ?? "", at: json["at"]?.int,
                  values: json["values"]?.object, time: json["time"]?.double, message: message)
    }

    public var json: JSONValue {
        var object: JSONObject = ["severity": .string(severity), "code": .string(code), "path": .string(path)]
        if let at { object["at"] = .int(at) }
        if let values { object["values"] = .object(values) }
        if let time { object["time"] = .number(Finding.format(time)) }
        object["message"] = .string(message)
        return .object(object)
    }

    /// The finding on one line, as section 21 writes it:
    /// `error expr /steps/a/actions/b/target @9 {a: 20} t=1.5: unknown name 'bo'`.
    public var line: String {
        var text = "\(severity) \(code) \(path.isEmpty ? "/" : path)"
        if let at { text += " @\(at)" }
        if let values {
            text += " {" + values.members.map { "\($0.key): \($0.value.serialized)" }.joined(separator: ", ") + "}"
        }
        if let time { text += " t=\(Finding.format(time))" }
        return text + ": " + Finding.oneLine(message)
    }

    static func format(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

/// One document of the open project, as `documents.list` gives it.
public struct DocumentSummary: Sendable, Equatable {
    /// The name the other methods take; the studio gives it, and the helper treats it as opaque.
    public var doc: String
    public var title: String?
    /// The document's short hash (section 19 of the format reference).
    public var hash: String
    /// The counts of the document's findings; nil when the studio has not checked it.
    public var errors: Int?
    public var warnings: Int?

    public init(doc: String, title: String? = nil, hash: String, errors: Int? = nil, warnings: Int? = nil) {
        self.doc = doc
        self.title = title
        self.hash = hash
        self.errors = errors
        self.warnings = warnings
    }

    public init?(json: JSONValue) {
        guard let doc = json["doc"]?.string, let hash = json["hash"]?.string else { return nil }
        self.init(doc: doc, title: json["title"]?.string, hash: hash, errors: json["errors"]?.int,
                  warnings: json["warnings"]?.int)
    }

    public var json: JSONValue {
        var object: JSONObject = ["doc": .string(doc)]
        if let title { object["title"] = .string(title) }
        object["hash"] = .string(hash)
        if let errors { object["errors"] = .int(errors) }
        if let warnings { object["warnings"] = .int(warnings) }
        return .object(object)
    }
}

#endif
