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
