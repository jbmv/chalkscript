import CoreGraphics
import Foundation

/// Reading the learner's marks against the drawing (EXP-14): whether a stroke crosses a piece and
/// whether a touch lands on one. Nothing is recognised as handwriting; a mark is only geometry
/// compared with what is drawn, in scene units.
public enum MarkGeometry {
    /// How far a mark moves, at most, and how quickly it ends, to be a tap rather than a stroke.
    public static let tapExtent: CGFloat = 14
    public static let tapDuration: Double = 0.6

    /// Whether a mark with these points, made in `duration` seconds, is a tap.
    public static func isTap(_ points: [CGPoint], duration: Double) -> Bool {
        guard let first = points.first else { return true }
        let xs = points.map(\.x), ys = points.map(\.y)
        let extent = hypot((xs.max() ?? first.x) - (xs.min() ?? first.x), (ys.max() ?? first.y) - (ys.min() ?? first.y))
        return extent < tapExtent && duration < tapDuration
    }

    /// Whether the stroke through `points` crosses `piece`: enough of it runs inside the piece
    /// (grown by `pad`), and it goes at least half way across the piece's width or along half
    /// its length. A ten is tall and thin, so a line across it and a line down part of it both
    /// count.
    public static func crosses(_ points: [CGPoint], _ piece: CGRect, pad: CGFloat = 4) -> Bool {
        let r = piece.insetBy(dx: -pad, dy: -pad)
        var inside: CGFloat = 0
        for (a, b) in zip(points, points.dropFirst()) { inside += lengthInside(a, b, r) }
        guard inside > 0, let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(),
            let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max()
        else { return false }
        let spanX = min(x1, r.maxX) - max(x0, r.minX)
        let spanY = min(y1, r.maxY) - max(y0, r.minY)
        let need = min(piece.width, piece.height) * 0.6
        return inside >= need && (spanX >= piece.width * 0.5 || spanY >= piece.height * 0.5)
    }

    /// How much of a piece's length a stroke has to run, as a share of the most-crossed piece's,
    /// for the piece to count as crossed too. A line drawn through one ten that only clips its
    /// neighbour's edge runs a fifth as far in the neighbour; a line drawn across two pieces on
    /// purpose, even a steeply slanting one, runs at least about a third as far in the shorter.
    public static let crossedShare: CGFloat = 0.3

    /// The length of the stroke through `points` that lies inside `piece` (grown by `pad`).
    public static func lengthInside(_ points: [CGPoint], _ piece: CGRect, pad: CGFloat = 4) -> CGFloat {
        let r = piece.insetBy(dx: -pad, dy: -pad)
        return zip(points, points.dropFirst()).reduce(0) { $0 + lengthInside($1.0, $1.1, r) }
    }

    /// The indices of the pieces the stroke crosses, the one it runs through most first and the
    /// others in their own order. A piece that `crosses` accepts but the stroke only grazes, with
    /// less than `share` of the most-crossed piece's length inside it, is left out.
    public static func crossed(
        _ points: [CGPoint], among pieces: [CGRect], share: CGFloat = crossedShare, pad: CGFloat = 4
    ) -> [Int] {
        let hit = pieces.indices.filter { crosses(points, pieces[$0], pad: pad) }
        let lengths = Dictionary(uniqueKeysWithValues: hit.map { ($0, lengthInside(points, pieces[$0], pad: pad)) })
        guard let top = hit.max(by: { lengths[$0]! < lengths[$1]! }) else { return [] }
        let kept = hit.filter { $0 == top || lengths[$0]! >= share * lengths[top]! }
        return [top] + kept.filter { $0 != top }
    }

    /// Whether `point` is on `piece`, or within `pad` of it.
    public static func inside(_ point: CGPoint, _ piece: CGRect, pad: CGFloat = 8) -> Bool {
        piece.insetBy(dx: -pad, dy: -pad).contains(point)
    }

    /// The length of the segment from `a` to `b` that lies inside `r` (Liang-Barsky clipping).
    static func lengthInside(_ a: CGPoint, _ b: CGPoint, _ r: CGRect) -> CGFloat {
        var t0: CGFloat = 0
        var t1: CGFloat = 1
        let dx = b.x - a.x, dy = b.y - a.y
        for (p, q) in [(-dx, a.x - r.minX), (dx, r.maxX - a.x), (-dy, a.y - r.minY), (dy, r.maxY - a.y)] {
            if p == 0 {
                if q < 0 { return 0 }
                continue
            }
            let t = q / p
            if p < 0 {
                if t > t1 { return 0 }
                t0 = max(t0, t)
            } else {
                if t < t0 { return 0 }
                t1 = min(t1, t)
            }
        }
        return hypot(dx, dy) * (t1 - t0)
    }
}
