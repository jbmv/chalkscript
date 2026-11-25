import CoreGraphics
import Foundation

/// Where each part of a tens-and-ones explainer stands (a picture 500 high, moved
/// down 20 to sit in the middle of the 540-high stage): the number across the top with its
/// digits together; under it the worksheet
/// drawing, tens on the left and ones on the right, in columns of five; the count on the right
/// of the divider. A ten is the shared ten (`Components.tenSize`), so every explainer draws a
/// ten the same size (EXP-13).
public struct TensOnesLayout: Equatable, Sendable {
    /// How far the picture (500 high) is moved down on the stage.
    public static let dy: CGFloat = 20

    /// Every ten that will be drawn, including the one a bundle makes (the last).
    public var tens: [CGRect]
    /// Every one drawn; with a bundle, the first ten are the ones boxed.
    public var ones: [CGRect]
    /// The box round the ten ones bundled, and the height of the arrow from it to the new ten.
    public var box: CGRect
    public var arrowY: CGFloat
    /// The x the tens digit and the ones digit are centred on, and their baseline.
    public var tensDigitX: CGFloat
    public var onesDigitX: CGFloat
    public var digitBaseline: CGFloat
    /// The top of a digit's slot, and the baseline of the place's name under a ring.
    public var slotTop: CGFloat
    public var placeWordBaseline: CGFloat
    /// Rectangles and squares: the labels under the tens and the ones.
    public var tensLabel: CGPoint
    public var onesLabel: CGPoint
    /// A chart: the headings, and the rule under them and between the places.
    public var tensHeading: CGPoint
    public var onesHeading: CGPoint
    public var headingRuleFrom: CGPoint
    public var headingRuleTo: CGPoint
    public var placeRuleFrom: CGPoint
    public var placeRuleTo: CGPoint
    public var dividerFrom: CGPoint
    public var dividerTo: CGPoint
    /// The total, and the worked form under it.
    public var totalAt: CGPoint
    public var workedAt: CGPoint

    public init(_ q: TensOnesQuestion) {
        let dy = Self.dy
        let y0: CGFloat = 215 + dy
        tens = (0..<q.tens).map { Components.ten(at: CGPoint(x: 70 + CGFloat($0) * 40, y: y0)) }
        // With ten ones to bundle, the ones past the first ten stand clear of the box drawn round
        // them.
        let bundles = q.bundles
        ones = (0..<q.drawnOnes).map { i in
            let column = i / 5
            let x = 478 + CGFloat(column) * 32 + (bundles && column >= 2 ? 24 : 0)
            return Components.one(at: CGPoint(x: x, y: y0 + 4 + CGFloat(i % 5) * 42))
        }
        box = CGRect(x: 466, y: y0 - 10, width: 32 + Components.oneSide + 24, height: 4 * 42 + Components.oneSide + 28)
        arrowY = y0 - 24
        tensDigitX = 312
        onesDigitX = 378
        digitBaseline = 118 + dy
        slotTop = 36 + dy
        placeWordBaseline = 170 + dy
        tensLabel = CGPoint(x: 240, y: 465 + dy)
        onesLabel = CGPoint(x: 550, y: 465 + dy)
        tensHeading = CGPoint(x: 240, y: 172 + dy)
        onesHeading = CGPoint(x: 550, y: 172 + dy)
        headingRuleFrom = CGPoint(x: 40, y: 184 + dy)
        headingRuleTo = CGPoint(x: 650, y: 184 + dy)
        placeRuleFrom = CGPoint(x: 450, y: 150 + dy)
        placeRuleTo = CGPoint(x: 450, y: 450 + dy)
        dividerFrom = CGPoint(x: 690, y: 140 + dy)
        dividerTo = CGPoint(x: 690, y: 440 + dy)
        totalAt = CGPoint(x: 835, y: 300 + dy)
        workedAt = CGPoint(x: 835, y: 360 + dy)
    }

    /// The new ten a bundle makes.
    public var bundledTen: CGRect? { tens.last }

    /// Where bundled one `i` (0 to 9) ends: stacked down the new ten, as ten ones make it.
    public func intoTen(_ i: Int) -> CGPoint {
        guard let ten = bundledTen else { return .zero }
        return CGPoint(x: ten.minX + 1, y: ten.minY + CGFloat(i) * ten.height / 10 + 1)
    }
}
