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
        #expect(DocumentFixture.subtraction.profileID == "maths" && DocumentFixture.equalGroups.profileID == "maths")
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

    // A document that conforms but asks for what the player does not draw is refused by the
    // player, not found by the reader (section 2.3), so one refusal names one fault at a time.
    @Test func aDocumentWithThreeColourFaultsIsRefusedOneStageAtATime() {
        let faults = tiny
            .setting("/elements/sum", try! JSONValue.parse(#"{"kind": "text", "at": [10, 60], "text": "label", "style": "total", "ink": "text"}"#))
            .setting("/elements/go", try! JSONValue.parse(#"{"kind": "arrow", "from": [0, 0], "to": [0, 50], "ink": "add.ink"}"#))
        let problem = DocumentFixture.values(("a", 1))
        func refusal(_ json: JSONValue) -> [String] {
            let doc = ExplainerDocument.read(json.data).document!
            do { _ = try DocumentExplainer(document: doc, problem: problem); return [] } catch { return error.findings.map(\.description) }
        }
        // The reader checks every element in one pass and finds the one fault that is its own.
        let r = read(faults)
        #expect(r.findings.map(\.description) == [
            "error capability /elements/go/ink: this uses the capability 'components.arithmetic', which requires does not list"
        ])
        #expect(refusal(faults) == r.findings.map(\.description))
        // With the capability required, the document reads without a finding. The player's
        // refusals are then its own, and the film stops at the first it meets.
        let required = faults.setting("/requires", .array([.string("components.arithmetic")]))
        #expect(read(required).findings.isEmpty)
        #expect(refusal(required) == [
            "error capability /elements/go/ink {a: 1}: this player draws a arrow only in an operation role or a colour of the document's named alone, not 'add.ink'"
        ])
        let arrowMended = required.setting("/elements/go/ink", .string("add"))
        #expect(refusal(arrowMended) == [
            "error capability /elements/sum {a: 1}: this player draws a total centred and in the result role only"
        ])
        #expect(refusal(arrowMended.setting("/elements/sum/ink", .string("result"))).isEmpty)
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

    @Test func sineAndCosineAreFunctionsAndNotReservedAsNames() throws {
        // A document with an element named sin, a value named cos and a call of each reads with no
        // finding: a call always names a function and a bare name never does.
        let text = try JSONValue.parse(#"{"kind": "text", "at": ["10 + 20 * sin(30)", 20], "text": "label"}"#)
        let doc = tiny.setting("/elements/sin", text).setting("/let/cos", .string("cos(a * 60)")).setting("/steps/show/actions/in/target", .string("sin"))
            .setting("/steps/show/hold", .string("cos + sin(90)"))
        let r = read(doc)
        #expect(r.conforms && r.findings.isEmpty, "\(r.findings)")
        // The functions of the first draft stay reserved.
        has(read(tiny.setting("/elements/abs", text)), .error, .schema, "/elements/abs", "reserved")
        has(read(tiny.setting("/let/floor", .number(1))), .error, .schema, "/let/floor", "reserved")
        // The wrong number of arguments, and a name that is not a function.
        for f in ["sin", "cos"] {
            has(read(tiny.setting("/steps/show/hold", .string("\(f)(1, 2)"))), .error, .expr, "/steps/show/hold", at: 0, "takes 1 argument, an angle in degrees, not 2")
            has(read(tiny.setting("/steps/show/hold", .string("\(f)()"))), .error, .expr, "/steps/show/hold", at: 0, "takes 1 argument, an angle in degrees, not 0")
        }
        has(read(tiny.setting("/steps/show/hold", .string("tan(1)"))), .error, .expr, "/steps/show/hold", at: 0, "unknown function")
        // A bare name that is no value is unknown, as for any name.
        has(read(tiny.setting("/steps/show/hold", .string("cos + 1"))), .error, .expr, "/steps/show/hold", at: 0, "unknown name 'cos'")
    }

    /// `tiny` with a repeated text element `nums` that has the `let` given.
    func withElementLet(_ lets: String, repeat count: JSONValue? = .number(3)) throws -> JSONValue {
        let element = try JSONValue.parse(#"{"kind": "text", "at": [10, 20], "text": "numeral"}"#)
            .setting("/repeat", count).setting("/let", try JSONValue.parse(lets))
        return tiny.setting("/elements/nums", element).setting("/wording/en-US/shared/numeral", try JSONValue.parse(#"{"text": "{k}", "visual": true}"#))
    }

    @Test func anElementsLetNamesLocalsAndIsReadWithItsKeys() throws {
        let ok = try withElementLet(#"{"k": "i + 1", "j": "k * 2"}"#)
            .setting("/elements/nums/at/0", .string("10 * k + j"))
            .setting("/elements/nums/z", .string("j"))
            .setting("/elements/nums/start", try JSONValue.parse(#"{"opacity": "k > 1 ? 1 : 0"}"#))
            .setting("/elements/nums/size", .string("20 + k"))
        let r = read(ok)
        #expect(r.conforms && r.findings.isEmpty, "\(r.findings)")
        // The same let and an entry that shows a name the element's let does not have.
        let wrong = try withElementLet(#"{"j": "i + 1"}"#)
        has(read(wrong), .error, .wording, "/wording/en-US/shared/numeral/text", "{k} cannot be filled")
        // The names of an element's let are a part of the first namespace for that element only:
        // two elements may name the same local.
        let twice = try withElementLet(#"{"k": "i"}"#).setting("/elements/more", tiny["elements"]!["label"]!
            .setting("/repeat", .number(2)).setting("/let", try JSONValue.parse(#"{"k": "i * 2"}"#)))
        #expect(read(twice).findings.isEmpty, "\(read(twice).findings)")
    }

    @Test func anElementsLetMayNotReuseANameOfTheDocument() throws {
        let cases: [(String, String)] = [
            ("a", "a parameter"), ("twice", "a let of the document"), ("label", "an element"), ("nums", "the element itself"), ("v", "a vars value"),
        ]
        for (name, what) in cases {
            let doc = try withElementLet("{\"\(name)\": \"i\"}").setting("/vars/v", .number(1))
            has(read(doc), .error, .schema, "/elements/nums/let/\(name)", "already a name of the document")
            #expect(!read(doc).conforms, "\(what)")
        }
        // Nor a reserved name: the index, a function of the first draft, a keyword.
        for name in ["i", "abs", "and", "left", "n"] {
            has(read(try withElementLet("{\"\(name)\": 1}")), .error, .schema, "/elements/nums/let/\(name)", "reserved")
        }
        // An element's let is an object of expressions, in a name's own form.
        has(read(try withElementLet(#"{"k": "i +"}"#)), .error, .expr, "/elements/nums/let/k")
        has(read(try withElementLet(#"{"Bad name": 1}"#)), .error, .schema, "/elements/nums/let/Bad name", "not a valid name")
        has(read(tiny.setting("/elements/label/let", .number(1))), .error, .schema, "/elements/label/let", "not an object")
        // Its values may name one another, but not in a cycle.
        has(read(try withElementLet(#"{"k": "j + 1", "j": "k + 1"}"#)), .error, .expr, "/elements/nums/let/j", "cycle")
    }

    @Test func anElementsLetNamesAreUnknownOutsideItsKeys() throws {
        let doc = try withElementLet(#"{"k": "i + 1"}"#)
        // The name of another element's let is an unknown name.
        let other = doc.setting("/elements/rule/to/0", .string("k"))
        has(read(other), .error, .expr, "/elements/rule/to/0", at: 0, "unknown name 'k'")
        has(read(doc.setting("/steps/show/hold", .string("k"))), .error, .expr, "/steps/show/hold", at: 0, "unknown name 'k'")
        // The names of an element's let are unknown in its own repeat and when, which fix how
        // many instances there are.
        has(read(try withElementLet(#"{"k": "i + 1"}"#, repeat: .string("k"))), .error, .expr, "/elements/nums/repeat", at: 0, "unknown name 'k'")
        has(read(doc.setting("/elements/nums/when", .string("k > 1"))), .error, .expr, "/elements/nums/when", at: 0, "unknown name 'k'")
        // i is a local of the let only when the element repeats.
        has(read(try withElementLet(#"{"k": "i + 1"}"#, repeat: nil)), .error, .expr, "/elements/nums/let/k", at: 0, "not in scope")
    }

    // MARK: the capability drawing.turn

    /// `tiny` with the line `rule` turned about a pivot by `turn`, and a step that turns it.
    var turning: JSONValue {
        tiny.setting("/elements/rule/turn", .number(30)).setting("/elements/rule/pivot", try! JSONValue.parse("[0, 0]"))
            .setting("/steps/show/actions/spin", try! JSONValue.parse(#"{"do": "turn", "target": "rule", "to": "a * 90", "at": "end(draw)"}"#))
    }

    @Test func aTurnWithoutTheCapabilityIsRefusedAndNamesIt() {
        // One finding for the capability, at the first place the document uses it.
        let r = read(turning)
        has(r, .error, .capability, "/elements/rule/turn", "drawing.turn")
        #expect(!r.conforms && r.findings.filter { $0.code == .capability }.count == 1)
        // The key alone, the pivot alone and the verb alone each name it.
        has(read(tiny.setting("/elements/rule/turn", .number(30))), .error, .capability, "/elements/rule/turn", "drawing.turn")
        has(read(tiny.setting("/elements/rule/pivot", try! JSONValue.parse("[0, 0]"))), .error, .capability, "/elements/rule/pivot", "drawing.turn")
        let verb = tiny.setting("/steps/show/actions/spin", try! JSONValue.parse(#"{"do": "turn", "target": "rule"}"#))
        has(read(verb), .error, .capability, "/steps/show/actions/spin/do", "drawing.turn")
        // Required, the same document reads with no finding; a reader without it refuses what requires it.
        let required = turning.setting("/requires", .array([.string("drawing.turn")]))
        let ok = read(required)
        #expect(ok.conforms && ok.findings.isEmpty, "\(ok.findings)")
        has(ExplainerDocument.read(required.data, capabilities: ["components.arithmetic"]), .error, .capability, "/requires/0", "not implemented")
    }

    @Test func aTurnIsForLinesArrowsAndShapesAndNotForText() throws {
        let required = tiny.setting("/requires", .array([.string("drawing.turn")]))
        for key in ["turn", "pivot"] {
            let value: JSONValue = key == "turn" ? .number(90) : try JSONValue.parse("[0, 0]")
            let r = read(required.setting("/elements/label/\(key)", value))
            has(r, .error, .schema, "/elements/label/\(key)", "turns a line, arrow or shape")
            #expect(!r.conforms)
        }
        let box = try JSONValue.parse(#"{"kind": "outline", "style": "hint", "rect": [0, 0, 10, 10], "turn": 90}"#)
        has(read(required.setting("/elements/frame", box)), .error, .schema, "/elements/frame/turn", "turns a line, arrow or shape")
        // A line, an arrow and a shape each turn, with expressions in the angle and the pivot.
        let kinds = [
            #"{"kind": "line", "from": [0, 0], "to": [0, 10], "turn": "i * 30", "pivot": ["i", 0], "repeat": 3}"#,
            #"{"kind": "arrow", "ink": "result", "from": [0, 0], "to": [0, 10], "turn": "a * 30", "pivot": [5, "a"]}"#,
            #"{"kind": "shape", "fill": "text", "points": [[0, 0], [10, 0], [5, 10]], "turn": 45, "pivot": [5, 5]}"#,
            #"{"kind": "shape", "ink": "text", "ellipse": [0, 0, 10, 20], "turn": 45}"#,
        ]
        for (k, kind) in kinds.enumerated() {
            let r = read(required.setting("/elements/spun", try JSONValue.parse(kind)))
            #expect(r.conforms && r.findings.isEmpty, "\(k): \(r.findings)")
        }
        // The angle and the pivot are numbers, and a pivot is a point.
        has(read(required.setting("/elements/rule/turn", .string("nope"))), .error, .expr, "/elements/rule/turn", at: 0, "unknown name")
        has(read(required.setting("/elements/rule/pivot", try JSONValue.parse("[0]"))), .error, .schema, "/elements/rule/pivot", "not a point")
        has(read(required.setting("/elements/rule/turn", .bool(true))), .error, .schema, "/elements/rule/turn")
        // The verb's `to` is an expression with the index of the target, and is optional.
        let verb = required.setting("/steps/show/actions/spin", try JSONValue.parse(#"{"do": "turn", "target": "rule", "to": "i * 10", "dur": 1}"#))
        #expect(read(verb).conforms)
        has(read(required.setting("/steps/show/actions/spin", try JSONValue.parse(#"{"do": "turn", "target": "rule", "by": 10}"#))), .warning, .unknown, "/steps/show/actions/spin/by")
    }

    /// A verb that names a text element is refused when the document is resolved, which is when
    /// its target is known.
    @Test func aTurnOfATextElementIsRefusedWhenResolved() throws {
        let doc = tiny.setting("/requires", .array([.string("drawing.turn")]))
            .setting("/steps/show/actions/spin", try JSONValue.parse(#"{"do": "turn", "target": "label", "to": 10}"#))
        let d = try #require(ExplainerDocument.read(doc.data).document)
        #expect(d.conforms, "\(d.findings)")
        #expect(throws: DocumentRefusal.self) { try d.resolve(problem: DocumentFixture.values(("a", 1))) }
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

// Profiles and a document's own colours (EXP-20).
struct ProfileAndColourTests {
    let tiny = DocumentFixture.tiny

    /// The document with `colours` drawn by its label's and its rule's ink.
    func coloured(_ colours: String, label: String = "hour", rule: String = "minute") throws -> JSONValue {
        tiny.setting("/colours", try JSONValue.parse(colours))
            .setting("/elements/label/ink", .string(label)).setting("/elements/rule/ink", .string(rule))
    }

    func warnings(_ r: DocumentReading) -> [DocumentFinding] { r.findings.filter { $0.code == .colour } }

    @Test func aDocumentThatDeclaresNoProfileIsOpenAndOneThatDeclaresMathsIsMaths() throws {
        let none = try #require(read(tiny).document)
        #expect(none.profileID == "open" && none.findings.isEmpty)
        let maths = read(tiny.setting("/profile", .string("maths")))
        #expect(maths.conforms && maths.document?.profileID == "maths" && maths.findings.isEmpty, "\(maths.findings)")
        let open = read(tiny.setting("/profile", .string("open")))
        #expect(open.document?.profileID == "open" && open.findings.isEmpty)
    }

    @Test func anUnknownProfileIsARefErrorNamingIt() {
        let r = read(tiny.setting("/profile", .string("science")))
        has(r, .error, .ref, "/profile", "'science'")
        #expect(!r.conforms)
        has(read(tiny.setting("/profile", .number(1))), .error, .schema, "/profile")
    }

    @Test func theOperationRolesStayDrawableInTheOpenProfileByADocumentThatRequiresThem() {
        let doc = tiny.setting("/requires", .array([.string("components.arithmetic")])).setting("/elements/label/ink", .string("add"))
        #expect(read(doc).findings.isEmpty)
        #expect(read(doc.setting("/profile", .string("maths"))).findings.isEmpty)
    }

    @Test func aStylePaletteInADocumentIsASchemaErrorNamingColours() {
        let r = read(tiny.setting("/style", try! JSONValue.parse(##"{"palette": {"light": {"pencil": "#000000"}}}"##)))
        has(r, .error, .schema, "/style/palette", "colours")
    }

    @Test func aDocumentColourIsNamedWhereARoleIsTakenAndGivesValuesOrASuggestedColour() throws {
        let both = ##"{"hour": {"light": "#B5481F", "dark": "#F59623", "cue": "the short hand"}, "minute": {"suggested": "purple", "cue": "the long hand"}}"##
        let r = read(try coloured(both))
        #expect(r.conforms && r.findings.isEmpty, "\(r.findings)")
        let doc = try #require(r.document)
        #expect(doc.colours["minute"] == DocumentColour(name: "minute", light: RGB(hex: 0x8A4FD0), dark: RGB(hex: 0xA569E6)))
        #expect(read(try coloured(both, label: "hour.soft", rule: "minute.fill")).findings.isEmpty)
        has(read(try coloured(both, label: "orange")), .error, .ref, "/elements/label/ink", "no role")
    }

    @Test func aDocumentColourIsHeldToTheFormat() throws {
        has(read(try coloured(##"{"hour": {"suggested": "teal", "cue": "x"}, "minute": {"suggested": "purple", "cue": "y"}}"##)),
            .error, .ref, "/colours/hour/suggested", "'teal'")
        has(read(try coloured(##"{"hour": {"light": "#B5481F", "cue": "x"}, "minute": {"suggested": "purple", "cue": "y"}}"##)),
            .error, .schema, "/colours/hour", "'dark'")
        has(read(try coloured(##"{"hour": {"light": "red", "dark": "#F59623", "cue": "x"}, "minute": {"suggested": "purple", "cue": "y"}}"##)),
            .error, .schema, "/colours/hour/light", "#RRGGBB")
        has(read(try coloured(##"{"hour": {"suggested": "orange", "light": "#B5481F", "dark": "#F59623", "cue": "x"}, "minute": {"suggested": "purple", "cue": "y"}}"##)),
            .error, .schema, "/colours/hour", "not both")
        has(read(try coloured(##"{"text": {"suggested": "orange", "cue": "x"}}"##, label: "text", rule: "text")), .error, .schema, "/colours/text", "role of the style")
        // The maths profile offers no suggested colours.
        has(read(try coloured(##"{"hour": {"suggested": "orange", "cue": "x"}}"##, rule: "hour").setting("/profile", .string("maths"))),
            .error, .ref, "/colours/hour/suggested", "offers no suggested colours")
    }

    @Test func aColourWithNoCueIsAWarning() throws {
        let r = read(try coloured(##"{"hour": {"suggested": "orange"}, "minute": {"suggested": "purple", "cue": "the long hand"}}"##))
        #expect(r.conforms)
        has(r, .warning, .colour, "/colours/hour", "no cue")
        #expect(warnings(r).count == 1)
    }

    @Test func aColourThatIsVeryPaleOnTheLightSheetGetsOneWarningNamingTheContrastAndAValueThatShows() throws {
        let r = read(try coloured(##"{"hour": {"suggested": "orange", "cue": "x"}, "minute": {"light": "#49F6FF", "dark": "#A569E6", "cue": "the long hand"}}"##))
        #expect(r.conforms)
        let found = warnings(r)
        #expect(found.count == 1, "\(r.findings)")
        let message = try #require(found.first).message
        #expect(message.contains("minute (#49F6FF)") && message.contains("light sheet") && message.contains("1.3:1") && message.contains("3:1"), "\(message)")
        // The nearest value is one that passes.
        let hex = try #require(message.split(separator: "#").last).prefix(6)
        let suggested = try #require(RGB(hexString: "#" + hex))
        let sheet = ExplainerStyle.standard.light.sheet
        let k = ColourChecks.contrasts(suggested, sheet: sheet, dark: false)
        #expect(k.sheet >= 3 && k.soft >= 3, "\(message)")
    }

    @Test func anInkThatKeepsLessThanThreeToOneOnItsOwnTintIsAWarning() throws {
        let r = read(try coloured(##"{"hour": {"light": "#D9711F", "dark": "#F59623", "cue": "x"}, "minute": {"suggested": "purple", "cue": "y"}}"##))
        let found = warnings(r)
        #expect(found.count == 1, "\(r.findings)")
        #expect(found.first?.message.contains("own tint") == true && found.first?.message.contains("2.8:1") == true, "\(found)")
    }

    @Test func twoColoursUnderTwentyApartWithADeficiencyGetOneWarningNamingBothTheAppearanceAndTheCondition() throws {
        let r = read(try coloured(##"{"hour": {"light": "#B5481F", "dark": "#F59623", "cue": "x"}, "minute": {"light": "#6B7A1F", "dark": "#A569E6", "cue": "y"}}"##))
        #expect(r.conforms)
        let found = warnings(r)
        #expect(found.count == 1, "\(r.findings)")
        let m = try #require(found.first).message
        #expect(m.contains("hour") && m.contains("minute") && m.contains("in light") && m.contains("deuteranopia") && m.contains("under 20"), "\(m)")
        #expect(found.first?.path == "/colours/hour")
    }

    @Test func aColourAndTheTextItIsDrawnBesideAreComparedAsAnyTwoAre() throws {
        // A grey close to the text colour in dark.
        let r = read(try coloured(##"{"hour": {"light": "#6B5B3E", "dark": "#C9D1CE", "cue": "x"}, "minute": {"suggested": "purple", "cue": "y"}}"##, label: "text", rule: "hour"))
        let found = warnings(r)
        #expect(found.contains { $0.message.contains("hour") && $0.message.contains("text") && $0.message.contains("in dark") }, "\(r.findings)")
    }

    @Test func aColourBesideTextDrawnAsInkAndAsFillIsWarnedOfOnce() throws {
        // The same grey, close to the text colour in dark, with text drawn as ink (the label) and as fill (a dot).
        let doc = try coloured(##"{"hour": {"light": "#6B5B3E", "dark": "#C9D1CE", "cue": "x"}, "minute": {"suggested": "purple", "cue": "y"}}"##, label: "text", rule: "hour")
            .setting("/elements/dot", try JSONValue.parse(##"{"kind": "shape", "ellipse": [0, 0, 5, 5], "fill": "text.fill"}"##))
        let r = read(doc)
        let found = warnings(r).filter { $0.message.contains("hour and text") }
        #expect(found.count == 1, "\(r.findings)")
    }

    @Test func inTheMathsProfileAColourNearAnOperationsIsAWarningAndInTheOpenProfileItIsNot() throws {
        // Near the standard add colour in light, and far from every other colour drawn.
        let colours = ##"{"hour": {"light": "#4F6D45", "dark": "#95E3A5", "cue": "x"}, "minute": {"suggested": "purple", "cue": "y"}}"##
        let open = read(try coloured(colours))
        #expect(warnings(open).isEmpty, "\(open.findings)")
        let maths = read(try coloured(colours.replacingOccurrences(of: "\"suggested\": \"purple\"", with: "\"light\": \"#8A4FD0\", \"dark\": \"#A569E6\"")).setting("/profile", .string("maths")))
        let found = warnings(maths)
        #expect(found.count == 1, "\(maths.findings)")
        #expect(found.first?.message.contains("adding or joining") == true && found.first?.message.contains("add") == true, "\(found)")
    }

    @Test func noColourWarningStopsTheDocumentPlaying() throws {
        let json = try coloured(##"{"hour": {"light": "#49F6FF", "dark": "#6B5B3E"}, "minute": {"light": "#B5481F", "dark": "#6B5B3E", "cue": "y"}}"##)
        let r = read(json)
        #expect(r.conforms && !warnings(r).isEmpty)
        let doc = try #require(r.document)
        #expect((try? DocumentExplainer(document: doc, problem: DocumentFixture.values(("a", 1)))) != nil)
    }

    @Test func aTagAndATintTakeADocumentColourAndTagDefaultsToTheAnswers() throws {
        let doc = tiny
            .setting("/colours", try JSONValue.parse(##"{"hour": {"suggested": "orange", "cue": "x"}}"##))
            .setting("/steps/show/actions/tag", try JSONValue.parse(##"{"do": "tag", "target": "label", "text": "label", "ink": "hour"}"##))
        let r = read(doc)
        #expect(r.conforms && r.findings.isEmpty, "\(r.findings)")
        has(read(doc.setting("/steps/show/actions/tag/ink", .string("nothing"))), .error, .ref, "/steps/show/actions/tag/ink")
    }
}
