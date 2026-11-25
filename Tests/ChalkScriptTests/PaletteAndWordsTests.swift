import Foundation
import Testing
@testable import ChalkScript

/// The colour tokens of EXP-6 and the spoken numbers of EXP-10.
struct PaletteTests {
    @Test func theTokensAreEXP6sTable() {
        let light = ExplainerPalette.light
        let dark = ExplainerPalette.dark
        let table: [(ExplainerOperation, String, String, String)] = [
            (.subtract, "#D55E00", "#D55E00", "#F08A4B"),
            (.trade, "#CC79A7", "#A04676", "#D28CA9"),
            (.result, "#0072B2", "#0072B2", "#5AA7E0"),
            (.add, "#4D6B43", "#4D6B43", "#95E3A5"),
            (.multiply, "#6B4301", "#6B4301", "#FED252"),
            (.divide, "#3937A2", "#3937A2", "#6A72D8"),
        ]
        for (op, fill, ink, darkValue) in table {
            #expect(light.colors(op).fill.hex == fill, "\(op.token) light fill")
            #expect(light.colors(op).ink.hex == ink, "\(op.token) light ink")
            #expect(dark.colors(op).fill.hex == darkValue, "\(op.token) dark")
            #expect(dark.colors(op).ink.hex == darkValue, "\(op.token) dark")
        }
        #expect(Set(ExplainerOperation.allCases.map(\.token)) == ["--op-sub", "--op-trade", "--op-result", "--op-add", "--op-mul", "--op-div"])
    }

    /// Thin strokes and text use the ink value, at least 3:1 with the sheet (EXP-6), in light
    /// and dark; so do the pencil and the text.
    @Test(arguments: [false, true]) func inkKeepsThreeToOneWithTheSheet(dark: Bool) {
        let p = ExplainerPalette.for(dark: dark)
        for op in ExplainerOperation.allCases {
            let c = p.colors(op).ink.contrast(with: p.sheet)
            #expect(c >= 3, "\(op.token) ink is \(c):1 on the \(dark ? "dark" : "light") sheet")
        }
        #expect(p.pencil.contrast(with: p.sheet) >= 4.5)
        #expect(p.ink.contrast(with: p.sheet) >= 4.5)
        // The marked digit sits on its operation's tint.
        for op in ExplainerOperation.allCases {
            #expect(p.colors(op).ink.contrast(with: p.colors(op).soft) >= 3, "\(op.token) ink on its tint")
        }
        // The answer's ink on its count-area fill, and the Watch control's label on its fill.
        #expect(p.onResult.contrast(with: p.colors(.result).fill) >= 3)
    }

    @Test func pencilPiecesAreNotColouredByPlace() {
        // EXP-6: a ten and a one on the worksheet are both pencil.
        let e = Fixture.explainer(54, 26)
        let worksheet = e.still(after: 0).visible.filter { $0.id.hasPrefix("ten.") || $0.id.hasPrefix("one.") }
        let styles = worksheet.compactMap { el -> PieceStyle? in
            switch el.kind {
            case let .ten(_, s), let .one(_, s): s
            default: nil
            }
        }
        #expect(styles.count == 9)
        #expect(Set(styles) == [.pencil])
    }
}

struct NumberWordsTests {
    @Test func wordsForTheShownNumbers() {
        #expect(NumberWords.spoken(0) == "zero")
        #expect(NumberWords.spoken(8) == "eight")
        #expect(NumberWords.spoken(13) == "thirteen")
        #expect(NumberWords.spoken(20) == "twenty")
        #expect(NumberWords.spoken(28) == "twenty-eight")
        #expect(NumberWords.spoken(54) == "fifty-four")
        #expect(NumberWords.spoken(99) == "ninety-nine")
    }

    /// EXP-10: the spoken form of every number the template can show (0 to 99) reads back as the
    /// shown number, and no two numbers share words.
    @Test func everyNumberInRangeReadsBackAsItself() {
        var seen: [String: Int] = [:]
        for n in 0...99 {
            let words = NumberWords.spoken(n)
            #expect(NumberWords.number(from: words) == n, "\(n) is spoken '\(words)'")
            let hasDigits = words.contains { $0.isNumber }
            #expect(!hasDigits, "\(n) is spoken with digits: '\(words)'")
            #expect(seen[words] == nil, "\(n) and \(seen[words] ?? -1) are both '\(words)'")
            seen[words] = n
        }
    }

    @Test func numeralsInALineAreReplaced() {
        #expect(NumberWords.replacingNumerals(in: "54 minus 26. Let's see how!") == "fifty-four minus twenty-six. Let's see how!")
        #expect(NumberWords.replacingNumerals(in: "20 plus 8 is 28.") == "twenty plus eight is twenty-eight.")
        #expect(NumberWords.replacingNumerals(in: "no numbers") == "no numbers")
    }
}
