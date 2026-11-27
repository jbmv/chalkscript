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
