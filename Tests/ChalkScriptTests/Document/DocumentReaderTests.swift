import Foundation
import Testing
@testable import ChalkScript

// Reading an explainer document (EXP-19, docs/format/explainer-1.0.md): each finding the
// reference defines for reading, with its code and JSON Pointer, and no trap on malformed input.

func has(
    _ r: DocumentReading, _ severity: DocumentFinding.Severity, _ code: DocumentFinding.Code, _ path: String, at: Int? = nil,
    _ text: String = "", sourceLocation: SourceLocation = #_sourceLocation
) {
    let hit = r.findings.contains {
        $0.severity == severity && $0.code == code && $0.path == path && (at == nil || $0.at == at) && (text.isEmpty || $0.message.contains(text))
    }
    #expect(hit, "no \(severity) \(code) at \(path)\(at.map { " @\($0)" } ?? "") '\(text)' in:\n\(r.findings.map(\.description).joined(separator: "\n"))",
            sourceLocation: sourceLocation)
}

struct DocumentReaderTests {
    let tiny = DocumentFixture.tiny

    @Test func theExamplesAndTheSmallDocumentReadWithNoFinding() {
        #expect(DocumentFixture.subtraction.findings.isEmpty, "\(DocumentFixture.subtraction.findings)")
        #expect(DocumentFixture.equalGroups.findings.isEmpty, "\(DocumentFixture.equalGroups.findings)")
        let r = read(tiny)
        #expect(r.conforms && r.findings.isEmpty, "\(r.findings)")
    }

