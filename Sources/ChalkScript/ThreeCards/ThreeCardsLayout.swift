import CoreGraphics
import Foundation

/// Where everything in the three-cards drawing stands, in scene units:
/// the question across the top, the equation of the cards that are up under it, the
/// five cards on their tray, and the three written lines of the work under them, each with its
/// short name to its left.
public enum ThreeCardsLayout {
    public static let cardSize = CGSize(width: 120, height: 136)
    /// The top of a card resting on the tray, and how far a lifted card rises.
    public static let cardTop: CGFloat = 196
    public static let lift: CGFloat = 46
    public static let firstCardX: CGFloat = 100
    public static let cardGap: CGFloat = 165
    public static let cardCorner: CGFloat = 12
    /// A card's outline: in pencil as dealt, thicker once it is up, put back or chosen.
    public static let cardWidth: CGFloat = 2.4
    public static let markedCardWidth: CGFloat = 3.2
    /// A card's number, centred on the card, and its baseline below the card's top.
    public static let cardNumberSize: Double = 72
    public static let cardNumberBaseline: CGFloat = 90
    /// How far a touch may land outside a card and still be on it.
    public static let touchPad: CGFloat = 8

    /// The tray the cards rest on, so a lifted card is seen to be up even when all five are.
    public static let trayY: CGFloat = cardTop + cardSize.height + 12
    public static let trayFrom = CGPoint(x: firstCardX - 30, y: trayY)
    public static let trayTo = CGPoint(x: firstCardX + 4 * cardGap + cardSize.width + 30, y: trayY)
    public static let trayWidth: CGFloat = 3

    public static let questionAt = CGPoint(x: 500, y: 56)
    public static let questionSize: Double = 26
    /// The equation of the cards that are up, centred over them.
    public static let sumCenter = CGPoint(x: 500, y: 126)
    public static let workSize: Double = 32

    /// The written lines: their baselines, where their names end and where their work begins.
    public static let workBaselines: [CGFloat] = [400, 450, 500]
    public static let workLabelX: CGFloat = 452
    public static let workX: CGFloat = 472
    public static let workLabelSize: Double = 18
    /// Try one's note, on the second line's baseline.
    public static let tryNoteAt = CGPoint(x: 500, y: 450)

    /// Card `i` (0 to 4), up by `lift` (0 resting on the tray, 1 lifted).
    public static func card(_ i: Int, lift: Double) -> CGRect {
        CGRect(
            x: firstCardX + CGFloat(i) * cardGap, y: cardTop - lift * Self.lift,
            width: cardSize.width, height: cardSize.height)
    }

    /// The room a number or a sign takes in a written line. Each is set centred in its own room,
    /// so each number can take its colour (EXP-6) without measuring the face: a digit's room is a
    /// little wider than the child face's figures, and a sign's includes the space either side.
    public static func room(_ text: String, sign: Bool, size: Double) -> CGFloat {
        sign ? CGFloat(size) * 1.05 : CGFloat(text.count) * CGFloat(size) * 0.62
    }

    // MARK: Why? (the comparison picture of EXP-7)

    public static let whyTitleAt = CGPoint(x: 500, y: 96)
    public static let whyTitleSize: Double = 26
    /// The bars start at `whyBarX`; all five cards' bar is `whyBarWidth` long.
    public static let whyBarX: CGFloat = 230
    public static let whyBarWidth: CGFloat = 620
    public static let whyBarHeight: CGFloat = 46
    public static let whyAllY: CGFloat = 180
    public static let whyWantY: CGFloat = 290
    public static let whyBarCorner: CGFloat = 3
    public static let whyNameSize: Double = 22
    public static let whyValueSize: Double = 24
    public static let whyWorkAt = CGPoint(x: 500, y: 420)
    public static let dashedDash: [CGFloat] = [8, 6]
    public static let dropDash: [CGFloat] = [6, 6]
}
