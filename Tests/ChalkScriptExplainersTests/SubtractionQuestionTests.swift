import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

/// EXP-17: subtraction gives its question inside the drawing, not apart from it.
@MainActor
struct SubtractionQuestionTests {
    @Test func subtractionGivesNoQuestionApart() {
        let subtraction = GuidedPlayer(
            lesson: SubtractionExplainer.lesson(watching: try! SubtractionProblem(54, minus: 26), wording: Fixture.guidedWording()),
            voice: RecordingVoice(), labels: Fixture.guidedLabels, drivesItself: false)
        #expect(subtraction.question == nil)
    }
}
