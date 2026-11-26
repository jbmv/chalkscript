import Darwin
import Foundation
import Testing
@testable import ChalkScriptMCP

/// A socket path in the temporary folder, short enough for `sockaddr_un`.
func temporarySocketPath() -> String {
    let folder = FileManager.default.temporaryDirectory.path
    return folder + "/csmcp-\(UUID().uuidString.prefix(8)).sock"
}

/// A stand-in for the studio app that answers every method with canned values, through the
/// library's own listener. It records what it was asked.
final class CannedStudio: StudioHandler, @unchecked Sendable {
    static let hash = "3f2a9c1b7e04"
    static let newHash = "aaaaaaaaaaaa"

    private let lock = NSLock()
    private var received: [(method: String, params: JSONObject, client: Implementation?)] = []

    var requests: [(method: String, params: JSONObject, client: Implementation?)] { lock.withLock { received } }

    func respond(to method: String, params: JSONObject, client: Implementation?) -> StudioReply {
        lock.withLock { received.append((method, params, client)) }
        let doc = params["doc"]?.string
        if let doc, !["subtraction", "many"].contains(doc) {
            return .error(code: Studio.ErrorCode.noDocument, message: "No document named \(doc) is in the project.")
        }
        switch method {
        case Studio.Method.list:
            return .result(.object([
                "project": .string("Examples"),
                "documents": .array([
                    DocumentSummary(doc: "subtraction", title: "Two-digit subtraction", hash: Self.hash, errors: 0, warnings: 2).json,
                    DocumentSummary(doc: "equal-groups", hash: "9ab1c2d3e4f5").json,
                ]),
            ]))
        case Studio.Method.read:
            let value = try! JSONValue.parse(#"{"say":"trade","dur":0.10,"actions":{"z":1,"a":2}}"#)
            return .result(.object(["hash": .string(Self.hash), "value": value]))
        case Studio.Method.patch:
            if params["base"]?.string == Self.hash {
                return .result(.object(["applied": .bool(true), "hash": .string(Self.newHash),
                                        "errors": .int(0), "warnings": .int(1)]))
            }
            let stale = Finding(severity: "error", code: "patch", path: "",
                                message: "The base is not the document's hash \(Self.hash).")
            return .result(.object(["applied": .bool(false), "hash": .string(Self.hash),
                                    "errors": .int(1), "warnings": .int(0), "findings": .array([stale.json])]))
        case Studio.Method.check:
            var findings: [Finding]
            if doc == "many" {
                findings = (0..<45).map {
                    Finding(severity: "warning", code: "unknown", path: "/steps/s\($0)/x", message: "Unknown key x.")
                }
            } else {
                findings = [
                    Finding(severity: "error", code: "expr", path: "/steps/takeOnes/actions/cross/target", at: 9,
                            message: "unknown name 'bo' (did you mean 'bO'?)"),
                    Finding(severity: "error", code: "eval", path: "/steps/takeTens/actions/cross/target",
                            values: ["a": .int(20), "b": .int(11)], time: 1.5, message: "ten[2] is outside ten (2 instances)"),
                ]
            }
            return .result(.object(["hash": .string(Self.hash), "errors": .int(findings.filter { $0.severity == "error" }.count),
                                    "warnings": .int(findings.filter { $0.severity == "warning" }.count),
                                    "findings": .array(findings.map(\.json))]))
        case Studio.Method.show:
            var result: JSONObject = ["step": .string(params["step"]?.string ?? "start"), "index": .int(3), "count": .int(7)]
            if params["image"]?.bool == true {
                result["image"] = .object(["data": .string("iVBORw0KGgo="), "mimeType": .string("image/png")])
                if let ratio = params["ratio"] {
                    result["ratio"] = ratio
                    result["layout"] = .string("tall")
                    if ratio == .number("0.75") { result["drawn"] = .number("0.9") }
                }
            }
            return .result(.object(result))
        case Studio.Method.guide:
            return .result(.object(["text": .string("Topics: format, verbs, editing.")]))
        default:
            return .error(code: Studio.RPCError.methodNotFound, message: "No method \(method).")
        }
    }
}

/// A listener running a `CannedStudio`, removed when the test ends.
final class RunningStudio {
    let path = temporarySocketPath()
    let studio = CannedStudio()
    let listener: StudioListener

    init() throws {
        listener = StudioListener(path: path, app: Implementation(name: "stand-in", version: "1"), handler: studio)
        try listener.start()
    }

