import Foundation
import Testing
@testable import ChalkScript

/// EXP-1: an approval is for one version of one explainer, and the version follows the steps and
/// the narration.
struct ApprovalFileTests {
    @Test func theFileStartsEmpty() throws {
        let empty = try ExplainerApprovals(yaml: "# none yet\napprovals: []\n")
        #expect(empty.entries.isEmpty)
        #expect(!empty.isApproved("subtraction", .child, version: "0123456789abcdef"))
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
        #expect(file.isApproved("subtraction", .child, version: "aaaaaaaaaaaaaaaa"))
        #expect(!file.isApproved("subtraction", .parent, version: "aaaaaaaaaaaaaaaa"))  // the other audience
        #expect(!file.isApproved("subtraction", .child, version: "cccccccccccccccc"))  // another version
        #expect(!file.isApproved("tens-ones-writing", .parent, version: "bbbbbbbbbbbbbbbb"))  // another explainer
        #expect(file.isApproved("tens-ones-reading", .parent, version: "bbbbbbbbbbbbbbbb"))
        #expect(file.entries[0].approvedOn == "2026-10-27" && file.entries[0].approvedBy == "reviewer")
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
