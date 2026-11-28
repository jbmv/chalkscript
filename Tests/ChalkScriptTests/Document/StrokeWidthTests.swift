import CoreGraphics
import Foundation
import SwiftUI
import Testing
import struct ChalkScript.Scene
@testable import ChalkScript

// The `width` of a line, arrow, outline and shape (EXP-19, section 9.3 of the format's reference):
// the stroke is drawn at that many drawing units, scaled with the drawing, and as it always was
// when the key is not given.

@MainActor
struct StrokeWidthTests {
    /// A document of the elements `elements` (a JSON object's members) and the tiny document's step.
    func document(_ elements: String) throws -> ExplainerDocument {
        var doc = DocumentFixture.tiny
        for (name, element) in try JSONValue.parse("{\(elements)}").object?.entries ?? [] { doc = doc.setting("/elements/\(name)", element) }
        let d = try #require(ExplainerDocument.read(doc.data).document)
        #expect(d.conforms, "\(d.findings)")
        return d
    }

    func scene(_ elements: String) throws -> Scene {
        try DocumentExplainer(document: document(elements), problem: DocumentFixture.values(("a", 1))).still(after: 0)
    }

    func paint(_ scene: Scene, _ id: String) throws -> Paint {
        guard case let .shape(_, paint)? = scene.element(id)?.kind else { throw WidthError.notAShape(id) }
        return paint
    }

    enum WidthError: Error { case notAShape(String) }

