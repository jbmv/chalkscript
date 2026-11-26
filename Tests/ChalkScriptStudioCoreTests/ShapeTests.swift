import ChalkScript
import struct ChalkScript.Scene
import ChalkScriptMCP
import CoreGraphics
import Foundation
import Testing
@testable import ChalkScriptStudioCore

/// The Preview menu, the status line's account of the drawing area, the agent's picture at a
/// ratio, and the presets and layouts a person chooses in the Layouts sheet (EXP-17).
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

    private func suits(_ doc: ExplainerDocument, _ layout: String) -> String? { doc.json["layouts"]?[layout]?["suits"]?.string }

    private func areaWarnings(_ doc: ExplainerDocument) -> [DocumentFinding] { doc.findings.filter { $0.code == .areas } }

    private func plan(_ model: StudioModel) throws -> LayoutPlan { try #require(model.layoutPlan) }

    // MARK: reading a document as presets

    @Test func presetsAreTheStudiosNamesForThreeRanges() {
        #expect(Preset.allCases.map(\.range) == [0.6...0.9, 0.9...1.35, 1.35...2.2])
        #expect(Preset.allCases.map(\.nominal) == [0.75, 1.1, 1.78])
        #expect(Preset.allCases.allSatisfy { $0.range.contains($0.nominal) })
        #expect(Preset.holding(0.9) == .tall)
        #expect(Preset.holding(1.35) == .square)
        #expect(Preset.holding(2) == .wide)
        #expect(Preset.holding(0.5) == nil)
    }

    @Test func aDocumentsAreasAreReadAsThePresetsTheyCover() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        // tall covers 0.6 to 1.35, which is Tall and Square; stage covers Wide.
        var p = try plan(model)
        #expect(p.declared)
        #expect(p.rows.map { "\($0.id) \($0.isOn) \($0.layout)" } == ["tall true tall", "square true tall", "wide true stage"])
        #expect(p.sharing("tall").map(\.id) == ["square"])
        #expect(model.previewItems.map(\.label) == ["Tall · 0.75", "Square · 1.10", "Wide · 1.78"])

        model.select("equal-groups")
        p = try plan(model)
        #expect(p.rows.map { "\($0.id) \($0.isOn) \($0.layout)" } == ["tall false stage", "square true stage", "wide true stage"])
        #expect(model.previewItems.map(\.label) == ["Square · 1.10", "Wide · 1.78"])
    }

    @Test func areasThatAreNotPresetsOpenAsCustomRangesAndSaveUnchangedWritesNothing() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.select("subtraction")
        let doc = try #require(model.selected?.document)
        let value = try DocJSON.parse(#"[{"layout": "tall", "ratio": [0.5, 1.2]}, {"layout": "stage", "ratio": [1.2, 3]}]"#)
        _ = try model.patch("subtraction", base: doc.shortHash, ops: [.object(DocObject([("op", .string("replace")), ("path", .string("/areas")), ("value", value)]))])
        model.undoManager = undo
        let before = try #require(model.selected?.hash)
        let p = try plan(model)
        #expect(p.rows.filter(\.isOn).map { "\($0.name) \($0.layout)" } == ["Custom 0.50 to 1.20 tall", "Custom 1.20 to 3.00 stage"])
        #expect(!p.rows.contains { $0.preset != nil && $0.isOn })
        #expect(model.previewItems.map(\.label) == ["Custom 0.50 to 1.20 · 0.77", "Custom 1.20 to 3.00 · 1.90"])
        #expect(try model.saveLayouts(p).isEmpty)
        #expect(model.selected?.hash == before)
        #expect(!undo.canUndo)
    }

    @Test func aDocumentWithoutAreasStartsFromASuggestionOfEveryPreset() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        var p = try plan(model)
        for row in p.rows { p.setOn(row.id, false) }
        #expect(try model.saveLayouts(p).isEmpty)
        let doc = try saved(model, "subtraction")
        #expect(doc.json["areas"] == nil)
        #expect(model.previewItems.isEmpty)
        p = try plan(model)
        #expect(!p.declared)
        #expect(p.rows.map { "\($0.id) \($0.isOn) \($0.layout)" } == ["tall true tall", "square true tall", "wide true stage"])
        // Saving the suggestion declares it; tall's suits already agrees and is not rewritten.
        #expect(try model.saveLayouts(p).isEmpty)
        let declared = try saved(model, "subtraction")
        #expect(areas(declared) == ["tall 0.6-1.35", "stage 1.35-2.2"])
        #expect(suits(declared, "tall") == "areaW <= areaH * 1.35")
        #expect(areaWarnings(declared).isEmpty)
    }

    // MARK: saving the sheet

    @Test func aPresetGivenItsOwnLayoutGetsACopyAndEverySuitsAgrees() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.undoManager = undo
        model.select("subtraction")
        let original = try saved(model, "subtraction")
        var p = try plan(model)
        p.useOwn("square")
        #expect(p.rows[1].layout == "square")
        #expect(p.copies == ["square": "tall"])
        #expect(try model.saveLayouts(p).isEmpty)
        #expect(undo.undoActionName == "Layouts")
        let doc = try saved(model, "subtraction")
        #expect(areas(doc) == ["tall 0.6-0.9", "square 0.9-1.35", "stage 1.35-2.2"])
        #expect(suits(doc, "tall") == "areaW <= areaH * 0.9")
        #expect(suits(doc, "square") == "areaW >= areaH * 0.9 and areaW <= areaH * 1.35")
        // The copy is tall's, but for its suits.
        var copy = try #require(original.json["layouts"]?["tall"]?.object)
        copy["suits"] = doc.json["layouts"]?["square"]?["suits"]
        #expect(doc.json["layouts"]?["square"]?.object == copy)
        #expect(areaWarnings(doc).isEmpty)
        #expect(!doc.findings.hasErrors)
        #expect(Preset.allCases.map { doc.layout(for: Shapes.namingArea($0.nominal), problem: doc.samples[0]) } == ["tall", "square", "stage"])
        // The patch is one step of Undo.
        undo.undo()
        #expect(try saved(model, "subtraction").json == original.json)
    }

    @Test func aPresetMayTakeTheLayoutOfAnother() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        var p = try plan(model)
        p.setOn("tall", true)
        p.useSame("tall", as: "square")
        #expect(try model.saveLayouts(p).isEmpty)
        var doc = try saved(model, "equal-groups")
        #expect(areas(doc) == ["stage 0.6-2.2"])
        #expect(model.previewItems.map(\.title) == ["Tall", "Square", "Wide"])

        // Wide's own layout starts as a copy of stage, with stage's size.
        p = try plan(model)
        p.useOwn("wide")
        #expect(try model.saveLayouts(p).isEmpty)
        doc = try saved(model, "equal-groups")
        #expect(areas(doc) == ["stage 0.6-1.35", "wide 1.35-2.2"])
        #expect(doc.json["layouts"]?["wide"] == (try DocJSON.parse(#"{"suits": "areaW >= areaH * 1.35", "size": [1000, 540]}"#)))
        #expect(areaWarnings(doc).isEmpty)
    }

    @Test func aPresetLeftOutLeavesAGapWhoseBoundaryIsInItsMiddle() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        var p = try plan(model)
        p.setOn("square", false)
        #expect(try model.saveLayouts(p).isEmpty)
        let doc = try saved(model, "subtraction")
        #expect(areas(doc) == ["tall 0.6-0.9", "stage 1.35-2.2"])
        // sqrt(0.9 * 1.35) is 1.102..., and 1.1 lies inside the gap.
        #expect(suits(doc, "tall") == "areaW <= areaH * 1.1")
        #expect(areaWarnings(doc).isEmpty)
    }

    @Test func theSheetRefusesWhatWouldLeaveALayoutUnusedOrRangesOverlapping() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        let hash = model.selected?.hash
        var p = try plan(model)
        p.setOn("tall", false)
        p.setOn("square", false)
        #expect(throws: ShapeError.self) { try model.saveLayouts(p) }
        // Drawn at Wide, tall is used again, and suits every declared shape.
        p.use("wide", layout: "tall")
        #expect(try model.saveLayouts(p).isEmpty)
        let doc = try saved(model, "subtraction")
        #expect(areas(doc) == ["tall 1.35-2.2"])
        #expect(suits(doc, "tall") == "true")
        #expect(areaWarnings(doc).isEmpty)

        model.select("equal-groups")
        let groups = model.selected?.hash
        p = try plan(model)
        let id = p.addCustom(min: "0.8", max: "1", layout: "stage")
        p.useOwn(id)
        #expect(throws: ShapeError.self) { try model.saveLayouts(p) }
        for (lo, hi) in [("", "1"), ("0", "1"), ("2", "1")] {
            var bad = try plan(model)
            bad.addCustom(min: lo, max: hi)
            #expect(throws: ShapeError.self) { try model.saveLayouts(bad) }
        }
        #expect(model.selected?.hash == groups)
        #expect(model.document(named: "subtraction")?.hash != hash)
    }

    @Test func aCustomRangeInTheSameLayoutAsItsNeighbourIsJoinedToIt() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        var p = try plan(model)
        p.addCustom(min: "2.2", max: "3", layout: "stage")
        #expect(try model.saveLayouts(p).isEmpty)
        #expect(areas(try saved(model, "equal-groups")) == ["stage 0.9-3"])
        // Its range is no longer a run of presets, so it opens as a custom range.
        #expect(try plan(model).included.map(\.name) == ["Custom 0.90 to 3.00"])
    }

    /// Every way the sheet can set the examples' presets: each preset on or off, and each on
    /// drawn in a layout of the document or in its own. Each either is refused for a layout left
    /// unused, or writes a document with no error and no `areas` warning in which every declared
    /// shape is drawn in the layout its range names.
    @Test func everyChoiceOfPresetsAndLayoutsAgreesWithItsSuits() throws {
        let project = try TemporaryProject()
        for name in ["subtraction", "equal-groups"] {
            let doc = try #require(ExplainerDocument.read(contentsOf: project.url(name)).document)
            let original = LayoutPlan(doc)
            let choices = original.layouts + ["own"]
            var written = 0, refused = 0
            for mask in 1..<8 {
                let on = Preset.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
                var assignments: [[String]] = [[]]
                for _ in on { assignments = assignments.flatMap { a in choices.map { a + [$0] } } }
                for assignment in assignments {
                    var p = original
                    for preset in Preset.allCases { p.setOn(preset.rawValue, on.contains(preset)) }
                    for (preset, choice) in zip(on, assignment) {
                        if choice == "own" { p.useOwn(preset.rawValue) } else { p.use(preset.rawValue, layout: choice) }
                    }
                    let ops: [DocJSON]?
                    do {
                        ops = try Shapes.patch(doc, plan: p, original: original)
                    } catch {
                        #expect(error.message.contains("would be drawn at no shape"), "\(name) \(on) \(assignment): \(error.message)")
                        refused += 1
                        continue
                    }
                    let result = doc.patch(base: doc.shortHash, ops: ops ?? [])
                    #expect(ops == nil || result.applied, "\(name) \(on) \(assignment): \(result.findings)")
                    let out = result.document
                    #expect(areaWarnings(out).isEmpty, "\(name) \(on) \(assignment): \(areaWarnings(out))")
                    for row in p.included {
                        let preset = try #require(row.preset)
                        for r in [preset.range.lowerBound, preset.nominal, preset.range.upperBound] {
                            let chosen = out.layout(for: Shapes.area(ratio: r, longerSide: 1000), problem: out.samples[0])
                            let allowed = p.included.filter { $0.preset!.range.contains(r) }.map(\.layout)
                            #expect(allowed.contains(chosen), "\(name) \(on) \(assignment) at \(r): \(chosen)")
                        }
                    }
                    written += 1
                }
            }
            #expect(written > 0 && refused > 0 || name == "equal-groups")
        }
    }

    // MARK: the status line and its button

    @Test func theStatusLineNamesTheLayoutAndAnAreaTheDocumentIsNotMadeFor() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.undoManager = undo
        model.select("subtraction")
        let player = try #require(model.player)
        player.layOut(for: CGSize(width: 400, height: 1000))
        #expect(model.areaStatus == "Layout tall · pane 0.40 is not a shape the document is made for; drawn at 0.60")
        #expect(model.additionLabel == "Add 0.40")
        let use = try #require(player.areaUse)
        #expect(abs(use.used.height - 400 / 0.6) < 0.01)
        // None shows the drawing as an app shows it: laid out for 0.6, with no frame.
        #expect(player.scene.element("studio.areaFrame") == nil)
        #expect(model.shaped?.shown.resolved.layout == "tall")

        #expect(model.addShownArea().isEmpty)
        #expect(areas(try saved(model, "subtraction")) == ["tall 0.4-1.35", "stage 1.35-2.2"])
        #expect(undo.undoActionName == "Add 0.40")
        #expect(model.areaStatus == "Layout tall · pane 0.40")
        #expect(model.additionLabel == nil)
        undo.undo()

        model.player?.layOut(for: CGSize(width: 900, height: 1000))
        #expect(model.areaStatus == "Layout tall · pane 0.90")
        #expect(model.additionLabel == nil)
        model.player?.layOut(for: CGSize(width: 2411, height: 1000))
        #expect(model.addShownArea().isEmpty)
        #expect(areas(try saved(model, "subtraction")) == ["tall 0.6-1.35", "stage 1.35-2.42"])
    }

    @Test func anAreaInsideAPresetTheDocumentLacksAddsThatPreset() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        model.player?.layOut(for: CGSize(width: 750, height: 1000))
        #expect(model.areaStatus == "Layout stage · pane 0.75 is not a shape the document is made for; drawn at 0.90")
        #expect(model.additionLabel == "Add Tall")
        #expect(model.addShownArea().isEmpty)
        let doc = try saved(model, "equal-groups")
        #expect(areas(doc) == ["stage 0.6-2.2"])
        #expect(model.areaStatus == "Layout stage · pane 0.75")
    }

    @Test func aPresetIsPreviewedAtItsNominalRatioInAFrame() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("equal-groups")
        model.setPreview(.ratio(Preset.square.nominal))
        let player = try #require(model.player)
        player.layOut(for: CGSize(width: 1000, height: 500))
        #expect(model.areaStatus == "Layout stage · previewing Square at 1.10")
        #expect(model.additionLabel == nil)
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

    @Test func aTestRatioOutsideTheDocumentSaysSoAndOffersToAddIt() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.select("subtraction")
        model.setPreview(.ratio(0.4))
        model.player?.layOut(for: CGSize(width: 1000, height: 1000))
        #expect(model.areaStatus == "Layout tall · 0.40 is not a shape the document is made for; drawn at 0.60")
        #expect(model.additionLabel == "Add 0.40")
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
