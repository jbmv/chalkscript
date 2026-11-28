import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript

// A shot's `up` (sections 10.1, 10.3 and 10.4 of the format's reference, EXP-18): the direction in
// the drawing shown at the top of the picture, in degrees clockwise from twelve. The camera turns
// the shorter way, text stays level about its `at`, and framing and dimming are measured in the
// turned picture's frame.

struct TurnedShotTests {
    /// A dot at (300, 200), another 100 to its right, a word under the dot, and two far corners
    /// that make the drawing's extent much larger than any shot here.
    static let source = #"""
        {
          "format": "chalkscript-explainer", "version": "1.0", "id": "turned", "title": "Turned", "sourceLocale": "en-US",
          "params": { "a": { "type": "int", "min": 1, "max": 1 } }, "samples": [{ "a": 1 }],
          "layouts": { "stage": { "size": [600, 400], "camera": true } },
          "elements": {
            "dot": { "kind": "shape", "ellipse": [290, 190, 20, 20], "fill": "text" },
            "right": { "kind": "shape", "ellipse": [390, 190, 20, 20], "fill": "text" },
            "word": { "kind": "text", "at": [300, 260], "anchor": "middle", "text": "word" },
            "near": { "kind": "shape", "rect": [-400, -400, 10, 10], "fill": "text" },
            "far": { "kind": "shape", "rect": [1000, 800, 10, 10], "fill": "text" }
          },
          "parts": { "dot": "dot" },
          "shots": {
            "level": { "frame": ["dot"], "margin": 40 },
            "full": { "frame": ["dot"], "margin": 40, "up": 360 },
            "quarter": { "frame": ["dot"], "margin": 40, "up": 90 },
            "late": { "frame": ["dot"], "margin": 40, "up": 350 },
            "early": { "frame": ["dot"], "margin": 40, "up": 10 },
            "half": { "frame": ["dot"], "margin": 40, "up": 180 },
            "tilted": { "region": [290, 190, 20, 20], "margin": 0, "up": 45 }
          },
          "sequence": ["s0", "s1", "s2", "s3", "s4", "s5", "s6"],
          "steps": {
            "s0": { "say": "line", "shot": "level" },
            "s1": { "say": "line", "shot": "late" },
            "s2": { "say": "line", "shot": "early" },
            "s3": { "say": "line", "shot": "level" },
            "s4": { "say": "line", "shot": "half" },
            "s5": { "say": "line", "shot": "quarter" },
            "s6": { "say": "line", "shot": "tilted" }
          },
          "wording": { "en-US": { "shared": { "word": { "text": "Moon", "visual": true } }, "plain": { "line": "Look." } } }
        }
        """#

    func document(_ source: String = Self.source) throws -> ExplainerDocument {
        let r = ExplainerDocument.read(Data(source.utf8))
        let d = try #require(r.document)
        #expect(r.conforms, "\(r.findings)")
        return d
    }

    func explainer(_ source: String = Self.source) throws -> DocumentExplainer {
        try DocumentExplainer(document: try document(source), problem: DocumentFixture.values(("a", 1)))
    }

    func camera(_ e: DocumentExplainer, _ shot: String) throws -> Camera { try #require(e.film.camera(shot)) }

    func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 1e-6) -> Bool { abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance }

    /// `a` and `b` are the same direction, whole turns apart.
    func same(_ a: Double, _ b: Double) -> Bool {
        let d = (a - b).truncatingRemainder(dividingBy: 360)
        return min(abs(d), 360 - abs(d)) < 1e-9
    }

    @Test func aShotWithUp90ShowsAPointToTheRightOfTheRegionsMiddleAtTheTop() throws {
        let e = try explainer()
        let c = try camera(e, "quarter")
        #expect(c.up == 90)
        let middle = CGPoint(x: 300, y: 200).applying(c.transform)
        let right = CGPoint(x: 400, y: 200).applying(c.transform)
        #expect(abs(right.x - middle.x) < 1e-9 && right.y < middle.y, "the point to the right is drawn straight above: \(middle), \(right)")
        // The region's middle is the picture's, since the drawing's extent leaves room all round.
        #expect(near(middle, CGPoint(x: c.viewport.midX, y: c.viewport.midY)))
        // A point below the middle is drawn to its right, and the scale is the unturned shot's.
        let below = CGPoint(x: 300, y: 300).applying(c.transform)
        #expect(abs(below.y - middle.y) < 1e-9 && below.x > middle.x)
        let level = try camera(e, "level")
        #expect(abs(c.scale - level.scale) < 1e-9)
        // Unturned, the point to the right is drawn to the right.
        let unturned = CGPoint(x: 400, y: 200).applying(level.transform)
        #expect(unturned.x > CGPoint(x: 300, y: 200).applying(level.transform).x)
    }

    @Test func aDocumentWithoutUpFramesAsBeforeAndAWholeTurnIsNoTurn() throws {
        let e = try explainer()
        let level = try camera(e, "level")
        #expect(level.up == 0)
        #expect(try camera(e, "full").view == level.view && camera(e, "full").up == 0, "360 shows twelve at the top")
        // The unturned transform is a scale and a move only.
        #expect(level.transform.b == 0 && level.transform.c == 0)
        // Removing the turned shots changes nothing about the others.
        var plain = try JSONValue.parse(Self.source)
        for shot in ["full", "quarter", "late", "early", "half", "tilted"] { plain = plain.setting("/shots/" + shot, nil) }
        plain = plain.setting("/sequence", try JSONValue.parse(#"["s0"]"#))
        for step in ["s1", "s2", "s3", "s4", "s5", "s6"] { plain = plain.setting("/steps/" + step, nil) }
        let d = try #require(ExplainerDocument.read(plain.data).document)
        let p = try DocumentExplainer(document: d, problem: DocumentFixture.values(("a", 1)))
        #expect(try camera(p, "level") == level)
    }

    @Test func aMoveFrom350To10TurnsTwentyDegreesClockwiseAndHalfATurnIsClockwise() throws {
        #expect(Camera.turn(from: 350, to: 10) == 20)
        #expect(Camera.turn(from: 10, to: 350) == -20)
        #expect(Camera.turn(from: 0, to: 180) == 180 && Camera.turn(from: 180, to: 0) == 180, "clockwise at exactly half a turn")
        #expect(Camera.turn(from: 0, to: 0) == 0 && Camera.turn(from: 90, to: 450) == 0)

        let e = try explainer()
        // Step s2 moves from late (350) to early (10).
        let lead = e.resolved.steps[2].lead
        #expect(lead > 0, "a shot that differs only in its angle moves the camera")
        // How far it has turned clockwise from 350, at each twentieth of the move.
        var last = 0.0
        for k in 0...20 {
            let up = try #require(e.camera(2, at: lead * Double(k) / 20)).up
            var turned = (up - 350).truncatingRemainder(dividingBy: 360)
            if turned < 0 { turned += 360 }
            #expect(turned >= last - 1e-9 && turned <= 20 + 1e-9, "at \(k) of 20 the camera shows \(up) at the top")
            last = turned
        }
        #expect(abs(last - 20) < 1e-9)
        let a = try camera(e, "late")
        let b = try camera(e, "early")
        #expect(same(Camera.between(a, b, 0.5).up, 0) && same(Camera.between(a, b, 0.25).up, 355))
        // The middle of the view moves in a straight line meanwhile; here it stays.
        #expect(near(CGPoint(x: Camera.between(a, b, 0.5).view.midX, y: Camera.between(a, b, 0.5).view.midY), CGPoint(x: a.view.midX, y: a.view.midY)))

        // Step s4 moves from level (0) to half (180): clockwise, through 90.
        let half = e.resolved.steps[4].lead
        for k in 1..<20 {
            let up = try #require(e.camera(4, at: half * Double(k) / 20)).up
            #expect(up > 0 && up < 180, "at \(k) of 20 the camera shows \(up) at the top")
        }
        #expect(same(Camera.between(try camera(e, "level"), try camera(e, "half"), 0.5).up, 90))
    }

    @Test func aTextElementStaysUprightInATurnedShot() throws {
        let e = try explainer()
        for (step, up) in [(5, 90.0), (6, 45.0), (4, 180.0)] {
            let scene = e.still(after: step)
            let c = try #require(scene.camera)
            #expect(c.up == up)
            let word = try #require(scene.element("word"))
            guard case let .words(_, set) = word.kind else { Issue.record("the word is not drawn as words"); return }
            // As drawn: the element's own transform, then the camera's.
            let drawn = word.transform.concatenating(c.transform)
            #expect(abs(drawn.b) < 1e-9 && abs(drawn.c) < 1e-9 && drawn.a > 0 && abs(drawn.a - drawn.d) < 1e-9, "level at \(up): \(drawn)")
            // It is turned about its `at`, which stays where the turned camera shows it.
            #expect(near(set.at.applying(drawn), set.at.applying(c.transform)))
            // The dot, which is not text, turns with the picture.
            let dot = try #require(scene.element("dot"))
            #expect(dot.transform == .identity)
        }
        // Unturned, the word is drawn as before, with no transform.
        #expect(try #require(e.still(after: 0).element("word")).transform == .identity)
        // Part-way through a turn (from 180 back to 90), it is level too.
        let lead = e.resolved.steps[5].lead
        let mid = e.scene(step: 5, at: lead / 2)
        let c = try #require(mid.camera)
        #expect(c.up > 90 && c.up < 180)
        let drawn = try #require(mid.element("word")).transform.concatenating(c.transform)
        #expect(abs(drawn.b) < 1e-9 && abs(drawn.c) < 1e-9)
    }

    @Test func whatIsOutsideTheRegionIsDimmedAsMeasuredInTheTurnedFrame() throws {
        let e = try explainer()
        let c = try camera(e, "tilted")
        let focus = try #require(c.focus)
        #expect(c.dim > 0)
        // The 20-unit square, turned 45 degrees, is a box 20 times the square root of 2 wide in the
        // picture's frame, about the square's middle.
        #expect(near(CGPoint(x: focus.midX, y: focus.midY), CGPoint(x: 300, y: 200)))
        #expect(abs(focus.width - 20 * 2.0.squareRoot()) < 1e-9 && abs(focus.height - focus.width) < 1e-9)
        func dimming(_ p: CGPoint) -> Double { c.dimming(of: SceneElement("p", .label("p", at: p))) }
        // 18 to the right of the middle is 8 out of the unturned square, but inside the box in the
        // turned frame, so it is not dimmed.
        #expect(dimming(CGPoint(x: 318, y: 200)) == 0)
        // 12 above the box in the turned frame is half the feather out: half dimmed.
        let half = focus.height / 2 + Camera.feather / 2
        let above = Camera.outOfFrame(CGPoint(x: 0, y: -half), up: 45)
        #expect(abs(dimming(CGPoint(x: 300 + above.x, y: 200 + above.y)) - c.dim / 2) < 1e-9)
        // Far along the picture's diagonal, fully dimmed.
        #expect(dimming(CGPoint(x: 400, y: 200)) == c.dim)
        // An unturned shot's dimming is as before.
        let level = try camera(e, "level")
        let lf = try #require(level.focus)
        #expect(level.dimming(of: SceneElement("p", .label("p", at: CGPoint(x: lf.maxX + Camera.feather / 2, y: lf.midY)))) == level.dim / 2)
    }

    /// The choice section 10.3 makes: a turned shot's view slides along the turned picture's own
    /// edges, to lie inside the box round the extent in that frame.
    @Test func aTurnedViewSlidesToLieInsideTheExtentAsTheTurnedPictureShowsIt() throws {
        // The dot near the drawing's corner: the unturned view slides right and down, and the
        // turned one slides along its own axes to the turned extent's edge.
        var source = try JSONValue.parse(Self.source)
        source = source.setting("/elements/near", nil).setting("/elements/far", nil)
            .setting("/elements/edge", try JSONValue.parse(#"{ "kind": "shape", "rect": [295, 195, 400, 300], "fill": "text" }"#))
        let d = try #require(ExplainerDocument.read(source.data).document)
        let r = Resolver(d, problem: DocumentFixture.values(("a", 1)), layout: "stage", area: nil, wording: "plain", locale: "en-US", playback: DocumentPlayback())
        let framing = CameraFraming(r, size: CGSize(width: 600, height: 400))
        let f = try framing.frame("tilted")
        #expect(f.up == 45)
        // The box it slides within: round the turned extent and the shot's region in that frame.
        let extent = framing.turnedExtent(45).union(Camera.box(CGRect(x: 290, y: 190, width: 20, height: 20), up: 45))
        let m = Camera.intoFrame(CGPoint(x: f.view.midX, y: f.view.midY), up: 45)
        let view = CGRect(x: m.x - f.view.width / 2, y: m.y - f.view.height / 2, width: f.view.width, height: f.view.height)
        #expect(extent.insetBy(dx: -1e-6, dy: -1e-6).contains(view), "the view \(view) lies inside \(extent)")
        // It touches the extent's edge, rather than being centred on the region.
        let touches = abs(view.minX - extent.minX) < 1e-6 || abs(view.minY - extent.minY) < 1e-6
            || abs(view.maxX - extent.maxX) < 1e-6 || abs(view.maxY - extent.maxY) < 1e-6
        #expect(touches, "\(view) in \(extent)")
    }
}
