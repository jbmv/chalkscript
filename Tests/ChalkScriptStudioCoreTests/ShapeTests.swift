import ChalkScript
import struct ChalkScript.Scene
import ChalkScriptMCP
import CoreGraphics
import Foundation
import Testing
@testable import ChalkScriptStudioCore

/// The Preview menu, the status line's account of the drawing area, the agent's picture at a
/// ratio, and the presets a person ticks (EXP-17).
@MainActor
struct ShapeTests {
    private func pngSize(_ r: ChalkScriptMCP.JSONValue) throws -> (Int, Int) {
        let data = try #require(r["image"]?["data"]?.string.flatMap { Data(base64Encoded: $0) })
        let width = data[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let height = data[20..<24].reduce(0) { $0 << 8 | Int($1) }
        return (width, height)
    }

    private func saved(_ model: StudioModel, _ name: String) throws -> ExplainerDocument {
        try #require(ExplainerDocument.read(contentsOf: model.document(named: name)!.url).document)
    }

    private func areas(_ doc: ExplainerDocument) -> [String] {
        (doc.json["areas"]?.array ?? []).map { e in
            let r = (e["ratio"]?.array ?? []).map { v -> String in
                if case let .number(n) = v { return Canonical.number(n) }
                return "?"
            }
            return "\(e["layout"]?.string ?? "?") \(r.joined(separator: "-"))"
        }
    }

    private func areaWarnings(_ doc: ExplainerDocument) -> [DocumentFinding] { doc.findings.filter { $0.code == .areas } }

    // MARK: the presets a document is made for

    @Test func tickingAndUntickingAPresetWritesOnlyAreas() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        let before = try saved(model, "subtraction")
        #expect(model.madeFor == [.tall, .square, .wide])
        // Ticking what is ticked changes nothing.
        #expect(model.setMadeFor(.square, true).isEmpty)
        #expect(try saved(model, "subtraction").shortHash == before.shortHash)

        #expect(model.setMadeFor(.wide, false).isEmpty)
        var doc = try saved(model, "subtraction")
        // The rule gives 1.35 itself to the wide layout, so without Wide the range stops short of it.
        #expect(areas(doc) == ["tall 0.6-1.34"])
        #expect(model.madeFor == [.tall, .square])
        #expect(doc.json["layouts"] == before.json["layouts"], "no layout is made, removed or given another rule")
        #expect(areaWarnings(doc).isEmpty)
        #expect(model.previewItems.map(\.label) == ["Custom 0.60 to 1.34 · 0.90"], "a range that stops short of a preset is a custom one")

        #expect(model.setMadeFor(.tall, false).isEmpty)
        #expect(areas(try saved(model, "subtraction")) == ["tall 0.9-1.34"])
        #expect(model.setMadeFor(.square, false).isEmpty)
        doc = try saved(model, "subtraction")
        #expect(doc.json["areas"] == nil && model.madeFor.isEmpty)
        #expect(model.previewItems.isEmpty)

        // Ticked again, each range names the layout the document's own rule chooses there.
        for preset in Preset.allCases { #expect(model.setMadeFor(preset, true).isEmpty) }
        doc = try saved(model, "subtraction")
        #expect(areas(doc) == ["tall 0.6-1.35", "stage 1.35-2.2"])
        #expect(doc.json["layouts"] == before.json["layouts"])
        #expect(areaWarnings(doc).isEmpty)
        #expect(model.previewItems.map(\.label) == ["Tall · 0.75", "Square · 1.10", "Wide · 1.78"])
    }

    @Test func aPresetIsMadeForWhenItsNominalRatioIsDeclaredAndOutsideRangesAreKept() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        #expect(model.madeFor == [.square, .wide], "stage is declared from 0.9 to 2.2")
        #expect(model.setMadeFor(.tall, true).isEmpty)
        var doc = try saved(model, "equal-groups")
        #expect(areas(doc) == ["stage 0.6-2.2"])
        #expect(areaWarnings(doc).isEmpty)
        #expect(model.previewItems.map(\.title) == ["Tall", "Square", "Wide"])
        // A range beyond the presets, written by an agent, survives a tick.
        let wider = try DocJSON.parse(#"[{"op": "add", "path": "/areas/-", "value": {"layout": "stage", "ratio": [2.5, 4]}}]"#)
        _ = try model.patch("equal-groups", base: doc.shortHash, ops: wider.array ?? [], actionName: "test")
        #expect(model.setMadeFor(.tall, false).isEmpty)
        doc = try saved(model, "equal-groups")
        #expect(areas(doc) == ["stage 0.9-2.2", "stage 2.5-4"])
    }

    @Test func aDocumentIsFirstShownAtTheDefaultPreview() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.defaultPreview = .ratio(Preset.square.nominal)
        model.select("subtraction")
        model.select("equal-groups")
        #expect(model.preview == .ratio(1.1))
        model.setPreview(.ratio(Preset.tall.nominal))
        model.select("subtraction")
        #expect(model.preview == .ratio(1.1))
        model.player?.layOut(for: CGSize(width: 800, height: 600))
        #expect(model.areaStatus == "Layout tall · previewing Square at 1.10")
    }

    // MARK: reading a document as presets

