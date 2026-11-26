import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

struct PencilPiecesTests {
    @Test func pencilPiecesAreNotColouredByPlace() {
        // EXP-6: a ten and a one on the worksheet are both pencil.
        let e = Fixture.explainer(54, 26)
        let worksheet = e.still(after: 0).visible.filter { $0.id.hasPrefix("ten.") || $0.id.hasPrefix("one.") }
        let styles = worksheet.compactMap { el -> PieceStyle? in
            switch el.kind {
            case let .ten(_, s), let .one(_, s): s
            default: nil
            }
        }
        #expect(styles.count == 9)
        #expect(Set(styles) == [.pencil])
    }
}
