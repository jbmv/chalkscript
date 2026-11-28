import Foundation
import Testing
@testable import ChalkScript

/// EXP-6: any two colours the palette gives to operations stay at least 20 apart (CIELAB) under
/// simulated protanopia, deuteranopia and tritanopia, in light and dark. What a particular
/// explainer shows together is checked with its own tests.
struct ColourVisionTests {
    static let minimum = 20.0

    /// The colours an operation can put on screen: its fill and its ink.
    static func shown(_ op: ExplainerOperation, _ p: ExplainerPalette) -> [RGB] {
        let c = p.colors(op)
        return c.fill == c.ink ? [c.ink] : [c.fill, c.ink]
    }

    /// The closest any colour of `a` comes to any colour of `b`.
    static func closest(_ a: [RGB], _ b: [RGB]) -> (distance: Double, seenWith: ColourVision, pair: (RGB, RGB)) {
        var best: (Double, ColourVision, (RGB, RGB))?
        for x in a {
            for y in b {
                let w = ColourVision.worst(x, y)
                if best == nil || w.distance < best!.0 { best = (w.distance, w.seenWith, (x, y)) }
            }
        }
        return best!
    }

    /// The simulation reproduces known distances for these colours, which fixes what the line of
    /// 20 means.
    @Test func reproducesTheFirstCheck() {
        let checks: [(UInt32, UInt32, Double, ColourVision)] = [
            (0xD55E00, 0x0072B2, 91.9, .protanopia),  // subtract and the answer
            (0xD55E00, 0xA8508A, 34.5, .tritanopia),  // subtract and a candidate trade ink
            (0xA8508A, 0x0072B2, 16.2, .protanopia),  // a candidate trade ink and the answer
            (0xA86F00, 0xD55E00, 1.0, .protanopia),  // a candidate multiply ink and subtract
            (0x2A84BE, 0x0072B2, 6.7, .tritanopia),  // a candidate divide ink and the answer
            (0x00805E, 0x0072B2, 10.9, .tritanopia),  // a candidate add ink and the answer
            (0xCC79A7, 0x0072B2, 22.7, .protanopia),  // trade lightened to its fill
        ]
        for (a, b, expected, condition) in checks {
            let w = ColourVision.worst(RGB(hex: a), RGB(hex: b))
            #expect(abs(w.distance - expected) < 0.1, "\(RGB(hex: a)) and \(RGB(hex: b)): \(w.distance)")
            #expect(w.seenWith == condition, "\(RGB(hex: a)) and \(RGB(hex: b)) are closest with \(w.seenWith)")
        }
        // The lightened trade fill has too little contrast with its tint to serve as an ink.
        #expect(RGB(hex: 0xCC79A7).contrast(with: RGB(hex: 0xF5E4EE)) < 3)
    }

    /// Add, multiply and divide have no explainer yet: each is checked as if shown with subtract,
    /// trade and the answer, and with each other, so every pair of operation colours passes and a
    /// later explainer can show any of them together.
    @Test(arguments: [false, true]) func everyPairOfOperationColoursStaysApart(dark: Bool) {
        let p = ExplainerPalette.for(dark: dark)
        let all = ExplainerOperation.allCases
        for (i, a) in all.enumerated() {
            for b in all[(i + 1)...] {
                let c = Self.closest(Self.shown(a, p), Self.shown(b, p))
                #expect(c.distance >= Self.minimum,
                    "\(a) \(c.pair.0) and \(b) \(c.pair.1) are \(c.distance) apart with \(c.seenWith) (\(dark ? "dark" : "light"))")
            }
            let neutral = Self.closest(Self.shown(a, p), [p.pencil, p.ink])
            #expect(neutral.distance >= Self.minimum,
                "\(a) and the pencil or text are \(neutral.distance) apart with \(neutral.seenWith) (\(dark ? "dark" : "light"))")
        }
    }
}

/// The open profile's suggested colours (EXP-20): the values, contrast with each sheet, and
/// separation from each other and from the neutrals the colours are drawn beside.
struct SuggestedColourTests {
    static let values: [String: (light: UInt32, dark: UInt32)] = [
        "orange": (0xC2600A, 0xF59623), "green": (0x1E7B4A, 0x5CCB8A), "purple": (0x8A4FD0, 0xA569E6),
    ]

