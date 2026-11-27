import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript

// Resolving a document for a problem (EXP-19): the steps, each action's targets, starts and
// durations, each step's duration, and the lines filled with their shown and spoken forms.

func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

func closeAll(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { close($0, $1) } }

struct ResolutionTests {
    let sub = DocumentFixture.subtraction
    let learner = DocumentPlayback(control: .paced, counts: .spoken, countPace: 1)
    let parent = DocumentPlayback(control: .skippable, counts: .shown, countPace: 0.4)

    func step(_ r: ResolvedExplainer, _ name: String) throws -> ResolvedStep { try #require(r.steps.first { $0.name == name }) }
    func action(_ s: ResolvedStep, _ name: String) throws -> ResolvedAction { try #require(s.actions.first { $0.name == name }) }

    @Test func theStepsAreThoseWhoseWhenIsTrue() throws {
        let steps: [(Double, Double, [String])] = [
            (54, 26, ["show", "short", "trade", "takeOnes", "takeTens", "count"]),
            (83, 12, ["show", "enough", "takeOnes", "takeTens", "count"]),
            (50, 20, ["show", "takeTens", "count"]),
            (44, 5, ["show", "short", "trade", "takeOnes", "count"]),
            (47, 5, ["show", "enough", "takeOnes", "count"]),
            (10, 10, ["show", "takeTens", "count"]),
        ]
        for (a, b, want) in steps {
            #expect(try sub.resolve(problem: DocumentFixture.values(("a", a), ("b", b)), wording: "everyday").stepNames == want, "\(a) - \(b)")
        }
    }

    /// 54 - 26, watched: the trade breaks the last ten, the ones are crossed out from the loose
    /// ones first, the tens still whole are crossed out from the last, and what is left is counted.
    @Test func theActionsAreResolvedWithTheirTargetsAndTimes() throws {
        let r = try sub.resolve(problem: DocumentFixture.values(("a", 54), ("b", 26)), wording: "everyday", playback: learner)
        #expect(r.layout == "stage" && r.size == CGSize(width: 1000, height: 540) && !r.camera)

        let show = try step(r, "show")
        #expect(close(show.duration, 1.99))
        let tens = try action(show, "tens")
        #expect(tens.targets == (0..<5).map { ten($0) } && closeAll(tens.starts, [0, 0.18, 0.36, 0.54, 0.72]) && close(tens.end, 1.04))
        let ones = try action(show, "ones")
        #expect(ones.targets == (0..<4).map { one($0) } && close(ones.start, 1.05) && close(ones.end, 1.79) && ones.ease == "linear")

        let short = try step(r, "short")
        #expect(close(short.duration, 1.5))
        let mark = try action(short, "mark")
        #expect(mark.mark && mark.targets == [DocumentInstance("equation", part: .run("bO"))] && mark.ease == "easeOut")

        let trade = try step(r, "trade")
        #expect(close(trade.duration, 5.93))
        let boxed = (0..<10).map { DocumentInstance("boxed", $0) }
        let split = try action(trade, "split")
        #expect(split.targets == boxed && close(split.start, 0.7) && close(split.end, 1.41))
        #expect(try action(trade, "fade").targets == [ten(4)])
        #expect(close(try action(trade, "cross").start, 1.51))
        let travel = try action(trade, "travel")
        // Staggered from the last instance: boxed[9] leaves first.
        #expect(travel.reverse && close(travel.start, 2.09) && close(travel.starts[9], 2.09) && close(travel.starts[0], 3.53) && close(travel.end, 5.03))
        #expect(travel.ease == "easeInOut" && close(travel.duration, 1.5))
        #expect(try action(trade, "settle").targets == [DocumentInstance("ten", 4, part: .cross)])

        let takeOnes = try step(r, "takeOnes")
        let crossOnes = try action(takeOnes, "cross")
        #expect(crossOnes.targets == (0..<4).map { one($0) } + [DocumentInstance("boxed", 0), DocumentInstance("boxed", 1)])
        #expect(close(crossOnes.end, 3.03) && close(takeOnes.hold, 0.15) && close(takeOnes.duration, 3.18))

        let takeTens = try step(r, "takeTens")
        #expect(try action(takeTens, "cross").targets == [ten(2), ten(3)])
        #expect(close(takeTens.duration, 1.26))

        let count = try step(r, "count")
        let gather = try action(count, "gather")
        #expect(gather.targets == [DocumentInstance("cten", 0), DocumentInstance("cten", 1)] + (0..<8).map { DocumentInstance("cone", $0) })
        #expect(close(gather.end, 1.76) && gather.ease == "settle")
        let each = try action(count, "count")
        #expect(each.iterations.count == 10)
        #expect(each.iterations.map { $0.locals["n"]!.integer! } == [10, 20, 1, 2, 3, 4, 5, 6, 7, 8])
        #expect(closeAll(each.iterations.map(\.start), [1.76, 2.61, 3.46, 4.02, 4.58, 5.14, 5.7, 6.26, 6.82, 7.38]))
        #expect(close(each.end, 7.94) && each.waitsForVoice)
        let first = try #require(each.iterations.first)
        #expect(first.actions.map(\.name) == ["look", "tag", "say", "total"])
        #expect(first.actions.first { $0.name == "tag" }?.targets == [DocumentInstance("cten", 0)])
        #expect(first.actions.first { $0.name == "total" }?.text?.shown == "10")
        #expect(each.iterations[2].actions.first { $0.name == "running" }?.text?.shown == "20 + 1")
        let join = try action(count, "join")
        let answerAction = try action(count, "answer")
        #expect(close(join.start, 8.19) && close(answerAction.end, 9.09))
        #expect(close(count.duration, 9.09))
        #expect(closeAll(count.waits, [1.76, 2.61, 3.46, 4.02, 4.58, 5.14, 5.7, 6.26, 6.82, 7.38, 8.19, 8.69, 9.09].reduce(into: [0.0]) { $0.append($1) }))
    }

    @Test func linesAreFilledWithTheirShownAndSpokenForms() throws {
        let r = try sub.resolve(problem: DocumentFixture.values(("a", 54), ("b", 26)), wording: "everyday", playback: learner)
        #expect(r.intro?.shown == "54 minus 26. Let's see how!" && r.intro?.spoken == "fifty-four minus twenty-six. Let's see how!")
        #expect(r.guidedIntro?.shown == "Now let's do one together: 54 minus 26.")
        let short = try step(r, "short").line
        #expect(short.shown == "We need to take away 6 ones. But we only have 4!")
        #expect(short.spoken == "We need to take away six ones. But we only have four!")
        let count = try step(r, "count")
        #expect(count.lines.map(\.entry.entry) == ["count"] + Array(repeating: "tick", count: 10) + ["join", "answer"])
        #expect(count.lines.filter(\.count).map(\.entry.spoken!) == ["ten", "twenty", "one", "two", "three", "four", "five", "six", "seven", "eight"])
        #expect(count.lines.filter(\.count).allSatisfy { $0.spoken && !$0.caption })
        let answer = try #require(count.lines.last)
        #expect(answer.entry.shown == "54 minus 26 is 28!" && answer.entry.spoken == "fifty-four minus twenty-six is twenty-eight!")
        #expect(answer.entry.emphasis == "28" && answer.entry.line.emphasisRange != nil && close(answer.time, 9.09))
        // One ten and one one take the singular forms.
        let few = try sub.resolve(problem: DocumentFixture.values(("a", 21), ("b", 11)), wording: "everyday")
        #expect(try step(few, "takeOnes").line.shown == "Cross out 1 one.")
        #expect(try step(few, "takeTens").line.shown == "Now cross out 1 ten.")
        // A visual entry is shown and never said.
        let set = try #require(try action(count, "count").iterations[3].actions.first { $0.name == "running" }?.text)
        #expect(set.shown == "20 + 2" && set.spoken == nil)
    }

    @Test func anotherWordingFillsItsOwnLinesAndSelectsItsCases() throws {
        let r = try sub.resolve(problem: DocumentFixture.values(("a", 54), ("b", 26)), wording: "formal", playback: parent)
        #expect(r.intro?.shown == "54 minus 26, trading a ten.")
        #expect(try step(r, "show").line.shown == "54 is 5 tens and 4 ones.")
        #expect(try step(r, "show").line.spoken == "fifty-four is five tens and four ones.")
        let plain = try sub.resolve(problem: DocumentFixture.values(("a", 83), ("b", 12)), wording: "formal", playback: parent)
        #expect(plain.intro?.shown == "83 minus 12. There are enough ones.")
        // The wording's do it with me line is absent, and only the watched part needs none.
        #expect(plain.guidedIntro?.entry == "intro")
        // plays suggests no wording here, so without one the first is used.
        #expect(try sub.resolve(problem: DocumentFixture.values(("a", 54), ("b", 26))).wording == "everyday")
    }

    @Test func countsShownAreNeitherSpokenNorCaptionedAndTheirStepIsPaced() throws {
        let values = DocumentFixture.values(("a", 54), ("b", 26))
        let spoken = try step(try sub.resolve(problem: values, wording: "formal", playback: learner), "count")
        let shown = try step(try sub.resolve(problem: values, wording: "formal", playback: parent), "count")
        #expect(shown.lines.filter(\.count).allSatisfy { !$0.spoken && !$0.caption })
        #expect(close(shown.duration, 0.4 * spoken.duration))
        #expect(closeAll(shown.lines.map(\.time), spoken.lines.map { 0.4 * $0.time }))
        // Steps not marked counts keep their pace.
        let a = try sub.resolve(problem: values, wording: "formal", playback: parent)
        #expect(close(try step(a, "trade").duration, 5.93))
    }

    @Test func theCameraLeadsAStepWhoseShotFramesDifferently() throws {
        #expect(sub.layout(for: CGSize(width: 660, height: 760)) == "tall")
        #expect(sub.layout(for: CGSize(width: 1000, height: 540)) == "stage")
        let r = try sub.resolve(problem: DocumentFixture.values(("a", 54), ("b", 26)), wording: "everyday", area: CGSize(width: 660, height: 760))
        #expect(r.layout == "tall" && r.camera && close(Double(r.size.height), (640.0 * 760 / 660).rounded()))
        #expect(r.steps.map(\.lead) == [0, 0.9, 0.9, 0.9, 0.9, 0.9])
        // takeOnes after the trade is in the ones shot again, but the trade's shot framed the ten too.
        let short = try step(r, "short")
        #expect(close(short.duration, 0.9 + 1.5) && short.lines[0].time == 0)
        #expect(close(try action(short, "loop").start, 0.9))
        // 83 - 12: enough and takeOnes share the ones shot, so the camera moves only once.
        let e = try sub.resolve(problem: DocumentFixture.values(("a", 83), ("b", 12)), wording: "everyday", area: CGSize(width: 660, height: 760))
        #expect(e.steps.map(\.lead) == [0, 0.9, 0, 0.9, 0.9])
    }

    @Test func equalGroupsResolves() throws {
        let d = DocumentFixture.equalGroups
        let r = try d.resolve(problem: DocumentFixture.values(("a", 3), ("b", 4)), wording: "everyday")
        #expect(r.stepNames == ["groups", "same", "skip"])
        let groups = try step(r, "groups")
        let build = try action(groups, "build")
        #expect(closeAll(build.iterations.map(\.start), [0, 0.78, 1.56]) && close(build.end, 2.42) && close(groups.duration, 2.82))
        #expect(build.iterations[1].actions.first { $0.name == "dots" }?.targets == (4..<8).map { DocumentInstance("dot", $0) })
        #expect(build.iterations[1].actions.first { $0.name == "ring" }?.targets == [DocumentInstance("ring", 1)])
        let skip = try step(r, "skip")
        #expect(skip.lines.map(\.entry.shown) == ["Count on 4 for each group.", "4", "8", "12", "3 times 4 is 12!"])
        #expect(closeAll(skip.lines.map(\.time), [0, 0, 0.9, 1.8, 3.85]) && close(skip.duration, 3.85))
        #expect(try step(r, "groups").line.spoken == "Make three groups, with four in each.")
        let formal = try d.resolve(problem: DocumentFixture.values(("a", 5), ("b", 6)), wording: "formal")
        #expect(formal.intro?.shown == "5 times 6: 5 groups of 6." && formal.intro?.spoken == "five times six: five groups of six.")
    }

    @Test func aProblemOutsideTheParametersIsRefused() {
        for values in [DocumentFixture.values(("a", 9), ("b", 1)), DocumentFixture.values(("a", 54), ("b", 60)), DocumentFixture.values(("a", 54)),
                       DocumentFixture.values(("a", 54.5), ("b", 1)), DocumentFixture.values(("a", 54), ("b", 1), ("c", 1))] {
            do {
                _ = try sub.resolve(problem: values)
                Issue.record("\(values) is resolved")
            } catch {
                #expect(error.findings.allSatisfy { $0.code == .range && $0.values == values }, "\(error)")
            }
        }
    }

    @Test func aDocumentThatIsNotSoundForAProblemIsRefusedWithTheFailure() throws {
        let tiny = DocumentFixture.tiny
        let div = try #require(ExplainerDocument.read(tiny.setting("/let/q", .string("abs(1 / (a - 2))")).setting("/steps/show/hold", .string("q")).data).document)
        #expect(div.conforms)
        _ = try div.resolve(problem: DocumentFixture.values(("a", 1)))
        do {
            _ = try div.resolve(problem: DocumentFixture.values(("a", 2)))
            Issue.record("a = 2 is resolved")
        } catch {
            let f = try #require(error.findings.first)
            #expect(f.code == .eval && f.path == "/let/q" && f.at == 6 && f.message == "division by zero" && f.values == ["a": .number(2)])
            #expect(f.description == "error eval /let/q @6 {a: 2}: division by zero")
        }
        // end() of an action that does not run for the problem.
        let skip = try #require(ExplainerDocument.read(tiny.setting("/steps/show/actions/in/when", .string("a > 1")).data).document)
        _ = try skip.resolve(problem: DocumentFixture.values(("a", 2)))
        do {
            _ = try skip.resolve(problem: DocumentFixture.values(("a", 1)))
            Issue.record("a = 1 is resolved")
        } catch {
            let f = try #require(error.findings.first)
            #expect(f.code == .eval && f.path == "/steps/show/actions/draw/at" && f.at == 0 && f.message.contains("does not run"), "\(f)")
        }
        // A value that fails only where it is not used does not make the document unsound.
        let unused = try #require(ExplainerDocument.read(tiny.setting("/let/q", .string("1 / (a - 2)")).setting("/let/r", .string("a == 2 ? 0 : q"))
            .setting("/steps/show/hold", .string("r")).data).document)
        #expect(try unused.resolve(problem: DocumentFixture.values(("a", 2))).steps[0].hold == 0)
        // A document with an error is not resolved.
        let broken = try #require(ExplainerDocument.read(tiny.setting("/steps/show/hold", .string("nope")).data).document)
        #expect(throws: DocumentRefusal.self) { try broken.resolve(problem: DocumentFixture.values(("a", 1))) }
    }

