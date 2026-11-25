import CoreGraphics
import Foundation

/// Where each piece of an addition stands: the
/// tens on the left (the first number's, then a new ten, then the second number's), the ones in
/// columns of five, and the count right of the divider. The first ten ones stand in two columns
/// of their own, with a gap before the rest, so the box round them never touches the ones left
/// over.
public struct AdditionLayout: Equatable, Sendable {
    /// Every place a ten can stand, in order: as many as the total has tens.
    public var tens: [CGRect]
    /// Every place a one can stand, in order: as many as both numbers have ones.
    public var ones: [CGRect]
    /// The box drawn round the first ten ones when they are bundled.
    public var box: CGRect
    public var arrowY: CGFloat
    /// Where a touch draws a one, or a ten, in do it with me.
    public var onesSide: CGRect
    public var tensSide: CGRect
    public var dividerFrom: CGPoint
    public var dividerTo: CGPoint
    public var tensLabel: CGPoint
    public var onesLabel: CGPoint
    public var equationCenter: CGPoint
    public var totalAt: CGPoint
    public var workedAt: CGPoint

    static let x0: CGFloat = 60
    static let tenGap: CGFloat = 32
    static let onesX: CGFloat = 380
    static let y0: CGFloat = 150

    public init(_ p: AdditionProblem) {
        let (x0, y0, onesX) = (Self.x0, Self.y0, Self.onesX)
        tens = (0..<p.sumTens).map { Components.ten(at: CGPoint(x: x0 + CGFloat($0) * Self.tenGap, y: y0)) }
        ones = (0..<p.onesTotal).map { i in
            let c = i / 5
            return Components.one(at: CGPoint(x: onesX + CGFloat(c) * 30 + (c >= 2 ? 26 : 0), y: y0 + 4 + CGFloat(i % 5) * 44))
        }
        box = CGRect(x: onesX - 12, y: y0 - 10, width: 74, height: Components.tenSize.height + 20)
        arrowY = y0 - 46
        onesSide = CGRect(x: onesX - 30, y: y0 - 30, width: 610 - (onesX - 30), height: 300)
        tensSide = CGRect(x: x0 - 30, y: y0 - 30, width: onesX - 40 - (x0 - 30), height: 300)
        dividerFrom = CGPoint(x: 620, y: 120)
        dividerTo = CGPoint(x: 620, y: 420)
        tensLabel = CGPoint(x: x0, y: 410)
        onesLabel = CGPoint(x: onesX, y: 410)
        equationCenter = CGPoint(x: 500, y: 70)
        totalAt = CGPoint(x: 800, y: 290)
        workedAt = CGPoint(x: 800, y: 345)
    }

    /// Roughly where run `run` of `runs`, the problem across the top, is drawn: the middle of its
    /// width and the bottom of its digits. Each piece comes down from its digit;
    /// the stage measures the problem only as it draws it, so this estimates it from the child
    /// face's advances (a digit about 0.58 of the size, a space about 0.26).
    func digitBottom(_ runs: [String], run: Int, size: Double) -> CGPoint {
        func width(_ s: String) -> CGFloat { s.reduce(0) { $0 + ($1 == " " ? 0.26 : 0.58) } * CGFloat(size) }
        let total = runs.reduce(0) { $0 + width($1) }
        let before = runs.prefix(run).reduce(0) { $0 + width($1) }
        let mid = equationCenter.x - total / 2 + before + width(runs.indices.contains(run) ? runs[run] : "") / 2
        return CGPoint(x: mid, y: equationCenter.y + CGFloat(size) * 0.2)
    }
}
