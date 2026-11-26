import Foundation

/// Why one JSON Patch operation could not be applied.
struct PatchFailure: Error {
    var message: String
}

/// A JSON Pointer (RFC 6901) split into its unescaped reference tokens.
struct PatchPointer {
    let tokens: [String]

    init(_ pointer: String) throws {
        if pointer.isEmpty {
            tokens = []
            return
        }
        guard pointer.hasPrefix("/") else { throw PatchFailure(message: "\"\(pointer)\" is not a JSON Pointer: it must be empty or start with \"/\"") }
        var out: [String] = []
        for raw in pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            var token = ""
            var chars = raw.makeIterator()
            while let c = chars.next() {
                guard c == "~" else {
                    token.append(c)
                    continue
                }
                switch chars.next() {
                case "0": token.append("~")
                case "1": token.append("/")
                default: throw PatchFailure(message: "\"\(pointer)\" has a \"~\" that is not \"~0\" or \"~1\"")
                }
            }
            out.append(token)
        }
        tokens = out
    }
}

/// Applies RFC 6902 operations to a JSON value. Each function returns a changed copy.
enum JSONPatch {
    /// Applies one operation (a decoded member of the patch array).
    static func apply(_ op: JSONValue, to doc: JSONValue) throws -> JSONValue {
        guard let o = op.object else { throw PatchFailure(message: "the operation is \(op.typeName), not an object") }
        guard case let .string(name)? = o["op"] else { throw PatchFailure(message: "the operation has no \"op\" string") }
        guard case let .string(path)? = o["path"] else { throw PatchFailure(message: "the operation has no \"path\" string") }
        let to = try PatchPointer(path).tokens
        switch name {
        case "add", "replace", "test":
            guard let value = o["value"] else { throw PatchFailure(message: "\(name) has no \"value\"") }
            switch name {
            case "add": return try insert(doc, to[...], value, replacing: false)
            case "replace": return try insert(doc, to[...], value, replacing: true)
            default:
                guard let found = doc.value(at: path) else { throw PatchFailure(message: "test: nothing is at the path") }
                guard found == value else { throw PatchFailure(message: "test: the value at the path is not the one given") }
                return doc
            }
        case "remove":
            return try remove(doc, to[...]).document
        case "move", "copy":
            guard case let .string(from)? = o["from"] else { throw PatchFailure(message: "\(name) has no \"from\" string") }
            let source = try PatchPointer(from).tokens
            guard let value = doc.value(at: from) else { throw PatchFailure(message: "\(name): nothing is at from \"\(from)\"") }
            if name == "move" {
                if to.count > source.count, Array(to.prefix(source.count)) == source {
                    throw PatchFailure(message: "move: the path is inside the value it moves")
                }
                return try insert(remove(doc, source[...]).document, to[...], value, replacing: false)
            }
            return try insert(doc, to[...], value, replacing: false)
        default:
            throw PatchFailure(message: "\"\(name)\" is not an operation: use add, remove, replace, move, copy or test")
        }
    }

    /// An array index token (RFC 6901): digits only, with no leading zero.
    private static func index(_ token: String) -> Int? {
        guard !token.isEmpty, token.allSatisfy({ $0.isASCII && $0.isNumber }), token == "0" || !token.hasPrefix("0") else { return nil }
        return Int(token)
    }

    private static func insert(_ v: JSONValue, _ tokens: ArraySlice<String>, _ new: JSONValue, replacing: Bool) throws -> JSONValue {
        guard let first = tokens.first else { return new }
        let last = tokens.count == 1
        switch v {
        case var .object(o):
            if last {
                if replacing, o[first] == nil { throw PatchFailure(message: "replace: no member \"\(first)\" to replace") }
                o[first] = new
            } else {
                guard let child = o[first] else { throw PatchFailure(message: "no member \"\(first)\"") }
                o[first] = try insert(child, tokens.dropFirst(), new, replacing: replacing)
            }
            return .object(o)
        case var .array(a):
            if last, first == "-" {
                if replacing { throw PatchFailure(message: "replace: \"-\" is past the end of the array") }
                a.append(new)
            } else if let i = index(first) {
                if last {
                    if replacing {
                        guard i < a.count else { throw PatchFailure(message: "replace: index \(i) is outside the array of \(a.count)") }
                        a[i] = new
                    } else {
                        guard i <= a.count else { throw PatchFailure(message: "add: index \(i) is past the end of the array of \(a.count)") }
                        a.insert(new, at: i)
                    }
                } else {
                    guard i < a.count else { throw PatchFailure(message: "index \(i) is outside the array of \(a.count)") }
                    a[i] = try insert(a[i], tokens.dropFirst(), new, replacing: replacing)
                }
            } else {
                throw PatchFailure(message: "\"\(first)\" is not an array index")
            }
            return .array(a)
        default:
            throw PatchFailure(message: "cannot reach \"\(first)\" inside \(v.typeName)")
        }
    }

    private static func remove(_ v: JSONValue, _ tokens: ArraySlice<String>) throws -> (document: JSONValue, removed: JSONValue) {
        guard let first = tokens.first else { throw PatchFailure(message: "the document itself cannot be removed") }
        let last = tokens.count == 1
        switch v {
        case var .object(o):
            guard let child = o[first] else { throw PatchFailure(message: "no member \"\(first)\"") }
            if last {
                o[first] = nil
                return (.object(o), child)
            }
            let r = try remove(child, tokens.dropFirst())
            o[first] = r.document
            return (.object(o), r.removed)
        case var .array(a):
            guard let i = index(first) else { throw PatchFailure(message: "\"\(first)\" is not an array index") }
            guard i < a.count else { throw PatchFailure(message: "index \(i) is outside the array of \(a.count)") }
            if last {
                let gone = a.remove(at: i)
                return (.array(a), gone)
            }
            let r = try remove(a[i], tokens.dropFirst())
            a[i] = r.document
            return (.array(a), r.removed)
        default:
            throw PatchFailure(message: "cannot reach \"\(first)\" inside \(v.typeName)")
        }
    }
}
