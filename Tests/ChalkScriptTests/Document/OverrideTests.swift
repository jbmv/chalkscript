import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import ChalkScript

// An operation's colour changed in one document of the maths profile (EXP-6, section 16.7 of the
// format's reference): what the reader makes of `style.overrides`, and what a player draws.

struct OverrideReadingTests {
    static let purple = ##"{"light": "#8A4FD0", "dark": "#A569E6", "asked": "Make taking away purple."}"##

    /// The tiny document made for `profile`, with a shape drawn in `subtract`, and `subtract`
    /// overridden as `override` says.
    static func document(profile: String? = "maths", role: String = "subtract", _ override: String = purple) throws -> JSONValue {
        var d = DocumentFixture.tiny
            .setting("/requires", try JSONValue.parse(#"["components.arithmetic"]"#))
            .setting("/elements/back", try JSONValue.parse(#"{"kind": "shape", "rect": [0, 0, 1000, 540], "fill": "subtract"}"#))
            .setting("/style", try JSONValue.parse(#"{"overrides": {"\#(role)": \#(override)}}"#))
        if let profile { d = d.setting("/profile", .string(profile)) }
        return d
    }

    @Test func anOverrideWithItsRequestReadsWithAWarningThatNamesTheOperation() throws {
        let r = read(try Self.document())
        #expect(r.conforms, "\(r.findings)")
        has(r, .warning, .override, "/style/overrides/subtract", "taking away (subtract)")
        has(r, .warning, .override, "/style/overrides/subtract", "the same in every maths explainer")
        #expect(r.findings.count == 1, "\(r.findings)")
        let o = try #require(r.document?.overrides[.subtract])
        #expect(o.asked == "Make taking away purple." && o.meaning == "taking away")
        #expect(o.colour == DocumentColour(name: "subtract", light: RGB(hex: 0x8A4FD0), dark: RGB(hex: 0xA569E6)))
        #expect(r.document?.overrides.count == 1)
        // The override is part of the document, and so of its hash.
        #expect(r.document?.hash != read(try Self.document().setting("/style", nil)).document?.hash)
    }

    @Test func anOverrideWithoutItsRequestIsAnError() throws {
        let none = read(try Self.document(##"{"light": "#8A4FD0", "dark": "#A569E6"}"##))
        has(none, .error, .schema, "/style/overrides/subtract", "no 'asked'")
        #expect(!none.conforms)
        let empty = read(try Self.document(##"{"light": "#8A4FD0", "dark": "#A569E6", "asked": "  "}"##))
        has(empty, .error, .schema, "/style/overrides/subtract/asked", "empty")
        let number = read(try Self.document(##"{"light": "#8A4FD0", "dark": "#A569E6", "asked": 3}"##))
        has(number, .error, .schema, "/style/overrides/subtract/asked", "not a string")
    }

    @Test func anOverrideInTheOpenProfileIsAnErrorThatSaysItNeedsNone() throws {
        for profile in ["open", nil] {
            let r = read(try Self.document(profile: profile))
            has(r, .error, .schema, "/style/overrides", "the open profile fixes no colour, so it needs no override")
            has(r, .error, .schema, "/style/overrides", "under colours")
            #expect(!r.conforms)
            #expect(!r.findings.contains { $0.code == .override })
            #expect(r.document?.overrides.isEmpty == true)
        }
    }

    @Test func anOverrideOfWhatTheProfileDoesNotFixIsAnError() throws {
        for role in ["text", "hour", "Subtract"] {
            let r = read(try Self.document(role: role))
            has(r, .error, .schema, "/style/overrides/\(role)", "not a colour the maths profile fixes")
            has(r, .error, .schema, "/style/overrides/\(role)", "subtract, trade, result, add, multiply, divide")
        }
        has(read(try Self.document().setting("/style/overrides", .string("purple"))), .error, .schema, "/style/overrides", "not an object")
    }

    @Test func anOverrideGivesAValueForEachAppearanceTheDocumentIsMadeFor() throws {
        let lightOnly = ##"{"light": "#8A4FD0", "asked": "Make taking away purple."}"##
        has(read(try Self.document(lightOnly)), .error, .schema, "/style/overrides/subtract", "no dark value")
        let light = read(try Self.document(lightOnly).setting("/appearances", try JSONValue.parse(#"["light"]"#)))
        #expect(light.conforms, "\(light.findings)")
        #expect(light.document?.overrides[.subtract]?.colour.dark == nil)
        has(read(try Self.document(##"{"light": "purple", "dark": "#A569E6", "asked": "x"}"##)), .error, .schema, "/style/overrides/subtract/light", "#RRGGBB")
        has(read(try Self.document(##"{"asked": "x"}"##)), .error, .schema, "/style/overrides/subtract", "no light value")
    }

    @Test func anOverrideIsHeldToTheChecksOfADocumentsOwnColour() throws {
        // Too pale to see on the light sheet.
        let pale = read(try Self.document(##"{"light": "#F3E9FF", "dark": "#A569E6", "asked": "x"}"##))
        #expect(pale.conforms)
        has(pale, .warning, .colour, "/style/overrides/subtract", "very pale on the light sheet")
        // Like another colour drawn with it: the label's ink is the answer's colour.
        let result = ExplainerStyle.standard.light.colors(.result).ink.hex
        let alike = read(try Self.document(##"{"light": "\##(result)", "dark": "#A569E6", "asked": "x"}"##).setting("/elements/label/ink", .string("result")))
        has(alike, .warning, .colour, "/style/overrides/subtract", "subtract and result look alike")
        // And like the colour every maths explainer uses for another operation.
        has(alike, .warning, .colour, "/style/overrides/subtract", "every maths explainer uses for the answer")
        // An operation is not compared with the standard colour it replaces.
        let own = ExplainerStyle.standard.light.colors(.subtract).ink.hex
        let same = read(try Self.document(##"{"light": "\##(own)", "dark": "#A569E6", "asked": "x"}"##))
        #expect(!same.findings.contains { $0.code == .colour }, "\(same.findings)")
    }

    @Test func theExamplesHaveNoOverride() {
        #expect(DocumentFixture.subtraction.overrides.isEmpty && DocumentFixture.equalGroups.overrides.isEmpty)
    }
}

@MainActor
struct OverrideDrawingTests {
    @Test func aPaletteDrawsAnOverriddenOperationInOneValueWithItsSoftFormDerived() {
        let c = DocumentColour(name: "subtract", light: RGB(hex: 0x8A4FD0), dark: RGB(hex: 0xA569E6))
        for dark in [false, true] {
            let standard = ExplainerStyle.standard.palette(dark: dark)
            let p = standard.overriding([.subtract: c])
            let ink = c.drawn(dark: dark)
            #expect(p.colors(.subtract).fill == ink && p.colors(.subtract).ink == ink)
            #expect(p.colors(.subtract).soft == DocumentColour.soft(ink, over: standard.sheet, dark: dark))
            #expect(p.colors(.trade) == standard.colors(.trade) && p.sheet == standard.sheet)
            #expect(standard.overriding([:]) == standard)
        }
    }

    @Test func aPlayerDrawsTheOverridingColourInBothAppearances() throws {
        let r = read(try OverrideReadingTests.document())
        let player = try AppearancePlayerTests.player(try #require(r.document))
        #expect(player.scene.operationColours.keys.map(\.rawValue) == ["subtract"])
        let view = ExplainerView(player: player, labels: ArrangementTests.labels, arrangement: .captionBelow)
        for dark in [false, true] {
            let image = try #require(AppearancePlayerTests.render(view, asked: dark ? .dark : .light))
            #expect(AppearancePlayerTests.drawn(RGB(hex: dark ? 0xA569E6 : 0x8A4FD0), in: image), "the override, \(dark ? "dark" : "light")")
            #expect(!AppearancePlayerTests.drawn(AppearancePlayerTests.palette(dark).colors(.subtract).fill, in: image), "the standard colour")
        }
        // Without the override the same document is drawn in the standard colour.
        let plain = try AppearancePlayerTests.player(try #require(read(try OverrideReadingTests.document().setting("/style", nil)).document))
        let image = try #require(AppearancePlayerTests.render(ExplainerView(player: plain, labels: ArrangementTests.labels, arrangement: .captionBelow), asked: .light))
        #expect(AppearancePlayerTests.drawn(AppearancePlayerTests.palette(false).colors(.subtract).fill, in: image))
    }

    @Test func aCrossOutDrawnByDefaultInSubtractTakesTheOverride() throws {
        // The subtraction example draws its cross-outs in `subtract` without naming the role.
        let json = try JSONValue.parse(String(decoding: DocumentFixture.data("subtraction.explainer"), as: UTF8.self))
            .setting("/style/overrides", try JSONValue.parse(#"{"subtract": \#(OverrideReadingTests.purple)}"#))
        let r = read(json)
        #expect(r.conforms, "\(r.findings.filter { $0.severity == .error })")
        has(r, .warning, .override, "/style/overrides/subtract", "taking away")
        let doc = try #require(r.document)
        let e = try DocumentExplainer(document: doc, problem: ["a": .number(52), "b": .number(17)])
        let scenes = (0..<e.stepCount).map { e.still(after: $0) }
        #expect(scenes.allSatisfy { $0.operationColours[.subtract]?.light == RGB(hex: 0x8A4FD0) })
        for dark in [false, true] {
            let used = ExplainerStage.colours(drawing: scenes, palette: ExplainerStyle.standard.palette(dark: dark), size: CGSize(width: 700, height: 500))
            let subtract = used.filter { if case .ink(.subtract) = $0.key { true } else if case .fill(.subtract) = $0.key { true } else { false } }
            #expect(!subtract.isEmpty)
            #expect(subtract.values.allSatisfy { $0 == RGB(hex: dark ? 0xA569E6 : 0x8A4FD0) }, "\(subtract)")
        }
    }
}
