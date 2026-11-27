import Foundation
import Testing
@testable import ChalkScript

// The expression language and selections of the explainer format (EXP-19, sections 6 and 7 of
// docs/format/explainer-1.0.md): every operator and function, precedence, and each error with
// the offset at which it is found.

/// A scope with fixed values: three tens (the middle one crossed out), two ones, a text element
/// with runs `a` and `ans`, an outline without repeat, and an action `a` that runs from 1 to 2.
struct FixedScope: EvaluationScope {
    var values: [String: DocumentValue] = ["dT": .number(1), "room": .number(30), "k": .number(2), "word": .string("ten")]
    var elements: [String: ScopeElement] = [
        "ten": ScopeElement(kind: "ten", repeated: true, count: 3, runs: [], isPiece: true, name: "ten"),
        "one": ScopeElement(kind: "one", repeated: true, count: 2, runs: [], isPiece: true, name: "one"),
        "equation": ScopeElement(kind: "text", repeated: false, count: 1, runs: ["a", "ans"], isPiece: false, name: "equation"),
        "box": ScopeElement(kind: "outline", repeated: false, count: 1, runs: [], isPiece: false, name: "box"),
    ]
    var crossed: Set<DocumentInstance> = [DocumentInstance("ten", 1)]
    var times: [String: (Double, Double)] = ["a": (1, 2)]

    func value(of name: String) throws(ExpressionError) -> DocumentValue? { values[name] }
    func element(_ name: String) -> ScopeElement? { elements[name] }
    func isWhole(_ instance: DocumentInstance) -> Bool { !crossed.contains(instance) }
    func time(_ function: String, of action: String, at: Int) throws(ExpressionError) -> Double {
        guard let t = times[action] else { throw ExpressionError("\(function)(\(action)): \(action) does not run for this problem", at: at) }
        return function == "start" ? t.0 : t.1
    }
}

func evaluate(_ source: String, _ scope: FixedScope = FixedScope()) throws -> DocumentValue {
    try Evaluator(scope: scope).evaluate(try DocumentExpression(source))
}

/// The error evaluating (or parsing) `source` gives.
func failure(_ source: String, _ scope: FixedScope = FixedScope()) -> ExpressionError? {
    do {
        _ = try Evaluator(scope: scope).evaluate(try DocumentExpression(source))
        return nil
    } catch let e as ExpressionError {
        return e
    } catch {
        return nil
    }
}

func ten(_ k: Int) -> DocumentInstance { DocumentInstance("ten", k) }
func one(_ k: Int) -> DocumentInstance { DocumentInstance("one", k) }
func sel(_ xs: DocumentInstance...) -> DocumentValue { .selection(DocumentSelection(xs)) }

struct ExpressionTests {
    @Test func literals() throws {
        #expect(try evaluate("12") == .number(12))
        #expect(try evaluate("1.25") == .number(1.25))
        #expect(try evaluate("'a b'") == .string("a b"))
        #expect(try evaluate("''") == .string(""))
        #expect(try evaluate("true") == .truth(true) && evaluate("false") == .truth(false))
        #expect(try evaluate("  \t( 3 )\n") == .number(3))
    }

    @Test func arithmetic() throws {
        #expect(try evaluate("1 + 2") == .number(3))
        #expect(try evaluate("5 - 7") == .number(-2))
        #expect(try evaluate("4 * 2.5") == .number(10))
        #expect(try evaluate("7 / 2") == .number(3.5))
        #expect(try evaluate("-3") == .number(-3))
        #expect(try evaluate("- -3") == .number(3))
        #expect(try evaluate("2 - -1") == .number(3))
        // Left to right within a level.
        #expect(try evaluate("7 - 2 - 1") == .number(4))
        #expect(try evaluate("8 / 2 / 2") == .number(2))
    }

