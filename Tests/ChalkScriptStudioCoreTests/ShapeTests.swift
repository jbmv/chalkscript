import ChalkScript
import struct ChalkScript.Scene
import ChalkScriptMCP
import CoreGraphics
import Foundation
import Testing
@testable import ChalkScriptStudioCore

/// The shapes the studio previews, the window's shape outside a declaration, the agent's picture
/// at a shape, and the declaration a person writes in the Declare Shapes sheet (EXP-17).
@MainActor
struct ShapeTests {
    private func pngSize(_ r: ChalkScriptMCP.JSONValue) throws -> (Int, Int) {
        let data = try #require(r["image"]?["data"]?.string.flatMap { Data(base64Encoded: $0) })
        let width = data[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let height = data[20..<24].reduce(0) { $0 << 8 | Int($1) }
        return (width, height)
    }

    private func areas(_ model: StudioModel, _ name: String) -> DocJSON? {
        ExplainerDocument.read(contentsOf: model.document(named: name)!.url).document?.json["areas"]
    }

    @Test func eachDeclaredRangeIsPreviewedAtItsEndsAndMiddle() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        #expect(model.previewShapes.map(\.label) == ["0.60 · tall", "0.90 · tall", "1.35 · tall", "1.72 · stage", "2.20 · stage"])
        model.select("equal-groups")
        #expect(model.previewShapes.map(\.label) == ["0.90 · stage", "1.41 · stage", "2.20 · stage"])
    }

