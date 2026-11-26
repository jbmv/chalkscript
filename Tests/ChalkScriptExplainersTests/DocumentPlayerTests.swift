import CoreGraphics
import Foundation
import class SwiftUI.ImageRenderer
import protocol SwiftUI.View
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

/// Documents played as explainers (EXP-19): the two examples play in the engine's player and
/// view; equal groups, which has no Swift template, passes the checks the templates do (EXP-5,
/// EXP-6, EXP-17); every verb it uses is drawn with its start, motion and end; and what the player
/// does not draw is refused by name.
@MainActor
struct DocumentPlayerTests {
    static let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/format/examples")

    static func read(_ name: String) -> ExplainerDocument {
        ExplainerDocument.read(contentsOf: examples.appendingPathComponent(name)).document!
    }

    static let equalGroups = read("equal-groups.explainer")

    /// The learner's playback and the parent's.
    static let playbacks: [(String, DocumentPlayback)] = [
        ("everyday", DocumentPlayback(control: .paced, counts: .spoken)),
        ("formal", DocumentPlayback(control: .skippable, counts: .shown, countPace: 0.4)),
    ]

    static func groups(_ a: Int, _ b: Int, wording: String = "everyday", playback: DocumentPlayback = DocumentPlayback()) throws -> DocumentExplainer {
        try DocumentExplainer(document: equalGroups, problem: ["a": .number(Double(a)), "b": .number(Double(b))], wording: wording, playback: playback)
    }

    /// Every sample of equal groups, in both playbacks.
    static func everyGroups() throws -> [DocumentExplainer] {
        var out: [DocumentExplainer] = []
        for s in equalGroups.samples {
            for (w, p) in playbacks {
                out.append(try DocumentExplainer(document: equalGroups, problem: s, wording: w, playback: p))
            }
        }
        return out
    }

    /// The pictures of `e`: before the first step, each step's still, and `n` moments of each step.
    static func pictures(_ e: any Explainer, moments n: Int = 8) -> [Scene] {
        var out = (-1..<e.stepCount).map { e.still(after: $0) }
        for k in 0..<e.stepCount {
            let d = e.script(for: k).duration
            out += (0...n).map { e.scene(step: k, at: d * Double($0) / Double(n)) }
        }
        return out
    }

    static func equation(_ s: Scene) -> String? {
        guard case let .equation(line)? = s.element("equation")?.kind else { return nil }
        return line.text
    }

    static func total(_ s: Scene) -> String? {
        guard let e = s.element("total"), e.isVisible, case let .total(text, _, _) = e.kind else { return nil }
        return text
    }

    // MARK: the engine's player and view

    /// Every sample plays through `ExplainerPlayer` step by step, says its counts in order when
    /// they are spoken and none when they are shown, and ends on the answer.
    @Test func everySampleOfEqualGroupsPlaysInThePlayer() throws {
        for e in try Self.everyGroups() {
            guard case let .number(a) = e.problem["a"], case let .number(b) = e.problem["b"] else { continue }
            let p = Int(a * b)
            let voice = RecordingVoice()
            let player = ExplainerPlayer(explainer: e, voice: voice, drivesItself: false)
            #expect(player.caption == e.intro)
            for k in 0..<e.stepCount {
                player.primary()
                #expect(player.phase == .playing(k))
                player.playToPause(voice)
                #expect(player.phase == .paused(k))
            }
            let counts = voice.said.filter { $0.key == "tick" }.map(\.display)
            let expected = e.playback.counts == .spoken ? (1...Int(a)).map { String($0 * Int(b)) } : []
            #expect(counts == expected, "\(e.problem)")
            #expect(voice.said.last?.display.contains("is \(p)") == true, "\(voice.said.last?.display ?? "-")")
            let end = e.still(after: e.stepCount - 1)
            #expect(Self.equation(end) == "\(Int(a)) × \(Int(b)) = \(p)")
            #expect(Self.total(end) == String(p))
            #expect(Self.equation(e.still(after: -1)) == "\(Int(a)) × \(Int(b)) = ?")
            // The skippable playback is the parent's: Next finishes a step that plays (EXP-9).
            #expect(e.version == (e.playback.control == .skippable ? .parent : .child))
        }
    }

    /// The subtraction document plays in the player as the template does: the same lines, said
    /// in the same order. (The fixture's wording has no singular, so no problem here says "1 ten".)
    @Test func theSubtractionDocumentSaysWhatTheTemplateSays() throws {
        for (a, b) in [(54, 26), (83, 25), (91, 9), (50, 20), (99, 99)] {
            let d = try DocumentExplainer(
                document: SubtractionDocumentTests.document, problem: ["a": .number(Double(a)), "b": .number(Double(b))], wording: "everyday")
            let e = Fixture.explainer(a, b)
            func said(_ x: any Explainer) -> [String] {
                let voice = RecordingVoice()
                let player = ExplainerPlayer(explainer: x, voice: voice, drivesItself: false)
                for _ in 0..<x.stepCount {
                    player.primary()
                    player.playToPause(voice)
                }
                return voice.said.map(\.display)
            }
            #expect(said(d) == said(e), "\(a) − \(b)")
        }
    }

