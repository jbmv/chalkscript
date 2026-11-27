import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import ChalkScript

// The appearances a document is made for (EXP-20, section 16.6 of the format's reference): what
// the reader makes of the declaration and of colours that give one value, and what a player draws
// when asked for an appearance the document is not made for.

struct AppearanceDeclarationTests {
    static let hour = ##""hour": {"light": "#B5481F", "dark": "#F59623", "cue": "the short hand"}"##
    static let minute = ##""minute": {"light": "#8A4FD0", "dark": "#A569E6", "cue": "the long hand"}"##

    /// The tiny document, its label and rule drawn in the colours `hour` and `minute`, with
    /// `colours` and `appearances` as given.
    func document(_ appearances: String?, colours: String) throws -> JSONValue {
        var d = DocumentFixture.tiny
            .setting("/colours", try JSONValue.parse(colours))
            .setting("/elements/label/ink", .string("hour")).setting("/elements/rule/ink", .string("minute"))
        if let appearances { d = d.setting("/appearances", try JSONValue.parse(appearances)) }
        return d
    }

    func colours(_ hour: String, _ minute: String) -> String { "{\(hour), \(minute)}" }

    func warnings(_ r: DocumentReading) -> [DocumentFinding] { r.findings.filter { $0.code == .colour } }

    @Test func aDocumentThatDeclaresNoAppearancesIsMadeForBoth() throws {
        let none = try #require(read(DocumentFixture.tiny).document)
        #expect(none.appearances == [.light, .dark] && none.findings.isEmpty)
        let both = try #require(read(DocumentFixture.tiny.setting("/appearances", try JSONValue.parse(#"["dark", "light"]"#))).document)
        #expect(both.appearances == [.light, .dark] && both.findings.isEmpty)
        let dark = try #require(read(DocumentFixture.tiny.setting("/appearances", try JSONValue.parse(#"["dark"]"#))).document)
        #expect(dark.appearances == [.dark] && dark.conforms)
        let light = try #require(read(DocumentFixture.tiny.setting("/appearances", try JSONValue.parse(#"["light"]"#))).document)
        #expect(light.appearances == [.light] && light.conforms)
        // The examples declare nothing, and are made for both.
        #expect(DocumentFixture.subtraction.appearances == [.light, .dark] && DocumentFixture.equalGroups.appearances == [.light, .dark])
    }

