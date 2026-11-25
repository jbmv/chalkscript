import Foundation
import Testing
@testable import ChalkScript

/// EXP-1: an approval is for one version of one explainer, and the version follows the steps and
/// the narration.
struct ApprovalFileTests {
    @Test func theFileStartsEmpty() throws {
        let empty = try ExplainerApprovals(yaml: "# none yet\napprovals: []\n")
        #expect(empty.entries.isEmpty)
        #expect(!empty.isApproved(.subtraction, .child, version: "0123456789abcdef"))
    }

    @Test func entriesAreReadPerExplainerAndAudience() throws {
        let file = try ExplainerApprovals(yaml: """
            approvals:
              - explainer: subtraction
                audience: child
                version: aaaaaaaaaaaaaaaa
                approved-by: reviewer
                approved-on: 2026-10-27   # a day
              - explainer: tens-ones-reading
                audience: parent
                version: "bbbbbbbbbbbbbbbb"
                approved-by: reviewer
                approved-on: 2026-10-28
            """)
        #expect(file.entries.count == 2)
        #expect(file.isApproved(.subtraction, .child, version: "aaaaaaaaaaaaaaaa"))
        #expect(!file.isApproved(.subtraction, .parent, version: "aaaaaaaaaaaaaaaa"))  // the other audience
        #expect(!file.isApproved(.subtraction, .child, version: "cccccccccccccccc"))  // another version
        #expect(!file.isApproved(.tensOnesWriting, .parent, version: "bbbbbbbbbbbbbbbb"))  // another explainer
        #expect(file.isApproved(.tensOnesReading, .parent, version: "bbbbbbbbbbbbbbbb"))
        #expect(file.entries[0].approvedOn == "2026-10-27" && file.entries[0].approvedBy == "reviewer")
    }

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

    @Test func aBadFileIsRefusedRatherThanReadAsEmpty() {
        #expect(throws: ExplainerApprovals.ParseError.notAnApprovalsFile) { try ExplainerApprovals(yaml: "") }
        #expect(throws: ExplainerApprovals.ParseError.notAnApprovalsFile) { try ExplainerApprovals(yaml: "other: 1") }
        #expect(throws: ExplainerApprovals.ParseError.incomplete(entry: 1, missing: "approved-on")) {
            try ExplainerApprovals(yaml: "approvals:\n  - explainer: subtraction\n    audience: child\n    version: a\n    approved-by: x\n")
        }
        #expect(throws: ExplainerApprovals.ParseError.incomplete(entry: 1, missing: "audience")) {
            try ExplainerApprovals(yaml: "approvals:\n  - explainer: subtraction\n    audience: kid\n    version: a\n    approved-by: x\n    approved-on: y\n")
        }
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
