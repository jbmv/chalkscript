import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import ChalkScript
import struct ChalkScript.Scene

// A text element's bounds are the box its line of text fills as drawn (section 9.1 of the format's
// reference), so that growing and pulsing, the camera, an outline's `around` and an arrow to the
// text all take that box, and a tag is as wide as its text (section 13.10).

@MainActor
struct TextBoundsTests {
    /// The tiny document with `elements` and `actions` added, and the entries `shared`.
    func document(elements: String, actions: String = "{}", shared: String = "{}", extra: [String: String] = [:]) throws -> ExplainerDocument {
        var doc = DocumentFixture.tiny
        let entries = try JSONValue.parse(#"{"phrase": {"text": "Gigypq", "visual": true}, "one": {"text": "{a}", "visual": true}, "pair": {"text": "{big}", "visual": true}, "words": {"text": "five minutes", "visual": true}}"#)
        for (name, entry) in entries.object?.entries ?? [] { doc = doc.setting("/wording/en-US/shared/\(name)", entry) }
        for (name, element) in try JSONValue.parse("{\(elements)}").object?.entries ?? [] { doc = doc.setting("/elements/\(name)", element) }
        for (name, action) in try JSONValue.parse(actions).object?.entries ?? [] { doc = doc.setting("/steps/show/actions/\(name)", action) }
        doc = doc.setting("/let/big", .string("a * 12 + 12"))
        for (pointer, json) in extra { doc = doc.setting(pointer, try JSONValue.parse(json)) }
        let d = try #require(ExplainerDocument.read(doc.data).document)
        #expect(d.conforms, "\(d.findings)")
        return d
    }

    func explainer(_ d: ExplainerDocument) throws -> DocumentExplainer { try DocumentExplainer(document: d, problem: DocumentFixture.values(("a", 1))) }

    func resolver(_ d: ExplainerDocument) -> Resolver {
        Resolver(d, problem: DocumentFixture.values(("a", 1)), layout: "stage", area: nil, wording: "plain", locale: "en-US", playback: DocumentPlayback())
    }

    /// The size SwiftUI sets `text` in, in the faces the stage uses by default.
    func setSize(_ text: String, size: Double, display: Bool) throws -> CGSize {
        let font: Font = display ? .system(size: size, weight: .bold, design: .rounded) : .system(size: size)
        return try #require(ImageRenderer(content: Text(verbatim: text).font(font)).nsImage).size
    }

    func near(_ a: CGRect, _ b: CGRect, _ tolerance: Double = 1) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    /// The point a scale transform leaves where it is.
    func fixedPoint(_ t: CGAffineTransform) -> CGPoint { CGPoint(x: t.tx / (1 - t.a), y: t.ty / (1 - t.d)) }

    @Test func aTextsBoundsAreItsDrawnBoxForEachAnchor() throws {
        let d = try document(elements: #"""
            "head": { "kind": "text", "at": [100, 200], "anchor": "start", "size": 40, "text": "phrase" },
            "mid": { "kind": "text", "at": [300, 200], "anchor": "middle", "size": 40, "text": "phrase" },
            "tail": { "kind": "text", "at": [500, 200], "anchor": "end", "size": 40, "text": "phrase" },
            "note": { "kind": "text", "at": [300, 300], "style": "label", "text": "phrase" },
            "total": { "kind": "text", "at": [300, 400], "style": "total", "text": "phrase" },
            "sum": { "kind": "text", "at": [300, 500], "style": "equation", "text": "phrase" }
            """#)
        let r = resolver(d)
        // (element, size and face, anchor, `at`)
        let cases: [(String, (Double, Bool), String, CGPoint)] = [
            ("head", (40, true), "start", CGPoint(x: 100, y: 200)), ("mid", (40, true), "middle", CGPoint(x: 300, y: 200)),
            ("tail", (40, true), "end", CGPoint(x: 500, y: 200)), ("note", (18, false), "start", CGPoint(x: 300, y: 300)),
            ("total", (54, true), "middle", CGPoint(x: 300, y: 400)), ("sum", (44, true), "middle", CGPoint(x: 300, y: 500)),
        ]
        for (name, (size, display), anchor, at) in cases {
            let set = try setSize("Gigypq", size: size, display: display)
            let x = anchor == "start" ? at.x : anchor == "end" ? at.x - set.width : at.x - set.width / 2
            let want = CGRect(x: x, y: at.y - set.height, width: set.width, height: set.height)
            let got = try r.bounds(DocumentInstance(name))
            #expect(near(got, want), "\(name): \(got), not \(want)")
        }
        // The bounds go with the text where a verb moves it.
        let before = try r.bounds(DocumentInstance("mid"))
        r.state[DocumentInstance("mid"), default: InstanceState()].place = CGPoint(x: 350, y: 260)
        let after = try r.bounds(DocumentInstance("mid"))
        #expect(abs(after.minX - before.minX - 50) < 1e-9 && abs(after.minY - before.minY - 60) < 1e-9 && after.size == before.size)
        // A text that shows nothing before the first step has no size.
        let empty = try document(elements: #""blank": { "kind": "text", "at": [120, 80] }"#)
        #expect(try resolver(empty).bounds(DocumentInstance("blank")) == CGRect(x: 120, y: 80, width: 0, height: 0))
    }

    @Test func aGrowAndAPulseOnTextAreAboutTheMiddleOfItsBox() throws {
        let d = try document(
            elements: #"""
                "num": { "kind": "text", "at": [300, 200], "anchor": "start", "size": 60, "text": "phrase", "start": { "opacity": 0 } },
                "total": { "kind": "text", "at": [600, 400], "style": "total" }
                """#,
            actions: #"""
                { "grow": { "do": "appear", "target": "num", "grow": 0.5, "dur": 1 },
                  "set": { "do": "set", "target": "total", "text": "phrase" },
                  "pulse": { "do": "pulse", "target": "num", "at": 2, "dur": 1 },
                  "bump": { "do": "pulse", "target": "total", "at": 2, "dur": 1 } }
                """#)
        let e = try explainer(d)
        let box = try resolver(d).bounds(DocumentInstance("num"))
        let set = try setSize("Gigypq", size: 60, display: true)
        #expect(near(box, CGRect(x: 300, y: 200 - set.height, width: set.width, height: set.height)))
        let middle = CGPoint(x: box.midX, y: box.midY)
        // At the start of the grow the number is half its size, about the middle of its box.
        let growing = try #require(e.scene(step: 0, at: 0).element("num")).transform
        #expect(abs(growing.a - 0.5) < 1e-9 && abs(growing.d - 0.5) < 1e-9)
        let grown = fixedPoint(growing)
        #expect(abs(grown.x - middle.x) < 1e-6 && abs(grown.y - middle.y) < 1e-6, "grows about \(grown), not \(middle)")
        // At the peak of the pulse it is 1.15 times its size, about the same point.
        let peak = try #require(e.scene(step: 0, at: 2.5).element("num")).transform
        #expect(abs(peak.a - 1.15) < 1e-9)
        let pulsed = fixedPoint(peak)
        #expect(abs(pulsed.x - middle.x) < 1e-6 && abs(pulsed.y - middle.y) < 1e-6, "pulses about \(pulsed), not \(middle)")
        // A total shows the text a verb set, and pulses about the middle of that text.
        let total = try #require(e.scene(step: 0, at: 2.5).element("total"))
        guard case let .total(shown, at, scale) = total.kind else { Issue.record("not a total"); return }
        #expect(shown == "Gigypq" && scale == 1 && at == CGPoint(x: 600, y: 400))
        let bump = fixedPoint(total.transform)
        let height = try setSize("Gigypq", size: Components.totalSize, display: true).height
        #expect(abs(total.transform.a - 1.15) < 1e-9 && abs(bump.x - 600) < 1e-6 && abs(bump.y - (400 - height / 2)) < 1, "pulses about \(bump)")
        // It is drawn at its own size when nothing grows it.
        #expect(try #require(e.still(after: 0).element("total")).transform == .identity)
    }

    @Test func aShotThatNamesTextFramesItsBox() throws {
        let d = try document(
            elements: #"""
                "num": { "kind": "text", "at": [500, 300], "anchor": "start", "size": 60, "text": "phrase" },
                "far": { "kind": "shape", "rect": [0, 0, 1000, 20], "fill": "muted" }
                """#,
            extra: [
                "/layouts": #"{"stage": {"size": [1000, 540], "camera": true}}"#,
                "/parts": #"{"word": "num"}"#,
                "/shots": #"{"on": {"frame": ["word"], "margin": 0}}"#,
            ])
        let r = resolver(d)
        let box = try r.bounds(DocumentInstance("num"))
        #expect(box.width > 100 && box.height > 40)
        #expect(try #require(try r.region(ofPart: "word")) == box)
        let frame = try CameraFraming(r, size: CGSize(width: 1000, height: 540)).frame("on")
        #expect(frame.region == box, "the shot's region is \(String(describing: frame.region)), not \(box)")
        #expect(frame.view.contains(box))
    }

    @Test func anArrowToTextEndsAboveItsBox() throws {
        let d = try document(elements: #"""
            "num": { "kind": "text", "at": [500, 300], "anchor": "start", "size": 60, "text": "phrase" },
            "pointer": { "kind": "arrow", "ink": "result", "from": [100, 100], "to": "num" }
            """#)
        let box = try resolver(d).bounds(DocumentInstance("num"))
        guard case let .arrow(points, _, _)? = try explainer(d).still(after: -1).element("pointer")?.kind, let end = points.last else {
            Issue.record("no arrow")
            return
        }
        #expect(abs(end.x - box.midX) < 1e-9 && abs(end.y - (box.minY - 8)) < 1e-9, "ends at \(end), above \(box)")
        #expect(end.x > 500 + 20, "the middle of the text, not its anchor")
    }

    @Test func aTagIsAsWideAsItsTextAndNeverNarrowerThanItWas() throws {
        func card(_ entry: String) throws -> CGRect {
            let d = try document(
                elements: #""num": { "kind": "text", "at": [500, 300], "text": "one" }"#,
                actions: "{\"mark\": {\"do\": \"tag\", \"target\": \"num\", \"text\": \"\(entry)\", \"dur\": 1}}")
            guard case let .numberTag(_, rect, scale)? = try explainer(d).scene(step: 0, at: 0.5).element("num.tag")?.kind, scale == 1 else {
                throw TagError.none
            }
            return rect
        }
        let one = try card("one")
        #expect(one.width == Components.oneTagSize.width && one.height == Components.oneTagSize.height, "\(one)")
        // Two digits fill the card: it is as wide as the digits plus 12.
        let pair = try card("pair")
        let digits = try setSize("24", size: Components.tagTextSize, display: true).width
        #expect(abs(pair.width - (digits + 12)) < 2 && pair.width > Components.oneTagSize.width, "\(pair)")
        // Two words are enclosed, with about 6 units to each side (SwiftUI's size is a whole number of points).
        let words = try card("words")
        let text = try setSize("five minutes", size: Components.tagTextSize, display: true).width
        #expect(abs(words.width - (text + 12)) < 2 && words.width > 120, "\(words), text \(text)")
        #expect(abs(words.midX - one.midX) < 1e-9 && abs(words.midY - one.midY) < 1e-9, "a wider card is centred where the narrow one was")
    }

    enum TagError: Error { case none }
}
