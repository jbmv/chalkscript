import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

// Subtraction laid out for the explainer screen (EXP-17), with the camera (EXP-18), on
// the iPad mini (1133 by 744 points): in portrait and in landscape, the column on either hand's
// side, the drawing fills its area, and every piece the child is asked to mark or touch in do it
// with me is a target of at least 44 points at the moment the child is asked.
//
// The drawing areas are the explainer's in a preview app on the iPad mini: 712 by 616.5 points
// in portrait, 580.5 by 539 in landscape.

@MainActor
struct SubtractionScreenTests {
    static let miniLandscape = CGSize(width: 580.5, height: 539)
    static let miniPortrait = CGSize(width: 712, height: 616.5)
    static let layouts: [(name: String, area: CGSize, hand: WritingHand)] = [
        ("portrait", miniPortrait, .right),
        ("landscape, right hand", miniLandscape, .right),
        ("landscape, left hand", miniLandscape, .left),
    ]

    /// Apple's smallest comfortable target, in points (Human Interface Guidelines).
    static let target: CGFloat = 44

    /// The range's edges, other problems, and the widest drawings: nine tens with a
    /// trade, eight tens and nine ones left to count.
    static let problems: [(Int, Int)] = Fixture.edges + [(90, 1), (98, 9), (91, 2), (62, 37), (35, 18)]

    static func explainer(_ a: Int, _ b: Int) -> SubtractionExplainer {
        SubtractionExplainer(problem: try! SubtractionProblem(a, minus: b), version: .child, wording: Fixture.guidedWording())
    }

    /// The pieces the child is asked to mark or touch on step `k` from `state`, with the margin
    /// within which the explainer reads a mark on them: a line across a piece (MarkGeometry's
    /// stroke pad) or a touch on it (the count's).
    static func asked(_ e: SubtractionExplainer, _ k: Int, _ state: SubtractionState) -> (pieces: [CGRect], pad: CGFloat) {
        switch e.steps[k] {
        case .trade: (e.wholeTens(state).map { e.layout.tens[$0] }, 4)
        case .takeOnes: (e.keptOnes(state).map(e.rect), 4)
        case .takeTens: (e.wholeTens(state).map { e.layout.tens[$0] }, 4)
        case .count: (e.countRects, SubtractionExplainer.countTouchPad)
        default: ([], 0)
        }
    }

    @Test func theDrawingFillsItsAreaInEachLayout() {
        for (name, area, _) in Self.layouts {
            for (a, b) in Self.problems {
                let e = Self.explainer(a, b).laidOut(for: area)
                guard let frame = e.frame else {
                    Issue.record("\(a) - \(b) is not laid out for \(name)")
                    continue
                }
                let scene = e.still(after: -1)
                // The scene has the area's shape: fitted, it leaves no band of empty sheet.
                let (s, origin) = scene.fit(in: area)
                #expect(abs(origin.x) < 1 && abs(origin.y) < 1, "\(name) \(a) - \(b): the scene sits at \(origin)")
                #expect(abs(scene.size.width * s - area.width) < 1 && abs(scene.size.height * s - area.height) < 1)
                // The whole drawing, as it opens, reaches across the viewport one way and is
                // centred the other.
                let viewport = frame.plan.viewport.applying(CGAffineTransform(scaleX: s, y: s))
                let drawn = scene.screenRect(e.layout.bounds(e.problem), in: area)
                let fills = max(drawn.width / viewport.width, drawn.height / viewport.height)
                #expect(fills > 0.9, "\(name) \(a) - \(b): the drawing fills \(Int(fills * 100))% of its area")
                #expect(viewport.insetBy(dx: -1, dy: -1).contains(drawn), "\(name) \(a) - \(b): the drawing runs out of its area")
                // The problem stays above the camera, in the band at the top.
                #expect(scene.element("equation")?.fixed == true)
            }
        }
    }

    /// Plays do it with me with every step the child's and measures, at each step as the child is
    /// first able to mark, the pieces the child is asked to mark: each is on screen, inside the
    /// drawing's area, and is a target at least 44 points across both ways.
    @Test func everyPieceTheChildMarksIsALargeEnoughTarget() {
        var smallestDrawn = CGFloat.infinity
        var smallestTarget = CGFloat.infinity
        for (name, area, hand) in Self.layouts {
            _ = hand
            for (a, b) in Self.problems {
                let e = Self.explainer(a, b)
                let laid = e.laidOut(for: area)
                let v = RecordingVoice()
                let p = GuidedPlayer(lesson: GuidedLesson(watch: e, doWithMe: e, tryOne: e), voice: v, labels: Fixture.guidedLabels, drivesItself: false)
                p.layOut(for: area)
                p.jump(to: .doWithMe)
                var state = laid.start
                for k in laid.steps.indices {
                    p.jump(toStep: k)
                    p.settle(v)
                    let s0 = state
                    state = laid.apply(laid.steps[k], s0)
                    // With nothing left to count (54 - 54) the count finishes by itself.
                    guard p.childDoes(k), !(laid.steps[k] == .count && laid.countCount == 0) else { continue }
                    #expect(p.readsMarks, "\(name) \(a) - \(b) step \(k) does not read marks")
                    let scene = p.scene
                    guard let camera = scene.camera else {
                        Issue.record("\(name) \(a) - \(b): no camera")
                        continue
                    }
                    // The state the child acts on: the step's start, framed and, for the count,
                    // gathered.
                    var acting = s0
                    if laid.steps[k] == .count { acting.gathered = true }
                    let (pieces, pad) = Self.asked(laid, k, acting)
                    let viewport = camera.viewport.applying(CGAffineTransform(scaleX: scene.fit(in: area).scale, y: scene.fit(in: area).scale))
                    var shown = 0
                    for piece in pieces {
                        // In the trade, the child may break any whole ten; the camera frames the
                        // last, and those beside it in shot are the ones asked for.
                        if laid.steps[k] == .trade, let focus = camera.focus, !focus.contains(CGPoint(x: piece.midX, y: piece.midY)) { continue }
                        shown += 1
                        let drawn = scene.screenRect(piece, in: area)
                        let target = scene.screenRect(piece.insetBy(dx: -pad, dy: -pad), in: area)
                        smallestDrawn = min(smallestDrawn, drawn.width, drawn.height)
                        smallestTarget = min(smallestTarget, target.width, target.height)
                        #expect(viewport.insetBy(dx: -1, dy: -1).contains(drawn), "\(name) \(a) - \(b) step \(k): a piece at \(drawn) is off the drawing")
                        #expect(
                            target.width >= Self.target && target.height >= Self.target,
                            "\(name) \(a) - \(b) step \(laid.steps[k]): a target is \(Int(target.width)) by \(Int(target.height)) points")
                    }
                    #expect(shown > 0 || pieces.isEmpty, "\(name) \(a) - \(b) step \(k): nothing to mark is in shot")
                }
            }
        }
        print("smallest piece drawn \(smallestDrawn) pt, smallest target \(smallestTarget) pt")
    }
}
