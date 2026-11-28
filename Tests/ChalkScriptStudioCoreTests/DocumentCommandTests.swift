import ChalkScript
import ChalkScriptMCP
import Foundation
import Testing
@testable import ChalkScriptStudioCore

/// The sidebar's commands on a document: Rename, Duplicate and Move to Trash.
@MainActor
struct DocumentCommandTests {
    /// The names of the files in the project folder's top level.
    private func files(_ project: TemporaryProject) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: project.folder.path).sorted()
    }

    /// The names the helper's `list` gives.
    private func listed(_ model: StudioModel) throws -> [String] {
        let reply = model.respond(to: Studio.Method.list, params: [:], client: nil)
        return try #require(reply.result?["documents"]?.array).compactMap { $0["doc"]?.string }
    }

    /// The document's `id` and `title` as its file holds them.
    private func onDisk(_ project: TemporaryProject, _ name: String) throws -> (id: String?, title: String?) {
        let json = try #require(ExplainerDocument.read(contentsOf: project.url(name)).document?.json)
        return (json["id"]?.string, json["title"]?.string)
    }

    /// Makes the model move a trashed file into a folder of the test's own, not the Mac's Trash.
    private func standInTrash(_ model: StudioModel) throws -> URL {
        let trash = FileManager.default.temporaryDirectory.appendingPathComponent("trash-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        model.moveToTrash = {
            let target = trash.appendingPathComponent($0.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: $0, to: target)
        }
        return trash
    }

    @Test func renameMovesTheFileAndWritesTheTitleAndIdAsTheName() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        try model.createDocument(title: "Reading the clock")
        let renamed = try model.renameDocument("reading-the-clock", title: "Telling the time")
        #expect(renamed.name == "telling-the-time")
        #expect(renamed.title == "Telling the time")
        #expect(renamed.errors == 0)
        #expect(try files(project) == ["equal-groups.explainer", "subtraction.explainer", "telling-the-time.explainer"])
        #expect(try listed(model) == ["equal-groups", "subtraction", "telling-the-time"])
        let file = try onDisk(project, "telling-the-time")
        #expect(file.id == "telling-the-time")
        #expect(file.title == "Telling the time")
        // The helper answers for the old name as for any name the project lacks.
        let reply = model.respond(to: Studio.Method.read, params: try params(#"{"doc":"reading-the-clock"}"#), client: nil)
        #expect(reply.errorCode == Studio.ErrorCode.noDocument)
    }

    @Test func aRenamedDocumentStaysShownOnItsStepWithItsProblem() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        let sample = try #require(model.document(named: "equal-groups")?.document?.samples.last)
        #expect(model.setProblem(sample, for: "equal-groups").isEmpty)
        let steps = model.stepNames
        let step = try #require(steps.last)
        model.play(stepNamed: step)
        let before = try #require(model.document(named: "equal-groups")?.document?.json.object)

        try model.renameDocument("equal-groups", title: "Groups of the same size")
        #expect(model.selectedName == "groups-of-the-same-size")
        #expect(model.stepNames == steps)
        #expect(model.player?.currentStep == steps.count - 1)
        #expect(model.problem(for: "groups-of-the-same-size") == sample)
        // Nothing but the title and the id is changed, and the keys keep their order.
        var after = try #require(model.selected?.document?.json.object)
        #expect(after.keys == before.keys)
        #expect(after["id"]?.string == "groups-of-the-same-size")
        var rest = before
        for key in ["id", "title"] { after[key] = nil; rest[key] = nil }
        #expect(after == rest)
    }

    @Test func renamingADocumentThatIsNotShownLeavesTheShownOneShown() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        try model.renameDocument("equal-groups", title: "Sharing out")
        #expect(model.selectedName == "subtraction")
        #expect(try listed(model) == ["sharing-out", "subtraction"])
    }

    @Test func aNameThatIsTakenGetsANumber() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        try model.createDocument(title: "Telling the time")
        try model.createDocument(title: "Reading the clock")
        let renamed = try model.renameDocument("reading-the-clock", title: "Telling the time")
        #expect(renamed.name == "telling-the-time-2")
        #expect(try onDisk(project, "telling-the-time-2").id == "telling-the-time-2")
        #expect(try onDisk(project, "telling-the-time").id == "telling-the-time")
        #expect(!FileManager.default.fileExists(atPath: project.url("reading-the-clock").path))
    }

    @Test func aTitleThatGivesTheSameNameKeepsTheFileAndMakesTheIdAgree() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        // The example's id is not its file's name.
        #expect(try onDisk(project, "subtraction").id == "subtraction-trading")
        let renamed = try model.renameDocument("subtraction", title: "Subtraction!")
        #expect(renamed.name == "subtraction")
        let file = try onDisk(project, "subtraction")
        #expect(file.id == "subtraction")
        #expect(file.title == "Subtraction!")
        #expect(try files(project) == ["equal-groups.explainer", "subtraction.explainer"])
    }

    @Test func aDocumentInAFolderIsRenamedWithinItsFolder() throws {
        let project = try TemporaryProject()
        let inner = project.folder.appendingPathComponent("drafts")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: project.url("subtraction"), to: inner.appendingPathComponent("subtraction.explainer"))
        let model = try openModel(project)
        let renamed = try model.renameDocument("drafts/subtraction", title: "Taking away")
        #expect(renamed.name == "drafts/taking-away")
        #expect(renamed.document?.json["id"]?.string == "taking-away")
        #expect(FileManager.default.fileExists(atPath: inner.appendingPathComponent("taking-away.explainer").path))
    }

    @Test func anEmptyTitleOrAFileThatCannotBeReadIsRefusedAndNothingChanges() throws {
        let project = try TemporaryProject()
        try Data("{".utf8).write(to: project.url("broken"))
        let model = try openModel(project)
        let before = try files(project)
        #expect(throws: (any Error).self) { try model.renameDocument("subtraction", title: "  ") }
        #expect(throws: (any Error).self) { try model.renameDocument("broken", title: "Mended") }
        #expect(throws: (any Error).self) { try model.renameDocument("absent", title: "Present") }
        #expect(try files(project) == before)
        #expect(try onDisk(project, "subtraction").title == "Two-digit subtraction by trading a ten")
    }

    /// A model with an undo manager of the test's own, in which each patch is one step.
    private func undoing(_ model: StudioModel) -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.undoManager = undo
        return undo
    }

    /// Sets a step's `hold` by a patch, as an agent does, which is one step of Undo.
    private func setHold(_ model: StudioModel, _ name: String, step: String, _ value: Int) throws {
        let hash = try #require(model.document(named: name)?.hash)
        let reply = model.respond(to: Studio.Method.patch, params: try params(
            #"{"doc":"\#(name)","base":"\#(hash)","ops":[{"op":"replace","path":"/steps/\#(step)/hold","value":\#(value)}]}"#), client: nil)
        #expect(reply.result?["applied"]?.bool == true)
    }

    private func hold(_ model: StudioModel, _ name: String, step: String) -> Double? {
        guard case let .number(n)? = model.document(named: name)?.document?.json["steps"]?[step]?["hold"] else { return nil }
        return n
    }

    @Test func undoAfterARenameTakesBackEarlierEditsAndKeepsTheNewName() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let undo = undoing(model)
        let original = hold(model, "equal-groups", step: "same")
        try setHold(model, "equal-groups", step: "same", 2)
        try setHold(model, "equal-groups", step: "same", 3)

        try model.renameDocument("equal-groups", title: "Sharing out")
        #expect(hold(model, "sharing-out", step: "same") == 3)

        // One step at a time, on the renamed document; the rename is not a step.
        undo.undo()
        #expect(hold(model, "sharing-out", step: "same") == 2)
        undo.undo()
        #expect(hold(model, "sharing-out", step: "same") == original)
        #expect(!undo.canUndo)
        #expect(try files(project) == ["sharing-out.explainer", "subtraction.explainer"])
        let file = try onDisk(project, "sharing-out")
        #expect(file.id == "sharing-out")
        #expect(file.title == "Sharing out")
        #expect(model.selectedName == "sharing-out")

        // Redo puts the edits back, and still leaves the name.
        undo.redo()
        #expect(hold(model, "sharing-out", step: "same") == 2)
        #expect(try onDisk(project, "sharing-out").title == "Sharing out")
    }

    @Test func undoWithoutARenameRestoresTheTitleAnEditChanged() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let undo = undoing(model)
        let hash = try #require(model.document(named: "equal-groups")?.hash)
        _ = model.respond(to: Studio.Method.patch, params: try params(
            #"{"doc":"equal-groups","base":"\#(hash)","ops":[{"op":"replace","path":"/title","value":"Another title"}]}"#), client: nil)
        #expect(try onDisk(project, "equal-groups").title == "Another title")
        undo.undo()
        #expect(try onDisk(project, "equal-groups").title == "Multiplying as equal groups")
    }

    @Test func undoNeverWritesToADocumentThatTookTheOldName() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let undo = undoing(model)
        try model.createDocument(title: "Reading the clock")
        let original = try Data(contentsOf: project.url("reading-the-clock"))
        let hash = try #require(model.document(named: "reading-the-clock")?.hash)
        _ = model.respond(to: Studio.Method.patch, params: try params(
            #"{"doc":"reading-the-clock","base":"\#(hash)","ops":[{"op":"add","path":"/about","value":{"licence":"CC-BY-4.0"}}]}"#), client: nil)
        #expect(undo.canUndo)

        try model.renameDocument("reading-the-clock", title: "Telling the time")
        try model.createDocument(title: "Reading the clock")
        let taker = try Data(contentsOf: project.url("reading-the-clock"))

        undo.undo()
        #expect(try Data(contentsOf: project.url("reading-the-clock")) == taker)
        let renamed = try #require(ExplainerDocument.read(contentsOf: project.url("telling-the-time")).document?.json)
        #expect(renamed["about"] == nil)
        #expect(renamed["id"]?.string == "telling-the-time")
        #expect(renamed["title"]?.string == "Telling the time")
        // Apart from the name the rename gave, the document is as it was before the edit.
        let before = try #require(ExplainerDocument.read(original).document?.json)
        #expect(DocumentStarter.copy(of: before, id: "telling-the-time", title: "Telling the time") == renamed)
    }

    @Test func trashForgetsTheTrashedDocumentsStepsAndKeepsTheOthers() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let trash = try standInTrash(model)
        defer { try? FileManager.default.removeItem(at: trash) }
        let undo = undoing(model)
        let kept = hold(model, "equal-groups", step: "same")
        try setHold(model, "equal-groups", step: "same", 2)
        try model.createDocument(title: "Zebra")
        let hash = try #require(model.document(named: "zebra")?.hash)
        _ = model.respond(to: Studio.Method.patch, params: try params(
            #"{"doc":"zebra","base":"\#(hash)","ops":[{"op":"add","path":"/about","value":{"licence":"CC-BY-4.0"}}]}"#), client: nil)

        try model.trashDocument("zebra")
        // A document made later under the trashed one's name is not written by its steps.
        try model.createDocument(title: "Zebra")
        let later = try Data(contentsOf: project.url("zebra"))

        // The one step left is the other document's.
        #expect(undo.canUndo)
        undo.undo()
        #expect(hold(model, "equal-groups", step: "same") == kept)
        #expect(!undo.canUndo)
        #expect(try Data(contentsOf: project.url("zebra")) == later)
    }

    @Test func trashingTheOnlyEditedDocumentLeavesNothingToUndo() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let trash = try standInTrash(model)
        defer { try? FileManager.default.removeItem(at: trash) }
        let undo = undoing(model)
        try setHold(model, "equal-groups", step: "same", 2)
        #expect(undo.canUndo)
        try model.trashDocument("equal-groups")
        #expect(!undo.canUndo)
    }

    @Test func openingAnotherProjectForgetsUndosSteps() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let undo = undoing(model)
        try setHold(model, "equal-groups", step: "same", 2)
        let other = try TemporaryProject()
        model.open(folder: other.folder, watch: false)
        #expect(!undo.canUndo)
    }

    @Test func duplicateMakesACopyTitledCopyWithItsOwnIdAndSelectsIt() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        let steps = model.stepNames
        let original = try Data(contentsOf: project.url("subtraction"))

        let copy = try model.duplicateDocument("subtraction")
        #expect(copy.name == "two-digit-subtraction-by-trading-a-ten-copy")
        #expect(copy.title == "Two-digit subtraction by trading a ten copy")
        #expect(copy.document?.json["id"]?.string == copy.name)
        #expect(copy.errors == 0)
        #expect(model.selectedName == copy.name)
        #expect(model.stepNames == steps)
        #expect(try Data(contentsOf: project.url("subtraction")) == original)
        #expect(try listed(model) == ["equal-groups", "subtraction", copy.name])

        // A second copy of the same document is numbered in its title and its name.
        let second = try model.duplicateDocument("subtraction")
        #expect(second.title == "Two-digit subtraction by trading a ten copy 2")
        #expect(second.name == "two-digit-subtraction-by-trading-a-ten-copy-2")
        #expect(second.document?.json["id"]?.string == second.name)
    }

    @Test func trashMovesTheFileAwayAndShowsTheDocumentThatFollows() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let trash = try standInTrash(model)
        defer { try? FileManager.default.removeItem(at: trash) }
        try model.createDocument(title: "Zebra")
        model.select("subtraction")

        try model.trashDocument("subtraction")
        #expect(try listed(model) == ["equal-groups", "zebra"])
        #expect(!FileManager.default.fileExists(atPath: project.url("subtraction").path))
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("subtraction.explainer").path))
        #expect(model.selectedName == "zebra")
        #expect(model.player != nil)

        // The last of the list gives way to the one before it, and one that is not shown to none.
        try model.trashDocument("zebra")
        #expect(model.selectedName == "equal-groups")
        try model.createDocument(title: "Zebra")
        model.select("equal-groups")
        try model.trashDocument("zebra")
        #expect(model.selectedName == "equal-groups")

        try model.trashDocument("equal-groups")
        #expect(model.documents.isEmpty)
        #expect(model.selectedName == nil)
        #expect(model.player == nil)
    }

    @Test func aFileThatCannotBeTrashedStaysListedAndShown() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        struct Refused: Error {}
        model.moveToTrash = { _ in throw Refused() }
        model.select("subtraction")
        #expect(throws: (any Error).self) { try model.trashDocument("subtraction") }
        #expect(model.selectedName == "subtraction")
        #expect(try listed(model) == ["equal-groups", "subtraction"])
    }
}
