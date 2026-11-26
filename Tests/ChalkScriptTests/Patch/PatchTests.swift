import Foundation
import Testing
@testable import ChalkScript

// Patching a document (EXP-19, section 20 of the format's reference): the operations of RFC 6902,
// the base hash, atomicity, the protected paths, and the reply the helper protocol needs.

private func ops(_ text: String) -> [JSONValue] { (try! JSONValue.parse(text)).array! }

private let tiny = ExplainerDocument.read(DocumentFixture.tiny.data).document!

/// Applies one operation to a plain value, for the operations' own semantics.
private func run(_ doc: String, _ op: String) throws -> JSONValue {
    try JSONPatch.apply(try JSONValue.parse(op), to: try JSONValue.parse(doc))
}

private func fails(_ doc: String, _ op: String) -> Bool {
    do { _ = try run(doc, op); return false } catch { return true }
}

struct JSONPatchTests {
    @Test func addSetsAMemberAndInsertsIntoAnArray() throws {
        #expect(try run(#"{"a":1}"#, #"{"op":"add","path":"/b","value":2}"#) == JSONValue.parse(#"{"a":1,"b":2}"#))
        #expect(try run(#"{"a":1}"#, #"{"op":"add","path":"/a","value":2}"#) == JSONValue.parse(#"{"a":2}"#))
        #expect(try run(#"{"a":[1,3]}"#, #"{"op":"add","path":"/a/1","value":2}"#) == JSONValue.parse(#"{"a":[1,2,3]}"#))
        #expect(try run(#"{"a":[1]}"#, #"{"op":"add","path":"/a/1","value":2}"#) == JSONValue.parse(#"{"a":[1,2]}"#))
        #expect(try run(#"{"a":[1]}"#, #"{"op":"add","path":"/a/-","value":2}"#) == JSONValue.parse(#"{"a":[1,2]}"#))
        #expect(try run(#"{"a":1}"#, #"{"op":"add","path":"/n","value":null}"#) == JSONValue.parse(#"{"a":1,"n":null}"#))
    }

