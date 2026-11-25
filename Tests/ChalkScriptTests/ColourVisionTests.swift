import Foundation
import Testing
@testable import ChalkScript

/// Colour-vision simulation for EXP-6: Machado, Oliveira and Fernandes (2009) at full severity,
/// applied to linear sRGB, with distances in CIELAB (D65, CIE76). Test-only: the app never
/// simulates, it only ships colours that pass.
enum ColourVision: String, CaseIterable, CustomStringConvertible {
    case normal, protanopia, deuteranopia, tritanopia

    var description: String { rawValue }

    /// Machado et al. 2009, severity 1.0, rows applied to linear (r, g, b).
    private var matrix: [[Double]]? {
        switch self {
        case .normal: nil
        case .protanopia:
            [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]
        case .deuteranopia:
            [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]
        case .tritanopia:
            [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]
        }
    }

    /// `colour` as seen with this condition, in CIELAB.
    func lab(_ colour: RGB) -> (l: Double, a: Double, b: Double) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        var rgb = [linear(colour.red), linear(colour.green), linear(colour.blue)]
        if let m = matrix {
            rgb = m.map { row in min(1, max(0, row[0] * rgb[0] + row[1] * rgb[1] + row[2] * rgb[2])) }
        }
        let (r, g, b) = (rgb[0], rgb[1], rgb[2])
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func f(_ t: Double) -> Double {
            let e = 6.0 / 29
            return t > e * e * e ? cbrt(t) : t / (3 * e * e) + 4.0 / 29
        }
        let (fx, fy, fz) = (f(x), f(y), f(z))
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// CIELAB distance between `a` and `b` as seen with this condition.
    func distance(_ a: RGB, _ b: RGB) -> Double {
        let (p, q) = (lab(a), lab(b))
        return ((p.l - q.l) * (p.l - q.l) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b)).squareRoot()
    }

    /// The smallest distance between `a` and `b` with normal vision and the three simulated
    /// deficiencies, and the condition it is seen with.
    static func worst(_ a: RGB, _ b: RGB) -> (distance: Double, seenWith: ColourVision) {
        allCases.map { ($0.distance(a, b), $0) }.min { $0.0 < $1.0 }!
    }
}

/// EXP-6: any two colours shown together in one explainer stay at least 20 apart (CIELAB) under
/// simulated protanopia, deuteranopia and tritanopia, in light and dark.
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

    /// The operations whose colours a subtraction explainer puts on screen, read from its pictures:
    /// every step's finished picture and five moments in each step, for the range's edges, in
    /// both versions. The player's controls and dots add the answer's fill.
    static func operationsShown(by explainer: any Explainer) -> Set<ExplainerOperation> {
        var ops: Set<ExplainerOperation> = [.result]
        var scenes = (-1..<explainer.stepCount).map { explainer.still(after: $0) }
        for step in 0..<explainer.stepCount {
            let d = explainer.script(for: step).duration
            scenes += [0.1, 0.3, 0.5, 0.7, 0.9].map { explainer.scene(step: step, at: d * $0) }
        }
        for element in scenes.flatMap(\.visible) {
            switch element.kind {
            case let .ten(_, style), let .one(_, style), let .stick(_, style), let .circle(_, style):
                switch style {
                case .pencil: break
                case .traded: ops.insert(.trade)
                case .counted: ops.insert(.result)
                }
            case .crossOut: ops.insert(.subtract)
            case let .arrow(_, _, op), let .box(_, _, op): ops.insert(op)
            case .count, .total, .numberTag: ops.insert(.result)
            case let .numeral(n):
                if n.digits.contains(where: { $0.role == .answer }) { ops.insert(.result) }
            case let .equation(line):
                if let mark = line.mark { ops.insert(mark.op) }
                if line.runs.contains(where: { $0.role == .answer }) { ops.insert(.result) }
            case let .ink(_, op): if let op { ops.insert(op) }
            case .target: ops.insert(.result)
            case let .shape(_, paint):
                for ink in [paint.fill, paint.stroke].compactMap({ $0 }) {
                    switch ink {
                    case let .fill(op), let .ink(op), let .soft(op): ops.insert(op)
                    default: break
                    }
                }
            case let .words(_, set):
                switch set.ink {
                case let .fill(op), let .ink(op), let .soft(op): ops.insert(op)
                default: break
                }
            case .divider, .label, .text, .rule, .hint: break
            }
        }
        return ops
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

    @Test func theSubtractionExplainerShowsSubtractTradeAndTheAnswer() {
        var ops: Set<ExplainerOperation> = []
        for (a, b) in Fixture.edges {
            for version in [ExplainerVersion.child, .parent] {
                ops.formUnion(Self.operationsShown(by: Fixture.explainer(a, b, version)))
            }
        }
        #expect(ops == [.subtract, .trade, .result])
    }

    /// Every pair of colours the subtraction explainer shows together, and each of them against
    /// the pencil and the text they mark, light and dark.
    @Test(arguments: [false, true]) func theSubtractionExplainersColoursStayApart(dark: Bool) {
        let p = ExplainerPalette.for(dark: dark)
        var ops: Set<ExplainerOperation> = []
        for (a, b) in Fixture.edges { ops.formUnion(Self.operationsShown(by: Fixture.explainer(a, b))) }
        let shown = ExplainerOperation.allCases.filter(ops.contains)
        for (i, a) in shown.enumerated() {
            for b in shown[(i + 1)...] {
                let c = Self.closest(Self.shown(a, p), Self.shown(b, p))
                #expect(c.distance >= Self.minimum,
                    "\(a.token) \(c.pair.0) and \(b.token) \(c.pair.1) are \(c.distance) apart with \(c.seenWith) (\(dark ? "dark" : "light"))")
            }
            let neutral = Self.closest(Self.shown(a, p), [p.pencil, p.ink])
            #expect(neutral.distance >= Self.minimum,
                "\(a.token) \(neutral.pair.0) and the pencil or text \(neutral.pair.1) are \(neutral.distance) apart with \(neutral.seenWith) (\(dark ? "dark" : "light"))")
        }
    }

    /// The tens-and-ones explainers show the trade colour (the bundle) and the answer's (the
    /// counts and the number made) beside pencil: a pair the subtraction explainer already shows,
    /// checked here from their own pictures.
    @Test(arguments: [false, true]) func theTensAndOnesExplainersShowTradeAndTheAnswerApart(dark: Bool) {
        var ops: Set<ExplainerOperation> = []
        for e in PlaceValueFixture.edges { ops.formUnion(Self.operationsShown(by: e)) }
        #expect(ops == [.trade, .result])
        let p = ExplainerPalette.for(dark: dark)
        let c = Self.closest(Self.shown(.trade, p), Self.shown(.result, p))
        #expect(c.distance >= Self.minimum)
        for op in ops {
            let neutral = Self.closest(Self.shown(op, p), [p.pencil, p.ink])
            #expect(neutral.distance >= Self.minimum, "\(op.token) and the pencil or text are \(neutral.distance) apart")
        }
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
                    "\(a.token) \(c.pair.0) and \(b.token) \(c.pair.1) are \(c.distance) apart with \(c.seenWith) (\(dark ? "dark" : "light"))")
            }
            let neutral = Self.closest(Self.shown(a, p), [p.pencil, p.ink])
            #expect(neutral.distance >= Self.minimum,
                "\(a.token) and the pencil or text are \(neutral.distance) apart with \(neutral.seenWith) (\(dark ? "dark" : "light"))")
        }
    }
}