    @Test func aLineIsStrokedAtItsWidthWithRoundEnds() throws {
        let s = try scene(#"""
            "thin": { "kind": "line", "from": [0, 0], "to": [100, 0] },
            "thick": { "kind": "line", "from": [0, 20], "to": [100, 20], "width": 12 },
            "expr": { "kind": "line", "from": [0, 40], "to": [100, 40], "width": "a + 5" }
            """#)
        #expect(try paint(s, "thin").width == Components.pencilWidth)
        #expect(try paint(s, "thick").width == 12)
        #expect(try paint(s, "expr").width == 6)
    }

    @Test func aDividerKeepsItsDashAndTakesItsWidth() throws {
        let s = try scene(#"""
            "plain": { "kind": "line", "style": "divider", "from": [0, 0], "to": [100, 0] },
            "wide": { "kind": "line", "style": "divider", "from": [0, 20], "to": [100, 20], "width": 5 }
            """#)
        guard case .divider? = s.element("plain")?.kind else { Issue.record("a divider with no width is the component"); return }
        let wide = try paint(s, "wide")
        #expect(wide.width == 5 && wide.dash == Components.dividerDash && wide.stroke == .line)
    }

    @Test func anArrowIsStrokedAtItsWidthAndKeepsItsHeadWithNone() throws {
        let s = try scene(#"""
            "plain": { "kind": "arrow", "ink": "result", "from": [0, 0], "to": [0, 100] },
            "same": { "kind": "arrow", "ink": "result", "from": [50, 0], "to": [50, 100], "width": 2.4 },
            "thick": { "kind": "arrow", "ink": "result", "from": [100, 0], "to": [100, 100], "width": 12 }
            """#)
        #expect(s.element("plain")?.strokeWidth == nil)
        #expect(s.element("same")?.strokeWidth == 2.4)
        #expect(s.element("thick")?.strokeWidth == 12)
        guard case let .arrow(points, _, _)? = s.element("thick")?.kind else { Issue.record("not an arrow"); return }
        #expect(points == [CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
    }

    @Test func anArrowsHeadScalesWithItsWidthAboveTheDefault() {
        #expect(Components.arrowHeadScale(forWidth: Components.tradeWidth) == 1)
        #expect(Components.arrowHeadScale(forWidth: 1) == 1)
        #expect(Components.arrowHeadScale(forWidth: 12) == 5)
        #expect(Components.arrowHeadScale(forWidth: .infinity) == 1)
        let tip = CGPoint(x: 100, y: 100)
        let path = [CGPoint(x: 100, y: 0), tip]
        #expect(Components.arrowHead(endingPath: path, scale: 1) == Components.arrowHead(endingPath: path))
        // A scale of 5 gives a head 40 across each side and 50 back from the tip, the tip where it was.
        #expect(Components.arrowHead(endingPath: path, scale: 5)
            == [CGPoint(x: 60, y: 50), CGPoint(x: 100, y: 101), CGPoint(x: 140, y: 50)])
    }

    @Test func anOutlineIsStrokedAtItsWidthInEveryStyle() throws {
        let s = try scene(#"""
            "box": { "kind": "outline", "style": "box", "ink": "result", "rect": [0, 0, 50, 50], "width": 6 },
            "ring": { "kind": "outline", "style": "ring", "ink": "result", "rect": [100, 0, 50, 50], "width": 7 },
            "hint": { "kind": "outline", "style": "hint", "rect": [200, 0, 50, 50], "width": 8 },
            "target": { "kind": "outline", "style": "target", "rect": [300, 0, 50, 50], "width": 9 },
            "plainBox": { "kind": "outline", "style": "box", "ink": "result", "rect": [0, 100, 50, 50] },
            "plainTarget": { "kind": "outline", "style": "target", "rect": [300, 100, 50, 50] }
            """#)
        #expect(s.element("box")?.strokeWidth == 6)
        #expect(s.element("ring")?.strokeWidth == 7)
        #expect(s.element("hint")?.strokeWidth == 8)
        #expect(try paint(s, "target").width == 9)
        #expect(s.element("plainBox")?.strokeWidth == nil)
        #expect(try paint(s, "plainTarget").width == Components.targetWidth)
    }

    @Test func aShapeIsStrokedAtItsWidth() throws {
        let s = try scene(#"""
            "bar": { "kind": "shape", "rect": [0, 0, 50, 50], "ink": "text", "width": 10 },
            "dot": { "kind": "shape", "ellipse": [100, 0, 50, 50], "fill": "text", "ink": "text", "width": "a * 3" },
            "poly": { "kind": "shape", "points": [[0, 100], [50, 150], [100, 100]], "ink": "text" }
            """#)
        #expect(try paint(s, "bar").width == 10)
        #expect(try paint(s, "dot").width == 3)
        #expect(try paint(s, "poly").width == Components.pencilWidth)
    }

    /// The alpha of each pixel of `scene` drawn into a stage `side` points wide, at one pixel to the point.
    func alpha(_ scene: Scene, side: CGFloat) throws -> (width: Int, height: Int, at: (Int, Int) -> UInt8) {
        let renderer = ImageRenderer(content: ExplainerStage(scene: scene).frame(width: side, height: side * 0.54))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let data = try #require(image.dataProvider?.data) as Data
        let bytes = image.bitsPerPixel / 8
        return (image.width, image.height, { x, y in data[y * image.bytesPerRow + x * bytes + 3] })
    }

    @Test func aWidthIsInDrawingUnitsAndIsScaledWithTheDrawing() throws {
        let s = try scene(#"""
            "bar": { "kind": "line", "from": [100, 270], "to": [900, 270], "width": 20, "ink": "text" }
            """#)
        // The scene is 1000 by 540 units; drawn at half the size, every unit is half as large.
        func thickness(_ side: CGFloat) throws -> Int {
            let image = try alpha(s, side: side)
            return (0..<image.height).filter { image.at(image.width / 2, $0) > 127 }.count
        }
        let full = try thickness(1000)
        let half = try thickness(500)
        #expect(abs(full - 20) <= 1, "\(full) pixels across a stroke of 20 units at a scale of 1")
        #expect(abs(half - 10) <= 1, "\(half) pixels across it at half the size")
    }

    @Test func aStrokeWithAWidthHasRoundEnds() throws {
        let s = try scene(#"""
            "bar": { "kind": "line", "from": [100, 270], "to": [900, 270], "width": 20, "ink": "text" }
            """#)
        let image = try alpha(s, side: 1000)
        // Five units past the end, on the line's axis, the end's cap is still inked; at its corner it is not.
        #expect(image.at(95, 270) > 127, "a round end reaches half the width past the end")
        #expect(image.at(91, 262) <= 127, "a round end does not fill the corner a square end would")
        #expect(image.at(85, 270) <= 127)
    }

    @Test func aWidthThatIsNotPositiveIsAnError() throws {
        for kind in [
            #""kind": "line", "from": [0, 0], "to": [10, 0]"#,
            #""kind": "arrow", "ink": "result", "from": [0, 0], "to": [10, 0]"#,
            #""kind": "outline", "style": "box", "ink": "result", "rect": [0, 0, 10, 10]"#,
            #""kind": "shape", "rect": [0, 0, 10, 10], "ink": "text""#,
        ] {
            for bad in ["0", "-3", "true", #""""#, "[2]", "null"] {
                let source = DocumentFixture.tiny.setting("/elements/x", try JSONValue.parse("{\(kind), \"width\": \(bad)}"))
                let r = ExplainerDocument.read(source.data)
                #expect(!r.conforms, "width \(bad) on \(kind)")
                #expect(r.findings.contains { $0.severity == .error && $0.code == .schema && $0.path == "/elements/x/width" }, "\(bad) on \(kind): \(r.findings)")
            }
            let source = DocumentFixture.tiny.setting("/elements/x", try JSONValue.parse("{\(kind), \"width\": 0.1}"))
            #expect(ExplainerDocument.read(source.data).conforms)
        }
        // A text element has no width.
        let text = DocumentFixture.tiny.setting("/elements/label/width", .number(3))
        let r = ExplainerDocument.read(text.data)
        #expect(r.findings.contains { $0.path == "/elements/label/width" }, "\(r.findings)")
    }

    @Test func anExpressionThatIsNotPositiveIsAnErrorWhenTheDocumentIsPlayed() throws {
        let d = try document(#""x": { "kind": "line", "from": [0, 0], "to": [10, 0], "width": "a - 1" }"#)
        _ = try DocumentExplainer(document: d, problem: DocumentFixture.values(("a", 2)))
        do {
            _ = try DocumentExplainer(document: d, problem: DocumentFixture.values(("a", 1)))
            Issue.record("a width of 0 is played")
        } catch let refusal as DocumentRefusal {
            #expect(refusal.findings.contains { $0.code == .eval && $0.path == "/elements/x/width" }, "\(refusal)")
        }
    }

    @Test func bothExamplesAndTheFixturesDrawAsBefore() throws {
        // No element of either example gives a width, so each is drawn at the component's own.
        for (name, doc) in [("subtraction.explainer", DocumentFixture.subtraction), ("equal-groups.explainer", DocumentFixture.equalGroups)] {
            #expect(doc.findings.isEmpty)
            #expect(!String(decoding: DocumentFixture.data(name), as: UTF8.self).contains("\"width\""))
        }
        let e = try DocumentExplainer(document: DocumentFixture.subtraction, problem: DocumentFixture.values(("a", 54), ("b", 26)))
        for step in -1..<3 { #expect(e.still(after: step).elements.allSatisfy { $0.strokeWidth == nil }) }
    }
}
