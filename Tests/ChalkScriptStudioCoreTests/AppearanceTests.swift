import ChalkScript
import struct ChalkScript.Scene
import ChalkScriptMCP
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import ChalkScriptStudioCore

/// A clock made for dark alone, whose two colours give only dark values, and pictures to look
/// for colours in.
@MainActor
enum DarkClock {
    static let name = "clock-hour-minute"
    static let hours = RGB(hex: 0xFF924A)
    static let minutes = RGB(hex: 0x49F6FF)
    static let fixture = repository.appendingPathComponent("Tests/ChalkScriptStudioCoreTests/Fixtures/clock-hour-minute.explainer")

    /// The fixture's clock with `hours` and `minutes` in place of the roles `add` and `multiply`,
    /// each with the values given, and made for `appearances`.
    static func text(appearances: String? = #"["dark"]"#, hours: String = ##"{"dark": "#FF924A", "cue": "the short hand"}"##,
                     minutes: String = ##"{"dark": "#49F6FF", "cue": "the long hand"}"##) throws -> String {
        var text = try String(contentsOf: fixture, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"add", with: "\"hours").replacingOccurrences(of: "\"multiply", with: "\"minutes")
        let declared = appearances.map { "\"appearances\": \($0),\n  " } ?? ""
        let head = "\"sourceLocale\": \"en-US\","
        #expect(text.contains(head))
        return text.replacingOccurrences(of: head, with: "\(head)\n  \(declared)\"colours\": {\"hours\": \(hours), \"minutes\": \(minutes)},")
    }

    /// A project holding the clock as `text` gives it.
    static func project(_ text: String) throws -> TemporaryProject {
        let project = try TemporaryProject(examples: [fixture])
        try Data(text.utf8).write(to: project.url(name))
        return project
    }

    /// A model showing the dark-only clock at its last step, where both hands are drawn.
    static func model(_ project: TemporaryProject) throws -> StudioModel {
        let model = try openModel(project)
        model.select(name)
        let player = try #require(model.player, "\(model.refusal)")
        player.layOut(for: CGSize(width: 600, height: 545))
        player.show(step: player.explainer.stepCount - 1)
        while case .playing = player.phase { player.advance(by: 0.5) }
        return model
    }

    static let labels = ExplainerLabels(watch: "Watch", next: "Next", watchAgain: "Watch again", again: "Again", progress: { "Step \($0) of \($1)" })

    /// The player's screen as the window draws it when `scheme` is asked for, at one pixel a point.
    static func screen(_ model: StudioModel, asked scheme: ColorScheme) throws -> Pixels {
        let player = try #require(model.player)
        let view = ExplainerView(player: player, labels: labels, arrangement: .captionBelow)
            .frame(width: 700, height: 1000)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try #require(renderer.cgImage.flatMap(Pixels.init))
    }

    static func palette(_ appearance: Appearance) -> ExplainerPalette { ExplainerStyle.standard.palette(dark: appearance.isDark) }
}

/// A picture's pixels, to find a colour in.
struct Pixels {
    let width: Int
    let height: Int
    private var bytes: [UInt8]

    init?(_ image: CGImage) {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let c = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        (width, height, bytes) = (w, h, pixels)
    }

    init?(png: Data) {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(image)
    }

    /// How many opaque pixels are within 3 of `colour` in each channel.
    func count(_ colour: RGB) -> Int {
        let want = [colour.red, colour.green, colour.blue].map { Int(($0 * 255).rounded()) }
        var n = 0
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] == 255 {
            if (0..<3).allSatisfy({ abs(Int(bytes[i + $0]) - want[$0]) <= 3 }) { n += 1 }
        }
        return n
    }

    func has(_ colour: RGB) -> Bool { count(colour) > 0 }

    /// How many pixels differ from `other`'s by more than 2 in a channel, which is more than one
    /// drawing of a picture differs from another of the same; every pixel when the sizes differ.
    func differing(from other: Pixels) -> Int {
        guard width == other.width, height == other.height else { return width * height }
        var n = 0
        for i in stride(from: 0, to: bytes.count, by: 4) where (0..<4).contains(where: { abs(Int(bytes[i + $0]) - Int(other.bytes[i + $0])) > 2 }) { n += 1 }
        return n
    }
}

