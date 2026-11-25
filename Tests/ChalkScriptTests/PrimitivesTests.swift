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
