import ChalkScript
import ChalkScriptMCP
import Foundation
import Testing
@testable import ChalkScriptStudioCore

/// The repository's root, for the example documents, the guide and the extension's manifest.
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let examples = ["subtraction.explainer", "equal-groups.explainer"].map {
    repository.appendingPathComponent("docs/format/examples").appendingPathComponent($0)
}

/// A project folder in the temporary folder holding copies of the examples, removed afterwards.
final class TemporaryProject {
    let folder: URL

    init(examples files: [URL] = examples) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("studio-\(UUID().uuidString.prefix(8))")
        try ProjectFolder.addExamples(files, to: folder)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    func url(_ name: String) -> URL { folder.appendingPathComponent(name + ".explainer") }
}

@MainActor
func openModel(_ project: TemporaryProject, watch: Bool = false) throws -> StudioModel {
    let guide = try AuthoringGuide(contentsOf: repository.appendingPathComponent("docs/format/authoring-guide.md"))
    let model = StudioModel(guide: guide, drivesPlayer: false)
    model.open(folder: project.folder, watch: watch)
    return model
}

extension StudioReply {
    var result: ChalkScriptMCP.JSONValue? {
        if case let .result(r) = self { return r }
        return nil
    }

    var errorCode: Int? {
        if case let .error(code, _, _) = self { return code }
        return nil
    }

    var errorMessage: String? {
        if case let .error(_, message, _) = self { return message }
        return nil
    }
}

func params(_ text: String) throws -> ChalkScriptMCP.JSONObject {
    try ChalkScriptMCP.JSONValue.parse(text).object!
}

