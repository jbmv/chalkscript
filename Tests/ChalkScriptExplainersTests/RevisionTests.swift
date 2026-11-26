import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

struct ExplainerIDTests {
    /// Every explainer the package draws has an id and says whether it has a parent version.
    @Test func everyExplainerHasAnIdAndSaysWhetherItHasAParentVersion() {
        #expect(ExplainerID.allCases.map(\.rawValue) == [
            "subtraction", "addition", "compare-tape", "compare-graph", "make-ten", "three-cards", "tens-ones-reading",
            "tens-ones-writing",
        ])
        #expect(ExplainerID.allCases.filter(\.hasParentVersion) == [.subtraction, .tensOnesReading, .tensOnesWriting])
    }
}

struct RevisionTests {
    @Test func aRevisionIsSixteenHexDigitsAndStable() {
        let r0 = SubtractionExplainer.currentRevision(.child, wording: Fixture.wording(.child))
        #expect(r0.count == 16 && r0.allSatisfy(\.isHexDigit))
        #expect(r0 == SubtractionExplainer.currentRevision(.child, wording: Fixture.wording(.child)))
    }

    @Test func eachAudienceHasItsOwnRevision() {
        let c = SubtractionExplainer.currentRevision(.child, wording: Fixture.wording(.child))
        let p = SubtractionExplainer.currentRevision(.parent, wording: Fixture.wording(.parent))
        #expect(c != p)
    }

    /// A change to the narration changes the revision.
    @Test func changedNarrationChangesTheRevision() {
        let base = Fixture.wording(.child)
        var changed = base
        changed.line = { l, p in
            var line = base.line(l, p)
            if l == .trade { line.display += " Wow." }
            return line
        }
        #expect(SubtractionExplainer.currentRevision(.child, wording: base) != SubtractionExplainer.currentRevision(.child, wording: changed))

        var spoken = base
        spoken.line = { l, p in
            var line = base.line(l, p)
            if l == .short { line.spoken = "different" }
            return line
        }
        #expect(SubtractionExplainer.currentRevision(.child, wording: base) != SubtractionExplainer.currentRevision(.child, wording: spoken))
    }

    /// A change to the steps changes the revision: here a step that comes out of the wording's
    /// lines (the trade's line gone) stands for a changed step list.
    @Test func changedStepsChangeTheRevision() throws {
        let w = Fixture.wording(.child)
        let a = try SubtractionExplainer(problem: SubtractionProblem(54, minus: 26), version: .child, wording: w)
        let b = try SubtractionExplainer(problem: SubtractionProblem(83, minus: 12), version: .child, wording: w)
        #expect(a.stepCount != b.stepCount)
        #expect(ExplainerFingerprint.of([a]) != ExplainerFingerprint.of([b]))
        #expect(ExplainerFingerprint.of([a], extra: ["x"]) != ExplainerFingerprint.of([a], extra: ["y"]))
    }

    @Test func theTensAndOnesExplainersHaveTheirOwnRevisions() throws {
        let w = PlaceValueFixture.wording(.child)
        let r = try #require(TensOnesExplainer.currentRevision(.tensOnesReading, .child, wording: w))
        let x = try #require(TensOnesExplainer.currentRevision(.tensOnesWriting, .child, wording: w))
        #expect(r != x)
        #expect(TensOnesExplainer.currentRevision(.subtraction, .child, wording: w) == nil)
        var changed = w
        changed.line = { l, q in
            var line = w.line(l, q)
            if case .answer = l { line.display += "!" }
            return line
        }
        #expect(TensOnesExplainer.currentRevision(.tensOnesReading, .child, wording: changed) != r)
    }
}
