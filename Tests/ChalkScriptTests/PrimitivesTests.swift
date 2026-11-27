import CoreGraphics
import Testing
@testable import ChalkScript

// An explainer draws shapes the shared components lack in palette roles (EXP-6), and can
// scale part of its picture, without editing Drawing/.

struct PrimitivesTests {
    @Test func inksAreThePalettesRolesInBothAppearances() {
        for palette in [ExplainerPalette.light, .dark] {
            #expect(Ink.text.rgb(palette) == palette.ink)
            #expect(Ink.pencil.rgb(palette) == palette.pencil)
            #expect(Ink.soft(.result).rgb(palette) == palette.colors(.result).soft)
            #expect(Ink.ink(.subtract).rgb(palette) == palette.colors(.subtract).ink)
        }
    }

    @Test func aShapeIsSeenWhenItIsPainted() {
        let bar = Outline.rect(CGRect(x: 0, y: 0, width: 100, height: 40), corner: 3)
        #expect(SceneElement("bar", .shape(bar, Paint(fill: .sheet, stroke: .pencil))).isVisible)
        #expect(!SceneElement("gap", .shape(bar, Paint(stroke: .ink(.result), dash: [8, 6], progress: 0))).isVisible, "a dashed part not yet drawn")
        #expect(!SceneElement("name", .words("", Typeset(at: .zero, size: 20))).isVisible)
        #expect(SceneElement("name", .words("Ana", Typeset(at: .zero, size: 20, anchor: .trailing))).isVisible)
    }

    // The head's three points for an arrow travelling down, as they were drawn before the head took
    // the arrow's direction (EXP-13).
    private func downwardHead(at tip: CGPoint) -> [CGPoint] {
        [CGPoint(x: tip.x - 8, y: tip.y - 10), CGPoint(x: tip.x, y: tip.y + 1), CGPoint(x: tip.x + 8, y: tip.y - 10)]
    }

    private func near(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0.x - $1.x) < 1e-9 && abs($0.y - $1.y) < 1e-9 }
    }

    @Test func anArrowEndingDownGivesTheHeadItAlwaysDid() {
        let tip = CGPoint(x: 120.5, y: 301.25)
        #expect(Components.arrowHead(at: tip) == downwardHead(at: tip))
        #expect(Components.arrowHead(endingPath: [CGPoint(x: 120.5, y: 40), tip]) == downwardHead(at: tip))
        let trade = Components.tradeArrow(from: CGRect(x: 0, y: 100, width: 22, height: 220), to: CGRect(x: 300, y: 100, width: 22, height: 220), y: 40)
        #expect(Components.arrowHead(endingPath: trade) == downwardHead(at: trade.last!))
    }

    @Test func anArrowsHeadPointsAlongItsLastSegment() {
        let tip = CGPoint(x: 100, y: 100)
        #expect(near(Components.arrowHead(endingPath: [CGPoint(x: 100, y: 200), tip]),
            [CGPoint(x: 108, y: 110), CGPoint(x: 100, y: 99), CGPoint(x: 92, y: 110)]), "upward")
        #expect(near(Components.arrowHead(endingPath: [CGPoint(x: 0, y: 100), tip]),
            [CGPoint(x: 90, y: 108), CGPoint(x: 101, y: 100), CGPoint(x: 90, y: 92)]), "to the right")
        #expect(near(Components.arrowHead(endingPath: [CGPoint(x: 200, y: 100), tip]),
            [CGPoint(x: 110, y: 92), CGPoint(x: 99, y: 100), CGPoint(x: 110, y: 108)]), "to the left")
        // A slant of 3 across for 4 down: the head keeps its size and is turned with the segment.
        let slant = Components.arrowHead(endingPath: [CGPoint(x: 70, y: 60), tip]) // 30 across, 40 down
        let u = CGPoint(x: 0.6, y: 0.8)
        let expected = [(-8.0, -10.0), (0.0, 1.0), (8.0, -10.0)].map { side, along in
            CGPoint(x: tip.x + u.y * side + u.x * along, y: tip.y - u.x * side + u.y * along)
        }
        #expect(near(slant, expected))
        #expect(abs(hypot(slant[0].x - tip.x, slant[0].y - tip.y) - hypot(8, 10)) < 1e-9)
        #expect(abs(hypot(slant[1].x - tip.x, slant[1].y - tip.y) - 1) < 1e-9)
    }

    @Test func aSegmentWithNoLengthLeavesTheNearestEarlierOneToPoint() {
        let tip = CGPoint(x: 100, y: 100)
        let right = Components.arrowHead(endingPath: [CGPoint(x: 0, y: 100), tip])
        #expect(Components.arrowHead(endingPath: [CGPoint(x: 0, y: 100), tip, tip]) == right)
        #expect(Components.arrowHead(endingPath: [tip, tip]) == downwardHead(at: tip))
        #expect(Components.arrowHead(endingPath: [tip]) == downwardHead(at: tip))
        #expect(Components.arrowHead(endingPath: []).isEmpty)
    }

    @Test func anElementCarriesItsTransform() {
        let k = CGAffineTransform(translationX: 100, y: 0).scaledBy(x: 0.77, y: 0.77)
        let e = SceneElement("bar", .shape(.lines([.zero, CGPoint(x: 10, y: 0)]), Paint(stroke: .pencil)), transform: k)
        #expect(e.transform == k && e != SceneElement("bar", e.kind))
        #expect(StageDrawing.path(.lines([.zero, CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)], closed: true)).boundingRect.width == 10)
    }

    @Test func theMostCrossedPieceComesFirstAndAGrazeIsLeftOut() {
        let a = CGRect(x: 0, y: 0, width: 22, height: 220), b = CGRect(x: 33, y: 0, width: 22, height: 220)
        let graze = [CGPoint(x: 11, y: 0), CGPoint(x: 15, y: 150), CGPoint(x: 45, y: 220)]
        #expect(MarkGeometry.crosses(graze, a) && MarkGeometry.crosses(graze, b))
        #expect(MarkGeometry.lengthInside(graze, a) > MarkGeometry.lengthInside(graze, b))
        #expect(MarkGeometry.crossed(graze, among: [b, a]) == [1])
        #expect(MarkGeometry.crossed(graze, among: [a, b], share: 0.1) == [0, 1])
        let both = [CGPoint(x: -3, y: 100), CGPoint(x: 58, y: 120)]
        #expect(MarkGeometry.crossed(both, among: [a, b]) == [0, 1])
        #expect(MarkGeometry.crossed([CGPoint(x: 300, y: 0), CGPoint(x: 300, y: 50)], among: [a, b]).isEmpty)
    }
}