    @Test func comparisonsAndTruth() throws {
        let cases: [(String, Bool)] = [
            ("1 == 1", true), ("1 == 2", false), ("1 != 2", true), ("1 != 1", false), ("1 < 2", true), ("2 < 2", false),
            ("2 <= 2", true), ("3 <= 2", false), ("3 > 2", true), ("2 > 2", false), ("2 >= 2", true), ("1 >= 2", false),
            ("'a' == 'a'", true), ("'a' != 'b'", true), ("true == true", true), ("true != false", true),
            ("not true", false), ("not false", true), ("true and true", true), ("true and false", false),
            ("false or true", true), ("false or false", false),
        ]
        for (source, want) in cases { #expect(try evaluate(source) == .truth(want), "\(source)") }
        // Numbers compare exactly.
        #expect(try evaluate("0.1 + 0.2 == 0.3") == .truth(false))
    }

    @Test func precedence() throws {
        #expect(try evaluate("1 + 2 * 3") == .number(7))
        #expect(try evaluate("(1 + 2) * 3") == .number(9))
        #expect(try evaluate("-2 * 3") == .number(-6))
        #expect(try evaluate("2 * -3 + 1") == .number(-5))
        #expect(try evaluate("1 + 2 < 4") == .truth(true))
        // not is looser than a comparison, and tighter than and.
        #expect(try evaluate("not 1 < 2") == .truth(false))
        #expect(try evaluate("not true or true") == .truth(true))
        #expect(try evaluate("not (true or true)") == .truth(false))
        // and is tighter than or.
        #expect(try evaluate("true or false and false") == .truth(true))
        #expect(try evaluate("(true or false) and false") == .truth(false))
        // The conditional is the loosest, and groups to the right.
        #expect(try evaluate("true or false ? 1 : 2") == .number(1))
        #expect(try evaluate("1 < 2 ? 3 : 4") == .number(3))
        #expect(try evaluate("true ? 1 : false ? 2 : 3") == .number(1))
        #expect(try evaluate("false ? 1 : true ? 2 : 3") == .number(2))
        #expect(try evaluate("false ? 1 : false ? 2 : 3") == .number(3))
        #expect(try evaluate("true ? false ? 1 : 2 : 3") == .number(2))
        // Indexing and member access are the tightest.
        #expect(try evaluate("first(1, ten)[0].cross") == sel(DocumentInstance("ten", 0, part: .cross)))
        #expect(try evaluate("ten[1 + 1]") == sel(ten(2)))
    }

    @Test func shortCircuits() throws {
        #expect(try evaluate("false and 1 / 0 > 0") == .truth(false))
        #expect(try evaluate("true or 1 / 0 > 0") == .truth(true))
        #expect(try evaluate("true ? 1 : 1 / 0") == .number(1))
        #expect(try evaluate("false ? 1 / 0 : 2") == .number(2))
        // The reference's own example, with dT 1.
        #expect(try evaluate("dT > 1 ? room / (dT - 1) : 40") == .number(40))
    }

    @Test func functions() throws {
        let cases: [(String, DocumentValue)] = [
            ("div(7, 2)", .number(3)), ("div(-7, 2)", .number(-4)), ("div(7, -2)", .number(-4)),
            ("mod(7, 3)", .number(1)), ("mod(-7, 3)", .number(2)), ("mod(7, -3)", .number(-2)), ("mod(54, 10)", .number(4)),
            ("min(3, 1, 2)", .number(1)), ("min(2, 5)", .number(2)), ("max(3, 1, 2)", .number(3)), ("max(-1, -4)", .number(-1)),
            ("abs(-4)", .number(4)), ("abs(4)", .number(4)),
            ("floor(2.7)", .number(2)), ("floor(-2.5)", .number(-3)),
            ("round(2.5)", .number(3)), ("round(-2.5)", .number(-3)), ("round(2.4)", .number(2)), ("round(-2.6)", .number(-3)),
            ("str(42)", .string("42")), ("str(-3)", .string("-3")), ("str(word)", .string("ten")), ("str(0)", .string("0")),
            ("start(a)", .number(1)), ("end(a)", .number(2)), ("end(a) + 0.25", .number(2.25)),
        ]
        for (source, want) in cases { #expect(try evaluate(source) == want, "\(source)") }
    }

    /// `sin` and `cos` take degrees, reduce the angle modulo 360, and are exact where the value is
    /// 0, 0.5, -0.5, 1 or -1 at a multiple of 30 (section 6.4).
    @Test func sineAndCosineAreInDegreesAndExactWhereTheValueIsSimple() throws {
        let exact: [(String, Double)] = [
            ("sin(30)", 0.5), ("cos(90)", 0), ("sin(-90)", -1), ("sin(390)", 0.5), ("sin(0)", 0), ("cos(0)", 1), ("sin(90)", 1),
            ("sin(150)", 0.5), ("sin(180)", 0), ("sin(210)", -0.5), ("sin(270)", -1), ("sin(330)", -0.5), ("sin(360)", 0),
            ("cos(60)", 0.5), ("cos(120)", -0.5), ("cos(180)", -1), ("cos(240)", -0.5), ("cos(270)", 0), ("cos(300)", 0.5),
            ("cos(360)", 1), ("cos(-60)", 0.5), ("cos(780)", 0.5), ("sin(-30)", -0.5), ("sin(-390)", -0.5), ("sin(3600)", 0),
            ("sin(30 * 13)", 0.5), ("cos(30 * 16)", -0.5), ("sin(6 * 5)", 0.5),
        ]
        for (source, want) in exact {
            let got = try evaluate(source)
            #expect(got == .number(want), "\(source) is \(got)")
        }
        // Elsewhere the platform's value, to within rounding.
        let near: [(String, Double)] = [
            ("sin(60)", 0.8660254037844386), ("cos(30)", 0.8660254037844386), ("sin(45)", 0.7071067811865476), ("sin(1)", 0.01745240643728351),
            ("sin(-60)", -0.8660254037844386), ("cos(135)", -0.7071067811865476), ("sin(7.5)", 0.13052619222005157),
        ]
        for (source, want) in near {
            guard case let .number(got) = try evaluate(source) else { Issue.record("\(source) is not a number"); continue }
            #expect(abs(got - want) < 1e-12, "\(source) is \(got)")
        }
        // A point round a centre, clockwise from twelve with y downward.
        #expect(try evaluate("440 + 100 * sin(90)") == .number(540) && evaluate("380 - 100 * cos(180)") == .number(480))
        #expect(try evaluate("floor(100 * sin(30))") == .number(50) && evaluate("sin(30) == 0.5") == .truth(true))
    }

    @Test func sineAndCosineTakeOneNumber() {
        for f in ["sin", "cos"] {
            for source in ["\(f)()", "\(f)(1, 2)"] {
                let e = failure(source)
                #expect(e?.at == 0 && e?.message.contains("takes 1 argument, an angle in degrees, not") == true, "\(source): \(e?.message ?? "")")
            }
            #expect(failure("\(f)('a')")?.message.contains("not a number") == true)
            #expect(failure("\(f)(true)")?.message.contains("not a number") == true)
        }
    }

    @Test func selections() throws {
        #expect(try evaluate("ten") == sel(ten(0), ten(1), ten(2)))
        #expect(try evaluate("ten[1]") == sel(ten(1)))
        #expect(try evaluate("equation") == sel(DocumentInstance("equation")))
        #expect(try evaluate("equation.ans") == sel(DocumentInstance("equation", part: .run("ans"))))
        #expect(try evaluate("ten[1].cross") == sel(DocumentInstance("ten", 1, part: .cross)))
        #expect(try evaluate("ten.cross") == sel(
            DocumentInstance("ten", 0, part: .cross), DocumentInstance("ten", 1, part: .cross), DocumentInstance("ten", 2, part: .cross)))
        #expect(try evaluate("ten + one") == sel(ten(0), ten(1), ten(2), one(0), one(1)))
        // Concatenation keeps the first of each instance.
        #expect(try evaluate("ten[2] + ten") == sel(ten(2), ten(0), ten(1)))
        #expect(try evaluate("first(2, ten)") == sel(ten(0), ten(1)))
        #expect(try evaluate("first(0, ten)") == sel())
        #expect(try evaluate("last(1, ten + one)") == sel(one(1)))
        #expect(try evaluate("last(3, ten)") == sel(ten(0), ten(1), ten(2)))
        #expect(try evaluate("slice(ten + one, 2, 2)") == sel(ten(2), one(0)))
        #expect(try evaluate("slice(ten, 3, 0)") == sel())
        // whole() leaves out what is crossed out or ghosted; ten[1] is.
        #expect(try evaluate("whole(ten)") == sel(ten(0), ten(2)))
        #expect(try evaluate("last(1, whole(ten))") == sel(ten(2)))
        // An index names the instance's index, not its position in the selection.
        #expect(try evaluate("whole(ten)[2]") == sel(ten(2)))
        #expect(try evaluate("split(ten[0])") == .placement(DocumentPlacement(source: ten(0))))
    }

