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