    /// A mark is undone as the next step begins (section 12.7), so the next step's selection sees
    /// the piece whole again; a cross-out that is not a mark lasts.
    @Test func selectionsSeeTheStateTheStepBeginsIn() throws {
        let doc = try JSONValue.parse(#"""
            {
              "format": "chalkscript-explainer", "version": "1.0", "requires": ["components.arithmetic"], "id": "marks", "title": "Marks",
              "sourceLocale": "en-US", "params": { "a": { "type": "int", "min": 3, "max": 3 } }, "samples": [{ "a": 3 }],
              "elements": { "dot": { "kind": "one", "repeat": "a", "rect": ["i * 30", 0, 20, 20] } },
              "sequence": ["look", "take", "again"],
              "steps": {
                "look": { "say": "line", "actions": { "x": { "do": "cross", "target": "dot[0]", "mark": true } } },
                "take": { "say": "line", "actions": { "x": { "do": "cross", "target": "first(1, whole(dot))", "fade": 0.35 } } },
                "again": { "say": "line", "actions": { "x": { "do": "cross", "target": "first(1, whole(dot))" } } }
              },
              "wording": { "en-US": { "shared": {}, "plain": { "line": "Look." } } }
            }
            """#)
        let d = try #require(ExplainerDocument.read(doc.data).document)
        #expect(d.conforms, "\(d.findings)")
        let r = try d.resolve(problem: DocumentFixture.values(("a", 3)))
        let dot = { (k: Int) in DocumentInstance("dot", k) }
        #expect(r.steps.map { $0.actions[0].targets } == [[dot(0)], [dot(0)], [dot(1)]])
    }

    @Test func aMissingTranslationFallsBackToTheSourceLocale() throws {
        let tiny = DocumentFixture.tiny
        let es = try JSONValue.parse(#"{"shared": {"label": {"text": "{a}", "visual": true}}, "plain": {}}"#)
        let d = try #require(ExplainerDocument.read(tiny.setting("/wording/es", es).data).document)
        let r = try d.resolve(problem: DocumentFixture.values(("a", 3)), wording: "plain", locale: "es")
        #expect(r.fallbacks == ["show"] && r.steps[0].line.locale == "en-US" && r.steps[0].line.shown == "This is 3, and twice it is 6.")
        let translated = try #require(ExplainerDocument.read(tiny.setting("/wording/es", es.setting("/plain/show", .string("Esto es {a}."))).data).document)
        let t = try translated.resolve(problem: DocumentFixture.values(("a", 3)), wording: "plain", locale: "es")
        #expect(t.fallbacks.isEmpty && t.steps[0].line.shown == "Esto es 3." && t.steps[0].line.spoken == "Esto es tres.")
    }

    @Test func pluralCategoriesFollowCLDR() {
        #expect(PluralRules.category(1, language: "en-US") == "one" && PluralRules.category(0, language: "en") == "other")
        #expect(PluralRules.category(0, language: "fr") == "one" && PluralRules.category(1_000_000, language: "es") == "many")
        #expect((1...5).map { PluralRules.category($0, language: "ru")! } == ["one", "few", "few", "few", "many"])
        #expect(PluralRules.category(21, language: "ru") == "one" && PluralRules.category(11, language: "ru") == "many")
        #expect(PluralRules.category(2, language: "ar") == "two" && PluralRules.category(5, language: "ja") == "other")
        #expect(PluralRules.category(3, language: "xx") == nil)
    }

    // MARK: an element's own let, and the entry its text shows

    /// `tiny` with the element `nums` added, and `numeral` as the entry it shows.
    func numerals(_ element: String, entry: String) throws -> ExplainerDocument {
        let json = try JSONValue.parse(element)
        let entryValue = try JSONValue.parse(entry)
        let doc = DocumentFixture.tiny.setting("/elements/nums", json).setting("/wording/en-US/shared/numeral", entryValue)
        return try #require(ExplainerDocument.read(doc.data).document)
    }

    func shown(_ doc: ExplainerDocument, _ prefix: String) throws -> [String] {
        let e = try DocumentExplainer(document: doc, problem: DocumentFixture.values(("a", 1)))
        return e.still(after: 0).elements(prefix).compactMap { if case let .words(text, _) = $0.kind { text } else { nil } }
    }

    /// A repeated text element shows `{k}` from its own `let`, here the numerals 1 to 12.
    @Test func aRepeatedTextElementShowsTheValuesOfItsOwnLet() throws {
        let doc = try numerals(
            #"{"kind": "text", "repeat": 12, "let": {"k": "i + 1"}, "at": ["30 * k", 100], "text": "numeral"}"#, entry: #"{"text": "{k}", "visual": true}"#)
        #expect(doc.conforms, "\(doc.findings)")
        #expect(try shown(doc, "nums") == (1...12).map(String.init))
        // The let's value places each instance, too.
        let e = try DocumentExplainer(document: doc, problem: DocumentFixture.values(("a", 1)))
        let at: [CGFloat] = e.still(after: 0).elements("nums.").compactMap { x -> CGFloat? in
            if case let .words(_, set) = x.kind { return set.at.x }
            return nil
        }
        #expect(at == (1...12).map { CGFloat(30 * $0) })
    }

    /// The reference lets a repeated element's own entry show `{i}`; the player once refused it.
    @Test func aRepeatedTextElementShowsItsIndex() throws {
        let doc = try numerals(#"{"kind": "text", "repeat": 3, "at": ["30 * i", 100], "text": "numeral"}"#, entry: #"{"text": "{i}", "visual": true}"#)
        #expect(doc.conforms, "\(doc.findings)")
        #expect(try shown(doc, "nums") == ["0", "1", "2"])
    }

    /// Values of an element's `let` may name one another, and are ordered by dependency; an
    /// element without `repeat` has no `i`.
    @Test func anElementsLetValuesAreOrderedByDependency() throws {
        let doc = try numerals(
            #"{"kind": "text", "let": {"b": "a2 * 2", "a2": "a + 1"}, "at": ["b", 100], "text": "numeral"}"#, entry: #"{"text": "{b}-{a2}", "visual": true}"#)
        #expect(doc.conforms, "\(doc.findings)")
        #expect(try shown(doc, "nums") == ["4-2"])
    }

    /// A clock's marks: sixty ticks, every fifth longer, placed with `sin` and `cos` and an
    /// element's `let` for the inner radius; the four at the quarters are exact.
    @Test func ticksAreRoundTheFaceWithSineAndCosine() throws {
        let doc = try numerals(
            #"""
            {"kind": "line", "repeat": 60, "let": {"r": "mod(i, 5) == 0 ? 254 : 268"},
             "from": ["440 + r * sin(6 * i)", "380 - r * cos(6 * i)"], "to": ["440 + 280 * sin(6 * i)", "380 - 280 * cos(6 * i)"]}
            """#, entry: #"{"text": "{a}", "visual": true}"#)
        #expect(doc.conforms, "\(doc.findings)")
        let e = try DocumentExplainer(document: doc, problem: DocumentFixture.values(("a", 1)))
        let ticks = e.still(after: 0).elements("nums.").compactMap { x -> [CGPoint]? in
            if case let .shape(.lines(points, _), _) = x.kind { return points }
            return nil
        }
        #expect(ticks.count == 60)
        #expect(ticks[0] == [CGPoint(x: 440, y: 126), CGPoint(x: 440, y: 100)])
        #expect(ticks[15] == [CGPoint(x: 694, y: 380), CGPoint(x: 720, y: 380)])
        #expect(ticks[30] == [CGPoint(x: 440, y: 634), CGPoint(x: 440, y: 660)])
        #expect(ticks[45] == [CGPoint(x: 186, y: 380), CGPoint(x: 160, y: 380)])
        let lengths = ticks.map { hypot($0[1].x - $0[0].x, $0[1].y - $0[0].y) }
        for (k, length) in lengths.enumerated() { #expect(abs(length - (k % 5 == 0 ? 26 : 12)) < 1e-9, "tick \(k) is \(length) long") }
    }

    // MARK: turning an element about its pivot (the capability drawing.turn)

    /// A hand drawn pointing at twelve, 100 units long, with its pivot at its hub.
    static let hand = #"{"kind": "shape", "closed": true, "fill": "text", "pivot": [200, 300], "points": [[210, 300], [200, 200], [190, 300], [200, 320]]}"#

    /// A document with the element `hand`, whatever else `extra` adds to `elements` (a JSON
    /// object's members, written with a leading comma), and one step for each entry of `steps`, a
    /// JSON object of actions.
    func handDocument(_ element: String = ResolutionTests.hand, extra: String = "", layouts: String = "", steps: [String]) throws -> ExplainerDocument {
        let names = steps.indices.map { "\"s\($0)\"" }.joined(separator: ", ")
        let body = steps.enumerated().map { "\"s\($0.offset)\": { \"say\": \"line\", \"actions\": \($0.element) }" }.joined(separator: ", ")
        let doc = try JSONValue.parse("""
            {
              "format": "chalkscript-explainer", "version": "1.0", "requires": ["drawing.turn"], "id": "hands", "title": "Hands",
              "sourceLocale": "en-US", "params": { "a": { "type": "int", "min": 1, "max": 1 } }, "samples": [{ "a": 1 }],
              \(layouts)
              "elements": { "hand": \(element)\(extra) },
              "sequence": [\(names)],
              "steps": { \(body) },
              "wording": { "en-US": { "shared": {}, "plain": { "line": "Turn." } } }
            }
            """)
        let d = try #require(ExplainerDocument.read(doc.data).document)
        #expect(d.conforms, "\(d.findings)")
        return d
    }

    func explainer(_ doc: ExplainerDocument) throws -> DocumentExplainer { try DocumentExplainer(document: doc, problem: DocumentFixture.values(("a", 1))) }

    /// The angle a scene draws the element at, in degrees from 0 up to 360.
    func angle(_ scene: Scene, _ id: String = "hand") throws -> Double {
        let t = try #require(scene.element(id)).transform
        let a = atan2(Double(t.b), Double(t.a)) * 180 / .pi
        return a < 0 ? a + 360 : a
    }

    func equal(_ a: Double, _ b: Double, _ what: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
        let d = abs(a - b)
        #expect(min(d, 360 - d) < 1e-6, "\(a) is not \(b) \(what)", sourceLocation: sourceLocation)
    }

    /// From 0, `to: 150` is at 75 half-way under linear, and at 150 at the end; `to: -30` turns
    /// anticlockwise, half-way at -15; and a later `to: 360` from 150 carries on round to twelve.
    @Test func aTurnGoesByTheDifferenceOfItsAnglesAndTheNumbersGiveTheDirection() throws {
        let clockwise = try explainer(try handDocument(steps: [#"{ "go": { "do": "turn", "target": "hand", "to": 150, "dur": 2, "ease": "linear" } }"#]))
        equal(try angle(clockwise.scene(step: 0, at: 0)), 0)
        equal(try angle(clockwise.scene(step: 0, at: 1)), 75)
        equal(try angle(clockwise.still(after: 0)), 150)
        let anticlockwise = try explainer(try handDocument(steps: [#"{ "go": { "do": "turn", "target": "hand", "to": -30, "dur": 2, "ease": "linear" } }"#]))
        equal(try angle(anticlockwise.scene(step: 0, at: 1)), -15)
        equal(try angle(anticlockwise.still(after: 0)), -30)
        // The turn is about the pivot, which stays where it is.
        let pivot = try #require(clockwise.scene(step: 0, at: 1).element("hand")).transform
        #expect(CGPoint(x: 200, y: 300).applying(pivot) == CGPoint(x: 200, y: 300))
        // Round: 150 then to 360 goes on through 255, not back through 45.
        let round = try explainer(try handDocument(steps: [
            #"{ "go": { "do": "turn", "target": "hand", "to": 150, "dur": 1 } }"#,
            #"{ "go": { "do": "turn", "target": "hand", "to": 360, "dur": 2, "ease": "linear" } }"#,
        ]))
        equal(try angle(round.scene(step: 1, at: 0)), 150, "the step starts where the last left it")
        equal(try angle(round.scene(step: 1, at: 1)), 255)
        equal(try angle(round.still(after: 1)), 0)
        // 390 is a whole turn and 30 more, and is drawn at 30.
        let more = try explainer(try handDocument(steps: [#"{ "go": { "do": "turn", "target": "hand", "to": 390, "dur": 2, "ease": "linear" } }"#]))
        equal(try angle(more.scene(step: 0, at: 1)), 195)
        equal(try angle(more.still(after: 0)), 30)
    }

    /// The turn key places the element at its angle before any step; a turn without `to` goes
    /// back to the place's angle, which is that angle or the last `to` a step left.
    @Test func aTurnWithoutToReturnsToTheAngleOfThePlace() throws {
        let keyed = ResolutionTests.hand.replacingOccurrences(of: #""closed""#, with: #""turn": 40, "closed""#)
        let marked = try explainer(try handDocument(keyed, steps: [#"""
            { "go": { "do": "turn", "target": "hand", "to": 150, "dur": 1, "ease": "linear", "mark": true },
              "back": { "do": "turn", "target": "hand", "at": "end(go)", "dur": 1, "ease": "linear" } }
            """#]))
        equal(try angle(marked.still(after: -1)), 40, "drawn at its turn before any step")
        equal(try angle(marked.scene(step: 0, at: 1)), 150)
        equal(try angle(marked.scene(step: 0, at: 1.5)), 95)
        equal(try angle(marked.still(after: 0)), 40)
        // A turn that is not a mark makes its `to` the place's angle for the steps after it.
        let kept = try explainer(try handDocument(keyed, steps: [
            #"{ "go": { "do": "turn", "target": "hand", "to": 150, "dur": 1 } }"#,
            #"""
            { "go": { "do": "turn", "target": "hand", "to": 60, "dur": 1, "ease": "linear", "mark": true },
              "back": { "do": "turn", "target": "hand", "at": "end(go)", "dur": 1, "ease": "linear" } }
            """#,
        ]))
        equal(try angle(kept.still(after: 0)), 150)
        equal(try angle(kept.scene(step: 1, at: 0)), 150, "the step starts at the place's angle")
        equal(try angle(kept.scene(step: 1, at: 1)), 60)
        equal(try angle(kept.still(after: 1)), 150, "back to 150, the place's angle, and not to the key's 40")
        // The turn after a mark that is undone is not carried to the next step.
        let marks = try explainer(try handDocument(steps: [
            #"{ "go": { "do": "turn", "target": "hand", "to": 90, "dur": 1, "mark": true } }"#,
            #"{ "wait": { "do": "pulse", "target": "hand" } }"#,
        ]))
        equal(try angle(marks.still(after: 0)), 90)
        equal(try angle(marks.scene(step: 1, at: 0)), 0)
    }

    /// An instance with a pivot grows and pulses about it, so the pivot stays still; one without
    /// grows and pulses about the middle of its geometry, which is not at its reference point.
    @Test func growAndPulseKeepThePivotStill() throws {
        let hub = CGPoint(x: 200, y: 300)
        func hubMoves(_ element: String) throws -> [CGPoint] {
            let e = try explainer(try handDocument(element, steps: [
                #"{ "in": { "do": "appear", "target": "hand", "dur": 2, "grow": 0.2, "ease": "linear" } }"#,
                #"{ "bump": { "do": "pulse", "target": "hand", "dur": 2 } }"#,
            ]))
            var seen: [CGPoint] = []
            for (step, t) in [(0, 1.0), (0, 2.0), (1, 1.0)] {
                let scene = e.scene(step: step, at: t)
                let element = try #require(scene.element("hand"))
                seen.append(hub.applying(element.transform))
            }
            return seen
        }
        for turn in [0.0, 90, 150] {
            let pivoted = ResolutionTests.hand.replacingOccurrences(of: #""closed""#, with: #""turn": \#(turn), "start": { "opacity": 0 }, "closed""#)
            for point in try hubMoves(pivoted) { #expect(abs(point.x - hub.x) < 1e-9 && abs(point.y - hub.y) < 1e-9, "turned \(turn): \(point)") }
        }
        // Without a pivot, the first point is where the shape is grown from its middle, so moves.
        let free = ResolutionTests.hand.replacingOccurrences(of: #""pivot": [200, 300], "#, with: "")
            .replacingOccurrences(of: #""closed""#, with: #""start": { "opacity": 0 }, "closed""#)
        let moved = try hubMoves(free)
        #expect(moved[0] != hub && moved[2] != hub, "\(moved)")
        // The pulse is by 15 per cent half-way, about the pivot: the tip is 115 units out.
        let e = try explainer(try handDocument(
            ResolutionTests.hand.replacingOccurrences(of: #""closed""#, with: #""turn": 90, "closed""#), steps: [#"{ "bump": { "do": "pulse", "target": "hand", "dur": 2 } }"#]))
        let t = try #require(e.scene(step: 0, at: 1).element("hand")).transform
        let pulsed = CGPoint(x: 200, y: 200).applying(t)
        #expect(abs(pulsed.x - 315) < 1e-9 && abs(pulsed.y - 300) < 1e-9, "\(pulsed)")
    }

    /// A turned instance is as large as the box round its turned geometry, and `around`, a part
    /// and a shot frame it so, at its angle now and at the angle a step has left it at.
    @Test func boundsAreTheBoxRoundTheTurnedGeometry() throws {
        let turned = ResolutionTests.hand.replacingOccurrences(of: #""closed""#, with: #""turn": 90, "closed""#)
        let frame = #", "frame": { "kind": "outline", "style": "hint", "around": "hand", "pad": 0 }, "far": { "kind": "text", "at": [500, 380], "text": "line" }"#
        let layouts = #""layouts": { "stage": { "size": [600, 400], "camera": true } }, "parts": { "handPart": "hand" }, "shots": { "handShot": { "frame": ["handPart"], "margin": 0 } },"#
        let doc = try handDocument(turned, extra: frame, layouts: layouts, steps: [#"{ "go": { "do": "turn", "target": "hand", "to": 180, "dur": 1 } }"#])
        let r = Resolver(doc, problem: DocumentFixture.values(("a", 1)), layout: "stage", area: nil, wording: "plain", locale: "en-US", playback: DocumentPlayback())
        // Pointing at twelve, the hand is 20 wide and 120 tall; turned 90 it is 120 wide and 20 tall,
        // from its hub to 100 on, with its tail 20 back.
        let box = CGRect(x: 180, y: 290, width: 120, height: 20)
        #expect(try r.bounds(DocumentInstance("hand")) == box)
        #expect(try r.bounds(DocumentInstance("frame")) == box, "around frames the turned hand")
        #expect(try r.region(ofPart: "handPart") == box)
        // A hand that has been turned to 180 and has then been moved is the box of that, at its place.
        r.state[DocumentInstance("hand"), default: InstanceState()].angle = 180
        #expect(try r.bounds(DocumentInstance("hand")) == CGRect(x: 190, y: 280, width: 20, height: 120))
        r.state[DocumentInstance("hand"), default: InstanceState()].place = CGPoint(x: 310, y: 400)
        #expect(try r.bounds(DocumentInstance("hand")) == CGRect(x: 290, y: 380, width: 20, height: 120), "its reference point (210, 300) is at (310, 400)")
        // The camera's shot frames the turned hand, in the player, and not the hand pointing up.
        let e = try explainer(doc)
        #expect(try #require(e.film.cameras["handShot"]).focus == box)
        // An ellipse is boxed by its turned ellipse, and a rectangle by its turned corners.
        let round = try handDocument(#"{ "kind": "shape", "ellipse": [100, 100, 80, 40], "fill": "text", "pivot": [140, 120], "turn": 90 }"#, steps: [#"{}"#])
        let r2 = Resolver(round, problem: DocumentFixture.values(("a", 1)), layout: "stage", area: nil, wording: "plain", locale: "en-US", playback: DocumentPlayback())
        let b = try r2.bounds(DocumentInstance("hand"))
        #expect(abs(b.minX - 120) < 1e-9 && abs(b.minY - 80) < 1e-9 && abs(b.width - 40) < 1e-9 && abs(b.height - 80) < 1e-9, "\(b)")
    }

    /// A turned arrow is drawn through its turn, so its head follows the turned path.
    @Test func aTurnedArrowIsDrawnThroughItsTurnWithItsHead() throws {
        let arrow = #"{"kind": "arrow", "ink": "result", "pivot": [200, 300], "from": [200, 300], "to": [200, 200], "turn": 90}"#
        let e = try explainer(try handDocument(arrow, steps: [#"{ "go": { "do": "turn", "target": "hand", "to": 180, "dur": 1 } }"#]))
        let before = try #require(e.still(after: -1).element("hand"))
        guard case let .arrow(points, _, _) = before.kind else { Issue.record("not an arrow"); return }
        // The arrow's points are where it is placed; the head is drawn from them, and both are turned.
        #expect(points == [CGPoint(x: 200, y: 300), CGPoint(x: 200, y: 200)])
        equal(try angle(e.still(after: -1)), 90)
        let tip = points[1].applying(before.transform)
        #expect(abs(tip.x - 300) < 1e-9 && abs(tip.y - 300) < 1e-9, "\(tip)")
        let after = try #require(e.still(after: 0).element("hand"))
        let down = points[1].applying(after.transform)
        #expect(abs(down.x - 200) < 1e-9 && abs(down.y - 400) < 1e-9, "\(down)")
    }

    // MARK: several turns of one target in one step

    /// Twelve small places, for a hand an `each` turns from one to the next.
    static let places = #", "places": { "kind": "shape", "repeat": 12, "ellipse": ["20 * i", 0, 10, 10], "fill": "muted" }"#

    /// A hand turned by an `each` over the first five of twelve places, with `i` in its `to`,
    /// ends at the fifth place's angle, and passes through each place's angle on the way.
    @Test func turnsInAnEachChainFromOnePlaceToTheNext() throws {
        let each = #"""
            { "count": { "do": "each", "gap": 1, "target": "first(5, places)",
                "then": { "go": { "do": "turn", "target": "hand", "to": "30 * (i + 1)", "dur": 0.5, "ease": "linear" } } } }
            """#
        let e = try explainer(try handDocument(extra: ResolutionTests.places, steps: [each]))
        equal(try angle(e.scene(step: 0, at: 0)), 0)
        for place in 0..<5 {
            let t = Double(place)
            equal(try angle(e.scene(step: 0, at: t + 0.25)), Double(30 * place) + 15, "half-way to place \(place + 1)")
            equal(try angle(e.scene(step: 0, at: t + 0.5)), Double(30 * (place + 1)), "at place \(place + 1)")
        }
        equal(try angle(e.still(after: 0)), 150, "the hand ends at the fifth place")
        // Its place's angle is the last `to`, so a turn without `to` in the next step goes back to it.
        let back = try explainer(try handDocument(extra: ResolutionTests.places, steps: [
            each, #"{ "go": { "do": "turn", "target": "hand", "to": 10, "dur": 1 }, "back": { "do": "turn", "target": "hand", "at": "end(go)", "dur": 1 } }"#,
        ]))
        equal(try angle(back.scene(step: 1, at: 0)), 150, "the next step starts at the fifth place")
        equal(try angle(back.still(after: 1)), 150)
    }

    /// Turns that are timed in the order opposite to the document's leave the angle of the last
    /// to start, and each starts from the angle the one before left.
    @Test func turnsOfOneTargetTakeEffectInTheOrderOfTheirTimes() throws {
        let later = #"""
            { "second": { "do": "turn", "target": "hand", "at": 2, "to": 50, "dur": 1, "ease": "linear" },
              "first": { "do": "turn", "target": "hand", "at": 0, "to": 120, "dur": 1, "ease": "linear" } }
            """#
        let e = try explainer(try handDocument(steps: [later, #"{ "back": { "do": "turn", "target": "hand", "dur": 1, "ease": "linear" } }"#]))
        equal(try angle(e.scene(step: 0, at: 1.5)), 120)
        equal(try angle(e.scene(step: 0, at: 2.5)), 85, "the second turn starts from 120")
        equal(try angle(e.still(after: 0)), 50)
        equal(try angle(e.scene(step: 1, at: 0)), 50, "the place's angle is the last to start, not the last in the document")
    }
}