    /// Each evaluation error of section 6.6, at the offset of what failed.
    @Test func evaluationErrorsGiveTheirOffset() {
        let cases: [(String, Int, String)] = [
            ("1 + 4 / 0", 6, "division by zero"),
            ("div(1, 0)", 0, "by zero"), ("mod(k, k - 2)", 0, "by zero"),
            ("ten[3]", 3, "outside ten"), ("ten[k + 2]", 3, "outside ten"),
            ("first(4, ten)", 0, "asks for 4 of 3"), ("last(0 - 1, ten)", 0, "asks for -1"), ("slice(ten, 2, 2)", 0, "outside a selection"),
            ("1 + true", 2, "adds"), ("not 1", 4, "not a truth value"), ("1 < 'a'", 4, "not a number"), ("2 ? 1 : 0", 0, "not a truth value"),
            ("1 == 'a'", 2, "compares"), ("ten == ten", 4, "cannot be compared"), ("-word", 1, "not a number"),
            ("true and 1", 9, "not a truth value"), ("ten + 1", 4, "adds"),
            ("10 * 1" + String(repeating: "0", count: 308), 3, "not finite"),
            ("end(z) + 1", 0, "does not run"),
            ("str(1.5)", 4, "integer or a string"), ("ten[0.5]", 4, "not an integer"), ("box[0]", 3, "cannot be indexed"),
            ("(ten + one)[0]", 11, "only one element"), ("ten.foo", 3, "no run"), ("box.cross", 3, "not a piece"),
            ("equation.zz", 8, "no run"), ("ten[0].cross.cross", 12, "no sub-part"), ("split(one[0])", 0, "one ten or stick"),
            ("k.x", 0, "not a selection"), ("nope + 1", 0, "unknown name 'nope'"), ("1 + abs(1, 2)", 4, "takes 1"),
            ("frobnicate(1)", 0, "unknown function"), ("first('a', ten)", 6, "not an integer"), ("whole(3)", 6, "not a selection"),
        ]
        for (source, at, message) in cases {
            let e = failure(source)
            #expect(e != nil, "\(source) evaluates")
            #expect(e?.at == at, "\(source): at \(e?.at ?? -1), not \(at): \(e?.message ?? "")")
            #expect(e?.message.contains(message) == true, "\(source): \(e?.message ?? "")")
        }
    }

