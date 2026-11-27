#if os(macOS)

/// A tool's result as MCP carries it: content blocks, and whether the call failed in a way the
/// agent can correct.
public struct ToolResult: Sendable, Equatable {
    public var content: [JSONValue]
    public var isError: Bool

    public init(content: [JSONValue], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    public static func text(_ text: String, isError: Bool = false) -> ToolResult {
        ToolResult(content: [.object(["type": .string("text"), "text": .string(text)])], isError: isError)
    }

    public var json: JSONValue {
        .object(["content": .array(content), "isError": .bool(isError)])
    }
}

/// The helper's tools: their definitions, and how each call becomes one request to the studio and
/// its reply becomes a short text.
public enum HelperTools {
    /// Server instructions, which Claude Code loads at session start even when it defers the tools.
    public static let instructions = """
        Make and edit explainers (.explainer documents) in ChalkScript Studio, which the person \
        has open beside this conversation. To change one: read the part to change by JSON Pointer, \
        not the whole document; edit with a JSON Patch against the hash read (every operation \
        applies or none; the new hash comes back, to use as the next base). Call guide only for \
        what this does not cover.
        """

    /// The tools in the order `tools/list` gives them.
    public static let definitions: [JSONValue] = {
        // The text is fixed, so a failure to parse it is a fault in this file.
        guard case .array(let tools) = try! JSONValue.parse(definitionsText) else { fatalError("tool list") }
        return tools
    }()

    public static var names: [String] { definitions.compactMap { $0["name"]?.string } }

