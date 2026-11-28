import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import ChalkScript
import struct ChalkScript.Scene

// A group is drawn as one layer and acts as one thing (EXP-19, section 9.6 of the format's
// reference); `appear` may come from a point (section 13.1); and `pivot` needs no capability (section
// 9.1).

@MainActor
struct GroupTests {
    /// Two overlapping rectangles, the upper drawn after the lower, 300 wide with its middle at (250, 150).
    static let shapes = #"""
        "lower": { "kind": "shape", "fill": "text", "rect": [100, 100, 200, 100] },
        "upper": { "kind": "shape", "fill": "muted", "rect": [200, 100, 200, 100] }
        """#
    static let middle = CGPoint(x: 250, y: 150)

    /// The tiny document with `elements` (members of a JSON object) and `extra` pointers set, and
    /// `actions` added to its step.
    func document(
        _ elements: String = GroupTests.shapes, actions: String = "{}", extra: [String: String] = [:], conforming: Bool = true
    ) throws -> ExplainerDocument {
        var doc = DocumentFixture.tiny
        for (name, element) in try JSONValue.parse("{\(elements)}").object?.entries ?? [] { doc = doc.setting("/elements/\(name)", element) }
        for (name, action) in try JSONValue.parse(actions).object?.entries ?? [] { doc = doc.setting("/steps/show/actions/\(name)", action) }
        for (pointer, json) in extra { doc = doc.setting(pointer, try JSONValue.parse(json)) }
        let d = try #require(ExplainerDocument.read(doc.data).document)
        if conforming { #expect(d.conforms, "\(d.findings)") }
        return d
    }

    func grouped(_ members: String = "lower + upper", rest: String = "", actions: String = "{}", extra: [String: String] = [:]) throws -> DocumentExplainer {
        let g = #""g": { "kind": "group", "members": "\#(members)"\#(rest.isEmpty ? "" : ", " + rest) }"#
        return try explainer(document(Self.shapes + ", " + g, actions: actions, extra: extra))
    }

    func explainer(_ d: ExplainerDocument) throws -> DocumentExplainer { try DocumentExplainer(document: d, problem: DocumentFixture.values(("a", 1))) }

    func resolver(_ d: ExplainerDocument) -> Resolver {
        Resolver(d, problem: DocumentFixture.values(("a", 1)), layout: "stage", area: nil, wording: "plain", locale: "en-US", playback: DocumentPlayback())
    }

    func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: Double = 1e-9) -> Bool { abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance }

    /// The point a scale transform leaves where it is.
    func fixedPoint(_ t: CGAffineTransform) -> CGPoint { CGPoint(x: t.tx / (1 - t.a), y: t.ty / (1 - t.d)) }

    func action(_ e: DocumentExplainer, _ name: String) throws -> ResolvedAction {
        try #require(e.resolved.steps[0].actions.first { $0.name == name })
    }

    /// The red, green, blue and alpha bytes of the pixel at `(x, y)` of `scene` drawn at one pixel to the unit.
    func pixel(_ scene: Scene, _ x: Int, _ y: Int) throws -> [UInt8] {
        let renderer = ImageRenderer(content: ExplainerStage(scene: scene).frame(width: scene.size.width, height: scene.size.height))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let data = try #require(image.dataProvider?.data) as Data
        let bytes = image.bitsPerPixel / 8
        return (0..<4).map { data[y * image.bytesPerRow + x * bytes + $0] }
    }

    // MARK: drawing

    @Test func aGroupAtHalfOpacityIsOneLayerWhoseOverlapShowsOnlyTheUpperShape() throws {
        let half = #""start": { "opacity": 0.5 }"#
        let both = try grouped(rest: half).still(after: 0)
        // The upper shape alone, in a group at half opacity, and the two as separate shapes at half opacity.
        let alone = try explainer(document(
            #""upper": { "kind": "shape", "fill": "muted", "rect": [200, 100, 200, 100] }, "g": { "kind": "group", "members": "upper", \#(half) }"#)).still(after: 0)
        let apart = try explainer(document(Self.shapes.replacingOccurrences(of: #""kind": "shape","#, with: #""kind": "shape", "start": { "opacity": 0.5 },"#)))
            .still(after: 0)
        let overlap = try pixel(both, 250, 150)
        let upper = try pixel(alone, 250, 150)
        #expect(overlap[3] > 100 && overlap[3] < 150, "alpha \(overlap)")
        for (a, b) in zip(overlap, upper) { #expect(abs(Int(a) - Int(b)) <= 1, "overlap \(overlap), the upper shape alone \(upper)") }
        // Without the layer the lower shape shows through: the two shapes cover more than half.
        #expect(try pixel(apart, 250, 150)[3] > 170)
        // Where only the lower shape is, the group is the lower shape at half strength.
        let lower = try pixel(both, 150, 150)
        #expect(lower[3] == overlap[3], "\(lower) against \(overlap)")
    }

    @Test func aGroupIsOneSceneElementWithItsMembersInsideInTheirOwnOrder() throws {
        let s = try grouped().still(after: 0)
        #expect(s.elements.contains { $0.id == "g" } && !s.elements.contains { $0.id == "lower" || $0.id == "upper" })
        guard case let .group(children)? = s.element("g")?.kind else { Issue.record("not a group"); return }
        #expect(children.map(\.id) == ["lower", "upper"])
        #expect(s.element("g")?.bounds == CGRect(x: 100, y: 100, width: 300, height: 100))
        // A group that has no instance leaves its members to be drawn on their own.
        let none = try explainer(document(Self.shapes + #", "g": { "kind": "group", "members": "lower + upper", "when": "a > 5" }"#)).still(after: 0)
        #expect(none.elements.contains { $0.id == "lower" } && none.elements.contains { $0.id == "upper" })
    }

    @Test func pulseAndGrowKeepAGroupsMembersTogetherAboutItsMiddle() throws {
        let actions = #"""
            { "pop": { "do": "pulse", "target": "g", "at": "end(draw)" },
              "swell": { "do": "appear", "target": "g", "grow": 0.5, "at": "end(pop)" } }
            """#
        let e = try grouped(rest: #""start": { "opacity": 0 }"#, actions: actions)
        let pop = try action(e, "pop")
        let pulsing = e.scene(step: 0, at: pop.start + pop.duration / 2)
        let t = try #require(pulsing.element("g")).transform
        #expect(abs(t.a - 1.15) < 1e-9 && near(fixedPoint(t), Self.middle, 1e-6), "\(t)")
        #expect(pulsing.element("lower")?.transform == CGAffineTransform.identity && pulsing.element("upper")?.transform == CGAffineTransform.identity)
        let swell = try action(e, "swell")
        let growing = e.scene(step: 0, at: swell.start)
        let g = try #require(growing.element("g")).transform
        #expect(abs(g.a - 0.5) < 1e-9 && near(fixedPoint(g), Self.middle, 1e-6), "\(g)")
        #expect(growing.element("lower")?.transform == CGAffineTransform.identity)
        // About a pivot of the group's own, with no capability.
        let pivoted = try grouped(rest: #""pivot": [100, 100]"#, actions: #"{ "pop": { "do": "pulse", "target": "g", "at": "end(draw)" } }"#)
        let p = try action(pivoted, "pop")
        let shown = try #require(pivoted.scene(step: 0, at: p.start + p.duration / 2).element("g")).transform
        #expect(near(fixedPoint(shown), CGPoint(x: 100, y: 100), 1e-6), "\(shown)")
    }

    @Test func moveOfAGroupWithToPutsItsMiddleThere() throws {
        let e = try grouped(actions: #"{ "go": { "do": "move", "target": "g", "to": [500, 300], "at": "end(draw)" } }"#)
        let t = try #require(e.still(after: 0).element("g")).transform
        #expect(near(Self.middle.applying(t), CGPoint(x: 500, y: 300)), "\(t)")
        #expect(near(CGPoint(x: 100, y: 100).applying(t), CGPoint(x: 350, y: 250)))
        // Before it moves, the group is where its members are.
        #expect(try #require(e.scene(step: 0, at: 0).element("g")).transform == CGAffineTransform.identity)
        // The place the move leaves is where bounds and regions find the group afterwards.
        let r = resolver(try document(extra: [:]))
        #expect(try r.bounds(DocumentInstance("lower")) == CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    @Test func aPartAndAShotFrameAGroupByItsMembersBounds() throws {
        let d = try document(Self.shapes + #", "g": { "kind": "group", "members": "lower + upper" }"#,
            extra: ["/parts": #"{ "both": "g", "one": "lower" }"#, "/shots": #"{ "close": { "frame": ["both"], "margin": 10 } }"#])
        let r = resolver(d)
        #expect(try r.bounds(DocumentInstance("g")) == CGRect(x: 100, y: 100, width: 300, height: 100))
        #expect(try r.region(ofPart: "both") == CGRect(x: 100, y: 100, width: 300, height: 100))
        let framing = CameraFraming(r, size: CGSize(width: 1000, height: 540))
        // The drawing's extent includes the group's box, and the shot's region is it grown by the margin.
        #expect(try framing.frame("close").region == CGRect(x: 90, y: 90, width: 320, height: 120))
    }

    @Test func anInstanceInTwoGroupsIsAnErrorThatNamesBoth() throws {
        let d = try document(Self.shapes + #"""
            , "gOne": { "kind": "group", "members": "lower" }, "gTwo": { "kind": "group", "members": "lower + upper" }
            """#)
        do {
            _ = try explainer(d)
            Issue.record("an instance in two groups was drawn")
        } catch let e as DocumentRefusal {
            let named = e.findings.filter { $0.code == .eval && $0.message.contains("gOne") && $0.message.contains("gTwo") && $0.message.contains("lower") }
            #expect(!named.isEmpty, "\(e.findings)")
        }
    }

    @Test func aGroupHoldsWholeInstancesThatAreNotGroupsAndNotFixed() throws {
        func refusal(_ elements: String) throws -> String {
            do { _ = try explainer(document(Self.shapes + ", " + elements)); return "" } catch let e as DocumentRefusal { return e.description } catch { return "\(error)" }
        }
        #expect(try refusal(#""ga": { "kind": "group", "members": "lower" }, "gb": { "kind": "group", "members": "ga" }"#).contains("groups do not nest"))
        #expect(try refusal(#""fixedOne": { "kind": "shape", "fill": "text", "rect": [0, 0, 5, 5], "fixed": true }, "g": { "kind": "group", "members": "fixedOne" }"#)
            .contains("must not be"))
        #expect(try refusal(#""g": { "kind": "group", "members": "first(0, lower)" }"#).contains("no members"))
    }

    // MARK: turning

    @Test func aGroupOfShapesTurnsAboutItsMiddleAndOneWithTextCannotBeTurned() throws {
        let turn = #"{ "do": "turn", "target": "g", "to": 90, "at": "end(draw)" }"#
        let required = ["/requires": #"["drawing.turn"]"#]
        let e = try grouped(actions: "{ \"spin\": \(turn) }", extra: required)
        let t = try #require(e.still(after: 0).element("g")).transform
        #expect(near(Self.middle.applying(t), Self.middle, 1e-9) && abs(t.b - 1) < 1e-9 && abs(t.a) < 1e-9, "\(t)")
        // The box round the members turned about the middle: 300 by 100 becomes 100 by 300.
        let r = resolver(try document(Self.shapes + #", "g": { "kind": "group", "members": "lower + upper", "turn": 90 }"#, extra: required))
        let b = try r.bounds(DocumentInstance("g"))
        #expect(abs(b.width - 100) < 1e-9 && abs(b.height - 300) < 1e-9 && near(CGPoint(x: b.midX, y: b.midY), Self.middle, 1e-9), "\(b)")
        // A text member: the verb and the key both refuse, naming the group and its member.
        for (extra, path) in [
            (["/steps/show/actions/spin": turn], "/steps/show/actions/spin/target"),
            (["/elements/g/turn": "45"], "/elements/g/turn"),
        ] as [([String: String], String)] {
            var more = required
            for (k, v) in extra { more[k] = v }
            let d = try document(Self.shapes + #", "g": { "kind": "group", "members": "lower + label" }"#, extra: more)
            do {
                _ = try explainer(d)
                Issue.record("a group with a text member was turned (\(path))")
            } catch let e as DocumentRefusal {
                #expect(e.findings.contains { $0.code == .eval && $0.path == path && $0.message.contains("cannot be turned") && $0.message.contains("label") }, "\(e.findings)")
            }
        }
    }

    // MARK: an entrance from a point

    @Test func appearFromAPointStartsTheMiddleThereAndCarriesItToItsPlaceAsItGrows() throws {
        let appear = #"{ "do": "appear", "target": "g", "from": [500, 400], "grow": 0.5, "dur": 1, "at": "end(draw)" }"#
        let e = try grouped(rest: #""start": { "opacity": 0 }"#, actions: "{ \"enter\": \(appear) }")
        let a = try action(e, "enter")
        for (p, scale, at) in [(0.0, 0.5, CGPoint(x: 500, y: 400)), (0.5, 0.75, CGPoint(x: 375, y: 275)), (1.0, 1.0, Self.middle)] {
            let s = e.scene(step: 0, at: a.start + p * a.duration)
            let g = try #require(s.element("g"))
            // The middle of the group is carried by the whole transform, which scales about the middle.
            #expect(near(Self.middle.applying(g.transform), at, 1e-6) && abs(g.transform.a - scale) < 1e-9, "p \(p): \(g.transform)")
            #expect(abs(g.opacity - p) < 1e-9)
        }
        // A pivot is the point that starts at `from`, in place of the middle.
        let pivoted = try grouped(rest: #""start": { "opacity": 0 }, "pivot": [100, 100]"#, actions: "{ \"enter\": \(appear) }")
        let g = try #require(pivoted.scene(step: 0, at: try action(pivoted, "enter").start).element("g"))
        #expect(near(CGPoint(x: 100, y: 100).applying(g.transform), CGPoint(x: 500, y: 400), 1e-6), "\(g.transform)")
    }

    @Test func appearFromTheMiddleOfOneInstanceAndOnAnElementThatIsNoGroup() throws {
        let actions = #"{ "enter": { "do": "appear", "target": "lower", "from": "upper", "grow": 0.25, "dur": 1, "at": "end(draw)" } }"#
        let e = try explainer(document(Self.shapes.replacingOccurrences(of: #""fill": "text","#, with: #""fill": "text", "start": { "opacity": 0 },"#), actions: actions))
        let a = try action(e, "enter")
        let start = try #require(e.scene(step: 0, at: a.start).element("lower")).transform
        // The middle of lower, (200, 150), starts at the middle of upper, (300, 150).
        #expect(near(CGPoint(x: 200, y: 150).applying(start), CGPoint(x: 300, y: 150), 1e-6), "\(start)")
        let end = e.still(after: 0).element("lower")?.transform
        #expect(end == .identity || end.map { near(CGPoint(x: 200, y: 150).applying($0), CGPoint(x: 200, y: 150), 1e-9) } == true)
        // From more than one instance is an error that says how many.
        let many = try document(Self.shapes, actions: #"{ "enter": { "do": "appear", "target": "lower", "from": "lower + upper" } }"#)
        do {
            _ = try explainer(many)
            Issue.record("from selected two instances")
        } catch let e as DocumentRefusal {
            #expect(e.findings.contains { $0.path == "/steps/show/actions/enter/from" && $0.message.contains("2 instances, not one") }, "\(e.findings)")
        }
    }

    // MARK: what the reader says

    @Test func fromWithRiseIsRefusedAndFromTakesAPointOrASelection() throws {
        func appear(_ rest: String) throws -> DocumentReading {
            read(DocumentFixture.tiny.setting("/steps/show/actions/enter", try JSONValue.parse(#"{ "do": "appear", "target": "label", \#(rest) }"#)))
        }
        has(try appear(#""from": [0, 0], "rise": 20"#), .error, .schema, "/steps/show/actions/enter", "from or rise")
        #expect(try appear(#""from": [0, 0], "grow": 0.5"#).conforms)
        #expect(try appear(#""from": "rule", "grow": 0.5"#).conforms)
        has(try appear(#""from": [0]"#), .error, .schema, "/steps/show/actions/enter/from", "not a point")
        has(try appear(#""from": "nope""#), .error, .expr, "/steps/show/actions/enter/from")
    }

    @Test func pivotNeedsNoCapabilityAndTurnStillDoes() throws {
        let tiny = DocumentFixture.tiny
        let pivot = try JSONValue.parse("[0, 0]")
        for element in ["rule"] {
            let r = read(tiny.setting("/elements/\(element)/pivot", pivot))
            #expect(r.conforms && r.findings.isEmpty, "\(r.findings)")
        }
        let g = try JSONValue.parse(#"{ "kind": "group", "members": "label + rule", "pivot": [10, 20] }"#)
        let withPivot = read(tiny.setting("/elements/g", g))
        #expect(withPivot.conforms && withPivot.findings.isEmpty, "\(withPivot.findings)")
        has(read(tiny.setting("/elements/g", g.setting("/turn", .number(30)))), .error, .capability, "/elements/g/turn", "drawing.turn")
        has(read(tiny.setting("/elements/rule/turn", .number(30))), .error, .capability, "/elements/rule/turn", "drawing.turn")
        let text = tiny.setting("/elements/label/pivot", pivot)
        has(read(text), .error, .schema, "/elements/label/pivot", "is for a line, arrow, shape or group")
    }

    @Test func aGroupNeedsMembersWhichDoNotDependOnTheState() throws {
        let tiny = DocumentFixture.tiny
        func build(_ json: String) throws -> DocumentReading { read(tiny.setting("/elements/g", try JSONValue.parse(json))) }
        #expect(try build(#"{ "kind": "group", "members": "label + rule" }"#).conforms)
        has(try build(#"{ "kind": "group" }"#), .error, .schema, "/elements/g", "no 'members'")
        has(try build(#"{ "kind": "group", "members": "whole(rule)" }"#), .error, .schema, "/elements/g/members", "whole()")
        has(try build(#"{ "kind": "group", "members": "nothing" }"#), .error, .expr, "/elements/g/members")
        has(try build(#"{ "kind": "group", "members": "rule", "start": { "progress": 0 } }"#), .warning, .unknown, "/elements/g/start/progress")
        has(try build(#"{ "kind": "group", "members": "rule", "width": 3 }"#), .warning, .unknown, "/elements/g/width")
        #expect(try build(#"{ "kind": "group", "repeat": 2, "members": "rule", "let": { "k": "i" }, "z": "k", "start": { "opacity": 0 } }"#).conforms)
    }
}
