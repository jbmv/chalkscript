#if os(macOS)
import Dispatch
import Foundation

/// The MCP server the helper runs on stdio. It holds no document state: each tool call is
/// forwarded to the studio, and only the legacy handshake leaves anything behind.
///
/// It serves both eras of the protocol. A request whose `_meta` names revision `2026-07-28` is
/// served statelessly by that revision; after an `initialize`, a request without that `_meta` is
/// served by the legacy revision the handshake agreed.
public final class MCPServer: @unchecked Sendable {
    /// The revision served by per-request metadata.
    public static let modernVersion = "2026-07-28"
    /// The revisions an `initialize` handshake may agree, newest first.
    public static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    enum Key {
        static let protocolVersion = "io.modelcontextprotocol/protocolVersion"
        static let clientInfo = "io.modelcontextprotocol/clientInfo"
        static let clientCapabilities = "io.modelcontextprotocol/clientCapabilities"
        static let serverInfo = "io.modelcontextprotocol/serverInfo"
    }

    enum Code {
        static let unsupportedProtocolVersion = -32022
    }

    private let studio: StudioClient
    private let send: @Sendable (String) -> Void
    private let lock = NSLock()
    private var legacyVersion: String?
    private var legacyClient: Implementation?
    /// Calls waiting on the studio, by their request id's JSON text.
    private var inFlight: [String: StudioCancellation] = [:]
    private let calls = DispatchGroup()

    /// - Parameter send: writes one message; called from several threads, so it serialises itself.
    public init(studio: StudioClient, send: @escaping @Sendable (String) -> Void) {
        self.studio = studio
        self.send = send
    }

    private var serverInfo: JSONValue { Implementation(name: HelperInfo.name, version: HelperInfo.version).json }

    /// Reads messages from `input` until it ends.
    public func run(input: Int32) {
        let reader = LineReader(fd: input)
        while true {
            switch reader.next() {
            case .line(let bytes): receive(bytes)
            case .tooLong: send(Self.error(id: .null, code: Studio.RPCError.parse, message: "Message too long"))
            case .end, .failed, .timedOut: return
            }
        }
    }

    /// Waits until every tool call has answered; for tests and an orderly exit.
    public func waitForCalls(timeout: Duration = .seconds(5)) {
        _ = calls.wait(timeout: .now() + .milliseconds(Int(timeout.components.seconds * 1000)))
    }

    /// Handles one message. A tool call runs on another thread, so that `ping` and cancellation are
    /// answered while it waits on the studio.
    public func receive(_ bytes: [UInt8]) {
        let message: JSONValue
        do {
            message = try JSONValue.parse(bytes)
        } catch {
            send(Self.error(id: .null, code: Studio.RPCError.parse, message: "Parse error: \(error)"))
            return
        }
        guard let object = message.object else {
            send(Self.error(id: .null, code: Studio.RPCError.invalidRequest,
                            message: "Invalid request: a message must be one JSON object"))
            return
        }
        guard let method = object["method"]?.string else {
            // A response from the client answers nothing this server asked, and is ignored.
            if object["result"] != nil || object["error"] != nil { return }
            send(Self.error(id: object["id"] ?? .null, code: Studio.RPCError.invalidRequest,
                            message: "Invalid request: no method"))
            return
        }
        let params = object["params"]
        guard let id = object["id"] else {
            notification(method, params?.object ?? [:])
            return
        }
        switch id {
        case .string, .number: break
        default:
            send(Self.error(id: .null, code: Studio.RPCError.invalidRequest,
                            message: "Invalid request: id must be a string or a number"))
            return
        }
        guard object["jsonrpc"]?.string == "2.0" else {
            send(Self.error(id: id, code: Studio.RPCError.invalidRequest, message: "Invalid request: jsonrpc must be \"2.0\""))
            return
        }
        if let params, params.object == nil {
            send(Self.error(id: id, code: Studio.RPCError.invalidParams, message: "Invalid params: params must be an object"))
            return
        }
        request(id: id, method: method, params: params?.object ?? [:])
    }

    private func notification(_ method: String, _ params: JSONObject) {
        guard method == "notifications/cancelled", let requestId = params["requestId"] else { return }
        let token = lock.withLock { inFlight[requestId.serialized] }
        token?.cancel()
    }

