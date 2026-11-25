import CoreGraphics
import Foundation

/// Easing curves, as CSS names them. Each returns exactly 0 at 0 and exactly 1 at 1, so the
/// end of a motion is the step's still picture with no rounding between them (EXP-11).
public enum Easing: Equatable, Sendable {
    case linear
    /// CSS `ease-out`: cubic-bezier(0, 0, .58, 1).
    case easeOut
    /// CSS `ease-in-out`: cubic-bezier(.42, 0, .58, 1).
    case easeInOut
    /// Any CSS cubic-bezier(x1, y1, x2, y2).
    case cubic(Double, Double, Double, Double)

    public func callAsFunction(_ p: Double) -> Double {
        if p <= 0 { return 0 }
        if p >= 1 { return 1 }
        switch self {
        case .linear: return p
        case .easeOut: return Self.bezier(0, 0, 0.58, 1, p)
        case .easeInOut: return Self.bezier(0.42, 0, 0.58, 1, p)
        case let .cubic(x1, y1, x2, y2): return Self.bezier(x1, y1, x2, y2, p)
        }
    }

    /// The y of a CSS cubic Bezier at x = `p` (bisection on x, which is monotonic for CSS curves).
    private static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ p: Double) -> Double {
        func coord(_ a: Double, _ b: Double, _ s: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
        }
        var lo = 0.0
        var hi = 1.0
        var s = p
        for _ in 0..<40 {
            s = (lo + hi) / 2
            if coord(x1, x2, s) < p { lo = s } else { hi = s }
        }
        return coord(y1, y2, s)
    }
}

/// How far a motion that starts at `start` and lasts `duration` seconds has got at `t`, 0 to 1,
/// eased. A motion of no length is done once it has started.
public func progress(_ t: Double, start: Double, duration: Double, _ easing: Easing = .linear) -> Double {
    if duration <= 0 { return t >= start ? 1 : 0 }
    return easing((t - start) / duration)
}

/// `a` to `b` by `p`, returning `a` and `b` exactly at the ends.
public func mix(_ a: Double, _ b: Double, _ p: Double) -> Double {
    if p <= 0 { return a }
    if p >= 1 { return b }
    return a + (b - a) * p
}

public func mix(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint {
    CGPoint(x: mix(a.x, b.x, p), y: mix(a.y, b.y, p))
}

/// The value of a keyframed motion at overall progress `p`: keyframes are (offset, value) with
/// offsets from 0 to 1, interpolated linearly between them, as a web animation
/// does when the easing is given for the whole motion.
public func keyframes(_ frames: [(Double, CGPoint)], _ p: Double) -> CGPoint {
    guard let first = frames.first, let last = frames.last else { return .zero }
    if p <= first.0 { return first.1 }
    if p >= last.0 { return last.1 }
    for (a, b) in zip(frames, frames.dropFirst()) where p <= b.0 {
        return mix(a.1, b.1, (p - a.0) / (b.0 - a.0))
    }
    return last.1
}

public func keyframes(_ frames: [(Double, Double)], _ p: Double) -> Double {
    keyframes(frames.map { ($0.0, CGPoint(x: $0.1, y: 0)) }, p).x
}
