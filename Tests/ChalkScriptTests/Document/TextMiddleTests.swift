import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript

// A text element may be placed by the vertical middle of its box as well as by its baseline
// (`vanchor`, section 9.2 of the format's reference), with each anchor across.

@MainActor
struct TextMiddleTests {
    let base = TextBoundsTests()

    static let anchors = ["start", "middle", "end"]

    /// The line's box as the stage sets it, from what the scene draws: its lower edge, and its height.
    func drawn(_ name: String, in d: ExplainerDocument) throws -> CGPoint {
        let e = try base.explainer(d)
        let el = try #require(e.still(after: -1).element(name))
        switch el.kind {
        case let .words(_, set): return set.at
        case let .label(_, at): return at
        case let .total(_, at, _): return at
        case let .equation(line): return line.center
        default: Issue.record("\(name) is not text"); return CGPoint.zero
        }
    }

    @Test(arguments: ["start", "middle", "end"])
    func aTextPlacedByItsMiddleHasThatPointAsTheMiddleOfItsBoundsWhateverItsAnchor(anchor: String) throws {
        let d = try base.document(elements: #"""
            "base": { "kind": "text", "at": [300, 200], "anchor": "\#(anchor)", "size": 40, "text": "phrase" },
            "same": { "kind": "text", "at": [300, 200], "anchor": "\#(anchor)", "vanchor": "baseline", "size": 40, "text": "phrase" },
            "mid": { "kind": "text", "at": [300, 200], "anchor": "\#(anchor)", "vanchor": "middle", "size": 40, "text": "phrase" }
            """#)
        let r = base.resolver(d)
        let below = try r.bounds(DocumentInstance("base"))
        // The baseline is the default, so that a document with no `vanchor` is drawn as before.
        #expect(try r.bounds(DocumentInstance("same")) == below)
        #expect(below.maxY == 200)
        let middle = try r.bounds(DocumentInstance("mid"))
        #expect(middle.midY == 200 && middle.size == below.size && middle.minX == below.minX)
        let baseAt = try drawn("base", in: d)
        let midAt = try drawn("mid", in: d)
        // The stage sets a line with its lower edge at the point, so the line is set half its height lower.
        #expect(baseAt == CGPoint(x: 300, y: 200))
        #expect(midAt.x == 300 && abs(midAt.y - (200 + below.height / 2)) < 1e-9, "\(midAt)")
        #expect(abs((midAt.y - below.height) - middle.minY) < 1e-9, "the drawn box is the bounds")
    }

    @Test(arguments: ["start", "middle", "end"])
    func everyStyleTakesTheVerticalMiddleWithTheAnchorsItAllows(anchor: String) throws {
        // `equation` and `total` are centred, so they are tried with that anchor only.
        let styles = anchor == "middle" ? ["body", "note", "label", "total", "equation"] : ["body", "note", "label"]
        for style in styles {
            let ink = style == "label" ? "muted" : style == "total" ? "result" : "text"
            let d = try base.document(elements: #"""
                "base": { "kind": "text", "at": [300, 200], "style": "\#(style)", "anchor": "\#(anchor)", "ink": "\#(ink)", "text": "phrase" },
                "mid": { "kind": "text", "at": [300, 200], "style": "\#(style)", "anchor": "\#(anchor)", "ink": "\#(ink)", "vanchor": "middle", "text": "phrase" }
                """#)
            let r = base.resolver(d)
            let box = try r.bounds(DocumentInstance("base"))
            let middle = try r.bounds(DocumentInstance("mid"))
            #expect(abs(middle.midY - 200) < 1e-9 && abs(box.maxY - 200) < 1e-9, "\(style) \(anchor)")
            let baseAt = try drawn("base", in: d)
            let midAt = try drawn("mid", in: d)
            #expect(baseAt.x == midAt.x && abs(midAt.y - baseAt.y - box.height / 2) < 1e-9, "\(style) \(anchor): \(midAt), \(baseAt)")
        }
    }

    @Test func aTextGrowsAndPulsesAboutTheMiddleOfItsBoxWherePlacedByItsMiddle() throws {
        let d = try base.document(
            elements: #""num": { "kind": "text", "at": [300, 200], "vanchor": "middle", "anchor": "start", "size": 60, "text": "phrase", "start": { "opacity": 0 } }"#,
            actions: #"{ "grow": { "do": "appear", "target": "num", "grow": 0.5, "dur": 1 } }"#)
        let box = try base.resolver(d).bounds(DocumentInstance("num"))
        let growing = try #require(base.explainer(d).scene(step: 0, at: 0).element("num")).transform
        let fixed = base.fixedPoint(growing)
        #expect(abs(fixed.x - box.midX) < 1e-6 && abs(fixed.y - 200) < 1e-6, "grows about \(fixed), and the middle is \(box.midX), 200")
    }

    @Test func aVerticalAnchorOtherThanBaselineOrMiddleIsASchemaError() throws {
        var doc = DocumentFixture.tiny
        doc = doc.setting("/elements/word", try JSONValue.parse(#"{"kind": "text", "at": [10, 10], "vanchor": "top"}"#))
        let r = read(doc)
        has(r, .error, .schema, "/elements/word/vanchor", "vanchor 'top' is not one of baseline, middle")
        let ok = read(doc.setting("/elements/word/vanchor", .string("middle")))
        #expect(ok.conforms, "\(ok.findings)")
    }
}
