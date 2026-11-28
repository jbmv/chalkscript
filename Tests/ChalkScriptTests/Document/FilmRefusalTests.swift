import Foundation
import Testing
@testable import ChalkScript

// What the player refuses only once a problem's values give the instances (EXP-19): the refusal
// names every place that fails, not the first only, so a document is mended in one round.

struct FilmRefusalTests {
    let tiny = DocumentFixture.tiny
    let problem = DocumentFixture.values(("a", 1))

    /// `tiny` with three numerals and the elements given, none of which the reader can fault.
    func document(_ extra: [String: String]) throws -> JSONValue {
        var doc = tiny.setting("/elements/nums", try JSONValue.parse(#"{"kind": "text", "at": [10, 40], "text": "label", "repeat": 3}"#))
        for (name, json) in extra { doc = doc.setting("/elements/" + name, try JSONValue.parse(json)) }
        return doc
    }

    func refusal(_ json: JSONValue) throws -> [DocumentFinding] {
        let reading = ExplainerDocument.read(json.data)
        let doc = try #require(reading.document)
        #expect(reading.findings.errors.isEmpty, "\(reading.findings)")
        do { _ = try DocumentExplainer(document: doc, problem: problem); return [] } catch { return error.findings }
    }

    @Test func everyInstanceThatFailsIsNamedInOneRefusal() throws {
        // Two arrows that start from three instances, and a third that is sound.
        let doc = try document([
            "up": #"{"kind": "arrow", "from": "nums", "to": [0, 50], "ink": "result"}"#,
            "down": #"{"kind": "arrow", "from": "nums", "to": [0, 90], "ink": "result"}"#,
            "ok": #"{"kind": "arrow", "from": [0, 0], "to": [0, 90], "ink": "result"}"#,
        ])
        let found = try refusal(doc)
        #expect(found.map(\.path) == ["/elements/down/from", "/elements/up/from"] || found.map(\.path) == ["/elements/up/from", "/elements/down/from"], "\(found)")
        #expect(found.allSatisfy { $0.message.contains("selects 3 instances, not one") && $0.values == problem })
    }

    @Test func everyActionThatFailsIsNamedInOneRefusal() throws {
        // A tint of a whole repeated element and a tint of one of its numerals, neither a run: the
        // target is not a bare element name, so the reader leaves both to the player.
        let tints = try document([:])
            .setting("/steps/show/actions/tintA", try JSONValue.parse(#"{"do": "tint", "target": "nums", "ink": "result"}"#))
            .setting("/steps/show/actions/tintB", try JSONValue.parse(#"{"do": "tint", "target": "nums[1]", "ink": "result"}"#))
        let found = try refusal(tints)
        #expect(found.map(\.path).sorted() == ["/steps/show/actions/tintA", "/steps/show/actions/tintB"], "\(found)")
        #expect(found.allSatisfy { $0.code == .capability })
    }

    @Test func aFaultInTheInstancesIsNamedBeforeAnythingThatNeedsThem() throws {
        // An arrow that starts from three instances, and a tint that cannot be told for the same
        // instances' sake: only the first is named, since the second depends on what was built.
        let doc = try document(["up": #"{"kind": "arrow", "from": "nums", "to": [0, 50], "ink": "result"}"#])
            .setting("/steps/show/actions/tintA", try JSONValue.parse(#"{"do": "tint", "target": "nums", "ink": "result"}"#))
        #expect(try refusal(doc).map(\.path) == ["/elements/up/from"])
    }

    @Test func aFaultAtOnePlaceIsNamedOnceHoweverManyInstancesShowIt() throws {
        // Three lines whose width is no number above 0 for any of them: one finding, at the element.
        let doc = try document(["thick": #"{"kind": "line", "from": [0, 0], "to": [9, 0], "repeat": 3, "width": "0 - i"}"#])
        let found = try refusal(doc)
        #expect(found.map(\.path) == ["/elements/thick/width"], "\(found)")
    }
}
