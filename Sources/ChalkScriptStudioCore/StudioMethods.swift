#if os(macOS)
import ChalkScript
import ChalkScriptMCP
import struct ChalkScript.Scene
import Foundation

extension StudioModel {
    /// Answers one request of the helper protocol (`docs/studio/helper-protocol.md`, section 6).
    /// `hello` is answered by the listener and never reaches here.
    public func respond(to method: String, params: ChalkScriptMCP.JSONObject, client: Implementation?) -> StudioReply {
        do {
            return .result(try answer(method, params, client))
        } catch {
            return .error(code: error.code, message: error.message)
        }
    }

    private func answer(_ method: String, _ params: WireObject, _ client: Implementation?) throws(MethodError) -> WireJSON {
        switch method {
        case Studio.Method.list:
            guard let folder else { throw MethodError.noProject }
            note("list", client: client)
            return .object([
                "project": .string(folder.lastPathComponent),
                "documents": .array(documents.map {
                    DocumentSummary(doc: $0.name, title: $0.title, hash: $0.hash, errors: $0.errors, warnings: $0.warnings).json
                }),
            ])

        case Studio.Method.read:
            let name = try Self.string(params, "doc")
            let pointer = try Self.string(params, "pointer", required: false) ?? ""
            let d = try existing(name)
            guard let doc = d.document else { throw MethodError.unreadable(d) }
            guard let value = doc.json.value(at: pointer) else { throw Self.noValue(pointer, in: doc.json, name) }
            note("read \(name)\(pointer)", client: client)
            return .object(["hash": .string(doc.shortHash), "value": Bridge.wire(value)])

        case Studio.Method.patch:
            let name = try Self.string(params, "doc")
            let base = try Self.string(params, "base")
            guard let raw = params["ops"]?.array else {
                throw MethodError(code: Studio.RPCError.invalidParams, "ops must be an array of JSON Patch operations.")
            }
            var ops: [DocJSON] = []
            for op in raw {
                guard let o = Bridge.doc(op) else {
                    throw MethodError(code: Studio.RPCError.invalidParams, "An operation holds a number that is not finite.")
                }
                ops.append(o)
            }
            let result = try patch(name, base: base, ops: ops)
            var reply = WireObject()
            reply["applied"] = .bool(result.applied)
            reply["hash"] = .string(result.hash)
            if result.applied, let d = document(named: name) {
                // The counts include what the samples' evaluation finds, as `check` gives them.
                reply["errors"] = .int(d.errors)
                reply["warnings"] = .int(d.warnings)
                note("edit \(name): applied", client: client)
            } else {
                reply["errors"] = .int(result.errors)
                reply["warnings"] = .int(result.warnings)
                reply["findings"] = .array(result.findings.map { Bridge.wire($0.json) })
                note("edit \(name): refused", client: client)
            }
            return .object(reply)

        case Studio.Method.check:
            let name = try Self.string(params, "doc")
            let pointer = try Self.string(params, "pointer", required: false) ?? ""
            let d = try existing(name)
            if let doc = d.document, doc.json.value(at: pointer) == nil { throw Self.noValue(pointer, in: doc.json, name) }
            let selected = d.findings.filter { pointer.isEmpty || $0.path == pointer || $0.path.hasPrefix(pointer + "/") }
            note("check \(name)\(pointer)", client: client)
            return .object([
                "hash": .string(d.hash), "errors": .int(d.errors), "warnings": .int(d.warnings),
                "findings": .array(selected.map { Bridge.wire($0.json) }),
            ])

        case Studio.Method.show:
            let name = try Self.string(params, "doc")
            let step = try Self.string(params, "step", required: false)
            var problem: [String: DocumentValue]?
            if let p = params["problem"] {
                guard let o = p.object else { throw MethodError(code: Studio.RPCError.invalidParams, "problem must be an object of parameter values.") }
                var values: [String: DocumentValue] = [:]
                for m in o.members {
                    guard let j = Bridge.doc(m.value), let v = DocumentValue(json: j) else {
                        throw MethodError(code: Studio.RPCError.invalidParams, "The value of \(m.key) must be a number, true, false or a string.")
                    }
                    values[m.key] = v
                }
                problem = values
            }
            let wantsImage: Bool
            switch params["image"] {
            case nil: wantsImage = false
            case let .bool(b)?: wantsImage = b
            default: throw MethodError(code: Studio.RPCError.invalidParams, "image must be true or false.")
            }
            var ratio: Double?
            if let r = params["ratio"] {
                guard let n = r.double, n > 0, n.isFinite else {
                    throw MethodError(code: Studio.RPCError.invalidParams, "ratio must be a number greater than 0, the area's width over its height.")
                }
                ratio = n
            }
            let shown = try show(name, step: step, problem: problem)
            var reply: WireObject = ["step": .string(shown.step), "index": .int(shown.index + 1), "count": .int(shown.count)]
            // Without a ratio, the picture is at the shape the window is showing.
            let shape = ratio ?? shownRatio ?? Double(Scene.stage.width / Scene.stage.height)
            if wantsImage, let e = shaped?.made, let picture = StepPicture.png(e, step: shown.index, ratio: shape) {
                reply["image"] = .object(["data": .string(picture.png.base64EncodedString()), "mimeType": .string("image/png")])
                reply["ratio"] = .number(Canonical.number((picture.ratio * 100).rounded() / 100))
                reply["layout"] = .string(picture.layout)
            }
            note("show \(name) \(shown.step)", client: client)
            return .object(reply)

        case Studio.Method.guide:
            let topic = try Self.string(params, "topic", required: false)
            note("guide \(topic ?? "")", client: client)
            guard let topic, !topic.isEmpty else { return .object(["text": .string(guide.contents)]) }
            guard let text = guide.topic(topic) else {
                throw MethodError(code: Studio.ErrorCode.failed,
                                  "The guide has no topic \(topic); its topics are \(guide.names.joined(separator: ", ")).")
            }
            return .object(["text": .string(text)])

        default:
            throw MethodError(code: Studio.RPCError.methodNotFound, "ChalkScript Studio has no method \(method).")
        }
    }

    private static func string(_ params: WireObject, _ key: String, required: Bool = true) throws(MethodError) -> String? {
        guard let v = params[key] else {
            if required { throw MethodError(code: Studio.RPCError.invalidParams, "The parameter \(key) is required.") }
            return nil
        }
        guard let s = v.string else { throw MethodError(code: Studio.RPCError.invalidParams, "The parameter \(key) must be a string.") }
        return s
    }

    private static func string(_ params: WireObject, _ key: String) throws(MethodError) -> String {
        guard let s = try string(params, key, required: true) else {
            throw MethodError(code: Studio.RPCError.invalidParams, "The parameter \(key) is required.")
        }
        return s
    }

    /// Error 4, naming the deepest value the pointer does reach.
    private static func noValue(_ pointer: String, in json: DocJSON, _ name: String) -> MethodError {
        var reached = pointer
        while !reached.isEmpty, json.value(at: reached) == nil {
            reached = reached.lastIndex(of: "/").map { String(reached[..<$0]) } ?? ""
        }
        var hint = ""
        if let o = json.value(at: reached)?.object {
            let keys = o.keys.prefix(12).joined(separator: ", ")
            hint = "; \(reached.isEmpty ? "the document" : reached) holds \(keys)\(o.count > 12 ? ", …" : "")"
        }
        return MethodError(code: Studio.ErrorCode.noValue, "The pointer \(pointer) names no value in \(name)\(hint).")
    }
}
#endif
