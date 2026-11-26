import Foundation

/// What applying a patch to a document gave (EXP-19, section 20 of the format's reference).
public struct PatchResult: Sendable {
    /// Whether the document changed.
    public var applied: Bool
    /// The patched document if it applied; otherwise the document the patch was made against.
    public var document: ExplainerDocument
    /// The short hash of `document`.
    public var hash: String
    /// The findings counted by severity: those of the patched document if it applied, otherwise
    /// those of `findings`.
    public var errors: Int
    public var warnings: Int
    /// When refused, why: a `patch` finding for a stale base, a protected path or an operation
    /// that failed, and the reader's own findings for an error in the result. When applied, the
    /// warnings.
    public var findings: [DocumentFinding]

    /// The result of `document.patch` as the helper protocol's section 6.4 gives it.
    public var reply: JSONValue {
        var o = JSONObject([("applied", .bool(applied)), ("hash", .string(hash)), ("errors", .number(Double(errors))), ("warnings", .number(Double(warnings)))])
        if !findings.isEmpty { o["findings"] = .array(findings.map(\.json)) }
        return .object(o)
    }
}

extension DocumentFinding {
    /// The finding as an object with the keys of the format reference's section 21.
    public var json: JSONValue {
        var o = JSONObject([("severity", .string(severity.rawValue)), ("code", .string(code.rawValue)), ("path", .string(path))])
        if let at { o["at"] = .number(Double(at)) }
        if let values {
            o["values"] = .object(JSONObject(values.keys.sorted().map { ($0, values[$0]!.json) }))
        }
        if let time { o["time"] = .number(time) }
        o["message"] = .string(message)
        return .object(o)
    }
}

extension ExplainerDocument {
    /// Paths no operation may name, as `path` or `from` (section 20).
    static let protectedPaths = ["", "/format", "/version"]

    /// Applies a JSON Patch (RFC 6902) to the document if `base` is its current short hash. The
    /// operations are applied in order to a copy; if one fails, or the result has an error when
    /// read, nothing changes and the refusal names the operation's index and pointer.
    public func patch(base: String, ops: [JSONValue]) -> PatchResult {
        if base != shortHash {
            return refused([.error(.patch, "", "the base \(base) is not the document's current hash \(shortHash); read the document again")])
        }
        var working = json
        for (index, op) in ops.enumerated() {
            let path = op.object?["path"]?.string ?? ""
            if let protected = Self.protectedPath(in: op) {
                let shown = protected.isEmpty ? "\"\"" : protected
                return refused([.error(.patch, protected, "operation \(index): the path \(shown) cannot be patched")])
            }
            do {
                working = try JSONPatch.apply(op, to: working)
            } catch let failure as PatchFailure {
                return refused([.error(.patch, path, "operation \(index) at \(path.isEmpty ? "\"\"" : path): \(failure.message)")])
            } catch {
                return refused([.error(.patch, path, "operation \(index) at \(path.isEmpty ? "\"\"" : path): \(error)")])
            }
        }
        let reading = ExplainerDocument.read(Self.layout(working))
        guard let document = reading.document, !reading.findings.hasErrors else {
            return refused(reading.findings)
        }
        return PatchResult(
            applied: true, document: document, hash: document.shortHash,
            errors: 0, warnings: reading.findings.warnings.count, findings: reading.findings.warnings)
    }

    private func refused(_ findings: [DocumentFinding]) -> PatchResult {
        PatchResult(applied: false, document: self, hash: shortHash, errors: findings.errors.count, warnings: findings.warnings.count, findings: findings)
    }

    /// The protected path or `from` an operation names, if it names one.
    private static func protectedPath(in op: JSONValue) -> String? {
        for key in ["path", "from"] {
            guard case let .string(p)? = op.object?[key] else { continue }
            if protectedPaths.contains(p) || p.hasPrefix("/format/") || p.hasPrefix("/version/") { return p }
        }
        return nil
    }

    /// The document as UTF-8 text with each object's keys in the order it holds them, which the
    /// canonical form does not keep, so that the reader's document keeps the author's order.
    static func layout(_ value: JSONValue) -> Data {
        var out = ""
        write(value, into: &out)
        return Data(out.utf8)
    }

    private static func write(_ value: JSONValue, into out: inout String) {
        switch value {
        case let .array(a):
            out += "["
            for (i, x) in a.enumerated() {
                if i > 0 { out += "," }
                write(x, into: &out)
            }
            out += "]"
        case let .object(o):
            out += "{"
            for (i, e) in o.entries.enumerated() {
                if i > 0 { out += "," }
                Canonical.string(e.key, into: &out)
                out += ":"
                write(e.value, into: &out)
            }
            out += "}"
        default:
            Canonical.write(value, into: &out)
        }
    }
}