    // Descriptions are kept short because a client sends them with every request; the guide holds
    // the detail and is read on demand.
    static let definitionsText = #"""
    [
    {"name":"list","description":"List the documents in the project open in ChalkScript Studio, with each one's hash and counts of errors and warnings.",
     "inputSchema":{"type":"object","additionalProperties":false}},
    {"name":"read","description":"Read the part of a document to change, at a JSON Pointer such as /steps/trade, not the whole document. The first line of the result is the document's hash, which edit takes as its base.",
     "inputSchema":{"type":"object","properties":{"doc":{"type":"string"},"pointer":{"type":"string"}},"required":["doc"],"additionalProperties":false}},
    {"name":"edit","description":"Change a document by JSON Patch (RFC 6902) made against its current hash. Every operation applies or none does. Returns the new hash and counts of findings, or why the patch was refused.",
     "inputSchema":{"type":"object","properties":{"doc":{"type":"string"},"base":{"type":"string"},"ops":{"type":"array","items":{"type":"object"}}},"required":["doc","base","ops"],"additionalProperties":false}},
    {"name":"check","description":"List a document's errors and warnings, one per line, or only those under a JSON Pointer.",
     "inputSchema":{"type":"object","properties":{"doc":{"type":"string"},"pointer":{"type":"string"}},"required":["doc"],"additionalProperties":false}},
    {"name":"show","description":"Play a step in the studio window: the first without step, the current problem without problem. Returns its timeline. With image, also a picture of its end, at ratio (width/height) and appearance or the window's.",
     "inputSchema":{"type":"object","properties":{"doc":{"type":"string"},"step":{"type":"string"},"problem":{"type":"object"},"ratio":{"type":"number","exclusiveMinimum":0},"appearance":{"enum":["light","dark"]},"image":{"type":"boolean"}},"required":["doc"],"additionalProperties":false}},
    {"name":"create","description":"Make a new explainer from a title and show it in the window. Its name comes from the title; name sets one, from copies a document. Returns the document to patch; read guide topic new first.",
     "inputSchema":{"type":"object","properties":{"title":{"type":"string"},"name":{"type":"string"},"from":{"type":"string"}},"required":["title"],"additionalProperties":false}},
    {"name":"guide","description":"Read the authoring guide to the explainer format and how to edit it. Without a topic, its list of topics.",
     "inputSchema":{"type":"object","properties":{"topic":{"type":"string"}},"additionalProperties":false}}
    ]
    """#

    /// The most findings `check` and a refused `edit` write out; the rest are counted.
    public static let findingLines = 40

    /// Runs one tool. Returns nil for a name that is not a tool, and for a call that was cancelled,
    /// to which nothing is sent.
    public static func call(_ name: String, arguments: JSONObject, studio: StudioClient,
                            client: Implementation? = nil, cancellation: StudioCancellation? = nil) -> ToolResult? {
        guard names.contains(name) else { return nil }
        let request: (method: String, params: JSONObject)
        switch prepare(name, arguments) {
        case .success(let prepared): request = prepared
        case .failure(let problem): return .text(problem.message, isError: true)
        }
        let outcome = studio.call(request.method, params: request.params, client: client, cancellation: cancellation)
        switch outcome {
        case .cancelled: return nil
        case .result(let result):
            return render(name, result) ?? .text(
                "ChalkScript Studio sent a reply the helper cannot read (the result of \(request.method) "
                + "lacks a field it needs).", isError: true)
        default:
            return .text(describe(outcome, studio: studio), isError: true)
        }
    }

    struct ArgumentProblem: Error {
        let message: String
    }

    static func prepare(_ name: String, _ arguments: JSONObject) -> Result<(method: String, params: JSONObject), ArgumentProblem> {
        func string(_ key: String, required: Bool) throws(ArgumentProblem) -> JSONValue? {
            guard let value = arguments[key] else {
                if required { throw ArgumentProblem(message: "The argument \(key) is required.") }
                return nil
            }
            guard case .string(let text) = value else { throw ArgumentProblem(message: "The argument \(key) must be a string.") }
            if required && text.isEmpty { throw ArgumentProblem(message: "The argument \(key) must not be empty.") }
            return value
        }
        func pointer() throws(ArgumentProblem) -> JSONValue? {
            guard let value = try string("pointer", required: false) else { return nil }
            if let text = value.string, !text.isEmpty, !text.hasPrefix("/") {
                throw ArgumentProblem(message: "The pointer must be empty or begin with '/', as in /steps/trade.")
            }
            return value
        }
        do throws(ArgumentProblem) {
            var params = JSONObject()
            switch name {
            case "list":
                return .success((Studio.Method.list, params))
            case "read":
                params["doc"] = try string("doc", required: true)
                params["pointer"] = try pointer() ?? .string("")
                return .success((Studio.Method.read, params))
            case "edit":
                params["doc"] = try string("doc", required: true)
                params["base"] = try string("base", required: true)
                guard let ops = arguments["ops"]?.array else {
                    throw ArgumentProblem(message: "The argument ops is required and must be an array of operations.")
                }
                guard ops.allSatisfy({ $0.object != nil }) else {
                    throw ArgumentProblem(message: "Each operation in ops must be an object.")
                }
                params["ops"] = .array(ops)
                return .success((Studio.Method.patch, params))
            case "check":
                params["doc"] = try string("doc", required: true)
                params["pointer"] = try pointer()
                return .success((Studio.Method.check, params))
            case "create":
                params["title"] = try string("title", required: true)
                params["name"] = try string("name", required: false)
                params["from"] = try string("from", required: false)
                return .success((Studio.Method.create, params))
            case "show":
                params["doc"] = try string("doc", required: true)
                params["step"] = try string("step", required: false)
                if let problem = arguments["problem"] {
                    guard problem.object != nil else { throw ArgumentProblem(message: "The argument problem must be an object.") }
                    params["problem"] = problem
                }
                if let ratio = arguments["ratio"] {
                    guard let r = ratio.double, r > 0, r.isFinite else {
                        throw ArgumentProblem(message: "The argument ratio must be a number greater than 0, the area's width over its height.")
                    }
                    params["ratio"] = ratio
                }
                if let appearance = arguments["appearance"] {
                    guard let a = appearance.string, a == "light" || a == "dark" else {
                        throw ArgumentProblem(message: "The argument appearance must be light or dark.")
                    }
                    params["appearance"] = appearance
                }
                if let image = arguments["image"] {
                    guard image.bool != nil else { throw ArgumentProblem(message: "The argument image must be true or false.") }
                    params["image"] = image
                }
                return .success((Studio.Method.show, params))
            default:
                params["topic"] = try string("topic", required: false)
                return .success((Studio.Method.guide, params))
            }
        } catch {
            return .failure(error)
        }
    }

    /// The text of a result, or nil when the result lacks what the protocol says it holds.
    static func render(_ name: String, _ result: JSONValue) -> ToolResult? {
        switch name {
        case "list":
            guard let documents = result["documents"]?.array else { return nil }
            let project = result["project"]?.string ?? "the project"
            if documents.isEmpty { return .text("No documents in \(project).") }
            var lines = ["project \(project)"]
            for item in documents {
                guard let summary = DocumentSummary(json: item) else { return nil }
                var line = "\(summary.doc) \(summary.hash) \(counts(summary.errors, summary.warnings))"
                if let title = summary.title { line += " " + JSONValue.string(title).serialized }
                lines.append(line)
            }
            return .text(lines.joined(separator: "\n"))
        case "read":
            guard let hash = result["hash"]?.string, let value = result["value"] else { return nil }
            return .text("hash \(hash)\n\(value.serialized)")
        case "edit":
            guard let applied = result["applied"]?.bool, let hash = result["hash"]?.string else { return nil }
            let findings = (result["findings"]?.array ?? []).compactMap(Finding.init(json:))
            if applied {
                return .text("applied; hash \(hash); \(counts(result["errors"]?.int, result["warnings"]?.int))")
            }
            return .text((["refused; hash \(hash)"] + lines(findings)).joined(separator: "\n"), isError: true)
        case "check":
            guard let hash = result["hash"]?.string, let items = result["findings"]?.array else { return nil }
            let findings = items.compactMap(Finding.init(json:))
            let errors = result["errors"]?.int ?? findings.filter { $0.severity == "error" }.count
            let warnings = result["warnings"]?.int ?? findings.filter { $0.severity == "warning" }.count
            return .text((["hash \(hash); \(counts(errors, warnings))"] + lines(findings)).joined(separator: "\n"))
        case "create":
            guard let doc = result["doc"]?.string, let hash = result["hash"]?.string, let value = result["value"] else { return nil }
            return .text("created \(doc); hash \(hash); \(counts(result["errors"]?.int, result["warnings"]?.int))\n\(value.serialized)")
        case "show":
            guard let step = result["step"]?.string else { return nil }
            var text = "showing \(step)"
            if let index = result["index"]?.int, let count = result["count"]?.int { text += " (\(index) of \(count))" }
            if result["image"] != nil, case .number(let ratio)? = result["ratio"] {
                text += "; the picture is at ratio \(ratio)"
                if let layout = result["layout"]?.string { text += " in the layout \(layout)" }
                if let appearance = result["appearance"]?.string { text += ", drawn \(appearance)" }
                if let other = result["notMadeFor"]?.string { text += "; the document is not made for \(other)" }
                if case .number(let drawn)? = result["drawn"] {
                    text += "; \(ratio) is not a shape the document is made for; drawn at \(drawn) inside it"
                }
            }
            if let timeline = result["timeline"]?.string, !timeline.isEmpty { text += "\n" + timeline }
            var content: [JSONValue] = [.object(["type": .string("text"), "text": .string(text)])]
            if let image = result["image"] {
                guard let data = image["data"]?.string else { return nil }
                content.append(.object(["type": .string("image"), "data": .string(data),
                                        "mimeType": .string(image["mimeType"]?.string ?? "image/png")]))
            }
            return ToolResult(content: content)
        default:
            guard let text = result["text"]?.string else { return nil }
            return .text(text)
        }
    }

    static func counts(_ errors: Int?, _ warnings: Int?) -> String {
        guard let errors, let warnings else { return "unchecked" }
        if errors == 0 && warnings == 0 { return "ok" }
        var parts: [String] = []
        if errors > 0 { parts.append(errors == 1 ? "1 error" : "\(errors) errors") }
        if warnings > 0 { parts.append(warnings == 1 ? "1 warning" : "\(warnings) warnings") }
        return parts.joined(separator: ", ")
    }

    static func lines(_ findings: [Finding]) -> [String] {
        var out = findings.prefix(findingLines).map(\.line)
        if findings.count > findingLines {
            out.append("and \(findings.count - findingLines) more; check a narrower pointer to see them")
        }
        return out
    }

    /// The tool error for an outcome that is not a result.
    static func describe(_ outcome: StudioOutcome, studio: StudioClient) -> String {
        switch outcome {
        case .notRunning:
            return "ChalkScript Studio is not open. Ask the person to open it, then try again."
        case .notOwned:
            return "The studio's socket belongs to another user, so the helper will not use it."
        case .versionMismatch(let versions):
            let theirs = versions.isEmpty ? "another version" : "version " + versions.map(String.init).joined(separator: ", ")
            return "ChalkScript Studio speaks \(theirs) of the helper protocol and this helper speaks version "
                + "\(Studio.protocolVersion). Ask the person to update the studio and its extension together."
        case .closed(afterRequest: true):
            return "ChalkScript Studio closed before answering, so the call may or may not have taken effect. "
                + "Ask the person whether the studio is still open; read the document before an edit is tried again."
        case .closed(afterRequest: false):
            return "ChalkScript Studio closed the connection before the call was sent. Ask the person whether it is still open."
        case .timedOut:
            return "ChalkScript Studio did not answer within \(studio.callTimeout.components.seconds) seconds."
        case .malformed(let detail):
            return "ChalkScript Studio sent a reply the helper cannot read (\(detail))."
        case .refused(_, let message, _):
            let text = Finding.oneLine(message)
            if text.isEmpty { return "ChalkScript Studio refused the call without saying why." }
            return text.count > 2000 ? String(text.prefix(2000)) + "…" : text
        case .failed(let detail):
            return "The helper could not reach ChalkScript Studio: \(detail)."
        case .result, .cancelled:
            return ""
        }
    }
}

#endif