    @Test func aTextThatIsNotADocumentIsRefused() {
        has(read("{"), .error, .json, "", "ends")
        has(read("[1, 2]"), .error, .json, "", "not an object")
        has(read(""), .error, .json, "")
        has(read("{\"a\": 1} x"), .error, .json, "", "after the JSON value")
        has(read("{\"a\": 01}"), .error, .json, "", "must not start with 0")
        has(read("{\"a\": \"\\ud800\"}"), .error, .json, "", "unpaired surrogate")
        has(read("{\"a\": \"tab\there\"}"), .error, .json, "", "control character")
        has(read("{\"a\": 1e999}"), .error, .json, "", "too large")
        has(ExplainerDocument.read(Data([0xEF, 0xBB, 0xBF]) + tiny.data), .error, .json, "", "byte order mark")
        has(ExplainerDocument.read(Data("{\"a\": \"".utf8) + Data([0xC3, 0x28]) + Data("\"}".utf8)), .error, .json, "", "UTF-8")
        let deep = String(repeating: "[", count: 10_000) + String(repeating: "]", count: 10_000)
        has(read(deep), .error, .json, "", "nested more than")
        // A duplicate key makes the document unreadable, at the object that has it.
        has(read(#"{"format": "chalkscript-explainer", "format": "chalkscript-explainer"}"#), .error, .json, "", "duplicate key \"format\"")
        has(read(#"{"params": {"a": {"type": "int", "type": "bool"}}}"#), .error, .json, "/params/a", "duplicate key")
        #expect(read("{").document == nil)
    }

    @Test func theFormatAndVersionAreChecked() {
        has(read(tiny.setting("/format", nil)), .error, .format, "/format", "missing")
        has(read(tiny.setting("/format", .string("explainer"))), .error, .format, "/format")
        has(read(tiny.setting("/version", .string("2.0"))), .error, .version, "/version", "not implemented")
        #expect(read(tiny.setting("/version", .string("2.0"))).document == nil)
        let newer = read(tiny.setting("/version", .string("1.3")))
        has(newer, .warning, .version, "/version", "newer")
        #expect(newer.conforms)
        has(read(tiny.setting("/version", .string("1"))), .error, .schema, "/version")
        has(read(tiny.setting("/version", .number(1))), .error, .schema, "/version")
    }

    @Test func unknownKeysAreWarnings() {
        let r = read(tiny.setting("/colour", .string("red")).setting("/steps/show/actions/in/speed", .number(2)))
        has(r, .warning, .unknown, "/colour")
        has(r, .warning, .unknown, "/steps/show/actions/in/speed")
        #expect(r.conforms)
        // Nothing under about or extensions is reported; an extension key is vendor.feature.
        #expect(read(tiny.setting("/about", .object(JSONObject([("anything", .number(1))])))).findings.isEmpty)
        #expect(read(tiny.setting("/extensions", .object(JSONObject([("acme.tool-2", .array([]))])))).findings.isEmpty)
        has(read(tiny.setting("/extensions", .object(JSONObject([("acme", .null)])))), .error, .schema, "/extensions/acme")
    }

    @Test func missingRequiredKeysAreErrors() {
        has(read(tiny.setting("/title", nil)), .error, .schema, "", "'title'")
        has(read(tiny.setting("/elements/label/at", nil)), .error, .schema, "/elements/label", "'at'")
        has(read(tiny.setting("/steps/show/actions/in/do", nil)), .error, .schema, "/steps/show/actions/in", "'do'")
        has(read(tiny.setting("/steps/show/say", nil)), .error, .schema, "/steps/show", "'say'")
        has(read(tiny.setting("/params/a/max", nil)), .error, .schema, "/params/a", "'max'")
        has(read(tiny.setting("/elements/arrow", try! JSONValue.parse(#"{"kind": "arrow", "from": [0, 0], "to": [1, 1]}"#))),
            .error, .schema, "/elements/arrow", "'ink'")
    }

    @Test func valuesOfTheWrongTypeAreErrors() {
        has(read(tiny.setting("/title", .number(5))), .error, .schema, "/title", "not a string")
        has(read(tiny.setting("/steps/show/hold", .bool(true))), .error, .schema, "/steps/show/hold", "not a number")
        has(read(tiny.setting("/steps/show/counts", .string("yes"))), .error, .schema, "/steps/show/counts")
        has(read(tiny.setting("/elements/label/at", .array([.number(1)]))), .error, .schema, "/elements/label/at", "point")
        has(read(tiny.setting("/steps/show/actions/in/target", .number(3))), .error, .schema, "/steps/show/actions/in/target", "selection")
        has(read(tiny.setting("/sequence", .array([]))), .error, .schema, "/sequence")
        has(read(tiny.setting("/samples", .object(JSONObject()))), .error, .schema, "/samples")
        has(read(tiny.setting("/params/a/type", .string("float"))), .error, .schema, "/params/a/type")
        has(read(tiny.setting("/id", .string("Tiny One"))), .error, .schema, "/id")
        has(read(tiny.setting("/elements/label/style", .string("huge"))), .error, .schema, "/elements/label/style")
        has(read(tiny.setting("/steps/show/actions/in/wait", .string("tap"))), .error, .schema, "/steps/show/actions/in/wait")
        has(read(tiny.setting("/wording/en-US/plain/show", .number(1))), .error, .schema, "/wording/en-US/plain/show")
        has(read(tiny.setting("/style", try! JSONValue.parse(#"{"palette": {"light": {"pencil": "grey"}}}"#))), .error, .schema, "/style/palette/light/pencil")
    }

    @Test func namesThatDoNotMatchTheirPatternAreErrors() {
        has(read(tiny.setting("/elements/Label", tiny["elements"]!["label"]!)), .error, .schema, "/elements/Label", "not a valid name")
        has(read(tiny.setting("/wording/en-US/plain/Show!", .string("x"))), .error, .schema, "/wording/en-US/plain/Show!", "not a valid entry name")
        // A reserved name, and one name in two places of the first namespace.
        has(read(tiny.setting("/let/i", .number(1))), .error, .schema, "/let/i", "reserved")
        has(read(tiny.setting("/let/a", .number(1))), .error, .schema, "/let/a", "already a name")
    }

    @Test func unknownVerbsKindsAndInputsAreErrors() {
        has(read(tiny.setting("/steps/show/actions/in/do", .string("explode"))), .error, .schema, "/steps/show/actions/in/do", "not a verb")
        has(read(tiny.setting("/elements/label/kind", .string("sprite"))), .error, .schema, "/elements/label/kind", "not an element kind")
        let act = try! JSONValue.parse(#"{"input": "voice", "targets": "label"}"#)
        has(read(tiny.setting("/steps/show/act", act)), .error, .schema, "/steps/show/act/input")
        // Instant verbs take no timing.
        has(read(tiny.setting("/steps/show/actions/say", try! JSONValue.parse(#"{"do": "say", "line": "show", "dur": 1}"#))),
            .warning, .unknown, "/steps/show/actions/say/dur")
    }

    @Test func referencesToNothingAreErrors() {
        has(read(tiny.setting("/sequence/1", .string("missing"))), .error, .ref, "/sequence/1", "no step 'missing'")
        has(read(tiny.setting("/steps/show/shot", .string("nowhere"))), .error, .ref, "/steps/show/shot", "no shot")
        has(read(tiny.setting("/opening", .string("nowhere"))), .error, .ref, "/opening")
        has(read(tiny.setting("/steps/show/say", .string("nothing"))), .error, .ref, "/steps/show/say", "no entry 'nothing'")
        has(read(tiny.setting("/steps/show/actions/draw/at", .string("end(out)"))), .error, .ref, "/steps/show/actions/draw/at", at: 4, "no action 'out'")
        has(read(tiny.setting("/steps/extra", try! JSONValue.parse(#"{"say": "show"}"#))), .error, .ref, "/steps/extra", "not in the sequence")
        has(read(tiny.setting("/steps/show/like", .string("other"))), .error, .ref, "/steps/show/like")
        has(read(tiny.setting("/shots", try! JSONValue.parse(#"{"close": {"frame": ["nopart"]}}"#))), .error, .ref, "/shots/close/frame/0")
        let act = try! JSONValue.parse(#"{"input": "tap", "targets": "label", "bind": "chosen", "begin": "fly", "then": "zoom", "done": ["in", "gone"]}"#)
        let r = read(tiny.setting("/steps/show/act", act))
        has(r, .error, .ref, "/steps/show/act/bind", "no vars value")
        has(r, .error, .ref, "/steps/show/act/begin")
        has(r, .error, .ref, "/steps/show/act/then")
        has(r, .error, .ref, "/steps/show/act/done/1")
        has(read(tiny.setting("/steps/show/actions/in/ease", .string("bouncy"))), .error, .ref, "/steps/show/actions/in/ease", "no curve")
        has(read(tiny.setting("/elements/label/ink", .string("glitter"))), .error, .ref, "/elements/label/ink", "no role")
        has(read(tiny.setting("/steps/show/actions/in/target", .string("label.zz"))), .error, .ref, "/steps/show/actions/in/target", at: 5, "no run 'zz'")
        has(read(tiny.setting("/plays", try! JSONValue.parse(#"{"paced": "fancy"}"#))), .error, .ref, "/plays/paced")
    }

    @Test func unmetCapabilitiesAreErrors() {
        has(read(tiny.setting("/requires", .array([.string("drawing.isometric")]))), .error, .capability, "/requires/0", "not implemented")
        // Used and not required: a piece, an operation role of the capability, and split().
        let piece = try! JSONValue.parse(#"{"kind": "ten", "rect": [0, 0, 22, 220]}"#)
        has(read(tiny.setting("/elements/stack", piece)), .error, .capability, "/elements/stack/kind", "components.arithmetic")
        has(read(tiny.setting("/elements/label/ink", .string("subtract"))), .error, .capability, "/elements/label/ink")
        // A player that does not implement the capability refuses the document that requires it.
        let r = ExplainerDocument.read(tiny.setting("/requires", .array([.string("components.arithmetic")])).data, capabilities: [])
        has(r, .error, .capability, "/requires/0")
        #expect(DocumentFixture.subtraction.conforms)
        has(ExplainerDocument.read(DocumentFixture.data("subtraction.explainer"), capabilities: []), .error, .capability, "/requires/0")
    }

    @Test func expressionsAreParsedAndTheirNamesChecked() {
        has(read(tiny.setting("/steps/show/actions/in/target", .string("lable"))), .error, .expr, "/steps/show/actions/in/target", at: 0,
            "unknown name 'lable' (did you mean 'label'?)")
        has(read(tiny.setting("/steps/show/hold", .string("1 +"))), .error, .expr, "/steps/show/hold", at: 3)
        has(read(tiny.setting("/steps/show/hold", .string("sqrt(2)"))), .error, .expr, "/steps/show/hold", at: 0, "unknown function")
        has(read(tiny.setting("/steps/show/hold", .string("max(2)"))), .error, .expr, "/steps/show/hold", at: 0, "takes 2 or more")
        has(read(tiny.setting("/steps/show/actions/in/target", .string("end(in)"))), .error, .expr, "/steps/show/actions/in/target", at: 0, "only in an action's at")
        has(read(tiny.setting("/let/x", .string("y + 1")).setting("/let/y", .string("x * 2"))), .error, .expr, "/let/x", "cycle")
        has(read(tiny.setting("/steps/show/actions/draw/at", .string("end(in)")).setting("/steps/show/actions/in/at", .string("start(draw)"))),
            .error, .expr, "/steps/show/actions/draw/at", "cycle")
        // A let must not name an element or a vars value, and an element's repeat must not name a vars value.
        has(read(tiny.setting("/let/x", .string("label"))), .error, .expr, "/let/x", at: 0, "element")
        let withVars = tiny.setting("/vars/v", .number(1))
        has(read(withVars.setting("/let/x", .string("v + 1"))), .error, .expr, "/let/x", at: 0, "vars value")
        has(read(withVars.setting("/elements/label/repeat", .string("v"))), .error, .expr, "/elements/label/repeat", "vars value")
        // A parameter's bounds name only parameters, without a cycle.
        has(read(tiny.setting("/params/a/max", .string("twice"))), .error, .expr, "/params/a/max", "only other parameters")
        let two = tiny.setting("/params/b", try! JSONValue.parse(#"{"type": "int", "min": "a", "max": 9}"#)).setting("/params/a/max", .string("b"))
        has(read(two), .error, .expr, "/params/a", "cycle")
        // i is a local only where an instance is being placed.
        has(read(tiny.setting("/steps/show/hold", .string("i"))), .error, .expr, "/steps/show/hold", "not in scope")
        #expect(read(tiny.setting("/elements/label/repeat", .number(3)).setting("/elements/label/at/0", .string("10 + i * 20"))).conforms)
    }

    @Test func wordingIsChecked() {
        has(read(tiny.setting("/wording/en-US/plain/show", .string("This is 5."))), .error, .wording, "/wording/en-US/plain/show", at: 8, "numeral")
        has(read(tiny.setting("/wording/en-US/plain/show", .string("Count by {a}s."))), .error, .wording, "/wording/en-US/plain/show", at: 12,
            "spoken form cannot be derived")
        has(read(tiny.setting("/wording/en-US/plain/label", .string("x"))), .error, .wording, "/wording/en-US/plain/label", "both shared and plain")
        has(read(tiny.setting("/wording/en-US/plain/show", .string("This is {zz}."))), .error, .wording, "/wording/en-US/plain/show", at: 8, "cannot be filled")
        has(read(tiny.setting("/wording/en-US/plain/show", .string("This is {label}."))), .error, .wording, "/wording/en-US/plain/show", at: 8, "element")
        has(read(tiny.setting("/wording/en-US/plain/show", .string("This is {a."))), .error, .wording, "/wording/en-US/plain/show", at: 8, "not closed")
        has(read(tiny.setting("/wording/en-US/plain/show", .string("We have {tens:a}."))), .error, .ref, "/wording/en-US/plain/show", at: 8, "no phrase")
        has(read(tiny.setting("/wording/en-US/plain/show", try! JSONValue.parse(#"{"text": "{a}", "forms": {"other": "{n}"}}"#))),
            .error, .schema, "/wording/en-US/plain/show", "exactly one")
        has(read(tiny.setting("/wording/en-US/plain/show", try! JSONValue.parse(#"{"forms": {"one": "{n}"}}"#))),
            .error, .schema, "/wording/en-US/plain/show/forms", "'other'")
        has(read(tiny.setting("/wording/en-US/plain/show", try! JSONValue.parse(#"{"text": "{a}!", "emphasis": "b"}"#))),
            .error, .wording, "/wording/en-US/plain/show/emphasis")
        // A visual entry is never said, so a number may stand next to a letter in it.
        #expect(read(tiny.setting("/wording/en-US/shared/label", try! JSONValue.parse(#"{"text": "{a}x", "visual": true}"#))).conforms)
    }

    @Test func aWordingMayLackWhatOnlyInteractionNeeds() throws {
        // The formal wordings carry only the watched part's lines: that is listed, not a finding.
        let d = DocumentFixture.subtraction
        let formal = try #require(d.coverage.first { $0.wording == "formal" })
        #expect(formal.playable == [.watch])
        #expect(formal.missing[.guided]?.contains("do.trade") == true && formal.missing[.tryOne]?.contains("do.tryNote") == true)
        let everyday = try #require(d.coverage.first { $0.wording == "everyday" })
        #expect(everyday.playable == [.watch, .guided, .tryOne] && everyday.missing.isEmpty)
    }

    @Test func translationsAreCheckedAgainstTheirSource() throws {
        let source = try #require(tiny["wording"]?["en-US"]?["plain"]?["show"])
        let of = String(Canonical.hash(source).prefix(8))
        let shared = try JSONValue.parse(#"{"label": {"text": "{a}", "visual": true, "of": "\#(String(Canonical.hash(tiny["wording"]!["en-US"]!["shared"]!["label"]!).prefix(8)))"}}"#)
        let es = JSONValue.object(JSONObject([
            ("shared", shared),
            ("plain", .object(JSONObject([("show", .object(JSONObject([("text", .string("Esto es {a}, y el doble es {twice}.")), ("of", .string(of))])))]))),
        ]))
        let good = read(tiny.setting("/wording/es", es))
        #expect(good.conforms && good.findings.isEmpty, "\(good.findings)")
        let stale = read(tiny.setting("/wording/es", es).setting("/wording/en-US/plain/show", .string("Here is {a}, and twice it is {twice}.")))
        has(stale, .warning, .wording, "/wording/es/plain/show/of", "changed since")
        let missing = read(tiny.setting("/wording/es", es.setting("/plain/show", nil)))
        has(missing, .warning, .wording, "/wording/es/plain", "no translation of show")
        let extra = read(tiny.setting("/wording/es", es.setting("/plain/more", .object(JSONObject([("text", .string("Más.")), ("of", .string("00000000"))])))))
        has(extra, .warning, .wording, "/wording/es/plain/more", "no entry in en-US")
    }

    @Test func samplesAreProblemsWithinTheParameters() {
        let r = read(tiny.setting("/samples/1", .object(JSONObject([("a", .number(9))]))))
        has(r, .error, .range, "/samples/1/a", "above its max 3")
        #expect(r.findings.first { $0.code == .range }?.values == ["a": .number(9)])
        has(read(tiny.setting("/samples/1", .object(JSONObject([("b", .number(1))])))), .error, .range, "/samples/1", "no value for 'a'")
        has(read(tiny.setting("/samples/1", .object(JSONObject([("a", .number(1))])))), .error, .schema, "/samples/1", "twice")
    }

    @Test func findingsAreWrittenOnOneLine() {
        let r = read(tiny.setting("/steps/show/actions/in/target", .string("lable")))
        let f = r.findings.first { $0.code == .expr }
        #expect(f?.description == "error expr /steps/show/actions/in/target @0: unknown name 'lable' (did you mean 'label'?)")
        let e = DocumentFinding(.error, .eval, "/steps/takeTens/actions/cross/target", values: ["a": .number(20), "b": .number(11)], time: 1.5, "ten[2] is outside ten")
        #expect(e.description == "error eval /steps/takeTens/actions/cross/target {a: 20, b: 11} t=1.5: ten[2] is outside ten")
    }

    /// Every value of the examples replaced, in turn, by each of a set of wrong values; and the
    /// files themselves cut and changed byte by byte. Each is read, and resolved when it conforms.
    @Test func malformedInputNeverTraps() {
        let replacements: [JSONValue?] = [nil, .null, .bool(true), .number(-1), .number(1e300), .string(""), .string("(("), .string("ten"), .array([]), .object(JSONObject())]
        var read = 0
        var conformed = 0
        for doc in [DocumentFixture.equalGroups.json, DocumentFixture.subtraction.json] {
            for (k, p) in doc.pointers.enumerated() where !p.isEmpty && (doc == DocumentFixture.equalGroups.json || k % 3 == 0) {
                for v in replacements {
                    let changed = doc.setting(p, v)
                    let r = ExplainerDocument.read(changed.data)
                    read += 1
                    guard let d = r.document, r.conforms else { continue }
                    conformed += 1
                    for s in d.samples.prefix(2) { _ = try? d.resolve(problem: s, area: CGSize(width: 660, height: 760)) }
                }
            }
        }
        var rng = SplitMix(seed: 19)
        let bytes = Array(DocumentFixture.data("equal-groups.explainer"))
        for _ in 0..<1500 {
            var b = bytes
            switch rng.next() % 4 {
            case 0: b[Int(rng.next() % UInt64(b.count))] = UInt8(truncatingIfNeeded: rng.next())
            case 1: b = Array(b.prefix(Int(rng.next() % UInt64(b.count))))
            case 2:
                let i = Int(rng.next() % UInt64(b.count))
                b.removeSubrange(i..<min(b.count, i + Int(rng.next() % 40)))
            default:
                let i = Int(rng.next() % UInt64(b.count))
                b.insert(contentsOf: b[i..<min(b.count, i + Int(rng.next() % 40))], at: Int(rng.next() % UInt64(b.count)))
            }
            let r = ExplainerDocument.read(Data(b))
            read += 1
            if let d = r.document, r.conforms {
                conformed += 1
                for s in d.samples.prefix(2) { _ = try? d.resolve(problem: s) }
            }
        }
        #expect(read > 3000 && conformed > 0)
    }
}

/// A small deterministic random number generator, so that the malformed inputs are the same on
/// every run.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
