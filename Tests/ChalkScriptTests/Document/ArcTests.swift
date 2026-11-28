import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import ChalkScript
import struct ChalkScript.Scene

// An entry of a shape's `points` may be an arc (EXP-19, section 9.3 of the format's reference): the
// curve of an ellipse between two angles, joined to the entries beside it by straight lines, with
// bounds round the true curve.

@MainActor
struct ArcTests {
    /// The tiny document with the shape `shape` added as `s`, and `extra` replacing other pointers.
    func document(_ shape: String, extra: [String: String] = [:]) throws -> ExplainerDocument {
        var doc = DocumentFixture.tiny.setting("/elements/s", try JSONValue.parse(shape))
        for (pointer, json) in extra { doc = doc.setting(pointer, try JSONValue.parse(json)) }
        let d = try #require(ExplainerDocument.read(doc.data).document)
        #expect(d.conforms, "\(d.findings)")
        return d
    }

    func resolver(_ d: ExplainerDocument) -> Resolver {
        Resolver(d, problem: DocumentFixture.values(("a", 1)), layout: "stage", area: nil, wording: "plain", locale: "en-US", playback: DocumentPlayback())
    }

    func near(_ a: CGRect, _ b: CGRect, _ tolerance: Double = 1e-9) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: Double = 1e-9) -> Bool { abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance }

    func path(_ d: ExplainerDocument) throws -> Path {
        let scene = try DocumentExplainer(document: d, problem: DocumentFixture.values(("a", 1))).still(after: 0)
        guard case let .shape(outline, _)? = scene.element("s")?.kind else { throw ArcFailure.notAShape }
        return StageDrawing.path(outline)
    }

    enum ArcFailure: Error { case notAShape }

    @Test func aHalfCircleHasBoundsRoundItsCurveAndItsStartAsReferencePoint() throws {
        let d = try document(#"{"kind": "shape", "ink": "text", "points": [{"arc": [0, 0, 10], "from": 0, "to": 180}]}"#)
        let r = resolver(d)
        #expect(try r.bounds(DocumentInstance("s")) == CGRect(x: 0, y: -10, width: 10, height: 20))
        let drawn = try DocumentFilm.instance(DocumentInstance("s"), r, DocumentRoles())
        #expect(drawn.reference == CGPoint(x: 0, y: -10))
        #expect(drawn.bounds == CGRect(x: 0, y: -10, width: 10, height: 20))
    }

    @Test func theBoundsIncludeTheExtremePointsAnArcPassesAndNotItsEndsOnly() throws {
        // From 45 to 135 degrees the curve reaches x = 10 at 90 and neither end does.
        let d = try document(#"{"kind": "shape", "ink": "text", "points": [{"arc": [0, 0, 10], "from": 45, "to": 135}]}"#)
        let b = try resolver(d).bounds(DocumentInstance("s"))
        #expect(abs(b.maxX - 10) < 1e-9 && abs(b.minX - 10 * 0.5.squareRoot()) < 1e-9, "\(b)")
        // A whole ellipse, drawn from nine o'clock anticlockwise.
        let e = try document(#"{"kind": "shape", "ink": "text", "points": [{"arc": [100, 50, 30, 20], "from": 270, "to": -90}]}"#)
        #expect(near(try resolver(e).bounds(DocumentInstance("s")), CGRect(x: 70, y: 30, width: 60, height: 40)))
    }

    @Test func anArcIsDrawnTheWayItsNumbersGo() throws {
        // From nine o'clock to nine o'clock, anticlockwise: a quarter of the way is six o'clock.
        let anticlockwise = try path(document(#"{"kind": "shape", "ink": "text", "points": [{"arc": [0, 0, 10], "from": 270, "to": -90}]}"#))
        let quarter = try #require(anticlockwise.trimmedPath(from: 0, to: 0.25).currentPoint)
        #expect(near(quarter, CGPoint(x: 0, y: 10), 0.05), "\(quarter)")
        let clockwise = try path(document(#"{"kind": "shape", "ink": "text", "points": [{"arc": [0, 0, 10], "from": 270, "to": 630}]}"#))
        let other = try #require(clockwise.trimmedPath(from: 0, to: 0.25).currentPoint)
        #expect(near(other, CGPoint(x: 0, y: -10), 0.05), "\(other)")
        // The curve stays on the circle between its Bézier pieces.
        for p in stride(from: 0.05, to: 1, by: 0.1) {
            let at = try #require(anticlockwise.trimmedPath(from: 0, to: p).currentPoint)
            #expect(abs(hypot(at.x, at.y) - 10) < 0.01, "\(p): \(at)")
        }
    }

    @Test func aSweepOfMoreThanThreeHundredSixtyDegreesIsAnError() throws {
        let whole = try document(#"{"kind": "shape", "ink": "text", "points": [{"arc": [0, 0, 10], "from": 0, "to": 360}]}"#)
        _ = try DocumentExplainer(document: whole, problem: DocumentFixture.values(("a", 1)))
        let more = try document(#"{"kind": "shape", "ink": "text", "points": [{"arc": [0, 0, 10], "from": 10, "to": "a + 370.5"}]}"#)
        do {
            _ = try DocumentExplainer(document: more, problem: DocumentFixture.values(("a", 1)))
            Issue.record("a sweep of 361.5 degrees was drawn")
        } catch {
            #expect(error.findings.contains { $0.code == .eval && $0.path == "/elements/s/points/0" && $0.message.contains("360") }, "\(error.findings)")
        }
        let backwards = try document(#"{"kind": "shape", "ink": "text", "points": [{"arc": [0, 0, 10], "from": 0, "to": -361}]}"#)
        #expect(throws: DocumentRefusal.self) { try DocumentExplainer(document: backwards, problem: DocumentFixture.values(("a", 1))) }
    }

    @Test func aNegativeRadiusMirrorsTheArcAndZeroFlattensIt() throws {
        let mirrored = try document(#"{"kind": "shape", "ink": "text", "points": [{"arc": [0, 0, -10, 10], "from": 0, "to": 180}]}"#)
        #expect(try resolver(mirrored).bounds(DocumentInstance("s")) == CGRect(x: -10, y: -10, width: 10, height: 20))
        let flat = try document(#"{"kind": "shape", "ink": "text", "points": [{"arc": [0, 0, 0, 10], "from": 0, "to": 180}]}"#)
        #expect(try resolver(flat).bounds(DocumentInstance("s")) == CGRect(x: 0, y: -10, width: 0, height: 20))
    }

    @Test func entriesAndPointsMakeOneOutlineJoinedByStraightLines() throws {
        // A point, then an arc, then a point: lines to the arc's start and from its end.
        let d = try document(#"{"kind": "shape", "closed": true, "fill": "text", "points": [[-20, 0], {"arc": [0, 0, 10], "from": 0, "to": 180}, [20, 0]]}"#)
        let drawn = try DocumentFilm.instance(DocumentInstance("s"), resolver(d), DocumentRoles())
        guard case let .shape(.path(segments), _, _) = drawn.shape else { Issue.record("not a path: \(drawn.shape)"); return }
        guard case let .move(first) = segments[0], case let .line(toStart) = segments[1], case let .arc(arc) = segments[2],
            case let .line(last) = segments[3], segments.last == .close
        else { Issue.record("\(segments)"); return }
        #expect(first == CGPoint(x: -20, y: 0) && toStart == CGPoint(x: 0, y: -10) && arc.end == CGPoint(x: 0, y: 10) && last == CGPoint(x: 20, y: 0))
        #expect(drawn.reference == CGPoint(x: -20, y: 0))
        #expect(drawn.bounds == CGRect(x: -20, y: -10, width: 40, height: 20))
        // A shape of points alone is drawn as lines, as it always was.
        let lines = try document(#"{"kind": "shape", "ink": "text", "points": [[0, 0], [10, 10]]}"#)
        guard case .shape(.lines, _, _) = try DocumentFilm.instance(DocumentInstance("s"), resolver(lines), DocumentRoles()).shape else {
            Issue.record("points alone are not lines")
            return
        }
    }

    @Test func anArcsValuesMayBeExpressionsOfTheElementsLocals() throws {
        let d = try document(#"""
            {"kind": "shape", "repeat": 2, "let": {"k": "i * 10"}, "ink": "text",
             "points": [{"arc": ["k", 0, "k + 5", 5], "from": "k", "to": "k + 90"}]}
            """#)
        let r = resolver(d)
        #expect(try r.bounds(DocumentInstance("s", 0)).width > 0)
        // The second instance: centre (10, 0), radii 15 and 5, from 10 to 100 degrees.
        let b = try r.bounds(DocumentInstance("s", 1))
        #expect(abs(b.maxX - 25) < 1e-9 && abs(b.minY + 5 * Evaluator.trigonometric(false, degrees: 10)) < 1e-9, "\(b)")
    }

    @Test func aTurnedOutlineWithArcsTurnsAsItsPointsDo() throws {
        // A half circle from twelve to six, turned a quarter clockwise about its centre, spans
        // from nine o'clock to three o'clock on its flat side.
        let d = try document(#"""
            {"kind": "shape", "ink": "text", "turn": 90, "pivot": [0, 0], "points": [{"arc": [0, 0, 10], "from": 0, "to": 180}]}
            """#, extra: ["/requires": #"["drawing.turn"]"#])
        #expect(near(try resolver(d).bounds(DocumentInstance("s")), CGRect(x: -10, y: 0, width: 20, height: 10)))
        // Half a turn puts the right half on the left.
        let half = try document(#"""
            {"kind": "shape", "ink": "text", "turn": 180, "pivot": [0, 0], "points": [{"arc": [0, 0, 10], "from": 0, "to": 180}]}
            """#, extra: ["/requires": #"["drawing.turn"]"#])
        #expect(near(try resolver(half).bounds(DocumentInstance("s")), CGRect(x: -10, y: -10, width: 10, height: 20)))
        // A turn of 45 degrees: the extreme points of the turned curve, not its ends.
        let eighth = try document(#"""
            {"kind": "shape", "ink": "text", "turn": 45, "pivot": [0, 0], "points": [{"arc": [0, 0, 10], "from": 0, "to": 360}]}
            """#, extra: ["/requires": #"["drawing.turn"]"#])
        #expect(near(try resolver(eighth).bounds(DocumentInstance("s")), CGRect(x: -10, y: -10, width: 20, height: 20), 1e-9))
    }

    // MARK: what the reader refuses

    @Test func anArcWithTwoNumbersOrAStrayKeyOrAMissingKeyIsASchemaError() {
        func shape(_ entry: String) -> JSONValue {
            DocumentFixture.tiny.setting("/elements/s", try! JSONValue.parse(#"{"kind": "shape", "ink": "text", "points": [\#(entry)]}"#))
        }
        has(read(shape(#"{"arc": [0, 0], "from": 0, "to": 90}"#)), .error, .schema, "/elements/s/points/0/arc", "not [cx, cy, r]")
        has(read(shape(#"{"arc": [0, 0, 5, 5, 5], "from": 0, "to": 90}"#)), .error, .schema, "/elements/s/points/0/arc")
        has(read(shape(#"{"arc": [0, 0, 5], "from": 0, "to": 90, "sweep": 90}"#)), .error, .schema, "/elements/s/points/0/sweep", "not a key of an arc")
        has(read(shape(#"{"arc": [0, 0, 5], "from": 0}"#)), .error, .schema, "/elements/s/points/0", "no 'to'")
        has(read(shape(#"{"from": 0, "to": 90}"#)), .error, .schema, "/elements/s/points/0", "no 'arc'")
        has(read(shape(#"{"arc": [0, 0, "q"], "from": 0, "to": 90}"#)), .error, .expr, "/elements/s/points/0/arc/2")
        #expect(read(shape(#"{"arc": [0, 0, 5], "from": 0, "to": 90}"#)).conforms)
        #expect(read(shape(#"{"arc": [0, 0, 5, 4], "from": 0, "to": 90}, [3, 4]"#)).conforms)
    }
}
