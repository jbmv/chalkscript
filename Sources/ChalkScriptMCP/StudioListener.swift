#if os(macOS)
import Darwin
import Foundation

/// A studio's answer to one request.
public enum StudioReply: Sendable, Equatable {
    case result(JSONValue)
    /// `message` is one sentence the agent reads, saying what to do differently.
    case error(code: Int, message: String, data: JSONValue? = nil)
}

/// What the studio app implements to answer the helper: one request at a time per connection,
/// with `hello` already handled.
///
/// Called on a background thread, one per connection; an app that keeps its state on the main
/// actor hops there itself.
public protocol StudioHandler: Sendable {
    func respond(to method: String, params: JSONObject, client: Implementation?) -> StudioReply
}

/// The studio's end of the socket: accepts the helper's connections and answers `hello` and the
/// requests that follow it through a `StudioHandler`.
public final class StudioListener: @unchecked Sendable {
    public let path: String
    private let app: Implementation
    private let handler: StudioHandler
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var stopped = false

    public init(path: String = StudioSocket.defaultPath, app: Implementation, handler: StudioHandler) {
        self.path = path
        self.app = app
        self.handler = handler
    }

    /// Creates the socket and starts accepting connections on a background thread.
    public func start() throws {
        let descriptor = try StudioSocket.listen(path: path)
        lock.withLock { fd = descriptor }
        let thread = Thread { [self] in acceptLoop(descriptor) }
        thread.name = "studio socket"
        thread.start()
    }

    /// Stops accepting and removes the socket file. Connections already open finish their request.
    public func stop() {
        lock.withLock {
            guard !stopped else { return }
            stopped = true
            unlink(path)
        }
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func acceptLoop(_ listening: Int32) {
        defer { close(listening) }
        while !isStopped {
            var pfd = pollfd(fd: listening, events: Int16(POLLIN), revents: 0)
            // A short poll lets `stop()` take effect without closing the descriptor under accept.
            if poll(&pfd, 1, 100) <= 0 { continue }
            let connection = accept(listening, nil, nil)
            if connection < 0 { continue }
            StudioSocket.noSignalOnBrokenPipe(connection)
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(connection, &uid, &gid) == 0, uid == getuid() else {
                close(connection)
                continue
            }
            let thread = Thread { [self] in serve(connection) }
            thread.name = "studio connection"
            thread.start()
        }
    }

    private func serve(_ connection: Int32) {
        defer { close(connection) }
        let reader = LineReader(fd: connection)
        let writer = LineWriter(fd: connection)
        var client: Implementation?
        var greeted = false
        while true {
            let bytes: [UInt8]
            switch reader.next() {
            case .line(let line): bytes = line
            case .tooLong:
                writer.write(line: Self.error(id: .null, code: Studio.RPCError.parse, message: "The line is too long."))
                continue
            case .end, .failed, .timedOut: return
            }
            guard let message = try? JSONValue.parse(bytes) else {
                writer.write(line: Self.error(id: .null, code: Studio.RPCError.parse, message: "The line is not JSON."))
                continue
            }
            guard let object = message.object, let method = object["method"]?.string else {
                writer.write(line: Self.error(id: .null, code: Studio.RPCError.invalidRequest,
                                              message: "The message is not a request."))
                continue
            }
            guard let id = object["id"] else { continue }
            let params = object["params"]?.object ?? [:]
            if method == Studio.Method.hello {
                guard params["protocol"]?.int == Studio.protocolVersion else {
                    writer.write(line: Self.error(
                        id: id, code: Studio.ErrorCode.unsupportedProtocol,
                        message: "This studio speaks protocol \(Studio.protocolVersion).",
                        data: .object(["supported": .array([.int(Studio.protocolVersion)])])))
                    return
                }
                greeted = true
                client = Implementation(json: params["client"])
                writer.write(line: Self.result(id: id, .object(["protocol": .int(Studio.protocolVersion),
                                                                "app": app.json])))
                continue
            }
            guard greeted else {
                writer.write(line: Self.error(id: id, code: Studio.RPCError.invalidRequest,
                                              message: "The first request must be hello."))
                return
            }
            switch handler.respond(to: method, params: params, client: client) {
            case .result(let result): writer.write(line: Self.result(id: id, result))
            case .error(let code, let text, let data): writer.write(line: Self.error(id: id, code: code, message: text, data: data))
            }
        }
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
