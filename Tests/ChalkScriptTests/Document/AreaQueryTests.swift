import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript

// What a consuming app asks of a document before playing it: the shapes it declares, whether an
// area is among them, and the area a player would lay it out for.

struct AreaQueryTests {
    func document(_ areas: String?) -> ExplainerDocument {
        var d = DocumentFixture.tiny
        if let areas { d = d.setting("/areas", try! JSONValue.parse(areas)) }
        return read(d).document!
    }

    @Test func aDocumentSaysWhichShapesItDeclares() {
        let d = document(#"[{"layout": "stage", "ratio": [0.6, 1.35]}, {"layout": "stage", "ratio": [2, 2.2]}]"#)
        #expect(d.declaresAreas)
        #expect(d.declaredShapes == [DeclaredShape(layout: "stage", ratio: 0.6...1.35), DeclaredShape(layout: "stage", ratio: 2...2.2)])
        #expect(d.declares(CGSize(width: 100, height: 100)))
        #expect(d.declares(CGSize(width: 210, height: 100)))
        #expect(!d.declares(CGSize(width: 170, height: 100)))
        #expect(!d.declares(CGSize(width: 100, height: 200)))
        #expect(!d.declares(CGSize(width: 0, height: 100)))
    }

    @Test func aDocumentWithoutAreasDeclaresNothing() {
        let d = document(nil)
        #expect(!d.declaresAreas && d.declaredShapes.isEmpty && !d.declares(CGSize(width: 100, height: 100)))
        #expect(d.areaUse(for: CGSize(width: 100, height: 400)).isGiven)
    }

    @Test func anIntervalIsDeclaredWhenTheRangesCoverIt() {
        let d = document(#"[{"layout": "stage", "ratio": [1.35, 2.2]}, {"layout": "stage", "ratio": [0.6, 1.35]}, {"layout": "stage", "ratio": [3, 3]}]"#)
        #expect(d.declares(ratiosFrom: 0.6, to: 2.2))
        #expect(d.declares(ratiosFrom: 1, to: 1.5))
        #expect(d.declares(ratiosFrom: 3, to: 3))
        #expect(!d.declares(ratiosFrom: 0.5, to: 1))
        #expect(!d.declares(ratiosFrom: 2, to: 3))
        #expect(!d.declares(ratiosFrom: 2.5, to: 2.6))
        let gap = document(#"[{"layout": "stage", "ratio": [1, 2]}, {"layout": "stage", "ratio": [3, 4]}]"#)
        #expect(!gap.declares(ratiosFrom: 1, to: 4))
    }

    @Test func theAreaUsedIsTheNearestDeclaredShapeByLogarithm() {
        let d = document(#"[{"layout": "stage", "ratio": [1, 2]}, {"layout": "stage", "ratio": [4, 4]}]"#)
        // 2.7 is nearer 2 than 4 by ln; 3 is nearer 4 (|ln 3 - ln 4| < |ln 3 - ln 2|).
        let a = d.areaUse(for: CGSize(width: 270, height: 100))
        #expect(abs(a.used.width / a.used.height - 2) < 1e-9 && a.used.width == 200 && a.used.height == 100)
        let b = d.areaUse(for: CGSize(width: 300, height: 100))
        #expect(abs(b.used.width / b.used.height - 4) < 1e-9 && b.used.width == 300)
        // Equally near (ratio sqrt(2), between 1 and 2): the greater.
        let c = document(#"[{"layout": "stage", "ratio": [1, 1]}, {"layout": "stage", "ratio": [2, 2]}]"#)
        let tie = c.areaUse(for: CGSize(width: 2.0.squareRoot() * 100, height: 100))
        #expect(abs(tie.used.width / tie.used.height - 2) < 1e-9)
    }
}