/// A document is drawn in the studio only in an appearance it is made for, with its own colours
/// (EXP-20): in the window's player and in the picture an agent is sent.
@MainActor
struct StudioAppearanceTests {
    private func picture(_ model: StudioModel, _ more: String = "") throws -> Pixels {
        let r = try #require(model.respond(to: Studio.Method.show, params: try params(
            #"{"doc":"\#(DarkClock.name)","step":"read","image":true\#(more)}"#), client: nil).result)
        return try #require(r["image"]?["data"]?.string.flatMap { Data(base64Encoded: $0) }.flatMap(Pixels.init(png:)))
    }

    @Test func theWindowDrawsADarkOnlyDocumentDarkWithItsColoursWhenLightIsAsked() throws {
        let model = try DarkClock.model(try DarkClock.project(try DarkClock.text()))
        #expect(model.player?.appearances == [.dark])
        let dark = DarkClock.palette(.dark), light = DarkClock.palette(.light)
        for scheme in [ColorScheme.light, .dark] {
            let screen = try DarkClock.screen(model, asked: scheme)
            // The drawing, in the colours the document gives.
            #expect(screen.has(DarkClock.hours), "the hour hand, \(scheme)")
            #expect(screen.has(DarkClock.minutes), "the minute hand, \(scheme)")
            // The sheet, the caption's paper behind it and the large control, in dark.
            #expect(screen.count(dark.sheet) > 10_000, "the sheet, \(scheme)")
            #expect(screen.has(dark.ink), "the caption and the dots, \(scheme)")
            #expect(screen.has(dark.colors(.result).fill), "the control, \(scheme)")
            // And nothing of the light palette's.
            #expect(!screen.has(light.sheet), "light sheet, \(scheme)")
            #expect(!screen.has(light.colors(.result).fill), "light control, \(scheme)")
        }
    }

    @Test func theExplainerTheStudioPlaysForwardsEveryPropertyOfTheDocumentsExplainer() throws {
        let doc = try #require(ExplainerDocument.read(Data(try DarkClock.text().utf8)).document)
        let made = try DocumentExplainer(document: doc, problem: doc.samples[0])
        #expect(made.appearances == [.dark])
        let shaped = ShapedExplainer(made, ratio: 1.1)
        let laid = shaped.laidOutExplainer(for: CGSize(width: 600, height: 545))
        for e in [shaped, laid] as [any Explainer] {
            #expect(e.appearances == made.appearances)
            #expect(e.version == made.version)
            #expect(e.stepCount == made.stepCount)
            #expect(e.intro == made.intro)
            #expect(e.script(for: 0) == made.script(for: 0))
        }
        #expect(laid.areaUse != nil)
    }

    @Test func thePictureAnAgentIsSentOfADarkOnlyDocumentIsDarkWithItsColours() throws {
        let model = try DarkClock.model(try DarkClock.project(try DarkClock.text()))
        let picture = try picture(model)
        #expect(picture.has(DarkClock.hours) && picture.has(DarkClock.minutes))
        #expect(picture.count(DarkClock.palette(.dark).sheet) > 10_000)
        #expect(!picture.has(DarkClock.palette(.light).sheet))
    }

    // A colour that has no value for an appearance is never drawn in the text colour there.
    @Test func aColourWithOnlyADarkValueIsDrawnAsGivenWhereverLightIsAsked() throws {
        let only = DocumentColour(name: "hours", light: nil, dark: DarkClock.hours)
        let light = DarkClock.palette(.light)
        // The palette's own answer, which every drawing takes its colours from.
        let colours = Hue.document(only).colors(in: light)
        #expect(colours.ink == DarkClock.hours && colours.fill == DarkClock.hours)
        #expect(colours.ink != light.ink)
        #expect(Hue.document(DocumentColour(name: "m", light: DarkClock.minutes, dark: nil)).colors(in: DarkClock.palette(.dark)).ink == DarkClock.minutes)

        // The stage, drawn by a host that asks for light and does not ask what the document is
        // made for.
        let doc = try #require(ExplainerDocument.read(Data(try DarkClock.text().utf8)).document)
        let made = try DocumentExplainer(document: doc, problem: doc.samples[0])
        let stage = ExplainerStage(scene: made.still(after: made.stepCount - 1))
            .frame(width: 440, height: 400)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: stage)
        renderer.scale = 1
        let drawn = try #require(renderer.cgImage.flatMap(Pixels.init))
        #expect(drawn.has(DarkClock.hours) && drawn.has(DarkClock.minutes))