    @Test func addKeepsAnExistingMembersPlace() throws {
        let v = try run(#"{"a":1,"b":2}"#, #"{"op":"add","path":"/a","value":9}"#)
        #expect(v.object?.keys == ["a", "b"])
    }

    @Test func removeDeletesAMemberOrAnElement() throws {
        #expect(try run(#"{"a":1,"b":2}"#, #"{"op":"remove","path":"/a"}"#) == JSONValue.parse(#"{"b":2}"#))
        #expect(try run(#"{"a":[1,2,3]}"#, #"{"op":"remove","path":"/a/1"}"#) == JSONValue.parse(#"{"a":[1,3]}"#))
    }

    @Test func replaceNeedsSomethingToReplace() throws {
        #expect(try run(#"{"a":1}"#, #"{"op":"replace","path":"/a","value":[2]}"#) == JSONValue.parse(#"{"a":[2]}"#))
        #expect(try run(#"{"a":[1,2]}"#, #"{"op":"replace","path":"/a/1","value":5}"#) == JSONValue.parse(#"{"a":[1,5]}"#))
        #expect(fails(#"{"a":1}"#, #"{"op":"replace","path":"/b","value":2}"#))
        #expect(fails(#"{"a":[1]}"#, #"{"op":"replace","path":"/a/1","value":2}"#))
        #expect(fails(#"{"a":[1]}"#, #"{"op":"replace","path":"/a/-","value":2}"#))
    }

    @Test func moveRemovesThenAdds() throws {
        #expect(try run(#"{"a":1,"b":{}}"#, #"{"op":"move","from":"/a","path":"/b/c"}"#) == JSONValue.parse(#"{"b":{"c":1}}"#))
        #expect(try run(#"{"a":[1,2,3]}"#, #"{"op":"move","from":"/a/0","path":"/a/2"}"#) == JSONValue.parse(#"{"a":[2,3,1]}"#))
        #expect(try run(#"{"a":1}"#, #"{"op":"move","from":"/a","path":"/a"}"#) == JSONValue.parse(#"{"a":1}"#))
        #expect(fails(#"{"a":{"b":1}}"#, #"{"op":"move","from":"/a","path":"/a/c"}"#))
        #expect(fails(#"{"a":1}"#, #"{"op":"move","from":"/x","path":"/y"}"#))
    }

    @Test func copyLeavesTheSourceInPlace() throws {
        #expect(try run(#"{"a":{"b":1}}"#, #"{"op":"copy","from":"/a","path":"/c"}"#) == JSONValue.parse(#"{"a":{"b":1},"c":{"b":1}}"#))
        #expect(fails(#"{"a":1}"#, #"{"op":"copy","from":"/x","path":"/y"}"#))
    }

    @Test func testComparesValues() throws {
        #expect(try run(#"{"a":{"x":1,"y":[2]}}"#, #"{"op":"test","path":"/a","value":{"y":[2],"x":1}}"#) == JSONValue.parse(#"{"a":{"x":1,"y":[2]}}"#))
        #expect(fails(#"{"a":1}"#, #"{"op":"test","path":"/a","value":2}"#))
        #expect(fails(#"{"a":1}"#, #"{"op":"test","path":"/b","value":1}"#))
        #expect(fails(#"{"a":1}"#, #"{"op":"test","path":"/a","value":"1"}"#))
    }

    @Test func pointersEscapeSlashAndTilde() throws {
        let doc = #"{"a/b":1,"m~n":2,"~1":3}"#
        #expect(try run(doc, #"{"op":"replace","path":"/a~1b","value":9}"#) == JSONValue.parse(#"{"a/b":9,"m~n":2,"~1":3}"#))
        #expect(try run(doc, #"{"op":"replace","path":"/m~0n","value":9}"#) == JSONValue.parse(#"{"a/b":1,"m~n":9,"~1":3}"#))
        #expect(try run(doc, #"{"op":"replace","path":"/~01","value":9}"#) == JSONValue.parse(#"{"a/b":1,"m~n":2,"~1":9}"#))
        #expect(fails(doc, #"{"op":"replace","path":"/m~2n","value":9}"#))
        #expect(fails(doc, #"{"op":"replace","path":"/m~","value":9}"#))
        #expect(try run(#"{"":1}"#, #"{"op":"replace","path":"/","value":2}"#) == JSONValue.parse(#"{"":2}"#))
    }

    @Test func arrayIndicesAreStrict() {
        #expect(fails(#"{"a":[1,2]}"#, #"{"op":"remove","path":"/a/01"}"#))
        #expect(fails(#"{"a":[1,2]}"#, #"{"op":"remove","path":"/a/-1"}"#))
        #expect(fails(#"{"a":[1,2]}"#, #"{"op":"remove","path":"/a/+1"}"#))
        #expect(fails(#"{"a":[1,2]}"#, #"{"op":"remove","path":"/a/-"}"#))
        #expect(fails(#"{"a":[1,2]}"#, #"{"op":"remove","path":"/a/2"}"#))
        #expect(fails(#"{"a":[1,2]}"#, #"{"op":"add","path":"/a/3","value":0}"#))
        #expect(fails(#"{"a":[1,2]}"#, #"{"op":"add","path":"/a/x","value":0}"#))
        #expect(fails(#"{"a":[1,2]}"#, #"{"op":"add","path":"/a/-/b","value":0}"#))
    }

    @Test func badOperationsAreRefused() {
        #expect(fails("{}", #"{"op":"add","path":"/a"}"#))
        #expect(fails("{}", #"{"op":"move","path":"/a"}"#))
        #expect(fails("{}", #"{"op":"flip","path":"/a"}"#))
        #expect(fails("{}", #"{"path":"/a","value":1}"#))
        #expect(fails("{}", #"{"op":"add","value":1}"#))
        #expect(fails("{}", #"{"op":"add","path":"a","value":1}"#))
        #expect(fails("{}", "3"))
        #expect(fails(#"{"a":1}"#, #"{"op":"add","path":"/a/b","value":1}"#))
        #expect(fails(#"{"a":1}"#, #"{"op":"add","path":"/x/y","value":1}"#))
    }
}

struct DocumentPatchTests {
    let base = tiny.shortHash

