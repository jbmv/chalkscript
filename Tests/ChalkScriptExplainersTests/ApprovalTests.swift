import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

struct ExplainerIDTests {
    /// Every explainer the package draws has an id and says whether it has a parent version.
    @Test func everyExplainerHasAnIdAndSaysWhetherItHasAParentVersion() throws {
        #expect(ExplainerID.allCases.map(\.rawValue) == [
            "subtraction", "addition", "compare-tape", "compare-graph", "make-ten", "three-cards", "tens-ones-reading",
            "tens-ones-writing",
        ])
        #expect(ExplainerID.allCases.filter(\.hasParentVersion) == [.subtraction, .tensOnesReading, .tensOnesWriting])
        let file = try ExplainerApprovals(yaml: """
            approvals:
              - explainer: make-ten
                audience: child
                version: aaaaaaaaaaaaaaaa
                approved-by: reviewer
                approved-on: 2026-11-16
            """)
        #expect(file.isApproved(.makeTen, .child, version: "aaaaaaaaaaaaaaaa"))
        #expect(!file.isApproved(.addition, .child, version: "aaaaaaaaaaaaaaaa"))
    }
}

struct VersionTests {
    @Test func aVersionIsSixteenHexDigitsAndStable() {
        let v = SubtractionExplainer.currentVersion(.child, wording: Fixture.wording(.child))
        #expect(v.count == 16 && v.allSatisfy(\.isHexDigit))
        #expect(v == SubtractionExplainer.currentVersion(.child, wording: Fixture.wording(.child)))
    }

    @Test func eachAudienceHasItsOwnVersion() {
        let c = SubtractionExplainer.currentVersion(.child, wording: Fixture.wording(.child))
        let p = SubtractionExplainer.currentVersion(.parent, wording: Fixture.wording(.parent))
        #expect(c != p)
    }

    /// A change to the narration changes the version.
    @Test func changedNarrationChangesTheVersion() {
        let base = Fixture.wording(.child)
        var changed = base
        changed.line = { l, p in
            var line = base.line(l, p)
            if l == .trade { line.display += " Wow." }
            return line
        }
        #expect(SubtractionExplainer.currentVersion(.child, wording: base) != SubtractionExplainer.currentVersion(.child, wording: changed))

        var spoken = base
        spoken.line = { l, p in
            var line = base.line(l, p)
            if l == .short { line.spoken = "different" }
            return line
        }
        #expect(SubtractionExplainer.currentVersion(.child, wording: base) != SubtractionExplainer.currentVersion(.child, wording: spoken))
    }

    /// A change to the steps changes the version: here a step that comes out of the wording's
    /// lines (the trade's line gone) stands for a changed step list.
    @Test func changedStepsChangeTheVersion() throws {
        let w = Fixture.wording(.child)
        let a = try SubtractionExplainer(problem: SubtractionProblem(54, minus: 26), version: .child, wording: w)
        let b = try SubtractionExplainer(problem: SubtractionProblem(83, minus: 12), version: .child, wording: w)
        #expect(a.stepCount != b.stepCount)
        #expect(ExplainerFingerprint.of([a]) != ExplainerFingerprint.of([b]))
        #expect(ExplainerFingerprint.of([a], extra: ["x"]) != ExplainerFingerprint.of([a], extra: ["y"]))
    }

    @Test func theTensAndOnesExplainersHaveTheirOwnVersions() throws {
        let w = PlaceValueFixture.wording(.child)
        let r = try #require(TensOnesExplainer.currentVersion(.tensOnesReading, .child, wording: w))
        let x = try #require(TensOnesExplainer.currentVersion(.tensOnesWriting, .child, wording: w))
        #expect(r != x)
        #expect(TensOnesExplainer.currentVersion(.subtraction, .child, wording: w) == nil)
        var changed = w
        changed.line = { l, q in
            var line = w.line(l, q)
            if case .answer = l { line.display += "!" }
            return line
        }
        #expect(TensOnesExplainer.currentVersion(.tensOnesReading, .child, wording: changed) != r)
    }
}
