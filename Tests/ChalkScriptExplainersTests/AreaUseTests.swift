import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

// A player given an area the document does not declare lays the document out for the nearest
// declared shape, centred, and says so (EXP-17, section 8.2 of the format's reference).

struct AreaUseTests {
    static let problem: [String: DocumentValue] = ["a": .number(54), "b": .number(26)]

    /// The subtraction document, which declares `tall` for 0.6 to 1.35 and `stage` for 1.35 to 2.2.
    static let declared = SubtractionDocumentTests.document

    /// The same document with `areas` removed.
    static let undeclared: ExplainerDocument = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/format/examples/subtraction.explainer")
        var object = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        object["areas"] = nil
        return ExplainerDocument.read(try! JSONSerialization.data(withJSONObject: object)).document!
    }()

    func play(_ document: ExplainerDocument, _ area: CGSize) throws -> DocumentExplainer {
        try DocumentExplainer(document: document, problem: Self.problem, area: area)
    }

    @Test func aShapeBelowTheRangesIsLaidOutForTheLeastDeclared() throws {
        let e = try play(Self.declared, CGSize(width: 400, height: 1000))
        let use = try #require(e.areaUse)
        #expect(!use.isGiven && use.given == CGSize(width: 400, height: 1000))
        #expect(use.used.width == 400 && abs(use.used.height - 400 / 0.6) < 1e-9)
        #expect(e.resolved.layout == "tall")
        // The size the layout asks for follows the area used (400 by 667): 640 by 1067.
        #expect(e.still(after: 0).size == CGSize(width: 640, height: 1067))
    }

    @Test func aShapeInsideTheRangesIsLaidOutAsGiven() throws {
        for area in [CGSize(width: 660, height: 760), CGSize(width: 1000, height: 540), CGSize(width: 1350, height: 1000)] {
            let e = try play(Self.declared, area)
            let use = try #require(e.areaUse)
            #expect(use.isGiven && use.used == area, "\(area)")
        }
        #expect(try play(Self.declared, CGSize(width: 660, height: 760)).resolved.layout == "tall")
        #expect(try play(Self.declared, CGSize(width: 1000, height: 540)).resolved.layout == "stage")
    }

    @Test func aShapeAboveTheRangesIsLaidOutForTheGreatestDeclared() throws {
        let e = try play(Self.declared, CGSize(width: 2400, height: 1000))
        let use = try #require(e.areaUse)
        #expect(!use.isGiven)
        #expect(abs(use.used.width - 2200) < 1e-9 && use.used.height == 1000)
        #expect(e.resolved.layout == "stage")
    }

    @Test func aDocumentWithoutAreasIsLaidOutForTheAreaGiven() throws {
        for area in [CGSize(width: 400, height: 1000), CGSize(width: 2400, height: 1000), CGSize(width: 660, height: 760)] {
            let e = try play(Self.undeclared, area)
            let use = try #require(e.areaUse)
            #expect(use.isGiven && use.used == area)
        }
        // As before: the tall layout is chosen for a narrow area, and the area is not clamped.
        let narrow = try play(Self.undeclared, CGSize(width: 400, height: 1000))
        #expect(narrow.resolved.layout == "tall" && narrow.still(after: 0).size == CGSize(width: 640, height: 1600))
        #expect(try DocumentExplainer(document: Self.undeclared, problem: Self.problem).areaUse == nil)
    }

    @MainActor @Test func thePlayerExposesTheAreaItUsed() throws {
        let d = try DocumentExplainer(document: Self.declared, problem: Self.problem)
        let player = ExplainerPlayer(explainer: d, voice: SilentVoice(), drivesItself: false)
        #expect(player.areaUse == nil)
        player.layOut(for: CGSize(width: 400, height: 1000))
        #expect(player.areaUse?.isGiven == false && player.areaUse?.given == CGSize(width: 400, height: 1000))
        player.layOut(for: CGSize(width: 660, height: 760))
        #expect(player.areaUse?.isGiven == true)
    }

    @Test func theScreenSaysTheDrawingAreaItGives() {
        // The iPad space worked in the format's design: a column of 360, a drawing of about 810 square.
        let ipad = ExplainerScreen.drawingArea(for: CGSize(width: 1194, height: 834))
        #expect(ipad == CGSize(width: 1194 - 360 - 1.5 - 24, height: 810))
        // A phone in landscape scrolls and the drawing has the stage's shape.
        let phone = ExplainerScreen.drawingArea(for: CGSize(width: 800, height: 390))
        #expect(phone.map { abs($0.width / $0.height - 1000.0 / 540.0) < 1e-9 } == true)
        // Portrait depends on the heights of the controls, which the engine does not fix.
        #expect(ExplainerScreen.drawingArea(for: CGSize(width: 600, height: 900)) == nil)
    }
}