/// The studio's end of the helper protocol, answered from a project of the two examples.
@MainActor
struct StudioMethodTests {
    @Test func listGivesEveryDocumentWithItsHashAndCounts() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let list = try #require(model.respond(to: Studio.Method.list, params: [:], client: nil).result)
        #expect(list["project"]?.string == project.folder.lastPathComponent)
        let docs = try #require(list["documents"]?.array).compactMap(DocumentSummary.init(json:))
        #expect(docs.map(\.doc) == ["equal-groups", "subtraction"])
        let groups = try #require(docs.first)
        #expect(groups.title == "Multiplying as equal groups")
        #expect(groups.hash.count == 12)
        #expect(groups.errors == 0)
        #expect(groups.warnings != nil)
    }

    @Test func readGivesThePartAtAPointerInTheDocumentsOrder() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let r = try #require(model.respond(to: Studio.Method.read, params: try params(#"{"doc":"equal-groups","pointer":"/steps/groups"}"#), client: nil).result)
        #expect(r["hash"]?.string == model.document(named: "equal-groups")?.hash)
        #expect(r["value"]?.object?.keys == ["shot", "say", "hold", "actions"])
        #expect(r["value"]?["hold"] == .number("0.4"))
    }

    @Test func readOfAMissingValueNamesWhatIsThere() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let reply = model.respond(to: Studio.Method.read, params: try params(#"{"doc":"equal-groups","pointer":"/steps/nope/hold"}"#), client: nil)
        #expect(reply.errorCode == Studio.ErrorCode.noValue)
        #expect(reply.errorMessage?.contains("the deepest part that exists is /steps, which holds groups, same, skip") == true)
        #expect(reply.errorMessage?.contains("…") == false)
        // Every key is listed, however many there are.
        let top = model.respond(to: Studio.Method.read, params: try params(#"{"doc":"equal-groups","pointer":"/nope"}"#), client: nil)
        let keys = try #require(model.document(named: "equal-groups")?.document?.json.object?.keys)
        #expect(keys.count > 12)
        #expect(top.errorMessage?.contains("the document, which holds " + keys.joined(separator: ", ")) == true)
        let missing = model.respond(to: Studio.Method.read, params: try params(#"{"doc":"nothing","pointer":""}"#), client: nil)
        #expect(missing.errorCode == Studio.ErrorCode.noDocument)
    }

    @Test func noProjectIsErrorTwo() throws {
        let model = StudioModel(guide: AuthoringGuide(text: ""), drivesPlayer: false)
        #expect(model.respond(to: Studio.Method.list, params: [:], client: nil).errorCode == Studio.ErrorCode.noProject)
        #expect(model.respond(to: Studio.Method.read, params: try params(#"{"doc":"x","pointer":""}"#), client: nil).errorCode
                == Studio.ErrorCode.noProject)
    }

    /// The edit the maintainer's test makes: a duration and a line of equal groups.
    @Test func anAcceptedPatchIsSavedAndPlayedAtOnce() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let before = try #require(model.document(named: "equal-groups"))
        model.select("equal-groups")
        model.player?.show(step: 0)
        let ops = #"[{"op":"replace","path":"/steps/groups/hold","value":1.5},"#
            + #"{"op":"replace","path":"/wording/en-US/everyday/make","value":"Make {groups:a}. Put {b} in each one."}]"#
        let reply = model.respond(to: Studio.Method.patch, params: try params(#"{"doc":"equal-groups","base":"\#(before.hash)","ops":\#(ops)}"#), client: nil)
        let r = try #require(reply.result)
        #expect(r["applied"]?.bool == true)
        let hash = try #require(r["hash"]?.string)
        #expect(hash != before.hash)
        #expect(r["errors"]?.int == 0)
        #expect(r["findings"] == nil)

        // Saved: the file reads back to the new hash, keeps its key order and stays laid out.
        let saved = ExplainerDocument.read(contentsOf: project.url("equal-groups"))
        #expect(saved.document?.shortHash == hash)
        #expect(saved.document?.json.object?.keys == before.document?.json.object?.keys)
        let text = try String(contentsOf: project.url("equal-groups"), encoding: .utf8)
        #expect(text.contains(#""make": "Make {groups:a}. Put {b} in each one.""#))
        #expect(text.split(separator: "\n").count > 40)

        // Shown: the player is new, plays the step it was on, and says the new line.
        let player = try #require(model.player)
        #expect(player.phase == .playing(0))
        let e = try #require((player.explainer as? ShapedExplainer)?.shown)
        #expect(e.resolved.steps[0].hold == 1.5)
        #expect(e.resolved.steps[0].line.line.display == "Make 2 groups. Put 2 in each one.")
    }

    /// The window plays with the stand-in voice, so a step whose action waits for the voice lasts
    /// longer than its motion.
    @Test func theWindowPlaysWithTheStandInVoiceSoAStepLastsAsSpoken() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        let player = try #require(model.player)
        let e = try #require((player.explainer as? ShapedExplainer)?.shown)
        var longer: [String] = []
        for (k, step) in e.resolved.steps.enumerated() where !step.waits.isEmpty {
            player.show(step: k)
            var clock = 0.0
            while case .playing = player.phase, clock < 600 {
                player.advance(by: 1.0 / 60)
                clock += 1.0 / 60
            }
            #expect(player.phase == .paused(k), "step \(step.name) ended")
            if clock > e.script(for: k).duration + 0.5 { longer.append(step.name) }
        }
        #expect(!longer.isEmpty, "a step with a wait for the voice lasts longer than its motion alone")
    }

    @Test func aStalePatchIsRefusedWithTheCurrentHash() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let hash = try #require(model.document(named: "equal-groups")?.hash)
        let reply = model.respond(to: Studio.Method.patch, params: try params(
            #"{"doc":"equal-groups","base":"000000000000","ops":[{"op":"replace","path":"/steps/groups/hold","value":1}]}"#), client: nil)
        let r = try #require(reply.result)
        #expect(r["applied"]?.bool == false)
        #expect(r["hash"]?.string == hash)
        let finding = try #require(r["findings"]?.array?.first.flatMap(ChalkScriptMCP.Finding.init(json:)))
        #expect(finding.code == "patch")
        #expect(try Data(contentsOf: project.url("equal-groups")) == Data(contentsOf: examples[1]))
    }

    @Test func aPatchWhoseResultHasAnErrorIsRefusedAndNothingIsSaved() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let hash = try #require(model.document(named: "equal-groups")?.hash)
        let reply = model.respond(to: Studio.Method.patch, params: try params(
            #"{"doc":"equal-groups","base":"\#(hash)","ops":[{"op":"replace","path":"/steps/groups/say","value":"nothing"}]}"#), client: nil)
        let r = try #require(reply.result)
        #expect(r["applied"]?.bool == false)
        #expect((r["errors"]?.int ?? 0) > 0)
        #expect(model.document(named: "equal-groups")?.hash == hash)
    }

    @Test func anAcceptedPatchIsOneStepOfUndo() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.undoManager = undo
        let hash = try #require(model.document(named: "equal-groups")?.hash)
        _ = model.respond(to: Studio.Method.patch, params: try params(
            #"{"doc":"equal-groups","base":"\#(hash)","ops":[{"op":"replace","path":"/steps/same/hold","value":2}]}"#), client: nil)
        let edited = try #require(model.document(named: "equal-groups")?.hash)
        #expect(edited != hash)
        #expect(undo.canUndo)
        #expect(undo.undoActionName == "Edit by Agent")
        undo.undo()
        #expect(model.document(named: "equal-groups")?.hash == hash)
        #expect(ExplainerDocument.read(contentsOf: project.url("equal-groups")).document?.shortHash == hash)
        undo.redo()
        #expect(model.document(named: "equal-groups")?.hash == edited)
    }

    @Test func checkGivesFindingsUnderAPointerAndAllTheCounts() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let r = try #require(model.respond(to: Studio.Method.check, params: try params(#"{"doc":"subtraction"}"#), client: nil).result)
        #expect(r["errors"]?.int == 0)
        let all = try #require(r["findings"]?.array)
        #expect(all.count == r["warnings"]?.int)
        let narrow = try #require(model.respond(to: Studio.Method.check, params: try params(#"{"doc":"subtraction","pointer":"/steps/show"}"#), client: nil).result)
        #expect(narrow["warnings"] == r["warnings"])
        for f in narrow["findings"]?.array ?? [] { #expect(f["path"]?.string?.hasPrefix("/steps/show") == true) }
    }

    @Test func checkFindsWhatRefusesASample() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let hash = try #require(model.document(named: "equal-groups")?.hash)
        // A slice past the last dot fails for every sample, though the document reads.
        let r = try #require(model.respond(to: Studio.Method.patch, params: try params(
            #"{"doc":"equal-groups","base":"\#(hash)","ops":[{"op":"replace","path":"/elements/hint/around","value":"slice(dot, 0, a * b + 1)"}]}"#), client: nil).result)
        #expect(r["applied"]?.bool == true)
        #expect(r["errors"]?.int == 1)
        let c = try #require(model.respond(to: Studio.Method.check, params: try params(#"{"doc":"equal-groups"}"#), client: nil).result)
        let f = try #require(c["findings"]?.array?.first.flatMap(ChalkScriptMCP.Finding.init(json:)))
        #expect(f.code == "eval")
        #expect(f.path == "/elements/hint/around")
        #expect(f.values != nil)
        #expect(model.player == nil)
        #expect(!model.refusal.isEmpty)
    }

    @Test func showPlaysTheStepForTheProblem() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let r = try #require(model.respond(to: Studio.Method.show, params: try params(
            #"{"doc":"subtraction","step":"trade","problem":{"a":54,"b":26}}"#), client: nil).result)
        #expect(r["step"]?.string == "trade")
        #expect(r["index"]?.int == 3)
        #expect(r["count"]?.int == 6)
        #expect(r["image"] == nil)
        #expect(model.selectedName == "subtraction")
        #expect(model.player?.phase == .playing(2))
        #expect(model.problem(for: "subtraction") == ["a": .number(54), "b": .number(26)])

        let first = try #require(model.respond(to: Studio.Method.show, params: try params(#"{"doc":"equal-groups"}"#), client: nil).result)
        #expect(first["step"]?.string == "groups")
        #expect(first["index"]?.int == 1)
    }

    @Test func showOfAStepTheProblemLacksNamesTheStepsItHas() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let reply = model.respond(to: Studio.Method.show, params: try params(
            #"{"doc":"subtraction","step":"trade","problem":{"a":58,"b":26}}"#), client: nil)
        #expect(reply.errorCode == Studio.ErrorCode.noStep)
        #expect(reply.errorMessage?.contains("does not have the step trade") == true)
        #expect(reply.errorMessage?.contains("show, enough, takeOnes, takeTens, count") == true)
        let outside = model.respond(to: Studio.Method.show, params: try params(#"{"doc":"subtraction","problem":{"a":5,"b":2}}"#), client: nil)
        #expect(outside.errorCode == Studio.ErrorCode.failed)
    }

    @Test func showReturnsASmallPictureOnlyWhenAsked() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let r = try #require(model.respond(to: Studio.Method.show, params: try params(#"{"doc":"equal-groups","step":"skip","image":true}"#), client: nil).result)
        let data = try #require(r["image"]?["data"]?.string.flatMap { Data(base64Encoded: $0) })
        #expect(r["image"]?["mimeType"]?.string == "image/png")
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        // The width and height in the PNG header: 480 by 259 pixels.
        let width = data[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let height = data[20..<24].reduce(0) { $0 << 8 | Int($1) }
        #expect(width == 480)
        #expect(height == 259)
    }

    @Test func guideGivesItsTopicsThenEachTopic() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let contents = try #require(model.respond(to: Studio.Method.guide, params: [:], client: nil).result?["text"]?.string)
        #expect(contents.contains("- editing: "))
        #expect(contents.contains("- all: the whole guide"))
        let editing = try #require(model.respond(to: Studio.Method.guide, params: try params(#"{"topic":"editing"}"#), client: nil).result?["text"]?.string)
        #expect(editing.hasPrefix("## editing"))
        #expect(!editing.contains("## document"))
        let unknown = model.respond(to: Studio.Method.guide, params: try params(#"{"topic":"nope"}"#), client: nil)
        #expect(unknown.errorCode == Studio.ErrorCode.failed)
        #expect(unknown.errorMessage?.contains("editing, new, document") == true)
    }

    @Test func anUnknownMethodIsMethodNotFound() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        #expect(model.respond(to: "document.export", params: [:], client: nil).errorCode == Studio.RPCError.methodNotFound)
    }
}

/// The open project, its documents and what is played.
@MainActor
struct StudioProjectTests {
    @Test func theFirstSampleIsPlayedUntilAnotherProblemIsChosen() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        #expect(model.problem(for: "subtraction") == ["a": .number(10), "b": .number(1)])
        let outside = model.setProblem(["a": .number(54), "b": .number(60)], for: "subtraction")
        #expect(outside.first?.code == .range)
        #expect(model.problem(for: "subtraction") == ["a": .number(10), "b": .number(1)])
        #expect(model.setProblem(["a": .number(54), "b": .number(26)], for: "subtraction").isEmpty)
        let e = try #require(model.shaped?.shown)
        #expect(e.problem == ["a": .number(54), "b": .number(26)])
    }

    @Test func wordingAndPlaybackAreChosen() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        #expect(model.playedWording == "everyday")
        model.setWording("formal")
        #expect(model.playedWording == "formal")
        model.setControl(.skippable)
        #expect(model.player?.explainer.version == .parent)
        // A wording the shown document lacks takes the document's own choice.
        model.setWording("nonesuch")
        #expect(model.playedWording == "everyday")
    }

    @Test func aChangeMadeOnDiskIsReadAgain() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        let text = try String(contentsOf: project.url("equal-groups"), encoding: .utf8)
        try text.replacingOccurrences(of: #""hold": 0.4"#, with: #""hold": 0.9"#).write(to: project.url("equal-groups"), atomically: true, encoding: .utf8)
        try String(contentsOf: examples[1], encoding: .utf8).write(to: project.url("copy"), atomically: true, encoding: .utf8)
        model.reload()
        #expect(model.documents.map(\.name) == ["copy", "equal-groups", "subtraction"])
        let e = try #require(model.shaped?.shown)
        #expect(e.resolved.steps[0].hold == 0.9)
    }

    @Test func theWatcherReadsAChangeWithoutBeingAsked() async throws {
        let project = try TemporaryProject()
        let model = try openModel(project, watch: true)
        let hash = model.document(named: "equal-groups")?.hash
        let text = try String(contentsOf: project.url("equal-groups"), encoding: .utf8)
        try text.replacingOccurrences(of: #""hold": 0.4"#, with: #""hold": 0.8"#).write(to: project.url("equal-groups"), atomically: true, encoding: .utf8)
        for _ in 0..<150 where model.document(named: "equal-groups")?.hash == hash {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(model.document(named: "equal-groups")?.hash != hash)
    }

    @Test func aFileThatIsNotJSONIsListedWithItsError() throws {
        let project = try TemporaryProject(examples: [])
        try "{ not json".write(to: project.url("broken"), atomically: true, encoding: .utf8)
        let model = try openModel(project)
        let d = try #require(model.document(named: "broken"))
        #expect(d.document == nil)
        #expect(d.errors == 1)
        #expect(d.hash.count == 12)
        #expect(model.player == nil)
        let read = model.respond(to: Studio.Method.read, params: try params(#"{"doc":"broken","pointer":""}"#), client: nil)
        #expect(read.errorCode == Studio.ErrorCode.failed)
    }

    @Test func documentsInFoldersAreNamedByTheirPath() throws {
        let project = try TemporaryProject(examples: [])
        let sub = project.folder.appendingPathComponent("Unit 1")
        try ProjectFolder.addExamples([examples[1]], to: sub)
        try ProjectFolder.addExamples([examples[0]], to: project.folder.appendingPathComponent(".hidden"))
        #expect(ProjectFolder.scan(project.folder).map(\.name) == ["Unit 1/equal-groups"])
    }

    @Test func examplesAreAddedOnlyWhereMissing() throws {
        let project = try TemporaryProject(examples: [examples[0]])
        try "{}".write(to: project.url("subtraction"), atomically: true, encoding: .utf8)
        let copied = try ProjectFolder.addExamples(examples, to: project.folder)
        #expect(copied.map(\.lastPathComponent) == ["equal-groups.explainer"])
        #expect(try String(contentsOf: project.url("subtraction"), encoding: .utf8) == "{}")
    }

    @Test func findingsHaveTheirLineInTheFile() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let d = try #require(model.document(named: "equal-groups"))
        let text = try String(contentsOf: project.url("equal-groups"), encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
        let line = try #require(d.line(of: "/steps/groups/hold"))
        #expect(text[line - 1].contains(#""hold": 0.4"#))
        #expect(d.line(of: "/steps/groups/nothing/here") == d.line(of: "/steps/groups"))
    }
}

/// The text a studio writes.
struct DocumentTextTests {
    @Test(arguments: examples)
    func writingKeepsTheDocumentAndItsKeyOrder(_ url: URL) throws {
        let doc = try #require(ExplainerDocument.read(contentsOf: url).document)
        let text = DocumentText.format(doc.json)
        let again = try #require(ExplainerDocument.read(Data(text.utf8)).document)
        #expect(again.hash == doc.hash)
        #expect(again.json.object?.keys == doc.json.object?.keys)
        #expect(DocumentText.format(again.json) == text)
        for line in text.split(separator: "\n") where line.count > DocumentText.width {
            // Only a value that cannot be broken, such as a long string, runs past the width.
            #expect(!line.hasSuffix("{") && !line.hasSuffix("["))
        }
    }

    @Test func smallValuesStayOnOneLineAndSymbolsAreNotEscaped() throws {
        let value = try DocJSON.parse(#"{"a":{"type":"int","min":2,"max":5},"t":"{a} × {b}\n","n":0.1}"#)
        #expect(DocumentText.format(value) == #"{ "a": { "type": "int", "min": 2, "max": 5 }, "t": "{a} × {b}\n", "n": 0.1 }"# + "\n")
    }
}

/// The desktop extension's manifest declares the helper's tools.
struct ExtensionManifestTests {
    @Test func theManifestNamesTheHelpersToolsAndBinary() throws {
        let url = repository.appendingPathComponent("Studio/Extension/manifest.json")
        let manifest = try ChalkScriptMCP.JSONValue.parse(String(contentsOf: url, encoding: .utf8))
        #expect(manifest["tools"]?.array?.compactMap { $0["name"]?.string } == HelperTools.names)
        func show(_ tools: [ChalkScriptMCP.JSONValue]?) -> String? { tools?.first { $0["name"]?.string == "show" }?["description"]?.string }
        #expect(show(manifest["tools"]?.array) == show(HelperTools.definitions))
        #expect(manifest["server"]?["type"]?.string == "binary")
        #expect(manifest["server"]?["mcp_config"]?["command"]?.string == "${__dirname}/server/chalkscript-mcp")
        #expect(manifest["version"]?.string == HelperInfo.version)
        #expect(manifest["compatibility"]?["platforms"] == .array([.string("darwin")]))
    }
}

/// The studio answering the helper's own client over a socket.
@MainActor
struct StudioSocketTests {
    @Test func theHelpersClientIsAnsweredThroughTheSocket() async throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let path = FileManager.default.temporaryDirectory.path + "/cs-\(UUID().uuidString.prefix(8)).sock"
        try model.startListening(path: path)
        defer { model.stopListening() }
        let outcome = await Task.detached {
            StudioClient(socketPath: path).call(Studio.Method.read, params: ["doc": .string("equal-groups"), "pointer": .string("/id")],
                                                client: Implementation(name: "test", version: "1"))
        }.value
        guard case let .result(r) = outcome else {
            Issue.record("the call gave \(outcome)")
            return
        }
        #expect(r["value"] == .string("multiply-equal-groups"))
        #expect(model.activity == "test: read equal-groups/id")
    }

    @Test func aSecondStudioCannotTakeTheSocket() throws {
        let project = try TemporaryProject()
        let a = try openModel(project)
        let b = try openModel(project)
        let path = FileManager.default.temporaryDirectory.path + "/cs-\(UUID().uuidString.prefix(8)).sock"
        try a.startListening(path: path)
        defer { a.stopListening() }
        #expect(throws: (any Error).self) { try b.startListening(path: path) }
    }
}

/// How long checking a document takes, since every edit is checked before it is answered.
@MainActor
struct CheckTimeTests {
    @Test func checkingTheLargerExampleTakesWellUnderASecond() throws {
        let data = try Data(contentsOf: examples[0])
        let start = ContinuousClock.now
        let d = StudioDocument(name: "subtraction", url: examples[0], data: data)
        let elapsed = ContinuousClock.now - start
        print("checked subtraction (\(d.findings.count) findings) in \(elapsed)")
        #expect(elapsed < .seconds(1))
    }
}

struct ConnectCommandTests {
    @Test func theClaudeCodeCommandQuotesTheHelpersPath() {
        let app = URL(fileURLWithPath: "/Applications/ChalkScript Studio.app")
        #expect(ConnectCommand.claudeCode(helper: ConnectCommand.helper(inApp: app))
                == "claude mcp add --transport stdio --scope user chalkscript -- '/Applications/ChalkScript Studio.app/Contents/Helpers/chalkscript-mcp'")
        #expect(ConnectCommand.quoted("it's") == #"'it'\''s'"#)
    }
}

/// Making a document (section 6.8 of the helper protocol).
@MainActor
struct CreateDocumentTests {
    func create(_ model: StudioModel, _ text: String) throws -> StudioReply {
        model.respond(to: Studio.Method.create, params: try params(text), client: nil)
    }

    /// The names of the files in the project folder's top level.
    func files(_ project: TemporaryProject) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: project.folder.path).sorted()
    }

    @Test func aTitleAloneWritesTheStarterAndShowsItSquare() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.defaultPreview = .ratio(Preset.square.nominal)
        let reply = try create(model, #"{"title":"Reading the clock"}"#)
        let r = try #require(reply.result)
        #expect(r["doc"]?.string == "reading-the-clock")
        #expect(r["errors"]?.int == 0 && r["warnings"]?.int == 0)
        #expect(r["hash"]?.string == model.document(named: "reading-the-clock")?.hash)
        #expect(r["value"]?["id"]?.string == "reading-the-clock")
        #expect(r["value"]?.object?.keys.prefix(4) == ["format", "version", "id", "title"])
        // The file is in the folder's top level, and the studio lists, selects and shows it without
        // the watcher (the model was opened without one).
        #expect(try files(project).contains("reading-the-clock.explainer"))
        #expect(model.documents.map(\.name).contains("reading-the-clock"))
        #expect(model.selectedName == "reading-the-clock")
        #expect(model.preview == .ratio(1.1))
        #expect(model.player != nil)
        #expect(model.shownLayout == "stage")
        #expect(model.stepNames == ["start"])
        #expect(model.madeFor == [.square])
    }

    @Test func theStarterIsReadWithNoFindingsAndIsMadeForSquareAtItsOwnSize() throws {
        let json = DocumentStarter.starter(id: "reading-the-clock", title: "Reading the clock")
        let reading = ExplainerDocument.read(Data(DocumentText.format(json).utf8))
        #expect(reading.findings.isEmpty, "\(reading.findings)")
        let doc = try #require(reading.document)
        #expect(DocumentCheck.findings(of: reading).isEmpty)
        #expect(doc.json.value(at: "/id") == .string("reading-the-clock"))
        #expect(doc.json.value(at: "/title") == .string("Reading the clock"))
        #expect(doc.json.value(at: "/areas") == (try DocJSON.parse(#"[{"layout":"stage","ratio":[0.9,1.35]}]"#)))
        #expect(doc.json.value(at: "/layouts") == (try DocJSON.parse(#"{"stage":{"size":[880,800]}}"#)))
        #expect(Shapes.madeFor(doc) == [.square])
        // Square's nominal ratio is the stage's own.
        #expect(Preset.square.nominal == 880.0 / 800.0)
        // A title with characters JSON escapes is kept as it is.
        let odd = DocumentStarter.starter(id: "odd", title: "Say \"hi\" \\ there\n")
        #expect(odd.value(at: "/title") == .string("Say \"hi\" \\ there\n"))
        #expect(ExplainerDocument.read(Data(DocumentText.format(odd).utf8)).findings.isEmpty)
    }

    @Test func aNameIsMadeFromATitle() {
        let cases: [(String, String)] = [
            ("Reading the clock", "reading-the-clock"),
            ("  Reading -- the  CLOCK!  ", "reading-the-clock"),
            ("Café au lait", "caf-au-lait"),
            ("2 + 3 = 5", "explainer-2-3-5"),
            ("!!!", "explainer"),
            ("日本語", "explainer"),
            (String(repeating: "a", count: 80), String(repeating: "a", count: 64)),
            (String(repeating: "ab ", count: 30), String(String(repeating: "ab-", count: 30).prefix(64))),
            // A cut that ends on a hyphen drops it.
            (String(repeating: "a", count: 63) + " b", String(repeating: "a", count: 63)),
        ]
        for (title, name) in cases {
            #expect(DocumentStarter.name(forTitle: title) == name, "\(title)")
            #expect(DocumentStarter.isValid(name: DocumentStarter.name(forTitle: title)), "\(title)")
        }
        #expect(DocumentStarter.available("clock") { $0 == "clock" || $0 == "clock-2" } == "clock-3")
        // The suffix keeps the whole within 64 characters.
        let long = String(repeating: "a", count: 64)
        #expect(DocumentStarter.available(long) { $0 == long }.count == 64)
        #expect(DocumentStarter.available(long) { $0 == long } == String(repeating: "a", count: 62) + "-2")
        for name in ["a", "reading-the-clock", "a1-b2"] { #expect(DocumentStarter.isValid(name: name)) }
        for name in ["", "Clock", "1a", "-a", "a_b", "a b", "é", String(repeating: "a", count: 65)] {
            #expect(!DocumentStarter.isValid(name: name), "\(name)")
        }
    }

    @Test func aSecondCreateWithTheSameTitleEndsInTwo() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        #expect(try create(model, #"{"title":"Reading the clock"}"#).result?["doc"]?.string == "reading-the-clock")
        let second = try create(model, #"{"title":"Reading the clock"}"#).result
        #expect(second?["doc"]?.string == "reading-the-clock-2")
        #expect(second?["value"]?["id"]?.string == "reading-the-clock-2")
        #expect(second?["value"]?["title"]?.string == "Reading the clock")
        #expect(try create(model, #"{"title":"Reading the clock"}"#).result?["doc"]?.string == "reading-the-clock-3")
        // A file the studio has not read yet takes its name too.
        try "{}".write(to: project.url("fresh"), atomically: true, encoding: .utf8)
        #expect(try create(model, #"{"title":"Fresh"}"#).result?["doc"]?.string == "fresh-2")
    }

    @Test func aNameThatIsTakenOrMalformedIsErrorSixAndWritesNoFile() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let before = try files(project)
        let hashes = model.documents.map(\.hash)
        let taken = try create(model, #"{"title":"Again","name":"subtraction"}"#)
        #expect(taken.errorCode == Studio.ErrorCode.failed)
        #expect(taken.errorMessage?.contains("subtraction") == true)
        #expect(model.document(named: "subtraction")?.title == "Two-digit subtraction by trading a ten")
        // One the folder holds that the studio has not read.
        try "{}".write(to: project.url("unread"), atomically: true, encoding: .utf8)
        let unread = try files(project)
        #expect(try create(model, #"{"title":"Again","name":"unread"}"#).errorCode == Studio.ErrorCode.failed)
        #expect(try String(contentsOf: project.url("unread"), encoding: .utf8) == "{}")
        for name in ["Clock", "1clock", "a_b", "", "-x", String(repeating: "a", count: 65)] {
            let reply = try create(model, #"{"title":"Again","name":\#(ChalkScriptMCP.JSONValue.string(name).serialized)}"#)
            #expect(reply.errorCode == Studio.ErrorCode.failed, "\(name)")
        }
        #expect(try files(project) == unread)
        #expect(Set(unread).subtracting(before) == ["unread.explainer"])
        #expect(model.documents.filter { $0.name != "unread" }.map(\.hash) == hashes)
        // A valid name is used as given.
        #expect(try create(model, #"{"title":"Again","name":"my-own-name"}"#).result?["doc"]?.string == "my-own-name")
    }

    @Test func aMissingOrEmptyTitleIsInvalidParams() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let before = try files(project)
        for text in [#"{}"#, #"{"title":""}"#, #"{"title":"   "}"#, #"{"title":3}"#, #"{"title":"A","name":3}"#, #"{"title":"A","from":false}"#] {
            #expect(try create(model, text).errorCode == Studio.RPCError.invalidParams, "\(text)")
        }
        #expect(try files(project) == before)
    }

    @Test func noProjectIsErrorTwo() throws {
        let model = StudioModel(guide: AuthoringGuide(text: ""), drivesPlayer: false)
        #expect(model.respond(to: Studio.Method.create, params: try params(#"{"title":"A"}"#), client: nil).errorCode
                == Studio.ErrorCode.noProject)
    }

    @Test func fromMakesACopyWithItsOwnIdAndTitleThatPlaysAsTheOriginalDoes() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let original = try Data(contentsOf: project.url("subtraction"))
        model.select("subtraction")
        let steps = model.stepNames
        let originalJSON = try #require(model.document(named: "subtraction")?.document?.json)
        let r = try #require(try create(model, #"{"title":"Adding tens","from":"subtraction"}"#).result)
        #expect(r["doc"]?.string == "adding-tens")
        #expect(r["value"]?["id"]?.string == "adding-tens")
        #expect(r["value"]?["title"]?.string == "Adding tens")
        #expect(model.selectedName == "adding-tens")
        #expect(!steps.isEmpty)
        #expect(model.stepNames == steps)
        // Everything but the two keys is the original's, in its order.
        var copy = try #require(model.document(named: "adding-tens")?.document?.json.object)
        var source = try #require(originalJSON.object)
        #expect(copy.keys == source.keys)
        for key in ["id", "title"] { copy[key] = nil; source[key] = nil }
        #expect(copy == source)
        #expect(model.document(named: "adding-tens")?.errors == 0)
        // The original's file and the studio's reading of it are unchanged.
        #expect(try Data(contentsOf: project.url("subtraction")) == original)
        #expect(model.document(named: "subtraction")?.document?.json == originalJSON)
        #expect(model.document(named: "subtraction")?.title == "Two-digit subtraction by trading a ten")
        // A copy takes a name given too, and a document in a folder can be copied.
        #expect(try create(model, #"{"title":"Again","from":"subtraction","name":"again"}"#).result?["doc"]?.string == "again")
    }

    @Test func aFromThatNamesNoDocumentIsErrorThreeAndWritesNoFile() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let before = try files(project)
        let reply = try create(model, #"{"title":"Adding tens","from":"nonesuch"}"#)
        #expect(reply.errorCode == Studio.ErrorCode.noDocument)
        #expect(try files(project) == before)
        // A document that cannot be read cannot be copied; that is error 6.
        try "not json".write(to: project.url("broken"), atomically: true, encoding: .utf8)
        let broken = try create(model, #"{"title":"Adding tens","from":"broken"}"#)
        #expect(broken.errorCode == Studio.ErrorCode.failed)
        #expect(!(try files(project)).contains("adding-tens.explainer"))
    }

    @Test func theGuidesFirstPatchIsAcceptedByANewDocumentAndPlays() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let guide = try #require(model.respond(to: Studio.Method.guide, params: try params(#"{"topic":"new"}"#), client: nil).result?["text"]?.string)
        let fence = "```json\n"
        let start = try #require(guide.range(of: fence)).upperBound
        let end = try #require(guide.range(of: "\n```", range: start..<guide.endIndex)).lowerBound
        let ops = try #require(try DocJSON.parse(String(guide[start..<end])).array)
        let made = try model.createDocument(title: "Counting dots")
        let result = try model.patch(made.name, base: made.hash, ops: ops)
        #expect(result.applied, "\(result.findings)")
        let after = try #require(model.document(named: made.name))
        #expect(after.errors == 0)
        #expect(after.warnings == 0)
        #expect(model.stepNames == ["dots", "count", "total"])
        #expect(model.player != nil)
    }

    @Test func theWindowCanCallItWithATitleAlone() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let made = try model.createDocument(title: "Counting up")
        #expect(made.name == "counting-up")
        #expect(model.selectedName == "counting-up")
        #expect(throws: (any Error).self) { try model.createDocument(title: "") }
    }

    @Test func theFirstDocumentOfAnEmptyProjectIsShownAtTheDefaultPreview() throws {
        let project = try TemporaryProject(examples: [])
        let model = try openModel(project)
        model.defaultPreview = .ratio(Preset.square.nominal)
        try model.createDocument(title: "Alpha")
        #expect(model.selectedName == "alpha")
        #expect(model.preview == .ratio(1.1))
        #expect(model.player != nil)
    }
}

/// What the authoring guide says of colour roles, `select` and `cases`, `draw` and `wait`,
/// checked against the reader and the player.
struct GuideStatementTests {
    /// A complete document of one integer parameter `k`, with `elements`, one step that makes the
    /// element `e` appear and then `extra` actions, and the wording `entries` (JSON members).
    private func document(
        requires: [String] = [], elements: String, extra: String = "", entries: String = "", params: String = #""k": {"type": "int", "min": 1, "max": 9}"#,
        samples: String = #"{"k": 3}"#, style: String = ""
    ) -> String {
        let req = requires.isEmpty ? "" : #""requires": [\#(requires.map { "\"\($0)\"" }.joined(separator: ", "))],"#
        return """
        {"format": "chalkscript-explainer", "version": "1.0", "id": "t", "title": "T", "sourceLocale": "en-US",
         \(req) \(style) "params": {\(params)}, "samples": [\(samples)],
         "elements": \(elements), "sequence": ["s"],
         "steps": {"s": {"say": "s", "actions": {"show": {"do": "appear", "target": "e"}\(extra)}}},
         "wording": {"en-US": {"shared": {"hi": {"text": "hi", "visual": true}, "eq": {"text": "{k} here", "visual": true}},
                               "everyday": {"s": "A line."\(entries)}}}}
        """
    }

    /// The errors of reading the document and playing every sample.
    private func errors(_ json: String) -> [DocumentFinding] {
        DocumentCheck.findings(of: ExplainerDocument.read(Data(json.utf8))).errors
    }

    private let neutral = ["text", "muted", "line", "pencil", "sheet"]
    private let operations = ["result", "add", "subtract", "trade", "multiply", "divide"]
    private let forms = ["", ".fill", ".ink", ".soft"]
    private func needsArithmetic(_ role: String) -> Bool { role.split(separator: ".").first.map { $0 != "result" && operations.contains(String($0)) } ?? false }

    /// Every form of every role, for a key that takes the roles of the table's first row.
    private var allRoles: [String] { neutral + ["paper", "onResult"] + neutral.map { $0 + ".ink" } + operations.flatMap { op in forms.map { op + $0 } } }

    private func acceptedByFirstRow(_ role: String) -> Bool {
        neutral.contains(role) || operations.contains { role.hasPrefix($0) && forms.contains(String(role.dropFirst($0.count))) }
    }

    @Test func theFirstRowOfTheRoleTableIsWhatTheReaderAndPlayerAccept() throws {
        let kinds: [(String, (String) -> String)] = [
            ("text ink", { #"{"e": {"kind": "text", "at": [100, 100], "text": "hi", "style": "body", "ink": "\#($0)"}}"# }),
            ("line ink", { #"{"e": {"kind": "line", "from": [0, 0], "to": [10, 10], "ink": "\#($0)"}}"# }),
            ("shape ink", { #"{"e": {"kind": "shape", "rect": [0, 0, 10, 10], "ink": "\#($0)"}}"# }),
            ("shape fill", { #"{"e": {"kind": "shape", "rect": [0, 0, 10, 10], "fill": "\#($0)"}}"# }),
        ]
        for (label, element) in kinds {
            for role in allRoles {
                for withCapability in [false, true] {
                    let findings = errors(document(requires: withCapability ? ["components.arithmetic"] : [], elements: element(role)))
                    let expected = acceptedByFirstRow(role) && (withCapability || !needsArithmetic(role))
                    #expect(findings.isEmpty == expected, "\(label) \(role) requires arithmetic: \(withCapability): \(findings)")
                }
            }
        }
    }

    @Test func theSecondRowTakesAnOperationRoleBareOnAnArrowABoxAndATint() throws {
        let arrow: (String) -> String = { #"{"e": {"kind": "arrow", "from": [0, 0], "to": [10, 10], "ink": "\#($0)"}}"# }
        let box: (String) -> String = { #"{"e": {"kind": "outline", "rect": [0, 0, 10, 10], "style": "box", "ink": "\#($0)"}}"# }
        let ring: (String) -> String = { #"{"e": {"kind": "outline", "rect": [0, 0, 10, 10], "style": "ring", "ink": "\#($0)"}}"# }
        let tint: (String) -> String = {
            document(elements: #"{"e": {"kind": "text", "style": "equation", "at": [100, 100], "text": "eq"}}"#,
                     extra: #", "t": {"do": "tint", "target": "e.k", "ink": "\#($0)"}"#)
        }
        for role in allRoles {
            for withCapability in [false, true] {
                let expected = operations.contains(role) && (withCapability || role == "result")
                let requires = withCapability ? ["components.arithmetic"] : []
                for (label, json) in [
                    ("arrow", document(requires: requires, elements: arrow(role))),
                    ("box", document(requires: requires, elements: box(role))),
                    ("ring", document(requires: requires, elements: ring(role))),
                    ("tint", withCapability ? tint(role).replacingOccurrences(of: #""params""#, with: #""requires": ["components.arithmetic"], "params""#) : tint(role)),
                ] {
                    let findings = errors(json)
                    #expect(findings.isEmpty == expected, "\(label) \(role) requires arithmetic: \(withCapability): \(findings)")
                }
            }
        }
    }

    @Test func hintAndTargetOutlinesTakeNoInk() throws {
        for style in ["hint", "target"] {
            #expect(errors(document(elements: #"{"e": {"kind": "outline", "rect": [0, 0, 10, 10], "style": "\#(style)"}}"#)).isEmpty)
            #expect(!errors(document(elements: #"{"e": {"kind": "outline", "rect": [0, 0, 10, 10], "style": "\#(style)", "ink": "result"}}"#)).isEmpty)
        }
    }

    @Test func aRunsInkIsResultOrTextInAnEquationOnly() throws {
        func run(_ style: String, _ role: String) -> String {
            document(elements: #"{"e": {"kind": "text", "style": "\#(style)", "at": [100, 100], "text": "eq", "runs": {"k": {"ink": "\#(role)"}}}}"#)
        }
        for role in allRoles {
            #expect(errors(run("equation", role)).isEmpty == ["result", "text"].contains(role), "equation \(role)")
            #expect(!errors(run("body", role)).isEmpty, "body \(role)")
        }
    }

    @Test func totalAndEquationTextAreCentredInTheirOwnRole() throws {
        func text(_ style: String, _ extra: String) -> String {
            document(elements: #"{"e": {"kind": "text", "style": "\#(style)", "at": [100, 100], "text": "hi"\#(extra)}}"#)
        }
        // Left out, they are what the guide says; given, only those values are drawn.
        for style in ["total", "equation"] { #expect(errors(text(style, "")).isEmpty) }
        #expect(errors(text("total", #", "ink": "result", "anchor": "middle""#)).isEmpty)
        #expect(errors(text("equation", #", "ink": "text", "anchor": "middle""#)).isEmpty)
        for extra in [#", "ink": "result.ink""#, #", "ink": "text""#, #", "ink": "muted""#, #", "anchor": "start""#] {
            #expect(!errors(text("total", extra)).isEmpty, "total \(extra)")
        }
        for extra in [#", "ink": "result""#, #", "ink": "muted""#, #", "anchor": "start""#] {
            #expect(!errors(text("equation", extra)).isEmpty, "equation \(extra)")
        }
        for style in ["label", "note", "body"] {
            for extra in [#", "ink": "result""#, #", "ink": "pencil""#, #", "anchor": "start""#, #", "anchor": "end""#] {
                #expect(errors(text(style, extra)).isEmpty, "\(style) \(extra)")
            }
        }
    }

    @Test func aDocumentWithAPaletteIsRefusedAsASchemaErrorNamingColours() throws {
        let json = document(elements: #"{"e": {"kind": "text", "at": [100, 100], "text": "hi"}}"#,
                            style: ##""style": {"palette": {"light": {"text": "#336699"}, "dark": {"text": "#99BBDD"}}},"##)
        let findings = errors(json)
        #expect(findings.map(\.code) == [.schema], "\(findings)")
        #expect(findings.first?.path == "/style/palette")
        #expect(findings.first?.message.contains("colours") == true)
    }

    // MARK: select and cases

    /// The `select` entry the guide gives, as it is printed there.
    private func guideSelectEntry() throws -> String {
        let guide = try String(contentsOf: repository.appendingPathComponent("docs/format/authoring-guide.md"), encoding: .utf8)
        let start = try #require(guide.range(of: #"{"select""#)).lowerBound
        let end = try #require(guide.range(of: "}}", range: start..<guide.endIndex)).upperBound
        return String(guide[start..<end]).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    private func said(_ json: String, minute: Double) throws -> String {
        let doc = try #require(ExplainerDocument.read(Data(json.utf8)).document)
        return try DocumentExplainer(document: doc, problem: ["minute": .number(minute)]).resolved.steps[0].line.line.display
    }

    private func clock(entry: String) -> String {
        document(elements: #"{"e": {"kind": "text", "at": [100, 100], "text": "hi"}}"#, entries: #", "hand": \#(entry)"#
                 ).replacingOccurrences(of: #""say": "s""#, with: #""say": "hand""#)
            .replacingOccurrences(of: #""k": {"type": "int", "min": 1, "max": 9}"#, with: #""minute": {"type": "int", "min": 0, "max": 59}"#)
            .replacingOccurrences(of: #"{"k": 3}"#, with: #"{"minute": 0}, {"minute": 25}"#)
    }

    @Test func theGuidesSelectEntryIsReadAndSaysEachCase() throws {
        let json = clock(entry: try guideSelectEntry())
        #expect(errors(json).isEmpty, "\(errors(json))")
        #expect(try said(json, minute: 0) == "The long hand points straight up.")
        #expect(try said(json, minute: 25) == "Move the long hand to 25 minutes.")
    }

    @Test func casesAreKeyedByTruthIntegerOrStringAndStarMatchesTheRest() throws {
        let byInteger = clock(entry: #"{"select": "mod(minute, 5)", "cases": {"0": "On a five.", "*": "Between fives."}}"#)
        #expect(errors(byInteger).isEmpty)
        #expect(try said(byInteger, minute: 25) == "On a five.")
        #expect(try said(byInteger, minute: 26) == "Between fives.")
        let byString = clock(entry: #"{"select": "minute == 0 ? 'zero' : 'other'", "cases": {"zero": "None.", "other": "Some."}}"#)
        #expect(try said(byString, minute: 0) == "None.")
        // A value with no case and no star is an error for that problem.
        let missing = clock(entry: #"{"select": "mod(minute, 5)", "cases": {"1": "Off by one."}}"#)
        #expect(errors(missing).first?.code == .eval, "\(errors(missing))")
    }

    // MARK: draw

    private func hand(_ element: String) throws -> DocumentExplainer {
        let json = document(elements: #"{"e": \#(element)}"#).replacingOccurrences(of: #""do": "appear""#, with: #""do": "draw""#)
        let doc = try #require(ExplainerDocument.read(Data(json.utf8)).document)
        return try DocumentExplainer(document: doc, problem: ["k": .number(3)])
    }

    @Test func drawSweepsAStrokeButAFillIsWholeFromTheStart() throws {
        // Both start with progress 0 and are drawn by `draw`; the fill is there before it, the stroke is not.
        let filled = try hand(#"{"kind": "shape", "points": [[0, 0], [90, 20], [0, 40]], "closed": true, "fill": "pencil", "start": {"progress": 0}}"#)
        #expect(filled.scene(step: 0, at: 0).element("e")?.isVisible == true)
        let stroked = try hand(#"{"kind": "shape", "points": [[0, 0], [90, 20], [0, 40]], "closed": true, "ink": "pencil", "start": {"progress": 0}}"#)
        #expect(stroked.scene(step: 0, at: 0).element("e")?.isVisible == false)
        #expect(stroked.scene(step: 0, at: 1).element("e")?.isVisible == true)
        for element in [#"{"kind": "line", "from": [0, 0], "to": [90, 20]"#, #"{"kind": "arrow", "from": [0, 0], "to": [90, 20], "ink": "result""#,
                        #"{"kind": "outline", "rect": [0, 0, 9, 9], "style": "box", "ink": "result""#] {
            let d = try hand(element + #", "start": {"progress": 0}}"#)
            #expect(d.scene(step: 0, at: 0).element("e")?.isVisible == false, "\(element)")
            #expect(d.scene(step: 0, at: 1).element("e")?.isVisible == true, "\(element)")
        }
    }

    @Test func aWaitForTheVoiceHoldsTheClockAtTheActionsStart() throws {
        let json = document(elements: #"{"e": {"kind": "text", "at": [100, 100], "text": "hi"}}"#,
                            extra: #", "later": {"do": "fade", "target": "e", "to": 0.5, "at": 0.5, "wait": "voice"}"#)
        let doc = try #require(ExplainerDocument.read(Data(json.utf8)).document)
        let d = try DocumentExplainer(document: doc, problem: ["k": .number(3)])
        #expect(d.resolved.steps[0].waits == [0.5])
    }
}

/// The timeline `step.show` returns: the step's lines, holds and actions on the stand-in voice's
/// clock.
@MainActor
struct StepTimelineTests {
    /// A clock document whose count runs over the twelve numerals, with a `when` on its actions.
    private let clock = repository.appendingPathComponent("Tests/ChalkScriptStudioCoreTests/Fixtures/clock-hour-minute.explainer")

    private func timeline(_ project: TemporaryProject, step: String, problem: String) throws -> [String] {
        let model = try openModel(project)
        let r = try #require(model.respond(to: Studio.Method.show, params: try params(
            #"{"doc":"clock-hour-minute","step":"\#(step)","problem":\#(problem)}"#), client: nil).result)
        return try #require(r["timeline"]?.string).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    @Test func aCountOverTwelveNumeralsGivesTheStepsLengthEachIterationsStartAndTheEmptyOnesAsOneRow() throws {
        let rows = try timeline(try TemporaryProject(examples: [clock]), step: "minutes", problem: #"{"hour":7,"minute":25}"#)
        #expect(rows[0] == "step minutes (10 of 12), hour 7, minute 25: 24.3 s as played, 18 s on its own clock, "
                + "which stops while held for the voice; ends of lines estimated")
        #expect(rows.contains { $0.hasPrefix("0-6.3 line says ") })
        #expect(rows.contains("0-6.3 held for the voice"))
        #expect(rows.contains("6.3-24.3 count each nums[0-11], 12 times, each waiting for the voice"))
        let starts = rows.filter { $0.hasPrefix("  ") && $0.contains("] word says") }.map { $0.split(separator: " ")[0] }
        #expect(starts == ["6.3", "7.8", "9.3", "10.8", "12.3"])
        #expect(rows.contains("  13.8-24.3 [5-11] nothing: every when is false"))
        #expect(rows.filter { $0.contains("nothing") }.count == 1)
        #expect(rows.contains { $0.hasPrefix("6.3-13.8 sweep turn minuteHand") })
    }

    @Test func aProblemWithNoWaitingIterationsHasNoEmptyRowAndAnOwnClockEqualToItsLength() throws {
        let rows = try timeline(try TemporaryProject(examples: [clock]), step: "circle", problem: #"{"hour":7,"minute":25}"#)
        #expect(rows[0] == "step circle (1 of 12), hour 7, minute 25: 3 s as played; ends of lines estimated")
        #expect(rows.count == 3)
    }

    /// The seconds the engine's player takes to play step `k` with the stand-in voice, advanced a
    /// millisecond at a time so that a line's end is found to a thousandth.
    private func played(_ e: DocumentExplainer, step k: Int) -> Double {
        let player = ExplainerPlayer(explainer: e, voice: EstimatedVoice(), drivesItself: false)
        player.show(step: k)
        var clock = 0.0
        while case .playing = player.phase, clock < 600 {
            player.advance(by: 0.001)
            clock += 0.001
        }
        return clock
    }

    @Test func theTimelinesLengthIsTheTimeThePlayerTakesForEveryStepOfTheExamplesAndTheClock() throws {
        var steps = 0
        for file in examples + [clock] {
            let doc = try #require(ExplainerDocument.read(contentsOf: file).document)
            for sample in doc.samples {
                let e = try DocumentExplainer(document: doc, problem: sample)
                for k in 0..<e.stepCount {
                    let length = StepTimeline.make(e, step: k).length
                    let took = played(e, step: k)
                    #expect(abs(length - took) <= 1.0 / 60, "\(file.lastPathComponent) \(e.resolved.steps[k].name) \(sample): \(length) s against \(took) s")
                    steps += 1
                }
            }
        }
        #expect(steps > 40)
    }
}

/// The picture `step.show` returns at a moment of a step, in the seconds of its timeline.
@MainActor
struct StepMomentTests {
    private let clock = repository.appendingPathComponent("Tests/ChalkScriptStudioCoreTests/Fixtures/clock-hour-minute.explainer")

    private func show(_ model: StudioModel, _ text: String) -> StudioReply {
        model.respond(to: Studio.Method.show, params: try! params(text), client: nil)
    }

    private func picture(_ model: StudioModel, _ text: String) throws -> Pixels {
        let r = try #require(show(model, text).result)
        return try #require(r["image"]?["data"]?.string.flatMap { Data(base64Encoded: $0) }.flatMap(Pixels.init(png:)))
    }

    @Test func atTheStartAStepWithOneAppearShowsNothingOfItsTargetAndAtItsLengthItsStill() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.previewAppearance = .light
        try model.createDocument(title: "Starter")
        let doc = try #require(model.document(named: "starter")?.document)
        let e = try DocumentExplainer(document: doc, problem: [:])
        let length = StepTimeline.make(e, step: 0).length
        #expect(e.resolved.steps[0].actions.map(\.verb) == ["appear"])

        // The scene: the note is not there at 0, is part shown on the way, and is whole at the end.
        func note(at moment: Double) -> Double? {
            let scene = StepPicture.scene(ShapedExplainer(e, ratio: 1.1), area: CGSize(width: 480, height: 436), step: 0, atPlayed: moment)
            return scene.elements.first { $0.id == "note" }?.opacity
        }
        #expect(note(at: 0) == 0)
        let part = try #require(note(at: 0.1))
        #expect(part > 0 && part < 1)
        #expect(note(at: length) == 1)

        // The picture, at the document's own shape: the sheet alone at 0, and the step's still at
        // its length.
        let asked = #""doc":"starter","image":true,"ratio":1.1"#
        let still = try picture(model, "{\(asked)}")
        let start = try picture(model, "{\(asked),\"at\":0}")
        let sheet = ExplainerStyle.standard.palette(dark: false).sheet
        #expect(start.count(sheet) == start.width * start.height)
        #expect(still.count(sheet) < still.width * still.height)
        #expect(try picture(model, "{\(asked),\"at\":\(length)}").differing(from: still) == 0)
        // The timeline writes the length to a tenth, and that is the end too.
        let tenth = (length * 10).rounded() / 10
        #expect(try picture(model, "{\(asked),\"at\":\(tenth)}").differing(from: still) == 0)
        let r = try #require(show(model, "{\(asked),\"at\":0.1}").result)
        #expect(r["at"] == .number("0.1"))
        #expect(show(model, "{\(asked)}").result?["at"] == nil)
    }

    @Test func aMomentInsideAHoldShowsThePictureBeforeTheWait() throws {
        let project = try TemporaryProject(examples: [clock])
        let model = try openModel(project)
        // The step's line is said from 0 to 6.3 with the clock held, and the minute hand sweeps after.
        func at(_ moment: String) throws -> Pixels {
            try picture(model, #"{"doc":"clock-hour-minute","step":"minutes","problem":{"hour":7,"minute":25},"image":true,"at":\#(moment)}"#)
        }
        let before = try at("0")
        #expect(try at("3").differing(from: before) == 0)
        #expect(try at("6.2").differing(from: before) == 0)
        let swept = try at("10")
        #expect(swept.differing(from: before) > 100)
        #expect(try at("12").differing(from: swept) > 100)
    }

    @Test func aMomentPastTheStepsLengthIsRefusedWithTheLength() throws {
        let project = try TemporaryProject(examples: [clock])
        let model = try openModel(project)
        let circle = #""doc":"clock-hour-minute","step":"circle","problem":{"hour":7,"minute":25},"image":true"#
        let past = show(model, "{\(circle),\"at\":3.5}")
        #expect(past.errorCode == Studio.ErrorCode.failed)
        #expect(past.errorMessage == "at 3.5 is past the end of the step circle, which lasts 3 s as played; "
                + "at is in the seconds of the step's timeline, from 0 to 3.")
        #expect(show(model, "{\(circle),\"at\":3}").result?["image"] != nil)
        for bad in ["-1", #""2""#, "true"] {
            let reply = show(model, "{\(circle),\"at\":\(bad)}")
            #expect(reply.errorCode == Studio.RPCError.invalidParams, "\(bad)")
            #expect(reply.errorMessage == "at must be a number of seconds from the step's start, 0 or more.")
        }
        // Without a picture, a moment is still checked against the step's length.
        #expect(show(model, #"{"doc":"clock-hour-minute","step":"circle","at":99}"#).errorCode == Studio.ErrorCode.failed)
    }
}