    /// The player lays a document out for its drawing area (EXP-17): a tall area takes the
    /// subtraction document's tall layout, with its camera (EXP-18), and the view draws it.
    @Test func theViewDrawsADocumentLaidOutForItsArea() throws {
        let d = try DocumentExplainer(document: SubtractionDocumentTests.document, problem: ["a": .number(54), "b": .number(26)])
        let player = ExplainerPlayer(explainer: d, voice: SilentVoice(), drivesItself: false)
        #expect(player.scene.camera == nil && player.scene.size == Scene.stage)
        player.layOut(for: SubtractionDocumentTests.tall)
        let laid = try #require(player.explainer as? DocumentExplainer)
        #expect(laid.resolved.layout == "tall" && player.scene.camera?.shot == "whole")
        #expect(player.scene.size == CGSize(width: 640, height: 737))
        let labels = ExplainerLabels(watch: "Watch", next: "Next", watchAgain: "Watch again", again: "Again", progress: { "Step \($0) of \($1)" })
        let view = ExplainerView(player: player, labels: labels).frame(width: 660, height: 900)
        #expect(ImageRenderer(content: view).cgImage != nil)
    }

    // MARK: the checks the templates pass

    /// EXP-5: at most two things are marked at any moment of any step.
    @Test func equalGroupsMarksNoMoreThanTwoThings() throws {
        for e in try Self.everyGroups() {
            for k in 0..<e.stepCount {
                let d = e.script(for: k).duration
                for i in 0...200 {
                    let s = e.scene(step: k, at: d * Double(i) / 200)
                    #expect(s.markedCount <= 2, "\(e.problem) step \(k) at \(d * Double(i) / 200)")
                }
                #expect(e.still(after: k).markedCount <= 2)
            }
        }
    }

    /// EXP-17: everything drawn lies inside the drawing.
    @Test func equalGroupsDrawsInsideTheDrawing() throws {
        for e in try Self.everyGroups() {
            for s in Self.pictures(e) {
                let drawing = CGRect(origin: .zero, size: s.size)
                for el in s.visible {
                    guard let b = el.bounds else { continue }
                    #expect(drawing.contains(b), "\(e.problem) \(el.id) at \(b)")
                }
            }
        }
    }

    /// EXP-6, EXP-19: every colour equal groups draws is a role of the style, so a second palette
    /// with the same roles changes every one of them.
    @Test func equalGroupsDrawsOnlyTheStylesRoles() throws {
        let scenes = try Self.everyGroups().flatMap { Self.pictures($0, moments: 4) }
        let second = StyleAndMotionFileTests.secondPalette()
        for dark in [false, true] {
            let a = StyleAndMotionFileTests.colours(scenes, ExplainerStyle.standard.palette(dark: dark))
            let b = StyleAndMotionFileTests.colours(scenes, second.palette(dark: dark))
            #expect(Set(a.keys) == Set(b.keys))
            #expect(Set(a.values).isDisjoint(with: Set(b.values)), "a colour stayed the same")
            for role: Ink in [.pencil, .sheet, .text, .muted, .ink(.multiply), .ink(.result), .soft(.result), .soft(.multiply)] {
                #expect(a[role] != nil, "equal groups does not draw \(role)")
            }
        }
    }

    /// EXP-6: equal groups shows multiply and the answer, which stay apart from each other and
    /// from the pencil and text under simulated colour-vision deficiencies.
    @Test(arguments: [false, true]) func equalGroupsColoursStayApart(dark: Bool) throws {
        var ops: Set<ExplainerOperation> = []
        for e in try Self.everyGroups() { ops.formUnion(ColourVisionTests.operationsShown(by: e)) }
        #expect(ops == [.multiply, .result])
        let p = ExplainerPalette.for(dark: dark)
        let c = ColourVisionTests.closest(ColourVisionTests.shown(.multiply, p), ColourVisionTests.shown(.result, p))
        #expect(c.distance >= ColourVisionTests.minimum)
        for op in ops {
            let n = ColourVisionTests.closest(ColourVisionTests.shown(op, p), [p.pencil, p.ink])
            #expect(n.distance >= ColourVisionTests.minimum, "\(op)")
        }
    }

    // MARK: the verbs (section 13)