    @Test func anAcceptedPatchGivesTheNewDocumentItsHashAndTheCounts() throws {
        let r = tiny.patch(base: base, ops: ops(#"[{"op":"replace","path":"/params/a/max","value":9}]"#))
        #expect(r.applied)
        #expect(r.document.json.value(at: "/params/a/max") == .number(9))
        #expect(r.hash == r.document.shortHash && r.hash != base)
        #expect(r.errors == 0 && r.warnings == 0 && r.findings.isEmpty)
        #expect(tiny.json.value(at: "/params/a/max") == .number(3))
    }

    @Test func theReplyIsBuiltFromTheResult() throws {
        let r = tiny.patch(base: base, ops: ops(#"[{"op":"replace","path":"/params/a/max","value":9}]"#))
        #expect(r.reply == (try JSONValue.parse(#"{"applied":true,"hash":"\#(r.hash)","errors":0,"warnings":0}"#)))
        let stale = tiny.patch(base: "000000000000", ops: [])
        let reply = try #require(stale.reply.object)
        #expect(reply["applied"] == .bool(false) && reply["hash"] == .string(base) && reply["errors"] == .number(1) && reply["warnings"] == .number(0))
        let finding = try #require(reply["findings"]?.array?.first?.object)
        #expect(finding["severity"] == .string("error") && finding["code"] == .string("patch") && finding["path"] == .string(""))
        #expect(finding["message"]?.string?.contains(base) == true)
    }

    @Test func anAcceptedPatchWithAWarningKeepsItAndCountsIt() throws {
        let r = tiny.patch(base: base, ops: ops(#"[{"op":"add","path":"/extra","value":1}]"#))
        #expect(r.applied && r.errors == 0 && r.warnings == 1)
        #expect(r.findings.count == 1 && r.findings[0].code == .unknown && r.findings[0].path == "/extra")
        #expect(r.reply.object?["findings"]?.array?.count == 1)
    }

    @Test func aStaleBaseIsRefusedWithTheCurrentHash() {
        let r = tiny.patch(base: "0123456789ab", ops: ops(#"[{"op":"replace","path":"/title","value":"New"}]"#))
        #expect(!r.applied && r.hash == base && r.document.json == tiny.json)
        #expect(r.findings.count == 1 && r.findings[0].code == .patch && r.findings[0].message.contains(base))
    }

    @Test func aPatchAfterAPatchNeedsTheNewHash() throws {
        let first = tiny.patch(base: base, ops: ops(#"[{"op":"replace","path":"/title","value":"New"}]"#))
        #expect(first.applied)
        let again = first.document.patch(base: base, ops: ops(#"[{"op":"replace","path":"/title","value":"Newer"}]"#))
        #expect(!again.applied && again.hash == first.hash)
        #expect(first.document.patch(base: first.hash, ops: ops(#"[{"op":"replace","path":"/title","value":"Newer"}]"#)).applied)
    }

    @Test func aFailedOperationRefusesTheWholePatchAndNamesItsIndexAndPointer() throws {
        let r = tiny.patch(base: base, ops: ops(#"""
            [{"op":"replace","path":"/title","value":"New"},
             {"op":"test","path":"/id","value":"other"},
             {"op":"replace","path":"/params/a/max","value":9}]
            """#))
        #expect(!r.applied && r.document.json == tiny.json && r.hash == base)
        let f = try #require(r.findings.first)
        #expect(r.findings.count == 1 && f.code == .patch && f.severity == .error && f.path == "/id")
        #expect(f.message.contains("operation 1") && f.message.contains("/id"))
        #expect(r.errors == 1)
    }

    @Test func aResultWithAnErrorIsRefusedWithTheReadersFindings() throws {
        let r = tiny.patch(base: base, ops: ops(#"[{"op":"replace","path":"/elements/rule/from","value":["nowhere", 0]}]"#))
        #expect(!r.applied && r.document.json == tiny.json && r.hash == base)
        #expect(r.errors >= 1 && r.findings.hasErrors)
        #expect(r.findings.allSatisfy { $0.code != .patch })
    }

    @Test func aResultThatIsNotADocumentIsRefused() {
        let r = tiny.patch(base: base, ops: ops(#"[{"op":"remove","path":"/steps"}]"#))
        #expect(!r.applied && r.errors >= 1)
    }

    @Test(arguments: [
        #"{"op":"remove","path":"/format"}"#, #"{"op":"replace","path":"/format","value":"x"}"#,
        #"{"op":"replace","path":"/version","value":"1.1"}"#, #"{"op":"add","path":"/version","value":"1.1"}"#,
        #"{"op":"test","path":"/version","value":"1.0"}"#, #"{"op":"replace","path":"","value":{}}"#,
        #"{"op":"move","from":"/title","path":"/version"}"#, #"{"op":"move","from":"/format","path":"/x"}"#,
        #"{"op":"copy","from":"/version","path":"/x"}"#, #"{"op":"copy","from":"","path":"/x"}"#,
    ])
    func theProtectedPathsCannotBePatched(_ op: String) throws {
        let r = tiny.patch(base: base, ops: ops("[\(op)]"))
        #expect(!r.applied && r.hash == base && r.document.json == tiny.json)
        #expect(r.findings.count == 1 && r.findings[0].code == .patch && r.findings[0].message.contains("operation 0"))
    }

    @Test func anEmptyPatchAppliesAndLeavesTheHash() {
        let r = tiny.patch(base: base, ops: [])
        #expect(r.applied && r.hash == base)
    }

    @Test func anyOperationOfAFailingPatchLeavesNothingChanged() {
        for bad in [#"{"op":"remove","path":"/nope"}"#, #"{"op":"nonsense","path":"/title"}"#, "5"] {
            let r = tiny.patch(base: base, ops: ops(#"[{"op":"replace","path":"/title","value":"New"},"# + bad + "]"))
            #expect(!r.applied && r.document.json == tiny.json)
            #expect(r.findings.first?.message.contains("operation 1") == true)
        }
    }

    @Test func thePatchedDocumentKeepsTheAuthorsKeyOrder() throws {
        let r = tiny.patch(base: base, ops: ops(#"[{"op":"replace","path":"/title","value":"New"}]"#))
        #expect(r.document.json.object?.keys == tiny.json.object?.keys)
    }

    // MARK: the example documents

    @Test func changingADurationChangesTheResolvedStepDuration() throws {
        let sub = DocumentFixture.subtraction
        let p = DocumentFixture.values(("a", 54), ("b", 26))
        let before = try sub.resolve(problem: p, wording: "everyday")
        let step = try #require(before.steps.first { $0.name == "takeOnes" })
        let r = sub.patch(base: sub.shortHash, ops: ops(#"[{"op":"replace","path":"/steps/takeOnes/hold","value":0.5}]"#))
        #expect(r.applied)
        let after = try r.document.resolve(problem: p, wording: "everyday")
        let changed = try #require(after.steps.first { $0.name == "takeOnes" })
        #expect(close(changed.hold, 0.5) && close(changed.duration, step.duration - step.hold + 0.5))
        #expect(zip(before.steps, after.steps).filter { $0.0.name != "takeOnes" }.allSatisfy { close($0.0.duration, $0.1.duration) })

        let eq = DocumentFixture.equalGroups
        let q = DocumentFixture.values(("a", 3), ("b", 4))
        let was = try #require(try eq.resolve(problem: q, wording: "everyday").steps.first { $0.name == "groups" })
        let e = eq.patch(base: eq.shortHash, ops: ops(#"[{"op":"replace","path":"/steps/groups/hold","value":0.9}]"#))
        #expect(e.applied)
        let now = try #require(try e.document.resolve(problem: q, wording: "everyday").steps.first { $0.name == "groups" })
        #expect(close(now.duration, was.duration + 0.5))
    }

    @Test func changingALineChangesTheFilledLine() throws {
        let sub = DocumentFixture.subtraction
        let p = DocumentFixture.values(("a", 54), ("b", 26))
        let r = sub.patch(base: sub.shortHash, ops: ops(#"[{"op":"replace","path":"/wording/en-US/everyday/takeOnes","value":"Cross out {ones:bO} now."}]"#))
        #expect(r.applied)
        let before = try #require(try sub.resolve(problem: p, wording: "everyday").steps.first { $0.name == "takeOnes" })
        let after = try #require(try r.document.resolve(problem: p, wording: "everyday").steps.first { $0.name == "takeOnes" })
        #expect(before.line.shown == "Cross out 6 ones.")
        #expect(after.line.shown == "Cross out 6 ones now.")

        let eq = DocumentFixture.equalGroups
        let e = eq.patch(base: eq.shortHash, ops: ops(#"[{"op":"replace","path":"/wording/en-US/everyday/same","value":"Every group has {b}."}]"#))
        #expect(e.applied)
        let line = try #require(try e.document.resolve(problem: DocumentFixture.values(("a", 3), ("b", 4)), wording: "everyday").steps.first { $0.name == "same" })
        #expect(line.line.shown == "Every group has 4.")
    }
}
