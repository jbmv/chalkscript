import ChalkScript
import CoreGraphics
import Foundation

/// Where each piece of a subtraction stands. On the stage, the
/// worksheet is on the left, as the learner draws it (tens, loose ones in columns of five, the box
/// for a traded ten's ones in two columns), and the count area right of the divider. Laid out for
/// a tall drawing area (`stacked`, EXP-17), the worksheet is the same and the count area is under
/// it, below a level divider, with the total under what is counted; the camera then frames the
/// parts each step acts on (EXP-18).
public struct SubtractionLayout: Equatable, Sendable {
    public var tens: [CGRect]
    public var looseOnes: [CGRect]
    public var box: CGRect
    public var boxedOnes: [CGRect]
    public var arrowY: CGFloat
    public var countTens: [CGRect]
    public var countOnes: [CGRect]
    public var dividerFrom: CGPoint
    public var dividerTo: CGPoint
    public var tensLabel: CGPoint
    public var onesLabel: CGPoint
    public var equationCenter: CGPoint
    public var totalAt: CGPoint
    /// The count area is under the worksheet rather than beside it.
    public var stacked: Bool

    /// The count area's right edge on the stage. Tens 40 apart whatever their number would run
    /// off the stage when seven or more tens are left with six or more ones (98 - 20), so the
    /// tens close up to fit, and are 40 apart whenever that fits.
    public static let countRight: CGFloat = 980

    /// Stacked: how far below the worksheet's tens the divider runs and the count area's tens
    /// stand, and the total's baseline under the count area's pieces.
    static let stackedDividerDrop: CGFloat = 290
    static let stackedCountDrop: CGFloat = 320
    static let stackedTotalDrop: CGFloat = 70

    public init(_ p: SubtractionProblem) { self.init(p, stacked: false) }

    public init(_ p: SubtractionProblem, stacked: Bool) {
        self.stacked = stacked
        let x0: CGFloat = 40
        let y0: CGFloat = 150
        let h = Components.tenSize.height
        let gap = min(44, 300 / CGFloat(max(p.minuendTens, 1)))
        tens = (0..<p.minuendTens).map { Components.ten(at: CGPoint(x: x0 + CGFloat($0) * gap, y: y0)) }
        let lx = x0 + CGFloat(p.minuendTens) * gap + 14
        func column(_ i: Int, from x: CGFloat, top y: CGFloat) -> CGRect {
            Components.one(at: CGPoint(x: x + CGFloat(i / 5) * 30, y: y + 4 + CGFloat(i % 5) * 44))
        }
        looseOnes = (0..<p.minuendOnes).map { column($0, from: lx, top: y0) }
        let bx = lx + CGFloat(max(1, (p.minuendOnes + 4) / 5)) * 30 + 26
        box = CGRect(x: bx, y: y0 - 10, width: 80, height: h + 20)
        boxedOnes = (0..<10).map {
            Components.one(at: CGPoint(x: bx + 12 + CGFloat($0 % 2) * 34, y: y0 + 4 + CGFloat($0 / 2) * 44))
        }
        arrowY = y0 - 46
        tensLabel = CGPoint(x: x0, y: 410)
        onesLabel = CGPoint(x: (looseOnes.first ?? box).minX, y: 410)
        equationCenter = CGPoint(x: 500, y: 70)

        let t = p.differenceTens
        let o = p.differenceOnes
        if stacked {
            // Under the worksheet there is room across, so the count area's tens stand 40 apart.
            let cx = x0
            let yc = y0 + Self.stackedCountDrop
            countTens = (0..<t).map { Components.ten(at: CGPoint(x: cx + CGFloat($0) * 40, y: yc)) }
            let clx = t == 0 ? cx + 14 : cx + CGFloat(t - 1) * 40 + 54
            countOnes = (0..<o).map { column($0, from: clx, top: yc) }
            let pieces = countTens + countOnes
            let midX = pieces.dropFirst().reduce(pieces.first ?? .zero) { $0.union($1) }.midX
            totalAt = CGPoint(x: max(pieces.isEmpty ? cx : midX, cx + 60), y: yc + h + Self.stackedTotalDrop)
            let worksheetRight = (p.regroups ? box : (looseOnes.last ?? tens.last ?? box)).maxX
            let right = max(worksheetRight, pieces.last?.maxX ?? cx)
            dividerFrom = CGPoint(x: x0 - 12, y: y0 + Self.stackedDividerDrop)
            dividerTo = CGPoint(x: right + 12, y: y0 + Self.stackedDividerDrop)
        } else {
            let cx: CGFloat = 660
            // The ones start 54 right of the last ten (the tens' 40 apart plus 14), or 14 in
            // when there are no tens; the room is what keeps the last column inside countRight.
            let onesColumns = CGFloat((o + 4) / 5)
            let room = o == 0
                ? Self.countRight - cx - Components.tenSize.width
                : Self.countRight - cx - 54 - (onesColumns - 1) * 30 - Components.oneSide
            let cgap = t > 1 ? min(40, room / CGFloat(t - 1)) : 40
            countTens = (0..<t).map { Components.ten(at: CGPoint(x: cx + CGFloat($0) * cgap, y: y0)) }
            let clx = t == 0 ? cx + 14 : cx + CGFloat(t - 1) * cgap + 54
            countOnes = (0..<o).map { column($0, from: clx, top: y0) }
            dividerFrom = CGPoint(x: 620, y: 120)
            dividerTo = CGPoint(x: 620, y: 420)
            totalAt = CGPoint(x: 800, y: 480)
        }
    }