    @Test func aValueOutsideLightAndDarkIsASchemaError() throws {
        for (text, path) in [
            (#"["sepia"]"#, "/appearances/0"), (#"[]"#, "/appearances"), (#"["dark", "dark"]"#, "/appearances/1"),
            (#""dark""#, "/appearances"), (#"[1]"#, "/appearances/0"), (#"["dark", "Dark"]"#, "/appearances/1"),
        ] {
            let r = read(DocumentFixture.tiny.setting("/appearances", try JSONValue.parse(text)))
            has(r, .error, .schema, path)
            #expect(!r.conforms, "\(text)")
        }
        has(read(DocumentFixture.tiny.setting("/appearances", try JSONValue.parse(#"["sepia"]"#))), .error, .schema, "/appearances/0", "'sepia'")
        // An unsound declaration is read as both, so that the other checks still run.
        let doc = try #require(read(DocumentFixture.tiny.setting("/appearances", try JSONValue.parse(#"["sepia"]"#))).document)
        #expect(doc.appearances == [.light, .dark])
    }

    @Test func aColourWithOnlyADarkValueInADarkOnlyDocumentHasNoFinding() throws {
        let c = colours(##""hour": {"dark": "#F59623", "cue": "the short hand"}"##, ##""minute": {"dark": "#A569E6", "cue": "the long hand"}"##)
        let r = read(try document(#"["dark"]"#, colours: c))
        #expect(r.conforms && r.findings.isEmpty, "\(r.findings)")
        let doc = try #require(r.document)
        #expect(doc.colours["hour"] == DocumentColour(name: "hour", light: nil, dark: RGB(hex: 0xF59623)))
        // No player takes the missing light value from the dark one.
        #expect(doc.colours["hour"]?.value(dark: false) == nil)
        // The same colours in a document made for both are an error each.
        let both = read(try document(nil, colours: c))
        has(both, .error, .schema, "/colours/hour", "no light value")
        has(both, .error, .schema, "/colours/minute", "no light value")
    }

    @Test func aDocumentMadeForOneAppearanceWhoseColourLacksItsValueIsASchemaError() throws {
        let dark = read(try document(#"["dark"]"#, colours: colours(##""hour": {"light": "#B5481F", "cue": "x"}"##, Self.minute)))
        has(dark, .error, .schema, "/colours/hour", "no dark value")
        has(dark, .error, .schema, "/colours/hour", "made for dark")
        #expect(!dark.conforms)
        let light = read(try document(#"["light"]"#, colours: colours(##""hour": {"dark": "#F59623", "cue": "x"}"##, Self.minute)))
        has(light, .error, .schema, "/colours/hour", "no light value")
        #expect(!light.conforms)
        // A colour that gives neither names no value for any appearance.
        has(read(try document(#"["dark"]"#, colours: colours(##""hour": {"cue": "x"}"##, Self.minute))), .error, .schema, "/colours/hour")
        // A value that is given for an appearance not made for is still a colour.
        has(read(try document(#"["dark"]"#, colours: colours(##""hour": {"light": "red", "dark": "#F59623", "cue": "x"}"##, Self.minute))),
            .error, .schema, "/colours/hour/light", "#RRGGBB")
    }

    @Test func aSuggestedColourIsGivenInBothAppearancesWhateverTheDocumentIsMadeFor() throws {
        let r = read(try document(#"["dark"]"#, colours: colours(##""hour": {"suggested": "orange", "cue": "x"}"##, ##""minute": {"suggested": "purple", "cue": "y"}"##)))
        #expect(r.conforms && r.findings.isEmpty, "\(r.findings)")
        let c = try #require(r.document?.colours["hour"])
        #expect(c.light != nil && c.dark != nil)
    }

    @Test func theColourChecksRunOnlyInTheAppearancesTheDocumentIsMadeFor() throws {
        // The bright values of a clock, which are very pale on the light sheet.
        let bright = colours(##""hour": {"light": "#FF924A", "dark": "#FF924A", "cue": "the short hand"}"##, ##""minute": {"light": "#49F6FF", "dark": "#49F6FF", "cue": "the long hand"}"##)
        let both = warnings(read(try document(nil, colours: bright)))
        #expect(both.contains { $0.message.contains("light sheet") }, "\(both)")
        let dark = read(try document(#"["dark"]"#, colours: bright))
        #expect(dark.conforms)
        #expect(!warnings(dark).contains { $0.message.contains("light sheet") }, "\(warnings(dark))")
        let light = read(try document(#"["light"]"#, colours: bright))
        #expect(!warnings(light).contains { $0.message.contains("dark sheet") }, "\(warnings(light))")
        #expect(warnings(light).contains { $0.message.contains("light sheet") })
        // Every warning of a document made for both that is about the dark sheet is still there
        // when it is made for dark alone, and none of the light sheet's is.
        let darkOnly = both.filter { !$0.message.contains("light") }
        #expect(warnings(dark).count == darkOnly.count, "\(warnings(dark)) against \(darkOnly)")
    }

    @Test func aValueForAnAppearanceTheDocumentIsNotMadeForIsKeptAndNotChecked() throws {
        // #49F6FF is very pale on the light sheet, and the document is made for dark.
        let kept = colours(##""hour": {"light": "#49F6FF", "dark": "#F59623", "cue": "x"}"##, Self.minute)
        let dark = read(try document(#"["dark"]"#, colours: kept))
        #expect(dark.conforms && dark.findings.isEmpty, "\(dark.findings)")
        #expect(dark.document?.colours["hour"]?.light == RGB(hex: 0x49F6FF))
        #expect(warnings(read(try document(nil, colours: kept))).contains { $0.message.contains("hour") && $0.message.contains("light sheet") })
        // Two colours that look alike only in light are not compared in a document made for dark.
        let alike = colours(##""hour": {"light": "#B5481F", "dark": "#F59623", "cue": "x"}"##, ##""minute": {"light": "#B8491F", "dark": "#A569E6", "cue": "y"}"##)
        let alikeInBoth = read(try document(nil, colours: alike))
        #expect(warnings(alikeInBoth).contains { $0.message.contains("hour and minute") && $0.message.contains("in light") }, "\(alikeInBoth.findings)")
        #expect(warnings(read(try document(#"["dark"]"#, colours: alike))).isEmpty)
    }
}

// MARK: what a player draws

@MainActor
struct AppearancePlayerTests {
    static let own = RGB(hex: 0xF59623)

    /// The tiny document with a shape filling its stage in a colour of its own that gives only a
    /// dark value, and made for dark alone, or for what `appearances` says.
    static func document(_ appearances: String = #"["dark"]"#, light: Bool = false) throws -> ExplainerDocument {
        let values = light ? ##"{"light": "#B5481F", "dark": "#F59623", "cue": "the sheet"}"## : ##"{"dark": "#F59623", "cue": "the sheet"}"##
        let json = DocumentFixture.tiny
            .setting("/requires", try JSONValue.parse(#"["components.arithmetic"]"#))
            .setting("/appearances", try JSONValue.parse(appearances))
            .setting("/colours", try JSONValue.parse(#"{"own": \#(values)}"#))
            .setting("/elements/back", try JSONValue.parse(#"{"kind": "shape", "rect": [0, 0, 1000, 540], "fill": "own"}"#))
        let r = read(json)
        #expect(r.conforms, "\(r.findings)")
        return try #require(r.document)
    }

    static func player(_ document: ExplainerDocument) throws -> ExplainerPlayer {
        let e = try DocumentExplainer(document: document, problem: ["a": .number(1)])
        return ExplainerPlayer(explainer: e, voice: RecordingVoice(), drivesItself: false)
    }

    /// Draws `view` as the host's `scheme` asks, at one pixel per point.
    static func render(_ view: some View, asked scheme: ColorScheme) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: 700, height: 1000).environment(\.colorScheme, scheme))
        renderer.scale = 1
        return renderer.cgImage
    }

    static func palette(_ dark: Bool) -> ExplainerPalette { ExplainerStyle.standard.palette(dark: dark) }

    /// Whether `colour` is drawn in `image`.
    static func drawn(_ colour: RGB, in image: CGImage) -> Bool { ArrangementTests.bounds(of: colour, in: image) != nil }

    @Test func theAppearanceUsedIsTheOneAskedForWhenTheDocumentIsMadeForItAndOtherwiseTheOneItIsMadeFor() {
        #expect(Appearance.use(asked: .light, madeFor: [.dark]) == AppearanceUse(asked: .light, used: .dark))
        #expect(Appearance.use(asked: .dark, madeFor: [.light]) == AppearanceUse(asked: .dark, used: .light))
        #expect(Appearance.use(asked: .dark, madeFor: [.dark]).differs == false)
        for asked in Appearance.allCases {
            #expect(Appearance.use(asked: asked, madeFor: Appearance.both) == AppearanceUse(asked: asked, used: asked))
        }
        #expect(Appearance.use(asked: .light, madeFor: [.dark]).differs)
    }

    @Test func aPlayerAskedForLightDrawsADarkOnlyDocumentDarkWithItsCaptionAndControls() throws {
        let player = try Self.player(Self.document())
        #expect(player.appearances == [.dark])
        let view = ExplainerView(player: player, labels: ArrangementTests.labels, arrangement: .captionBelow)
        let dark = Self.palette(true), light = Self.palette(false)
        // The same picture whichever is asked for.
        let asked = try #require(Self.render(view, asked: .light))
        let darkAsked = try #require(Self.render(view, asked: .dark))
        for image in [asked, darkAsked] {
            // The drawing, in the colour the document gives for dark.
            #expect(Self.drawn(Self.own, in: image))
            // The sheet and its frame, the progress dots and the large control, in dark.
            #expect(Self.drawn(dark.sheet, in: image), "the sheet")
            #expect(Self.drawn(dark.line, in: image), "the frame")
            #expect(Self.drawn(dark.ink, in: image), "the dots")
            #expect(Self.drawn(dark.colors(.result).fill, in: image), "the control")
            // And nothing of the light palette's.
            #expect(!Self.drawn(light.sheet, in: image), "light sheet")
            #expect(!Self.drawn(light.line, in: image), "light frame")
            #expect(!Self.drawn(light.colors(.result).fill, in: image), "light control")
        }
    }

    @Test func aDocumentMadeForBothIsDrawnInTheAppearanceAsked() throws {
        let player = try Self.player(Self.document(#"["light", "dark"]"#, light: true))
        let view = ExplainerView(player: player, labels: ArrangementTests.labels, arrangement: .captionBelow)
        for dark in [false, true] {
            let image = try #require(Self.render(view, asked: dark ? .dark : .light))
            #expect(Self.drawn(Self.palette(dark).line, in: image))
            #expect(!Self.drawn(Self.palette(!dark).line, in: image))
        }
    }

    @Test func aPlayerTellsItsHostTheAppearanceItUsed() throws {
        let player = try Self.player(Self.document())
        var told: [AppearanceUse] = []
        let view = ExplainerView(player: player, labels: ArrangementTests.labels, arrangement: .captionBelow) { told.append($0) }
        _ = Self.render(view, asked: .light)
        #expect(told.last == AppearanceUse(asked: .light, used: .dark) && told.last?.differs == true, "\(told)")
        _ = Self.render(view, asked: .dark)
        #expect(told.last == AppearanceUse(asked: .dark, used: .dark) && told.last?.differs == false, "\(told)")
    }

    @Test func aDocumentMadeForLightIsDrawnLightWhenDarkIsAsked() throws {
        let values = ##"{"light": "#B5481F", "cue": "the sheet"}"##
        let json = DocumentFixture.tiny
            .setting("/requires", try JSONValue.parse(#"["components.arithmetic"]"#))
            .setting("/appearances", try JSONValue.parse(#"["light"]"#))
            .setting("/colours", try JSONValue.parse(#"{"own": \#(values)}"#))
            .setting("/elements/back", try JSONValue.parse(#"{"kind": "shape", "rect": [0, 0, 1000, 540], "fill": "own"}"#))
        let document = try #require(read(json).document)
        #expect(document.conforms)
        let player = try Self.player(document)
        let image = try #require(Self.render(ExplainerView(player: player, labels: ArrangementTests.labels, arrangement: .captionBelow), asked: .dark))
        #expect(Self.drawn(RGB(hex: 0xB5481F), in: image) && Self.drawn(Self.palette(false).line, in: image))
        #expect(!Self.drawn(Self.palette(true).line, in: image))
    }
}

// MARK: chalkscript-render

struct AppearanceRenderTests {
    /// The `chalkscript-render` built beside the test bundle, which `swift test` builds with the
    /// package, if it is there.
    static var tool: URL? {
        let bundle = ProcessInfo.processInfo.arguments.first { $0.contains(".xctest/") }
            .flatMap { path in path.range(of: ".xctest/").map { URL(fileURLWithPath: String(path[..<$0.lowerBound]) + ".xctest") } }
        let url = bundle?.deletingLastPathComponent().appendingPathComponent("chalkscript-render")
        return url.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }

    /// Runs the tool on `document`, writing pictures into `directory`, and returns what it printed
    /// to standard error.
    static func render(_ document: URL, into directory: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = try #require(tool, "chalkscript-render is not built")
        process.arguments = [document.path, directory.path, "a=1"] + arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let text = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return String(decoding: text, as: UTF8.self)
    }

    @Test func renderAskedForLightDrawsADarkOnlyDocumentDarkAndSaysSo() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("appearances-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let json = DocumentFixture.tiny
            .setting("/requires", try JSONValue.parse(#"["components.arithmetic"]"#))
            .setting("/appearances", try JSONValue.parse(#"["dark"]"#))
            .setting("/colours", try JSONValue.parse(##"{"own": {"dark": "#F59623", "cue": "the sheet"}}"##))
            .setting("/elements/back", try JSONValue.parse(#"{"kind": "shape", "rect": [0, 0, 1000, 540], "fill": "own"}"#))
        let document = work.appendingPathComponent("dark-only.explainer")
        try json.data.write(to: document)

        let asked = try Self.render(document, into: work.appendingPathComponent("light-asked"), arguments: [])
        #expect(asked.contains("note: asked for light, but the document is made for dark only, so it is drawn dark"), "\(asked)")
        let darkAsked = try Self.render(document, into: work.appendingPathComponent("dark-asked"), arguments: ["--dark"])
        #expect(!darkAsked.contains("note: asked for"), "\(darkAsked)")

        // The pictures are the same: the dark one, with its line under it.
        let names = try FileManager.default.contentsOfDirectory(atPath: work.appendingPathComponent("light-asked").path).sorted()
        #expect(!names.isEmpty)
        for name in names {
            let a = try Data(contentsOf: work.appendingPathComponent("light-asked").appendingPathComponent(name))
            let b = try Data(contentsOf: work.appendingPathComponent("dark-asked").appendingPathComponent(name))
            #expect(a == b, "\(name)")
        }
    }
}
