import CoreGraphics
import Foundation

/// Where each part of the make-a-ten drawing stands, in scene units:
/// two ten frames of five by two boxes on the left, the top one over the bottom one,
/// the number bond and the worked lines right of the divider, and the problem across the top.
public enum MakeTenLayout {
    /// A box of a ten frame, and the counter drawn in it.
    public static let cell: CGFloat = 56
    public static let counterRadius: CGFloat = 19
    /// The frames' left edge, and the tops of the top and the bottom frame.
    public static let frameX: CGFloat = 150
    public static let topY: CGFloat = 130
    public static let bottomY: CGFloat = 300

    /// The number bond: its top circle's centre and radius, how far down and across its two
    /// parts are, and their radius.
    public static let bondCenter = CGPoint(x: 760, y: 168)
    public static let bondRadius: CGFloat = 32
    public static let bondDX: CGFloat = 64
    public static let bondDY: CGFloat = 96
    public static let bondPartRadius: CGFloat = 27
    /// The two worked lines under the bond, centred on the bond's x: "8 + 2 = 10" and
    /// "10 + 5 = 15".
    public static let workY: (CGFloat, CGFloat) = (386, 440)

    public static let equationCenter = CGPoint(x: 500, y: 70)
    public static let dividerFrom = CGPoint(x: 590, y: 120)
    public static let dividerTo = CGPoint(x: 590, y: 470)
    /// The number each frame holds, written left of it.
    public static let valueX: CGFloat = frameX - 22

    /// Type sizes and strokes.
    public static let valueSize: Double = 24
    public static let bondTextSize: Double = 30
    public static let workSize: Double = 32
    public static let frameWidth: CGFloat = 2.4
    public static let frameLineWidth: CGFloat = 1.6
    public static let frameCorner: CGFloat = 4
    public static let filledWidth: CGFloat = 2.4
    public static let openWidth: CGFloat = 2.8
    public static let markWidth: CGFloat = 2.4
    public static let markDash: [CGFloat] = [4, 5]
    public static let bondWidth: CGFloat = 2.4

    /// How near a dot a drag must start to pick it up, and how far outside the top frame a dot
    /// let go still drops into it.
    public static let pickUp: CGFloat = counterRadius + 12
    public static let dropMargin: CGFloat = 20
    /// How far outside a box or a frame a touch still counts as on it.
    public static let boxPad: CGFloat = 4
    public static let countPad: CGFloat = 6

    /// The top of the top (`top` true) or the bottom frame.
    public static func frameTop(_ top: Bool) -> CGFloat { top ? topY : bottomY }

    /// The centre of box `i` (0 to 9, along the top row, then the bottom row).
    public static func center(top: Bool, _ i: Int) -> CGPoint {
        CGPoint(x: frameX + CGFloat(i % 5) * cell + cell / 2, y: frameTop(top) + CGFloat(i / 5) * cell + cell / 2)
    }

    /// Box `i`, inset 4 from the frame's lines: where a touch counts as on it.
    public static func box(top: Bool, _ i: Int) -> CGRect {
        let c = center(top: top, i)
        return CGRect(x: c.x - cell / 2 + 4, y: c.y - cell / 2 + 4, width: cell - 8, height: cell - 8)
    }

    /// The counter drawn round `c`.
    public static func counter(at c: CGPoint) -> CGRect {
        CGRect(x: c.x - counterRadius, y: c.y - counterRadius, width: 2 * counterRadius, height: 2 * counterRadius)
    }

    /// The whole frame.
    public static func frame(top: Bool) -> CGRect {
        CGRect(x: frameX, y: frameTop(top), width: 5 * cell, height: 2 * cell)
    }

    /// The frame's inner lines: four between the columns and one between the rows.
    public static func frameLines(top: Bool) -> [Outline.Segment] {
        let f = frame(top: top)
        var out: [Outline.Segment] = []
        for c in 1..<5 {
            let x = f.minX + CGFloat(c) * cell
            out += [.move(CGPoint(x: x, y: f.minY)), .line(CGPoint(x: x, y: f.maxY))]
        }
        out += [.move(CGPoint(x: f.minX, y: f.minY + cell)), .line(CGPoint(x: f.maxX, y: f.minY + cell))]
        return out
    }

    /// Whether `p`, where a dot is let go, is over the top frame or near enough to drop into it.
    public static func overTopFrame(_ p: CGPoint) -> Bool {
        frame(top: true).insetBy(dx: -dropMargin, dy: -dropMargin).contains(p)
    }

    /// The bond's two parts' centres: what the ten needs (left) and what is left (right).
    public static var bondLeft: CGPoint { CGPoint(x: bondCenter.x - bondDX, y: bondCenter.y + bondDY) }
    public static var bondRight: CGPoint { CGPoint(x: bondCenter.x + bondDX, y: bondCenter.y + bondDY) }

    /// Where a number is written in a bond circle centred on `c`: its baseline 11 below the
    /// centre.
    public static func bondText(at c: CGPoint) -> CGPoint { CGPoint(x: c.x, y: c.y + 11) }

    /// The number tag shown on the top frame while it is counted as ten, and on a dot while it
    /// is counted on (wide enough for two digits).
    public static func tenTag() -> CGRect { Components.numberTag(on: frame(top: true), ten: true) }

    public static func oneTag(_ i: Int, digits: Int) -> CGRect {
        let b = box(top: false, i)
        let w = max(Components.oneTagSize.width, CGFloat(digits) * 15 + 14)
        let h = Components.oneTagSize.height
        return CGRect(x: b.midX - w / 2, y: b.midY - h / 2, width: w, height: h)
    }
}