    // MARK: the parts a shot frames (EXP-18)

    /// The trade's arrow, as drawn from the ten the watched explainer breaks.
    func arrowBounds(_ p: SubtractionProblem) -> CGRect? {
        guard p.regroups, let ten = tens.last else { return nil }
        let points = Components.tradeArrow(from: ten, to: box, y: arrowY)
        return points.dropFirst().reduce(CGRect(origin: points[0], size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
            .insetBy(dx: -Components.tradeWidth, dy: -Components.tradeWidth)
    }

    /// Where the total is set, roughly: a box round its widest text ("80 + 9") on its baseline.
    var totalBounds: CGRect {
        let size = CGFloat(Components.totalSize)
        return CGRect(x: totalAt.x - 95, y: totalAt.y - size * 0.8, width: 190, height: size)
    }

    /// The labels under the worksheet ("tens", "ones"), roughly.
    var labelBounds: CGRect {
        let size = CGFloat(Components.labelSize)
        return CGRect(x: tensLabel.x, y: tensLabel.y - size, width: max(onesLabel.x - tensLabel.x + 50, 50), height: size + 4)
    }

    /// The regions of the drawing by part (`SubtractionPart`), for this problem: a part it does
    /// not draw (no trade, nothing left to count) is absent.
    public func parts(_ p: SubtractionProblem) -> [String: CGRect] {
        func union(_ rects: [CGRect]) -> CGRect? {
            guard let first = rects.first else { return nil }
            return rects.dropFirst().reduce(first) { $0.union($1) }
        }
        var out: [SubtractionPart: CGRect] = [:]
        out[.tens] = union(tens)
        out[.ones] = union(looseOnes + (p.regroups ? [box] : []))
        if p.regroups, let ten = tens.last { out[.tradedTen] = ten }
        out[.arrow] = arrowBounds(p)
        out[.worksheet] = union(tens + looseOnes + (p.regroups ? [box] : []) + [arrowBounds(p), labelBounds].compactMap { $0 })
        out[.count] = union(countTens + countOnes + [totalBounds])
        return Dictionary(uniqueKeysWithValues: out.map { ($0.key.rawValue, $0.value) })
    }

    /// The whole drawing: the worksheet and the count area.
    public func bounds(_ p: SubtractionProblem) -> CGRect {
        let parts = parts(p)
        let worksheet = parts[SubtractionPart.worksheet.rawValue]!
        return parts[SubtractionPart.count.rawValue].map { worksheet.union($0) } ?? worksheet
    }
}

/// A subtraction laid out for a drawing area (EXP-17, EXP-18): the scene has the area's shape, a
/// fixed band across its top holds the problem, and the camera shows the drawing (the stacked
/// layout, in its own units) in the rest, framing the motion file's shots.
public struct SubtractionFrame: Equatable, Sendable {
    /// The scene's width in its own units; its height follows the area's shape.
    public static let width: CGFloat = 640
    /// The band across the top that holds the problem, outside the camera.
    public static let questionBand: CGFloat = 96
    /// The problem's baseline in the band.
    public static let questionBaseline: CGFloat = 70
    /// The widest area, for its height, laid out again: about square or taller, as EXP-17 gives
    /// the drawing in both layouts, with some room. A wider one (a phone in landscape) keeps the
    /// stage, which suits it.
    public static let widest: CGFloat = 1.35

    public var size: CGSize
    public var equationCenter: CGPoint
    public var plan: CameraPlan

    /// Whether a drawing area of `area` points is laid out again, rather than given the stage.
    public static func suits(_ area: CGSize) -> Bool {
        area.width > 0 && area.height > 0 && area.width <= area.height * widest
    }

    init(area: CGSize, layout: SubtractionLayout, problem: SubtractionProblem, motion: ExplainerMotion) {
        let w = Self.width
        let h = (w * area.height / area.width).rounded()
        size = CGSize(width: w, height: h)
        equationCenter = CGPoint(x: w / 2, y: Self.questionBaseline)
        let viewport = CGRect(x: 0, y: Self.questionBand, width: w, height: h - Self.questionBand)
        let world = layout.bounds(problem).insetBy(dx: -motion.margin, dy: -motion.margin)
        plan = CameraPlan.resolve(motion, parts: layout.parts(problem), world: world, viewport: viewport)
    }
}