    deinit { listener.stop() }
}

/// A stand-in that accepts one connection and runs a script against the raw socket, for the
/// cases a well-behaved studio never produces.
final class ScriptedStudio: @unchecked Sendable {
    let path = temporarySocketPath()
    private let listening: Int32
    let done = DispatchSemaphore(value: 0)

    init(_ script: @escaping @Sendable (_ reader: LineReader, _ writer: LineWriter) -> Void) throws {
        listening = try StudioSocket.listen(path: path)
        let fd = listening
        let done = done
        Thread {
            let connection = accept(fd, nil, nil)
            if connection >= 0 {
                StudioSocket.noSignalOnBrokenPipe(connection)
                script(LineReader(fd: connection), LineWriter(fd: connection))
                close(connection)
            }
            done.signal()
        }.start()
    }

    deinit {
        close(listening)
        unlink(path)
    }

    /// Reads the helper's hello and answers it as a studio of protocol 1 would.
    static func greet(_ reader: LineReader, _ writer: LineWriter) {
        guard case .line(let bytes) = reader.next(deadline: .now + .seconds(5)),
              let hello = try? JSONValue.parse(bytes), let id = hello["id"] else { return }
        writer.write(line: StudioListener.result(id: id, .object(["protocol": .int(1),
                                                                  "app": .object(["name": .string("scripted")])])))
    }

    /// Reads one request and returns its id.
    @discardableResult
    static func readRequest(_ reader: LineReader) -> JSONValue? {
        guard case .line(let bytes) = reader.next(deadline: .now + .seconds(5)) else { return nil }
        return (try? JSONValue.parse(bytes))?["id"]
    }
}

/// The helper executable, launched as a client launches it, with pipes for its standard streams.
final class HelperProcess {
    let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let reader: LineReader
    private var nextId = 100

    static var executable: URL {
        // The tests' bundle is built beside the executable, in the same products folder.
        for bundle in Bundle.allBundles where bundle.bundleURL.pathExtension == "xctest" {
            let candidate = bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("chalkscript-mcp")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        var folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while folder.path != "/" {
            let candidate = folder.appendingPathComponent(".build/debug/chalkscript-mcp")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            folder.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: "chalkscript-mcp")
    }

    init(socket: String) throws {
        process.executableURL = Self.executable
        process.arguments = ["--socket", socket]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        reader = LineReader(fd: stdout.fileHandleForReading.fileDescriptor)
    }

    deinit {
        if process.isRunning { process.terminate() }
    }

    func sendRaw(_ bytes: [UInt8]) {
        stdin.fileHandleForWriting.write(Data(bytes))
    }

    func send(_ text: String) { sendRaw(Array((text + "\n").utf8)) }

    func send(_ message: JSONValue) { send(message.serialized) }

    /// The next message on stdout, or nil if none comes in time.
    func receive(within timeout: Duration = .seconds(10)) -> JSONValue? {
        guard case .line(let bytes) = reader.next(deadline: .now + timeout) else { return nil }
        return try? JSONValue.parse(bytes)
    }

    static let modernMeta: JSONValue = .object([
        MCPServer.Key.protocolVersion: .string(MCPServer.modernVersion),
        MCPServer.Key.clientInfo: .object(["name": .string("test-client"), "version": .string("1.0")]),
        MCPServer.Key.clientCapabilities: .object([:]),
    ])

    /// Sends a modern request and returns its reply.
    func modern(_ method: String, _ params: JSONObject = [:]) -> JSONValue? {
        var params = params
        params["_meta"] = Self.modernMeta
        return request(method, params)
    }

    func request(_ method: String, _ params: JSONObject = [:]) -> JSONValue? {
        nextId += 1
        let id = nextId
        send(.object(["jsonrpc": .string("2.0"), "id": .int(id), "method": .string(method), "params": .object(params)]))
        let reply = receive()
        #expect(reply?["id"]?.int == id, "the reply answers the request")
        return reply
    }

    /// Calls a tool by the modern revision and returns its text and whether it is an error.
    func tool(_ name: String, _ arguments: JSONObject = [:]) -> (text: String, isError: Bool, result: JSONValue?) {
        let reply = modern("tools/call", ["name": .string(name), "arguments": .object(arguments)])
        let result = reply?["result"]
        let text = result?["content"]?.array?.first?["text"]?.string ?? ""
        return (text, result?["isError"]?.bool ?? false, result)
    }

    func closeInput() { try? stdin.fileHandleForWriting.close() }
}
