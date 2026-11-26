#if os(macOS)
import Darwin
import Foundation

/// What became of one call forwarded to the studio.
public enum StudioOutcome: Sendable, Equatable {
    case result(JSONValue)
    /// The studio answered with an error, whose message is meant to be read by the agent.
    case refused(code: Int, message: String, data: JSONValue?)
    case notRunning
    case notOwned
    /// The studio speaks other versions of the protocol than the helper.
    case versionMismatch(studio: [Int])
    /// The connection closed before the reply came. `afterRequest` is true when the request had
    /// been sent, so the studio may have acted on it.
    case closed(afterRequest: Bool)
    case timedOut
    /// The studio sent something that is not a reply this protocol allows.
    case malformed(String)
    case cancelled
    case failed(String)
}

/// Lets another thread stop a call that is waiting on the studio.
public final class StudioCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var cancelledFlag = false

    public init() {}

    public var isCancelled: Bool { lock.withLock { cancelledFlag } }

    /// Closes the call's connection, which the studio sees as the helper going away.
    public func cancel() {
        lock.withLock {
            cancelledFlag = true
            if fd >= 0 { shutdown(fd, SHUT_RDWR) }
        }
    }

    func attach(_ descriptor: Int32) -> Bool {
        lock.withLock {
            if cancelledFlag { return false }
            fd = descriptor
            return true
        }
    }

    func detach() { lock.withLock { fd = -1 } }
}

/// The helper's end of the studio socket. Each call opens a connection, says `hello`, sends one
/// request, reads its reply and closes, so no state outlives a call and calls may run at once.
public struct StudioClient: Sendable {
    public var socketPath: String
    public var helper: Implementation
    public var helloTimeout: Duration
    public var callTimeout: Duration

    public init(socketPath: String = StudioSocket.defaultPath,
                helper: Implementation = Implementation(name: "chalkscript-mcp", version: HelperInfo.version),
                helloTimeout: Duration = .seconds(5), callTimeout: Duration = .seconds(120)) {
        self.socketPath = socketPath
        self.helper = helper
        self.helloTimeout = helloTimeout
        self.callTimeout = callTimeout
    }

    /// - Parameter client: the MCP client's name and version, which the studio may show.
    public func call(_ method: String, params: JSONObject = [:], client: Implementation? = nil,
                     cancellation: StudioCancellation? = nil) -> StudioOutcome {
        let fd: Int32
        switch StudioSocket.connect(path: socketPath) {
        case .success(let descriptor): fd = descriptor
        case .failure(.notRunning): return .notRunning
        case .failure(.notOwned): return .notOwned
        case .failure(.pathTooLong): return .failed("the socket path is longer than \(StudioSocket.maximumPathLength) bytes")
        case .failure(.failed(let code)): return .failed(String(cString: strerror(code)))
        }
        defer {
            cancellation?.detach()
            close(fd)
        }
        if let cancellation, !cancellation.attach(fd) { return .cancelled }
        let outcome = exchange(fd: fd, method: method, params: params, client: client)
        if cancellation?.isCancelled == true { return .cancelled }
        return outcome
    }

    private func exchange(fd: Int32, method: String, params: JSONObject, client: Implementation?) -> StudioOutcome {
        let writer = LineWriter(fd: fd)
        let reader = LineReader(fd: fd)

        var helloParams: JSONObject = ["protocol": .int(Studio.protocolVersion), "helper": helper.json]
        if let client { helloParams["client"] = client.json }
        guard writer.write(line: request(id: 1, method: Studio.Method.hello, params: helloParams)) else {
            return .closed(afterRequest: false)
        }
        switch reply(to: 1, from: reader, deadline: .now + helloTimeout, afterRequest: false) {
        case .result(let result):
            guard result["protocol"]?.int == Studio.protocolVersion else {
                return .malformed("hello's result does not name protocol \(Studio.protocolVersion)")
            }
        case .refused(let code, _, let data) where code == Studio.ErrorCode.unsupportedProtocol:
            return .versionMismatch(studio: data?["supported"]?.array?.compactMap(\.int) ?? [])
        case let other:
            return other
        }

        guard writer.write(line: request(id: 2, method: method, params: params)) else {
            return .closed(afterRequest: false)
        }
        return reply(to: 2, from: reader, deadline: .now + callTimeout, afterRequest: true)
    }

    private func request(id: Int, method: String, params: JSONObject) -> String {
        JSONValue.object(["jsonrpc": .string("2.0"), "id": .int(id), "method": .string(method),
                          "params": .object(params)]).serialized
    }

    private func reply(to id: Int, from reader: LineReader, deadline: ContinuousClock.Instant,
                       afterRequest: Bool) -> StudioOutcome {
        while true {
            switch reader.next(deadline: deadline) {
            case .end, .failed: return .closed(afterRequest: afterRequest)
            case .timedOut: return .timedOut
            case .tooLong: return .malformed("a line longer than the helper reads")
            case .line(let bytes):
                guard let message = try? JSONValue.parse(bytes), let object = message.object else {
                    return .malformed("a line that is not a JSON object")
                }
                // A notification is allowed and ignored, so a later studio may send progress.
                if object["id"] == nil, object["method"] != nil { continue }
                guard object["id"]?.int == id else { return .malformed("a reply to a request it was not sent") }
                if let result = object["result"] { return .result(result) }
                if let error = object["error"], let code = error["code"]?.int {
                    return .refused(code: code, message: error["message"]?.string ?? "", data: error["data"])
                }
                return .malformed("a reply with neither a result nor an error")
            }
        }
    }
}

public enum HelperInfo {
    public static let name = "chalkscript-mcp"
    public static let version = "0.1.0"
}

#endif
