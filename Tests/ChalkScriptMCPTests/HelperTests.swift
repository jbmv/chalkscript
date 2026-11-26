import Darwin
import Foundation
import Synchronization
import Testing
@testable import ChalkScriptMCP

/// The helper executable driven over stdio, with a stand-in for the studio on a socket.
@Suite(.timeLimit(.minutes(1)))
struct InitialisationTests {
    @Test func legacyInitializeAgreesTheRequestedRevision() throws {
        let helper = try HelperProcess(socket: temporarySocketPath())
        let reply = helper.request("initialize", [
            "protocolVersion": .string("2025-06-18"), "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("legacy"), "version": .string("1")]),
        ])
        let result = try #require(reply?["result"])
        #expect(result["protocolVersion"] == .string("2025-06-18"))
        #expect(result["capabilities"]?["tools"] != nil)
        #expect(result["serverInfo"]?["name"] == .string("chalkscript-mcp"))
        #expect(result["instructions"]?.string?.contains("ChalkScript Studio") == true)
        #expect(result["resultType"] == nil, "a legacy result has no resultType")
        helper.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)

        let list = helper.request("tools/list")
        #expect(list?["result"]?["tools"]?.array?.count == 6)
        #expect(list?["result"]?["resultType"] == nil)
    }

    @Test func instructionsAndToolDefinitionsStayUnder3000Characters() {
        let size = JSONValue.string(HelperTools.instructions).serialized.count
            + JSONValue.array(HelperTools.definitions).serialized.count
        #expect(size < 3000, "\(size) characters")
        #expect(HelperTools.instructions.contains("JSON Pointer"))
        #expect(HelperTools.definitions.first { $0["name"]?.string == "read" }?["description"]?.string?
            .contains("not the whole document") == true)
    }

    @Test func legacyInitializeOffersTheNewestLegacyRevisionForAnUnknownOne() throws {
        let helper = try HelperProcess(socket: temporarySocketPath())
        let reply = helper.request("initialize", ["protocolVersion": .string("2099-01-01"), "capabilities": .object([:])])
        #expect(reply?["result"]?["protocolVersion"] == .string("2025-11-25"))
    }

    @Test func modernDiscoverNeedsNoHandshake() throws {
        let helper = try HelperProcess(socket: temporarySocketPath())
        let result = try #require(helper.modern("server/discover")?["result"])
        #expect(result["resultType"] == .string("complete"))
        #expect(result["supportedVersions"] == .array([.string("2026-07-28")]))
        #expect(result["capabilities"]?["tools"] != nil)
        #expect(result["_meta"]?[MCPServer.Key.serverInfo]?["name"] == .string("chalkscript-mcp"))
        #expect(result["instructions"] != nil)

        let list = try #require(helper.modern("tools/list")?["result"])
        #expect(list["resultType"] == .string("complete"))
        #expect(list["tools"]?.array?.compactMap { $0["name"]?.string } == ["list", "read", "edit", "check", "show", "guide"])
    }

    @Test func modernRequestForAnUnsupportedRevisionIsRefusedWithTheSupportedOnes() throws {
        let helper = try HelperProcess(socket: temporarySocketPath())
        let reply = helper.request("tools/list", ["_meta": .object([
            MCPServer.Key.protocolVersion: .string("1900-01-01"), MCPServer.Key.clientCapabilities: .object([:]),
        ])])
        #expect(reply?["error"]?["code"]?.int == -32022)
        #expect(reply?["error"]?["data"]?["supported"] == .array([.string("2026-07-28")]))
        #expect(reply?["error"]?["data"]?["requested"] == .string("1900-01-01"))
    }

    @Test func modernRequestWithoutCapabilitiesIsInvalid() throws {
        let helper = try HelperProcess(socket: temporarySocketPath())
        let reply = helper.request("tools/list", ["_meta": .object([MCPServer.Key.protocolVersion: .string("2026-07-28")])])
        #expect(reply?["error"]?["code"]?.int == -32602)
    }

    @Test func requestWithNeitherMetadataNorHandshakeIsInvalid() throws {
        let helper = try HelperProcess(socket: temporarySocketPath())
        #expect(helper.request("tools/list")?["error"]?["code"]?.int == -32602)
        // A ping is answered in either era.
        #expect(helper.request("ping")?["result"] == .object([:]))
    }

    @Test func toolListIsShort() throws {
        // The whole list as a client receives it, measured on the serialised `tools` array.
        let size = JSONValue.array(HelperTools.definitions).serialized.count
        #expect(size < 2_500, "the tool list is \(size) characters")
        for tool in HelperTools.definitions {
            #expect((tool["description"]?.string?.count ?? 0) <= 220)
        }
    }

    @Test func exitsWhenInputCloses() throws {
        let helper = try HelperProcess(socket: temporarySocketPath())
        helper.closeInput()
        helper.process.waitUntilExit()
        #expect(helper.process.terminationStatus == 0)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ToolCallTests {
    @Test func listGivesEachDocumentOnOneLine() throws {
        let studio = try RunningStudio()
        let helper = try HelperProcess(socket: studio.path)
        let call = helper.tool("list")
        #expect(!call.isError)
        #expect(call.text == """
            project Examples
            subtraction 3f2a9c1b7e04 2 warnings "Two-digit subtraction"
            equal-groups 9ab1c2d3e4f5 unchecked
            """)
        #expect(call.result?["resultType"] == .string("complete"))
        #expect(studio.studio.requests.last?.method == "documents.list")
        #expect(studio.studio.requests.last?.client?.name == "test-client", "the client's name reaches the studio")
    }

    @Test func readForwardsThePointerAndKeepsTheValueAsWritten() throws {
        let studio = try RunningStudio()
        let helper = try HelperProcess(socket: studio.path)
        let call = helper.tool("read", ["doc": .string("subtraction"), "pointer": .string("/steps/trade")])
        #expect(!call.isError)
        #expect(call.text == "hash 3f2a9c1b7e04\n" + #"{"say":"trade","dur":0.10,"actions":{"z":1,"a":2}}"#)
        let request = try #require(studio.studio.requests.last)
        #expect(request.method == "document.read")
        #expect(request.params["pointer"] == .string("/steps/trade"))
        // Without a pointer the whole document is asked for.
        _ = helper.tool("read", ["doc": .string("subtraction")])
        #expect(studio.studio.requests.last?.params["pointer"] == .string(""))
    }

    @Test func editForwardsThePatchAndReportsTheNewHash() throws {
        let studio = try RunningStudio()
        let helper = try HelperProcess(socket: studio.path)
        let ops = try JSONValue.parse(#"[{"op":"replace","path":"/steps/trade/hold","value":0.5},{"op":"add","path":"/elements/x","value":{"kind":"text","at":[1,2]}}]"#)
        let call = helper.tool("edit", ["doc": .string("subtraction"), "base": .string(CannedStudio.hash), "ops": ops])
        #expect(!call.isError)
        #expect(call.text == "applied; hash aaaaaaaaaaaa; 1 warning")
        let request = try #require(studio.studio.requests.last)
        #expect(request.method == "document.patch")
        #expect(request.params["ops"] == ops, "the operations arrive as sent, keys in order")
        #expect(request.params["base"] == .string(CannedStudio.hash))
    }

    @Test func editAgainstAStaleHashIsAToolError() throws {
        let studio = try RunningStudio()
        let helper = try HelperProcess(socket: studio.path)
        let call = helper.tool("edit", ["doc": .string("subtraction"), "base": .string("000000000000"), "ops": .array([])])
        #expect(call.isError)
        #expect(call.text == "refused; hash 3f2a9c1b7e04\nerror patch /: The base is not the document's hash 3f2a9c1b7e04.")
    }

    @Test func checkWritesFindingsAsTheFormatWritesThem() throws {
        let studio = try RunningStudio()
        let helper = try HelperProcess(socket: studio.path)
        let call = helper.tool("check", ["doc": .string("subtraction"), "pointer": .string("/steps")])
        #expect(!call.isError)
        #expect(call.text == """
            hash 3f2a9c1b7e04; 2 errors
            error expr /steps/takeOnes/actions/cross/target @9: unknown name 'bo' (did you mean 'bO'?)
            error eval /steps/takeTens/actions/cross/target {a: 20, b: 11} t=1.5: ten[2] is outside ten (2 instances)
            """)
        #expect(studio.studio.requests.last?.params["pointer"] == .string("/steps"))
    }

    @Test func checkCountsWhatItDoesNotWriteOut() throws {
        let studio = try RunningStudio()
        let helper = try HelperProcess(socket: studio.path)
        let lines = helper.tool("check", ["doc": .string("many")]).text.split(separator: "\n")
        #expect(lines.first == "hash 3f2a9c1b7e04; 45 warnings")
        #expect(lines.count == 1 + HelperTools.findingLines + 1)
        #expect(lines.last == "and 5 more; check a narrower pointer to see them")
    }

    @Test func showReturnsAPictureOnlyWhenAsked() throws {
        let studio = try RunningStudio()
        let helper = try HelperProcess(socket: studio.path)
        let plain = helper.tool("show", ["doc": .string("subtraction"), "step": .string("trade")])
        #expect(plain.text == "showing trade (3 of 7)")
        #expect(plain.result?["content"]?.array?.count == 1)

        let problem: JSONValue = .object(["a": .int(52), "b": .int(17)])
        let pictured = helper.tool("show", ["doc": .string("subtraction"), "step": .string("trade"),
                                            "problem": problem, "image": .bool(true)])
        let content = try #require(pictured.result?["content"]?.array)
        #expect(content.count == 2)
        #expect(content[1]["type"] == .string("image"))
        #expect(content[1]["mimeType"] == .string("image/png"))
        #expect(studio.studio.requests.last?.params["problem"] == problem)
    }

    @Test func guideIsFetchedFromTheStudio() throws {
        let studio = try RunningStudio()
        let helper = try HelperProcess(socket: studio.path)
        #expect(helper.tool("guide", ["topic": .string("verbs")]).text == "Topics: format, verbs, editing.")
        #expect(studio.studio.requests.last?.method == "guide.read")
        #expect(studio.studio.requests.last?.params["topic"] == .string("verbs"))
    }

    @Test func aStudioRefusalReachesTheAgentAsAToolError() throws {
        let studio = try RunningStudio()
        let helper = try HelperProcess(socket: studio.path)
        let call = helper.tool("read", ["doc": .string("nothing")])
        #expect(call.isError)
        #expect(call.text == "No document named nothing is in the project.")
    }

    @Test func legacyCallsAreForwardedToo() throws {
        let studio = try RunningStudio()
        let helper = try HelperProcess(socket: studio.path)
        _ = helper.request("initialize", ["protocolVersion": .string("2025-11-25"), "capabilities": .object([:]),
                                          "clientInfo": .object(["name": .string("legacy-client"), "version": .string("2")])])
        let reply = helper.request("tools/call", ["name": .string("guide"), "arguments": .object([:])])
        #expect(reply?["result"]?["content"]?.array?.first?["text"] == .string("Topics: format, verbs, editing."))
        #expect(reply?["result"]?["resultType"] == nil)
        #expect(studio.studio.requests.last?.client?.name == "legacy-client")
    }

    @Test(arguments: [
        ("read", [:] as JSONObject, "The argument doc is required."),
        ("read", ["doc": .int(3)] as JSONObject, "The argument doc must be a string."),
        ("read", ["doc": .string("subtraction"), "pointer": .string("steps")] as JSONObject,
         "The pointer must be empty or begin with '/', as in /steps/trade."),
        ("edit", ["doc": .string("subtraction"), "base": .string("x"), "ops": .object([:])] as JSONObject,
         "The argument ops is required and must be an array of operations."),
        ("edit", ["doc": .string("subtraction"), "base": .string("x"), "ops": .array([.int(1)])] as JSONObject,
         "Each operation in ops must be an object."),
        ("show", ["doc": .string("subtraction"), "image": .string("yes")] as JSONObject, "The argument image must be true or false."),
    ])
    func badArgumentsAreToolErrorsAndReachNoStudio(_ name: String, _ arguments: JSONObject, _ message: String) throws {
        let studio = try RunningStudio()
        let helper = try HelperProcess(socket: studio.path)
        let call = helper.tool(name, arguments)
        #expect(call.isError)
        #expect(call.text == message)
        #expect(studio.studio.requests.isEmpty)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct StudioAbsentOrFaultyTests {
    @Test func noSocketMeansTheStudioIsNotOpen() throws {
        let helper = try HelperProcess(socket: temporarySocketPath())
        let call = helper.tool("list")
        #expect(call.isError)
        #expect(call.text == "ChalkScript Studio is not open. Ask the person to open it, then try again.")
    }

    @Test func aSocketLeftByAStudioThatQuitMeansTheStudioIsNotOpen() throws {
        let path = temporarySocketPath()
        close(try StudioSocket.listen(path: path))
        defer { unlink(path) }
        let helper = try HelperProcess(socket: path)
        #expect(helper.tool("read", ["doc": .string("subtraction")]).text.hasPrefix("ChalkScript Studio is not open."))
    }

    @Test func studioClosingMidCallIsAToolError() throws {
        let studio = try ScriptedStudio { reader, writer in
            ScriptedStudio.greet(reader, writer)
            ScriptedStudio.readRequest(reader)
        }
        let helper = try HelperProcess(socket: studio.path)
        let call = helper.tool("edit", ["doc": .string("subtraction"), "base": .string("x"), "ops": .array([])])
        #expect(call.isError)
        #expect(call.text.hasPrefix("ChalkScript Studio closed before answering"))
        // The helper is still serving.
        #expect(helper.request("ping")?["result"] != nil)
    }

    @Test func studioClosingBeforeHelloIsAToolError() throws {
        let studio = try ScriptedStudio { _, _ in }
        let helper = try HelperProcess(socket: studio.path)
        let call = helper.tool("list")
        #expect(call.isError)
        #expect(call.text.hasPrefix("ChalkScript Studio closed"))
    }

    @Test(arguments: [
        "this is not json",
        #"[1,2,3]"#,
        #"{"jsonrpc":"2.0","id":99,"result":{}}"#,
        #"{"jsonrpc":"2.0","id":2}"#,
        #"{"jsonrpc":"2.0","id":2,"error":{"message":"no code"}}"#,
    ])
    func malformedRepliesFromTheStudioAreToolErrors(_ line: String) throws {
        let studio = try ScriptedStudio { reader, writer in
            ScriptedStudio.greet(reader, writer)
            ScriptedStudio.readRequest(reader)
            writer.write(line: line)
        }
        let helper = try HelperProcess(socket: studio.path)
        let call = helper.tool("list")
        #expect(call.isError)
        #expect(call.text.hasPrefix("ChalkScript Studio sent a reply the helper cannot read"))
        #expect(helper.request("ping")?["result"] != nil)
    }

    @Test func aResultLackingWhatTheToolNeedsIsAToolError() throws {
        let studio = try ScriptedStudio { reader, writer in
            ScriptedStudio.greet(reader, writer)
            let id = ScriptedStudio.readRequest(reader) ?? .null
            writer.write(line: StudioListener.result(id: id, .object(["documents": .string("not an array")])))
        }
        let helper = try HelperProcess(socket: studio.path)
        let call = helper.tool("list")
        #expect(call.isError)
        #expect(call.text.contains("lacks a field it needs"))
    }

    @Test func aHelloWithoutTheProtocolIsMalformed() throws {
        let studio = try ScriptedStudio { reader, writer in
            let id = ScriptedStudio.readRequest(reader) ?? .null
            writer.write(line: StudioListener.result(id: id, .object([:])))
        }
        let helper = try HelperProcess(socket: studio.path)
        #expect(helper.tool("list").text.hasPrefix("ChalkScript Studio sent a reply the helper cannot read"))
    }

    @Test func aStudioOfAnotherProtocolVersionIsNamed() throws {
        let studio = try ScriptedStudio { reader, writer in
            let id = ScriptedStudio.readRequest(reader) ?? .null
            writer.write(line: StudioListener.error(id: id, code: Studio.ErrorCode.unsupportedProtocol, message: "No.",
                                                    data: .object(["supported": .array([.int(2)])])))
        }
        let helper = try HelperProcess(socket: studio.path)
        let call = helper.tool("list")
        #expect(call.isError)
        #expect(call.text.hasPrefix("ChalkScript Studio speaks version 2 of the helper protocol"))
    }

    @Test func notificationsFromTheStudioAreIgnored() throws {
        let studio = try ScriptedStudio { reader, writer in
            ScriptedStudio.greet(reader, writer)
            let id = ScriptedStudio.readRequest(reader) ?? .null
            writer.write(line: #"{"jsonrpc":"2.0","method":"progress","params":{}}"#)
            writer.write(line: StudioListener.result(id: id, .object(["text": .string("guide text")])))
        }
        let helper = try HelperProcess(socket: studio.path)
        #expect(helper.tool("guide").text == "guide text")
    }

    @Test func aStudioThatDoesNotAnswerTimesOut() throws {
        let studio = try ScriptedStudio { reader, writer in
            ScriptedStudio.greet(reader, writer)
            ScriptedStudio.readRequest(reader)
            _ = reader.next(deadline: .now + .seconds(5))
        }
        let client = StudioClient(socketPath: studio.path, callTimeout: .milliseconds(300))
        let result = try #require(HelperTools.call("list", arguments: [:], studio: client))
        #expect(result.isError)
        #expect(result.content.first?["text"]?.string?.hasPrefix("ChalkScript Studio did not answer within") == true)
    }

    @Test func aCancelledCallIsNotAnsweredAndClosesItsConnection() throws {
        let sawClose = Mutex(false)
        let studio = try ScriptedStudio { reader, writer in
            ScriptedStudio.greet(reader, writer)
            ScriptedStudio.readRequest(reader)
            if reader.next(deadline: .now + .seconds(10)) == .end { sawClose.withLock { $0 = true } }
        }
        let helper = try HelperProcess(socket: studio.path)
        var params: JSONObject = ["name": .string("list"), "arguments": .object([:])]
        params["_meta"] = HelperProcess.modernMeta
        helper.send(.object(["jsonrpc": .string("2.0"), "id": .string("call-1"), "method": .string("tools/call"),
                             "params": .object(params)]))
        Thread.sleep(forTimeInterval: 0.3)
        helper.send(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":"call-1"}}"#)
        #expect(studio.done.wait(timeout: .now() + 5) == .success)
        #expect(sawClose.withLock { $0 }, "the studio sees the call's connection close")
        // The next message is the ping's reply, not the cancelled call's.
        let reply = helper.request("ping")
        #expect(reply?["result"] != nil)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct MalformedClientInputTests {
    @Test func helperAnswersAndSurvivesMalformedInput() throws {
        let helper = try HelperProcess(socket: temporarySocketPath())
        let cases: [(String, Int?)] = [
            ("not json at all", -32700),
            (#"{"jsonrpc":"2.0","id":1,"method":"tools/list""#, -32700),
            (#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#, -32600),
            (#""a string""#, -32600),
            (#"{"jsonrpc":"2.0","id":1}"#, -32600),
            (#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#, -32600),
            (#"{"jsonrpc":"2.0","id":{"x":1},"method":"ping"}"#, -32600),
            (#"{"jsonrpc":"1.0","id":1,"method":"ping"}"#, -32600),
            (#"{"jsonrpc":"2.0","id":1,"method":"ping","params":[1]}"#, -32602),
            (#"{"jsonrpc":"2.0","id":1,"method":"no/such","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}"#, -32601),
            (#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"nope","_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}"#, -32602),
            (#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list","arguments":[],"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}"#, -32602),
            (#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}"#, -32602),
            (String(repeating: "[", count: 50_000), -32700),
            // A response and an unknown notification get no reply.
            (#"{"jsonrpc":"2.0","id":7,"result":{}}"#, nil),
            (#"{"jsonrpc":"2.0","method":"notifications/whatever"}"#, nil),
            (#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":"never-sent"}}"#, nil),
        ]
        for (line, code) in cases {
            helper.send(line)
            if let code {
                let reply = helper.receive()
                #expect(reply?["error"]?["code"]?.int == code, "\(line.prefix(80))")
            }
        }
        // Invalid UTF-8, and a blank line, which is skipped.
        helper.sendRaw([0x7B, 0xFF, 0xFE, 0x7D, 0x0A, 0x0A])
        #expect(helper.receive()?["error"]?["code"]?.int == -32700)
        // After all of it, the helper still answers.
        #expect(helper.request("ping")?["result"] != nil)
        #expect(helper.process.isRunning)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct StudioListenerTests {
    @Test func listenerRefusesAnotherProtocolAndRequestsBeforeHello() throws {
        let studio = try RunningStudio()
        let other = StudioClient(socketPath: studio.path)

        // A request before hello is refused.
        let fd = try StudioSocket.connect(path: studio.path).get()
        defer { close(fd) }
        LineWriter(fd: fd).write(line: #"{"jsonrpc":"2.0","id":1,"method":"documents.list","params":{}}"#)
        guard case .line(let bytes) = LineReader(fd: fd).next(deadline: .now + .seconds(5)) else {
            Issue.record("no reply")
            return
        }
        #expect(try JSONValue.parse(bytes)["error"]?["code"]?.int == Studio.RPCError.invalidRequest)
        #expect(studio.studio.requests.isEmpty)

        // A well-formed call goes through.
        #expect(other.call(Studio.Method.guide) == .result(.object(["text": .string("Topics: format, verbs, editing.")])))

        // A hello naming another protocol is answered with the supported one.
        let fd2 = try StudioSocket.connect(path: studio.path).get()
        defer { close(fd2) }
        LineWriter(fd: fd2).write(line: #"{"jsonrpc":"2.0","id":1,"method":"hello","params":{"protocol":9}}"#)
        guard case .line(let reply) = LineReader(fd: fd2).next(deadline: .now + .seconds(5)) else {
            Issue.record("no reply")
            return
        }
        let error = try JSONValue.parse(reply)["error"]
        #expect(error?["code"]?.int == Studio.ErrorCode.unsupportedProtocol)
        #expect(error?["data"]?["supported"] == .array([.int(1)]))
    }

    @Test func listenerRemovesItsSocketWhenStopped() throws {
        let path = temporarySocketPath()
        let listener = StudioListener(path: path, app: Implementation(name: "x", version: "1"), handler: CannedStudio())
        try listener.start()
        #expect(FileManager.default.fileExists(atPath: path))
        listener.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(StudioClient(socketPath: path).call(Studio.Method.list) == .notRunning)
    }
}