    /// 3 × 4, verb by verb: each instance's start, motion and end as the reference defines them.
    @Test func equalGroupsDrawsEachVerb() throws {
        let e = try Self.groups(3, 4)
        func ring(_ s: Scene, _ i: Int) -> (CGRect, Double)? {
            guard case let .box(r, p, op)? = s.element("ring.\(i)")?.kind, op == .multiply else { return nil }
            return (r, p)
        }
        // Before the first step: the rings not drawn, the dots not shown, the answer unknown.
        let before = e.still(after: -1)
        #expect(ring(before, 0)?.1 == 0 && before.element("dot.0")?.opacity == 0)
        // groups: each ring is drawn (draw: progress 0 to 1), then its dots appear one after
        // another (appear: opacity 0 to 1).
        let gap = 0.3 + 4 * 0.12
        let drawing = e.scene(step: 0, at: 0.15)
        #expect(ring(drawing, 0).map { $0.1 > 0 && $0.1 < 1 } == true, "ring 0 is being drawn")
        #expect(ring(drawing, 1)?.1 == 0, "ring 1 waits for its turn")
        let appearing = e.scene(step: 0, at: 0.3 + 0.12 + 0.1)
        #expect(appearing.element("dot.0")?.opacity == 1)
        #expect(appearing.element("dot.1").map { $0.opacity > 0 && $0.opacity < 1 } == true)
        #expect(appearing.element("dot.2")?.opacity == 0, "a staggered dot waits at its start state")
        #expect(e.scene(step: 0, at: gap + 0.1).element("dot.4")?.opacity == 0)
        let grouped = e.still(after: 0)
        #expect((0..<3).allSatisfy { ring(grouped, $0)?.1 == 1 } && (0..<12).allSatisfy { grouped.element("dot.\($0)")?.opacity == 1 })
        // same: the digit is tinted (tint: the run takes the colour at once, the tint grows) and
        // a loop is drawn round the first group; both are marks, gone as the next step begins.
        guard case let .equation(marked)? = e.scene(step: 1, at: 0.1).element("equation")?.kind, let m = marked.mark else {
            Issue.record("the digit is not marked")
            return
        }
        #expect(marked.runs[m.run].text == "4" && m.op == .multiply && m.progress > 0 && m.progress < 1)
        guard case let .hint(_, p)? = e.still(after: 1).element("hint")?.kind else { Issue.record("no loop"); return }
        #expect(p == 1)
        guard case let .equation(unmarked)? = e.scene(step: 2, at: 0).element("equation")?.kind else { return }
        #expect(unmarked.mark == nil)
        guard case .hint(_, 0)? = e.scene(step: 2, at: 0).element("hint")?.kind else { Issue.record("the loop stays"); return }
        // skip: each group counted in turn (look: counted at the iteration's start; tag: a card
        // over the group that comes and goes; set: the total), then the total pulses and the
        // answer appears in the equation.
        let s = e.script(for: 2)
        let counting = e.scene(step: 2, at: 0.9 + 0.3)
        #expect((0..<8).allSatisfy {
            if case .circle(_, .counted)? = counting.element("dot.\($0)")?.kind { true } else { false }
        })
        if case .circle(_, .pencil)? = counting.element("dot.8")?.kind {} else { Issue.record("dot 8 is counted too soon") }
        #expect(Self.total(counting) == "8")
        guard case let .numberTag(text, rect, scale)? = counting.element("ring.1.tag")?.kind else { Issue.record("no tag"); return }
        let ringRect = ring(counting, 1)!.0
        #expect(text == "8" && scale == 1 && counting.element("ring.1.tag")!.opacity == 1)
        #expect(abs(rect.midX - ringRect.midX) < 1e-9 && abs(rect.midY - ringRect.midY) < 1e-9, "the tag is centred on its group")
        #expect(e.still(after: 2).element("ring.1.tag") == nil, "a tag leaves nothing in the still")
        let pulseAt = 3 * 0.9 + 0.25
        guard case let .total(_, _, grown)? = e.scene(step: 2, at: pulseAt + 0.25).element("total")?.kind else { return }
        #expect(abs(grown - 1.15) < 1e-9)
        guard case let .equation(answering)? = e.scene(step: 2, at: pulseAt + 0.5 + 0.2).element("equation")?.kind,
            let ans = answering.runs.last
        else { return }
        #expect(ans.text == "12" && ans.role == .answer && ans.opacity > 0 && ans.opacity < 1)
        #expect(abs(s.duration - (pulseAt + 0.9)) < 1e-9)
    }

    // MARK: refusal

    /// A document is refused, naming what is not drawn, when it asks for what this player does
    /// not draw yet: never drawn approximately (section 2.3).
    @Test func whatIsNotDrawnIsRefusedByName() throws {
        let source = try String(contentsOf: Self.examples.appendingPathComponent("equal-groups.explainer"), encoding: .utf8)
        let cases: [(String, String, String)] = [
            ("\"target\": \"equation.b\"", "\"target\": \"ring\"", "tints only a run"),
            ("\"style\": \"total\", \"at\": [\"cx\", \"totalY\"]", "\"style\": \"total\", \"at\": [\"cx\", \"totalY\"], \"ink\": \"text\"",
             "a total centred and in the result role"),
            ("\"ink\": \"multiply\",\n", "\"ink\": \"pencil\",\n", "operation role"),
        ]
        for (old, new, says) in cases {
            #expect(source.contains(old), "\(old)")
            let reading = ExplainerDocument.read(Data(source.replacingOccurrences(of: old, with: new).utf8))
            let doc = try #require(reading.document)
            #expect(doc.conforms, "\(doc.findings)")
            do {
                _ = try DocumentExplainer(document: doc, problem: ["a": .number(3), "b": .number(4)])
                Issue.record("played a document with \(new)")
            } catch {
                #expect(error.findings.first?.code == .capability && error.findings.first?.message.contains(says) == true, "\(error)")
            }
        }
    }
}