    /// Syntax errors, and the format's limits, each at its offset.
    @Test func syntaxErrorsGiveTheirOffset() {
        let cases: [(String, Int, String)] = [
            ("", 0, "empty"), ("1 +", 3, "expected a value but found the end"), ("(1", 2, "expected ')'"), ("'abc", 0, "not closed"),
            ("1 # 2", 2, "unexpected character '#'"), ("k < 2 < 3", 6, "do not chain"), ("k = 1", 2, "unexpected character '='"),
            ("and", 0, "found 'and'"), ("1 2", 2, "unexpected the number 2"), ("min(1,)", 6, "found ')'"),
            ("ten.", 4, "expected a name"), ("ten[1", 5, "expected ']'"), ("true ? 1", 8, "expected ':'"), ("a_b", 1, "unexpected character '_'"),
            ("1.", 2, "expected a name"), (".5", 0, "found '.'"), ("café", 3, "unexpected character 'é'"),
        ]
        for (source, at, message) in cases {
            do {
                _ = try DocumentExpression(source)
                Issue.record("\(source) parses")
            } catch {
                #expect(error.at == at, "\(source): at \(error.at), not \(at): \(error.message)")
                #expect(error.message.contains(message), "\(source): \(error.message)")
            }
        }
        // 256 nodes are allowed, 257 are not.
        let ok = "max(" + Array(repeating: "1", count: 255).joined(separator: ",") + ")"
        #expect((try? DocumentExpression(ok))?.root.nodeCount == 256)
        let big = "max(" + Array(repeating: "1", count: 256).joined(separator: ",") + ")"
        #expect(throws: ExpressionError.self) { try DocumentExpression(big) }
        // 24 deep is allowed, 25 is not.
        #expect((try? DocumentExpression(String(repeating: "-", count: 23) + "1"))?.root.depth == 24)
        #expect(throws: ExpressionError.self) { try DocumentExpression(String(repeating: "-", count: 24) + "1") }
        // Parentheses add no nodes, but deep nesting is still refused rather than exhausting the stack.
        #expect(throws: ExpressionError.self) { try DocumentExpression(String(repeating: "(", count: 5000) + "1" + String(repeating: ")", count: 5000)) }
        #expect((try? DocumentExpression("((((1))))"))?.root.nodeCount == 1)
        #expect(throws: ExpressionError.self) { try DocumentExpression(String(repeating: "not ", count: 5000) + "true") }
        #expect(throws: ExpressionError.self) { try DocumentExpression(String(repeating: "true ? 1 : ", count: 5000) + "0") }
        // A keyword is never a name.
        #expect(throws: ExpressionError.self) { try DocumentExpression("true(1)") }
    }

    @Test func offsetsCountCodePoints() {
        // 'é' and '€' are one code point each, though more bytes in UTF-8.
        #expect(failure("'é€' == 1")?.at == 5)
    }
}