    func suggested(dark: Bool) throws -> [String: RGB] {
        try #require(ExplainerStyle.profiles["open"]).palette(dark: dark).suggested
    }

    @Test(arguments: [false, true]) func theOpenProfileSuggestsOrangeGreenAndPurpleAtTheirValues(dark: Bool) throws {
        let s = try suggested(dark: dark)
        #expect(Set(s.keys) == Set(Self.values.keys))
        for (name, v) in Self.values { #expect(s[name] == RGB(hex: dark ? v.dark : v.light), "\(name)") }
    }

    @Test(arguments: [false, true]) func theySatisfyTheContrastAndSeparationMeasures(dark: Bool) throws {
        let s = try suggested(dark: dark)
        let p = ExplainerStyle.standard.palette(dark: dark)
        for (name, ink) in s {
            // 3.6:1 on the light sheet and 4.5:1 on the dark one keep the ink 3:1 on its own soft form.
            #expect(ink.contrast(with: p.sheet) >= (dark ? 4.5 : 3.6), "\(name) with the sheet")
            #expect(ColourChecks.contrasts(ink, sheet: p.sheet, dark: dark).soft >= 3, "\(name) on its soft form")
            for (other, neutral) in [("text", p.ink), ("muted", p.muted), ("pencil", p.pencil), ("line", p.line)] {
                let w = ColourVision.worst(ink, neutral)
                #expect(w.distance >= 20, "\(name) and \(other) are \(w.distance) apart with \(w.seenWith)")
            }
        }
        for (a, x) in s {
            for (b, y) in s where a < b {
                let w = ColourVision.worst(x, y)
                #expect(w.distance >= 20, "\(a) and \(b) are \(w.distance) apart with \(w.seenWith)")
            }
        }
    }

    @Test func theMathsProfileFixesTheOperationsAndSuggestsNothing() throws {
        let maths = try #require(ExplainerStyle.profiles["maths"]?.profile)
        #expect(maths.overrides == .explained)
        #expect(Set(maths.fixed.keys) == ["subtract", "trade", "result", "add", "multiply", "divide"])
        #expect(try #require(ExplainerStyle.profiles["maths"]).light.suggested.isEmpty)
        let open = try #require(ExplainerStyle.profiles["open"]?.profile)
        #expect(open.overrides == .free && open.fixed.isEmpty)
        #expect(ExplainerStyle.profiles.values.allSatisfy { $0.issues.filter(\.isProblem).isEmpty })
    }
}

/// The table of colours people name, in the authoring guide, holds values that show (EXP-20).
struct GuideColourTableTests {
    static let guide = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("docs/format/authoring-guide.md")

    /// Each row of the guide's colour table: the name and its light and dark values.
    func rows() throws -> [(name: String, light: RGB, dark: RGB)] {
        let text = try String(contentsOf: Self.guide, encoding: .utf8)
        var out: [(String, RGB, RGB)] = []
        for line in text.split(separator: "\n") where line.hasPrefix("| ") {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
            guard cells.count == 3, let l = RGB(hexString: cells[1]), let d = RGB(hexString: cells[2]) else { continue }
            out.append((cells[0], l, d))
        }
        return out
    }

    @Test func theTableHasTheColoursPeopleName() throws {
        let names = Set(try rows().map(\.name))
        #expect(names.isSuperset(of: ["orange", "teal", "green", "purple", "pink", "blue"]), "\(names)")
    }

    @Test(arguments: [false, true]) func everyColourKeepsItsContrastAndItsDistanceFromTheNeutrals(dark: Bool) throws {
        let p = ExplainerStyle.standard.palette(dark: dark)
        for row in try rows() {
            let ink = dark ? row.dark : row.light
            let k = ColourChecks.contrasts(ink, sheet: p.sheet, dark: dark)
            #expect(k.sheet >= (dark ? 4.5 : 3.6), "\(row.name) with the sheet: \(k.sheet)")
            #expect(k.soft >= 3, "\(row.name) on its soft form: \(k.soft)")
            for (other, neutral) in [("text", p.ink), ("pencil", p.pencil), ("line", p.line)] {
                let w = ColourVision.worst(ink, neutral)
                #expect(w.distance >= 20, "\(row.name) and \(other) are \(w.distance) apart with \(w.seenWith)")
            }
        }
    }
}