        // The window's player and the agent's picture, asked for light.
        let model = try DarkClock.model(try DarkClock.project(try DarkClock.text()))
        let screen = try DarkClock.screen(model, asked: .light)
        #expect(screen.has(DarkClock.hours) && screen.has(DarkClock.minutes))
        let picture = try picture(model)
        #expect(picture.has(DarkClock.hours) && picture.has(DarkClock.minutes))
    }
}

/// The Light and Dark ticks, the value a tick derives, the status line's account of an appearance
/// the document is not made for, and the appearance of an agent's picture (EXP-20).
@MainActor
struct AppearanceTickTests {
    private func saved(_ model: StudioModel) throws -> ExplainerDocument {
        try #require(ExplainerDocument.read(contentsOf: model.document(named: DarkClock.name)!.url).document)
    }

    private func colourWarnings(_ model: StudioModel, on sheet: String) -> [DocumentFinding] {
        (model.selected?.findings ?? []).filter { $0.code == .colour && $0.message.contains("on the \(sheet) sheet") }
    }

    private func undoing(_ model: StudioModel) -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.undoManager = undo
        return undo
    }

    @Test func untickingLightRemovesItAndItsWarningsAndUndoRestoresBothInOneStep() throws {
        // Colours bright enough to be pale on the light sheet, in a document that declares nothing.
        let bright = try DarkClock.text(
            appearances: nil, hours: ##"{"light": "#FF924A", "dark": "#FF924A", "cue": "the short hand"}"##,
            minutes: ##"{"light": "#49F6FF", "dark": "#49F6FF", "cue": "the long hand"}"##)
        let modelProject = try DarkClock.project(bright)
        defer { withExtendedLifetime(modelProject) {} }
        let model = try DarkClock.model(modelProject)
        let undo = undoing(model)
        let before = try saved(model)
        #expect(model.madeForAppearances == [.light, .dark])
        #expect(!colourWarnings(model, on: "light").isEmpty)
        // Ticking what is ticked changes nothing.
        #expect(model.setMadeFor(.light, true).isEmpty)
        #expect(!undo.canUndo)

        #expect(model.setMadeFor(.light, false).isEmpty)
        var doc = try saved(model)
        #expect(doc.json["appearances"] == (try DocJSON.parse(#"["dark"]"#)))
        #expect(model.madeForAppearances == [.dark])
        #expect(colourWarnings(model, on: "light").isEmpty)
        #expect(doc.json["colours"] == before.json["colours"], "the light values stay, for ticking Light again")
        // The declaration stands just before `areas`.
        let keys = try #require(doc.json.object?.keys)
        #expect(keys.firstIndex(of: "appearances").map { $0 + 1 } == keys.firstIndex(of: "areas"))
        #expect(model.notice == nil)
        #expect(undo.undoActionName == "Not made for Light")

        // The last appearance stays.
        #expect(model.setMadeFor(.dark, false).isEmpty)
        #expect(try saved(model).shortHash == doc.shortHash)
        #expect(model.madeForAppearances == [.dark])

        undo.undo()
        doc = try saved(model)
        #expect(doc.shortHash == before.shortHash && !undo.canUndo)
        #expect(model.madeForAppearances == [.light, .dark])
        #expect(!colourWarnings(model, on: "light").isEmpty)

        // Ticking Light again, where every colour has a light value, writes none.
        undo.redo()
        #expect(model.setMadeFor(.light, true).isEmpty)
        #expect(try saved(model).json["colours"] == before.json["colours"])
        #expect(model.notice == nil)
    }

    /// The rows of the guide's colour table: a name, its light value and its dark value.
    private func guideColours() throws -> [(name: String, light: RGB, dark: RGB)] {
        let guide = try String(contentsOf: repository.appendingPathComponent("docs/format/authoring-guide.md"), encoding: .utf8)
        return guide.split(separator: "\n").compactMap { line in
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " `")) }
            guard cells.count == 3, let l = RGB(hexString: cells[1]), let d = RGB(hexString: cells[2]) else { return nil }
            return (cells[0], l, d)
        }
    }

    @Test func theValueDerivedForEachOfTheGuidesColoursIsTheOneMeasured() throws {
        let rows = try guideColours()
        #expect(rows.map(\.name) == ["orange", "teal", "green", "purple", "pink", "blue"])
        // Measured apart from the engine, by the same rule: the given hue and chroma at lightness
        // 72 for dark or 52 for light, then the nearest colour that passes.
        let dark = ["#FF9033", "#4EBABA", "#5AC672", "#C07BFF", "#FF6FBA", "#6690FF"]
        let light = ["#CF6C00", "#008A8A", "#159042", "#A25DDB", "#D54593", "#4278E4"]
        for (k, row) in rows.enumerated() {
            #expect(AppearanceTicks.derived(from: row.light, for: .dark)?.hex == dark[k], "\(row.name), dark from light")
            #expect(AppearanceTicks.derived(from: row.dark, for: .light)?.hex == light[k], "\(row.name), light from dark")
        }
    }

    @Test func tickingLightOnADarkOnlyDocumentAddsLightValuesInOnePatchAndSaysSo() throws {
        let modelProject = try DarkClock.project(try DarkClock.text())
        defer { withExtendedLifetime(modelProject) {} }
        let model = try DarkClock.model(modelProject)
        let undo = undoing(model)
        let before = try saved(model)
        model.previewAppearance = .dark
        #expect(model.setMadeFor(.light, true).isEmpty)
        let doc = try saved(model)
        #expect(doc.json["appearances"] == (try DocJSON.parse(#"["light","dark"]"#)))
        let hours = try #require(AppearanceTicks.derived(from: DarkClock.hours, for: .light))
        let minutes = try #require(AppearanceTicks.derived(from: DarkClock.minutes, for: .light))
        #expect(doc.colours["hours"] == DocumentColour(name: "hours", light: hours, dark: DarkClock.hours))
        #expect(doc.colours["minutes"] == DocumentColour(name: "minutes", light: minutes, dark: DarkClock.minutes))
        #expect(doc.json.value(at: "/colours/hours/cue") == before.json.value(at: "/colours/hours/cue"))
        #expect(model.notice == "Added light values for hours and minutes; preview Light to see them.")
        #expect(colourWarnings(model, on: "light").isEmpty, "a derived value is easy to see: \(model.selected?.findings ?? [])")
        #expect(model.appearanceStatus == nil)

        // Light is now drawn light, with the values added.
        model.previewAppearance = .light
        let player = try #require(model.player)
        player.layOut(for: CGSize(width: 600, height: 545))
        player.show(step: player.explainer.stepCount - 1)
        while case .playing = player.phase { player.advance(by: 0.5) }
        let screen = try DarkClock.screen(model, asked: .light)
        #expect(screen.has(hours) && screen.has(minutes))
        #expect(screen.count(DarkClock.palette(.light).sheet) > 10_000 && !screen.has(DarkClock.palette(.dark).sheet))

        // One step of Undo takes back the declaration and the values, and the notice with them.
        undo.undo()
        #expect(try saved(model).shortHash == before.shortHash && !undo.canUndo)
        #expect(model.notice == nil)
        undo.redo()
        #expect(model.notice != nil)
        // The notice is the shown document's.
        model.select(nil)
        #expect(model.notice == nil)
    }

    @Test func aTickNamesTheAppearanceToPreviewOnlyWhenItIsNotTheOnePreviewed() throws {
        let modelProject = try DarkClock.project(try DarkClock.text())
        defer { withExtendedLifetime(modelProject) {} }
        let model = try DarkClock.model(modelProject)
        model.previewAppearance = .light
        #expect(model.setMadeFor(.light, true).isEmpty)
        #expect(model.notice == "Added light values for hours and minutes.")
        #expect(AppearanceTicks.list(["a"]) == "a" && AppearanceTicks.list(["a", "b", "c"]) == "a, b and c")
    }

    @Test func aColourThatNamesASuggestedColourOrHasAValueIsLeftAsItIs() throws {
        let text = try DarkClock.text(hours: ##"{"suggested": "orange", "cue": "the short hand"}"##,
                                      minutes: ##"{"light": "#1B8A8A", "dark": "#49F6FF", "cue": "the long hand"}"##)
        let modelProject = try DarkClock.project(text)
        defer { withExtendedLifetime(modelProject) {} }
        let model = try DarkClock.model(modelProject)
        let before = try saved(model)
        #expect(model.setMadeFor(.light, true).isEmpty)
        #expect(try saved(model).json["colours"] == before.json["colours"])
        #expect(model.notice == nil)
    }

    @Test func theStatusLineSaysWhyAPreviewIsNotDrawnInTheAppearanceChosen() throws {
        let modelProject = try DarkClock.project(try DarkClock.text())
        defer { withExtendedLifetime(modelProject) {} }
        let model = try DarkClock.model(modelProject)
        model.previewAppearance = .light
        #expect(model.appearanceStatus == "Previewing Light; the explainer is made for dark only, so it is drawn dark.")
        model.previewAppearance = .dark
        #expect(model.appearanceStatus == nil)
        let bothProject = try DarkClock.project(try String(contentsOf: DarkClock.fixture, encoding: .utf8))
        defer { withExtendedLifetime(bothProject) {} }
        let both = try DarkClock.model(bothProject)
        both.previewAppearance = .light
        #expect(both.appearanceStatus == nil && both.madeForAppearances == [.light, .dark])
        let light = try DarkClock.model(try DarkClock.project(try DarkClock.text(
            appearances: #"["light"]"#, hours: ##"{"light": "#CF6900", "cue": "the short hand"}"##,
            minutes: ##"{"light": "#995DE1", "cue": "the long hand"}"##)))
        light.previewAppearance = .dark
        #expect(light.appearanceStatus == "Previewing Dark; the explainer is made for light only, so it is drawn light.")
    }

    private func show(_ model: StudioModel, _ more: String = "") throws -> ChalkScriptMCP.JSONValue {
        try #require(model.respond(to: Studio.Method.show, params: try params(
            #"{"doc":"\#(DarkClock.name)","step":"read","image":true\#(more)}"#), client: nil).result)
    }

    private func pixels(_ r: ChalkScriptMCP.JSONValue) throws -> Pixels {
        try #require(r["image"]?["data"]?.string.flatMap { Data(base64Encoded: $0) }.flatMap(Pixels.init(png:)))
    }

    @Test func showReturnsAPictureInTheAppearanceAskedOrTheWindowsPreview() throws {
        let both = try DarkClock.text(appearances: nil, hours: ##"{"light": "#CF6900", "dark": "#FCA200", "cue": "the short hand"}"##,
                                      minutes: ##"{"light": "#995DE1", "dark": "#C67EFF", "cue": "the long hand"}"##)
        let modelProject = try DarkClock.project(both)
        defer { withExtendedLifetime(modelProject) {} }
        let model = try DarkClock.model(modelProject)
        let light = DarkClock.palette(.light), dark = DarkClock.palette(.dark)
        // Without an appearance, the window's preview.
        for preview in Appearance.allCases {
            model.previewAppearance = preview
            let r = try show(model)
            #expect(r["appearance"]?.string == preview.rawValue && r["notMadeFor"] == nil)
            let picture = try pixels(r)
            #expect(picture.count(DarkClock.palette(preview).sheet) > 10_000)
            #expect(picture.has(RGB(hex: preview.isDark ? 0xFCA200 : 0xCF6900)))
        }
        // With one, that appearance whatever the window previews.
        model.previewAppearance = .light
        let asked = try show(model, #","appearance":"dark""#)
        #expect(asked["appearance"]?.string == "dark")
        #expect(try pixels(asked).count(dark.sheet) > 10_000 && !(try pixels(asked).has(light.sheet)))
        #expect(model.previewAppearance == .light, "the window's preview is not changed")
        let other = try show(model, #","appearance":"light""#)
        #expect(try pixels(other).count(light.sheet) > 10_000)

        for bad in [#""sepia""#, "true", "1"] {
            let reply = model.respond(to: Studio.Method.show, params: try params(
                #"{"doc":"\#(DarkClock.name)","image":true,"appearance":\#(bad)}"#), client: nil)
            #expect(reply.errorCode == Studio.RPCError.invalidParams && reply.errorMessage == "appearance must be light or dark.")
        }
    }

    @Test func showSaysWhenTheDocumentIsNotMadeForTheAppearanceAsked() throws {
        let modelProject = try DarkClock.project(try DarkClock.text())
        defer { withExtendedLifetime(modelProject) {} }
        let model = try DarkClock.model(modelProject)
        let r = try show(model, #","appearance":"light""#)
        #expect(r["appearance"]?.string == "dark" && r["notMadeFor"]?.string == "light")
        #expect(try pixels(r).count(DarkClock.palette(.dark).sheet) > 10_000)
        let made = try show(model, #","appearance":"dark""#)
        #expect(made["notMadeFor"] == nil)
    }

    @Test func aNewExplainerIsMadeForBothAppearances() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let made = try model.createDocument(title: "Reading the clock")
        #expect(made.document?.json["appearances"] == (try DocJSON.parse(#"["light","dark"]"#)))
        #expect(model.madeForAppearances == [.light, .dark])
        let keys = try #require(made.document?.json.object?.keys)
        #expect(keys.firstIndex(of: "appearances").map { $0 + 1 } == keys.firstIndex(of: "areas"))
        #expect(made.errors == 0 && made.warnings == 0)
    }
}