    @Test func presetsAreTheStudiosNamesForThreeRanges() {
        #expect(Preset.allCases.map(\.range) == [0.6...0.9, 0.9...1.35, 1.35...2.2])
        #expect(Preset.allCases.map(\.nominal) == [0.75, 1.1, 1.78])
        #expect(Preset.allCases.allSatisfy { $0.range.contains($0.nominal) })
    }

    @Test func aDocumentsAreasAreReadAsThePresetsTheyCover() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        // tall covers 0.6 to 1.35, which is Tall and Square; stage covers Wide.
        #expect(model.previewItems.map(\.label) == ["Tall · 0.75", "Square · 1.10", "Wide · 1.78"])

        model.select("equal-groups")
        #expect(model.previewItems.map(\.label) == ["Square · 1.10", "Wide · 1.78"])
    }

    @Test func areasThatAreNotPresetsAreReadAsCustomRanges() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        let doc = try #require(model.selected?.document)
        let value = try DocJSON.parse(#"[{"layout": "tall", "ratio": [0.5, 1.2]}, {"layout": "stage", "ratio": [1.2, 3]}]"#)
        _ = try model.patch("subtraction", base: doc.shortHash, ops: [.object(DocObject([("op", .string("replace")), ("path", .string("/areas")), ("value", value)]))])
        #expect(model.previewItems.map(\.label) == ["Custom 0.50 to 1.20 · 0.77", "Custom 1.20 to 3.00 · 1.90"])
        #expect(model.madeFor == [.tall, .square, .wide])
    }

    // MARK: the status line and its button

    @Test func theStatusLineNamesTheLayoutAndAnAreaTheDocumentIsNotMadeFor() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        let player = try #require(model.player)
        player.layOut(for: CGSize(width: 400, height: 1000))
        #expect(model.areaStatus == "Layout tall · pane 0.40 is not a shape the document is made for; drawn at 0.60")
        let use = try #require(player.areaUse)
        #expect(abs(use.used.height - 400 / 0.6) < 0.01)
        // None shows the drawing as an app shows it: laid out for 0.6, with no frame.
        #expect(player.scene.element("studio.areaFrame") == nil)
        #expect(model.shaped?.shown.resolved.layout == "tall")


        model.player?.layOut(for: CGSize(width: 900, height: 1000))
        #expect(model.areaStatus == "Layout tall · pane 0.90")
    }

    @Test func anAreaInsideAPresetTheDocumentLacksIsSaidToBeOneItIsNotMadeFor() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        model.player?.layOut(for: CGSize(width: 750, height: 1000))
        #expect(model.areaStatus == "Layout stage · pane 0.75 is not a shape the document is made for; drawn at 0.90")
    }

    @Test func aPresetIsPreviewedAtItsNominalRatioInAFrame() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        model.setPreview(.ratio(Preset.square.nominal))
        let player = try #require(model.player)
        player.layOut(for: CGSize(width: 1000, height: 500))
        #expect(model.areaStatus == "Layout stage · previewing Square at 1.10")
        let use = try #require(player.areaUse)
        #expect(abs(use.used.width - 550) < 0.01 && use.used.height == 500)
        let scene = player.scene
        #expect(abs(Double(scene.size.width / scene.size.height) - 1.1) < 0.001)
        let frame = try #require(scene.element("studio.areaFrame"))
        #expect(frame.fixed)

        // A pane of the preview's own shape needs no frame.
        player.layOut(for: CGSize(width: 1100, height: 1000))
        #expect(player.scene.element("studio.areaFrame") == nil)

        // The preview changes nothing in the document, and choosing another document returns to None.
        let hash = model.selected?.hash
        model.select("subtraction")
        #expect(model.preview == .none)
        #expect(model.document(named: "equal-groups")?.hash == hash)
    }

    @Test func aTestRatioOutsideTheDocumentSaysSo() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        model.setPreview(.ratio(0.4))
        model.player?.layOut(for: CGSize(width: 1000, height: 1000))
        #expect(model.areaStatus == "Layout tall · 0.40 is not a shape the document is made for; drawn at 0.60")
        #expect(model.player?.scene.element("studio.areaFrame") != nil)
        model.setPreview(.ratio(1.2))
        #expect(model.areaStatus == "Layout tall · previewing 1.20")
    }

    // MARK: the agent's picture

    @Test func theAgentsPictureIsLaidOutForTheRatioAskedFor() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let tall = try #require(model.respond(to: Studio.Method.show, params: try params(
            #"{"doc":"subtraction","step":"trade","ratio":0.6,"image":true}"#), client: nil).result)
        #expect(try pngSize(tall) == (288, 480))
        #expect(tall["ratio"] == .number("0.6"))
        #expect(tall["layout"]?.string == "tall")

        // An undeclared shape is pictured as the player lays it out: the nearest declared shape, scaled, centred and framed in the area asked for.
        let narrow = try #require(model.respond(to: Studio.Method.show, params: try params(
            #"{"doc":"subtraction","step":"trade","ratio":0.4,"image":true}"#), client: nil).result)
        #expect(try pngSize(narrow) == (192, 480))
        #expect(narrow["ratio"] == .number("0.4"))
        #expect(narrow["drawn"] == .number("0.6"))
        #expect(tall["drawn"] == nil)

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
