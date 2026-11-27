import Foundation

/// Colour-vision simulation for EXP-20 and EXP-6: Machado, Oliveira and Fernandes (2009) at full
/// severity, applied to linear sRGB and clamped, with distances in CIELAB (D65, CIE76). The reader
/// uses it to check the colours a document draws, and the engine's tests use it to check the
/// style's own colours.
public enum ColourVision: String, CaseIterable, CustomStringConvertible, Sendable {
    case normal, protanopia, deuteranopia, tritanopia

    public var description: String { rawValue }

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
    public func lab(_ colour: RGB) -> (l: Double, a: Double, b: Double) {
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
    public func distance(_ a: RGB, _ b: RGB) -> Double {
        let (p, q) = (lab(a), lab(b))
        return ((p.l - q.l) * (p.l - q.l) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b)).squareRoot()
    }

    /// The smallest distance between `a` and `b` with normal vision and the three simulated
    /// deficiencies, and the condition it is seen with.
    public static func worst(_ a: RGB, _ b: RGB) -> (distance: Double, seenWith: ColourVision) {
        allCases.map { ($0.distance(a, b), $0) }.min { $0.0 < $1.0 }!
    }
}