    @Test func aDocumentWithoutADeclarationHasNoPreviewsAndStartsTheSheetFromASuggestion() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        #expect(try model.declareShapes([]).isEmpty)
        #expect(areas(model, "subtraction") == nil)
        #expect(model.previewShapes.isEmpty)
        let doc = try #require(model.selected?.document)
        // tall suits up to 1.35, so the runs of the ratios 0.5, 0.55, ... 2.5 meet between 1.35 and 1.4.
        #expect(Shapes.rows(doc).map { "\($0.layout) \($0.min) \($0.max)" } == ["tall 0.5 1.35", "stage 1.4 2.5"])
    }

    @Test func theWindowOutsideTheDeclarationIsShownAsThePlayerLaysItOut() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        let player = try #require(model.player)
        player.layOut(for: CGSize(width: 400, height: 1000))
        #expect(model.shapeStatus == "Window 0.40 is not a declared shape; shown as 0.60")
        #expect(model.canDeclareShownShape)
        let use = try #require(player.areaUse)
        #expect(use.given == CGSize(width: 400, height: 1000))
        #expect(abs(use.used.height - 400 / 0.6) < 0.01)
        // The picture is the 0.6 one, framed so that the margin above and below is seen.
        let scene = player.scene
        #expect(abs(Double(scene.size.width / scene.size.height) - 0.6) < 0.005)
        #expect(scene.element("studio.areaFrame") != nil)
        #expect(model.shaped?.shown.resolved.layout == "tall")

        // A declared window shape says nothing and is not framed.
        player.layOut(for: CGSize(width: 900, height: 1000))
        #expect(model.shapeStatus == nil)
        #expect(!model.canDeclareShownShape)
        #expect(player.scene.element("studio.areaFrame") == nil)
    }

    @Test func aPreviewLaysTheDocumentOutForTheLargestAreaOfItsShape() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        model.setShape(.ratio(0.9))
        let player = try #require(model.player)
        player.layOut(for: CGSize(width: 1000, height: 500))
        #expect(model.shapeStatus == "Previewing 0.90 · stage")
        let use = try #require(player.areaUse)
        #expect(abs(use.used.width - 450) < 0.01 && use.used.height == 500)
        // The stage is fitted into the 0.9 area, not into the pane: the scene is widened to 0.9.
        let scene = player.scene
        #expect(abs(Double(scene.size.width / scene.size.height) - 0.9) < 0.001)
        #expect(scene.size.width == 1000)
        let frame = try #require(scene.element("studio.areaFrame"))
        #expect(frame.fixed)

        // A pane of the preview's own shape needs no frame.
        player.layOut(for: CGSize(width: 900, height: 1000))
        #expect(player.scene.element("studio.areaFrame") == nil)
        #expect(player.scene.size == Scene.stage)

        // The preview changes nothing in the document, and choosing another document returns to the window.
        let hash = model.selected?.hash
        model.select("subtraction")
        #expect(model.shape == .window)
        #expect(model.document(named: "equal-groups")?.hash == hash)
    }

    @Test func aPreviewOfAnUndeclaredShapeSaysSo() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        model.setShape(.ratio(0.4))
        model.player?.layOut(for: CGSize(width: 1000, height: 1000))
        #expect(model.shapeStatus == "0.40 is not a declared shape; shown as 0.60")
    }

    @Test func declareThisShapeMovesTheNearestEndAsOneStepOfUndo() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.undoManager = undo
        model.select("subtraction")
        model.player?.layOut(for: CGSize(width: 452, height: 1000))
        let before = model.selected?.hash
        #expect(model.declareShownShape().isEmpty)
        #expect(areas(model, "subtraction")?.array?[0]["ratio"] == .array([.number(0.45), .number(1.35)]))
        #expect(undo.undoActionName == "Declare This Shape")
        // The window is played again at its own shape, now declared.
        #expect(model.shapeStatus == nil)
        undo.undo()
        #expect(model.selected?.hash == before)

        model.player?.layOut(for: CGSize(width: 2411, height: 1000))
        #expect(model.declareShownShape().isEmpty)
        #expect(areas(model, "subtraction")?.array?[1]["ratio"] == .array([.number(1.35), .number(2.42)]))
    }

    @Test func theSheetAddsChangesAndRemovesRangesAsOnePatch() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.undoManager = undo
        model.select("subtraction")
        let doc = try #require(model.selected?.document)
        var rows = Shapes.rows(doc)
        #expect(rows.map(\.layout) == ["tall", "stage"])
        #expect(rows.map(\.max) == ["1.35", "2.2"])

        rows[1].max = "2.4"
        rows.append(DeclaredRow(layout: "stage", min: "2.4", max: "3"))
        #expect(try model.declareShapes(rows).isEmpty)
        #expect(undo.undoActionName == "Declare Shapes")
        #expect(areas(model, "subtraction")?.array?.count == 3)
        #expect(areas(model, "subtraction")?.array?[1]["ratio"] == .array([.number(1.35), .number(2.4)]))
        undo.undo()
        #expect(areas(model, "subtraction")?.array?.count == 2)
        // Unchanged rows make no patch.
        #expect(try model.declareShapes(Shapes.rows(try #require(model.selected?.document))).isEmpty)
        #expect(!undo.canUndo)

        rows = Shapes.rows(try #require(model.selected?.document))
        rows.removeFirst()
        #expect(try model.declareShapes(rows).isEmpty)
        #expect(areas(model, "subtraction")?.array?.map { $0["layout"]?.string } == ["stage"])
        // A layout no range names is a warning, not a refusal.
        #expect(model.selected?.findings.contains { $0.code == .areas && $0.path == "/layouts/tall" } == true)
    }

    @Test func theSheetRefusesWhatCannotBeDeclared() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        let hash = model.selected?.hash
        #expect(throws: ShapeError.self) { try model.declareShapes([DeclaredRow(layout: "stage", min: "2", max: "1")]) }
        #expect(throws: ShapeError.self) { try model.declareShapes([DeclaredRow(layout: "stage", min: "0", max: "1")]) }
        #expect(throws: ShapeError.self) { try model.declareShapes([DeclaredRow(layout: "stage", min: "", max: "1")]) }
        // A layout the document lacks is refused by the patch engine, with its finding.
        let refused = try model.declareShapes([DeclaredRow(layout: "wide", min: "1", max: "2")])
        #expect(refused.contains { $0.code == .ref })
        #expect(model.selected?.hash == hash)
    }

    @Test func theAgentsPictureIsLaidOutForTheRatioAskedFor() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let tall = try #require(model.respond(to: Studio.Method.show, params: try params(
            #"{"doc":"subtraction","step":"trade","ratio":0.6,"image":true}"#), client: nil).result)
        #expect(try pngSize(tall) == (288, 480))
        #expect(tall["ratio"] == .number("0.6"))
        #expect(tall["layout"]?.string == "tall")

        // An undeclared shape is pictured as the player lays it out: the nearest declared shape inside it.
        let narrow = try #require(model.respond(to: Studio.Method.show, params: try params(
            #"{"doc":"subtraction","step":"trade","ratio":0.4,"image":true}"#), client: nil).result)
        #expect(try pngSize(narrow) == (192, 320))
        #expect(narrow["ratio"] == .number("0.6"))

        let wide = try #require(model.respond(to: Studio.Method.show, params: try params(
            #"{"doc":"subtraction","step":"trade","ratio":2.2,"image":true}"#), client: nil).result)
        #expect(try pngSize(wide) == (480, 218))
        #expect(wide["layout"]?.string == "stage")

        // Without a ratio, the shape the window shows.
        model.player?.layOut(for: CGSize(width: 900, height: 1000))
        let window = try #require(model.respond(to: Studio.Method.show, params: try params(
            #"{"doc":"subtraction","step":"trade","image":true}"#), client: nil).result)
        #expect(try pngSize(window) == (432, 480))
        #expect(window["layout"]?.string == "tall")

        let bad = model.respond(to: Studio.Method.show, params: try params(#"{"doc":"subtraction","ratio":-1}"#), client: nil)
        #expect(bad.errorCode == Studio.RPCError.invalidParams)
    }
}