    private func request(id: JSONValue, method: String, params: JSONObject) {
        if method == "initialize" {
            initialize(id: id, params: params)
            return
        }
        if method == "ping" {
            reply(id: id, modern: params["_meta"]?[Key.protocolVersion] != nil, .object([:]))
            return
        }

        // Which era serves this request.
        let modern: Bool
        let client: Implementation?
        let meta = params["_meta"]?.object
        if let version = meta?[Key.protocolVersion] {
            guard version.string == Self.modernVersion else {
                send(Self.error(id: id, code: Code.unsupportedProtocolVersion, message: "Unsupported protocol version",
                                data: .object(["supported": .array([.string(Self.modernVersion)]), "requested": version])))
                return
            }
            guard meta?[Key.clientCapabilities]?.object != nil else {
                send(Self.error(id: id, code: Studio.RPCError.invalidParams,
                                message: "Invalid params: _meta lacks \(Key.clientCapabilities)"))
                return
            }
            modern = true
            client = Implementation(json: meta?[Key.clientInfo])
        } else if let agreed = lock.withLock({ legacyVersion.map { ($0, legacyClient) } }) {
            modern = false
            client = agreed.1
        } else {
            send(Self.error(id: id, code: Studio.RPCError.invalidParams,
                            message: "Invalid params: _meta lacks \(Key.protocolVersion); "
                                + "a client of revision \(Self.legacyVersions[0]) or earlier sends initialize first"))
            return
        }

        switch method {
        case "server/discover" where modern:
            reply(id: id, modern: true, .object([
                "supportedVersions": .array([.string(Self.modernVersion)]),
                "capabilities": .object(["tools": .object([:])]),
                "instructions": .string(HelperTools.instructions),
            ]))
        case "tools/list":
            reply(id: id, modern: modern, .object(["tools": .array(HelperTools.definitions)]))
        case "tools/call":
            toolCall(id: id, modern: modern, params: params, client: client)
        default:
            send(Self.error(id: id, code: Studio.RPCError.methodNotFound, message: "Method not found: \(method)"))
        }
    }

    private func initialize(id: JSONValue, params: JSONObject) {
        let requested = params["protocolVersion"]?.string
        let agreed = requested.flatMap { Self.legacyVersions.contains($0) ? $0 : nil } ?? Self.legacyVersions[0]
        lock.withLock {
            legacyVersion = agreed
            legacyClient = Implementation(json: params["clientInfo"])
        }
        send(Self.result(id: id, .object([
            "protocolVersion": .string(agreed),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": serverInfo,
            "instructions": .string(HelperTools.instructions),
        ])))
    }

    private func toolCall(id: JSONValue, modern: Bool, params: JSONObject, client: Implementation?) {
        guard let name = params["name"]?.string else {
            send(Self.error(id: id, code: Studio.RPCError.invalidParams, message: "Invalid params: name must be a string"))
            return
        }
        let arguments: JSONObject
        switch params["arguments"] {
        case nil, .null?: arguments = [:]
        case .object(let object)?: arguments = object
        default:
            send(Self.error(id: id, code: Studio.RPCError.invalidParams, message: "Invalid params: arguments must be an object"))
            return
        }
        guard HelperTools.names.contains(name) else {
            send(Self.error(id: id, code: Studio.RPCError.invalidParams, message: "Unknown tool: \(name)"))
            return
        }
        let key = id.serialized
        let cancellation = StudioCancellation()
        lock.withLock { inFlight[key] = cancellation }
        calls.enter()
        DispatchQueue.global().async { [self] in
            defer { calls.leave() }
            let result = HelperTools.call(name, arguments: arguments, studio: studio, client: client,
                                          cancellation: cancellation)
            lock.withLock { inFlight[key] = nil }
            // A cancelled call is not answered.
            guard let result, !cancellation.isCancelled else { return }
            reply(id: id, modern: modern, result.json)
        }
    }

    /// Sends a result; a modern one carries `resultType` and the server's identity.
    private func reply(id: JSONValue, modern: Bool, _ result: JSONValue) {
        guard modern, var object = result.object else {
            send(Self.result(id: id, result))
            return
        }
        object["resultType"] = .string("complete")
        object["_meta"] = .object([Key.serverInfo: serverInfo])
        send(Self.result(id: id, .object(object)))
    }

    static func result(id: JSONValue, _ result: JSONValue) -> String {
        JSONValue.object(["jsonrpc": .string("2.0"), "id": id, "result": result]).serialized
    }

    static func error(id: JSONValue, code: Int, message: String, data: JSONValue? = nil) -> String {
        var error: JSONObject = ["code": .int(code), "message": .string(message)]
        if let data { error["data"] = data }
        return JSONValue.object(["jsonrpc": .string("2.0"), "id": id, "error": .object(error)]).serialized
    }
}

#endif
