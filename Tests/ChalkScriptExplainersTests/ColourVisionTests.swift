import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

/// EXP-6: any two colours shown together in one explainer stay at least 20 apart (CIELAB) under
/// simulated protanopia, deuteranopia and tritanopia, in light and dark. The palette's own check,
/// of every pair of operation colours, is in the engine's tests.
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
        func insert(_ hue: Hue) { if case let .operation(op) = hue { ops.insert(op) } }
        for element in scenes.flatMap(\.visible) {
            switch element.kind {
            case let .ten(_, style), let .one(_, style), let .stick(_, style), let .circle(_, style):
                switch style {
                case .pencil: break
                case .traded: ops.insert(.trade)
                case .counted: ops.insert(.result)
                }
            case .crossOut: ops.insert(.subtract)
            case let .arrow(_, _, op), let .box(_, _, op): insert(op)
            case .count, .total, .numberTag: ops.insert(.result)
            case .hueTag: break
            case let .numeral(n):
                if n.digits.contains(where: { $0.role == .answer }) { ops.insert(.result) }
            case let .equation(line):
                if let mark = line.mark { insert(mark.op) }
                if line.runs.contains(where: { $0.role == .answer }) { ops.insert(.result) }
            case let .ink(_, op): if let op { ops.insert(op) }
            case .target: ops.insert(.result)
            case let .shape(_, paint):
                for ink in [paint.fill, paint.stroke].compactMap({ $0 }) {
                    switch ink {
                    case let .fill(hue), let .ink(hue), let .soft(hue): insert(hue)
                    default: break
                    }
                }
            case let .words(_, set):
                switch set.ink {
                case let .fill(hue), let .ink(hue), let .soft(hue): insert(hue)
                default: break
                }
            case .divider, .label, .text, .rule, .hint: break
            }
        }
        return ops
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
                    "\(a) \(c.pair.0) and \(b) \(c.pair.1) are \(c.distance) apart with \(c.seenWith) (\(dark ? "dark" : "light"))")
            }
            let neutral = Self.closest(Self.shown(a, p), [p.pencil, p.ink])
            #expect(neutral.distance >= Self.minimum,
                "\(a) \(neutral.pair.0) and the pencil or text \(neutral.pair.1) are \(neutral.distance) apart with \(neutral.seenWith) (\(dark ? "dark" : "light"))")
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
            #expect(neutral.distance >= Self.minimum, "\(op) and the pencil or text are \(neutral.distance) apart")
        }
    }
}
