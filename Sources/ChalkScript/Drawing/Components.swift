import CoreGraphics
import CoreText
import Foundation

/// The shared drawing components (EXP-13), as geometry in scene units: every template places its
/// pieces, ghosts, cross-outs, arrows, boxes, count area and digit mark with these, and
/// `ExplainerStage` draws each kind the same way in every explainer.
public enum Components {
    /// A ten: a tall rectangle (EXP-7).
    public static let tenSize = CGSize(width: 22, height: 220)
    /// A one: a small square.
    public static let oneSide: CGFloat = 20
    /// How strongly a ghost, a piece traded or taken away, still shows: it is never erased
    /// (EXP-5).
    public static let ghostOpacity: Double = 0.28
    public static let pieceCorner: CGFloat = 2
    public static let boxCorner: CGFloat = 16

    /// Stroke widths.
    public static let pencilWidth: CGFloat = 2.4
    public static let countedWidth: CGFloat = 2.8
    public static let tradeWidth: CGFloat = 2.4
    public static let crossWidth: CGFloat = 3
    public static let dividerWidth: CGFloat = 2
    public static let dividerDash: [CGFloat] = [4, 7]

    /// Type sizes, in scene units.
    public static let equationSize: Double = 44
    public static let labelSize: Double = 18
    public static let countSize: Double = 26
    public static let totalSize: Double = 54

    /// How far a cross-out reaches past a piece: more for a ten than for a one.
    public static let tenCrossPad: CGFloat = 8
    public static let oneCrossPad: CGFloat = 5

    // MARK: place value (the tens-and-ones explainers)

    /// A ten drawn as a stick: its width, and how far it stops short of the ten's ends.
    public static let stickWidth: CGFloat = 4
    public static let stickInset: CGFloat = 6
    /// The number tag a piece shows while it is counted: wider over a ten than over a one.
    public static let tenTagSize = CGSize(width: 48, height: 34)
    public static let oneTagSize = CGSize(width: 30, height: 34)
    public static let tagCorner: CGFloat = 9
    public static let tagWidth: CGFloat = 2.4
    public static let tagTextSize: Double = 24
    /// The number written across the top, and the slot a digit is written in.
    public static let numeralSize: Double = 88
    public static let slotSize = CGSize(width: 60, height: 100)
    public static let slotCorner: CGFloat = 10
    public static let slotWidth: CGFloat = 2
    public static let slotDash: [CGFloat] = [6, 6]
    /// The pencil ring round a digit read or written, and the place's name under it.
    public static let ringRadii = CGSize(width: 40, height: 58)
    public static let ringWidth: CGFloat = 3
    public static let placeWordSize: Double = 22
    /// A chart's ruled lines and headings, and the worked form under a total.
    public static let ruleWidth: CGFloat = 2
    public static let ruleOpacity: Double = 0.55
    public static let headingSize: Double = 24
    public static let workedSize: Double = 28

    // MARK: the learner's marks (EXP-14) and try one

    /// The learner's own lines: kept in an action's colour, or in pencil while drawn.
    public static let inkWidth: CGFloat = 3.2
    public static let liveInkWidth: CGFloat = 3.2
    /// How long a line that was not read as a mark takes to fade away.
    public static let inkFade: Double = 0.5
    /// The dashed pencil loop round pieces a step looks at.
    public static let hintWidth: CGFloat = 2
    public static let hintDash: [CGFloat] = [3, 6]
    public static let hintOpacity: Double = 0.8
    public static let hintCorner: CGFloat = 18
    public static let hintPad: CGFloat = 12
    /// The answer's dashed box, and the problem and note of try one.
    public static let targetWidth: CGFloat = 2.4
    public static let targetDash: [CGFloat] = [2, 6]
    public static let targetCorner: CGFloat = 14
    public static let problemSize: Double = 72
    public static let noteSize: Double = 26

    /// The loop round `rects`, `hintPad` clear of them.
    public static func hint(around rects: [CGRect]) -> CGRect? {
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -hintPad, dy: -hintPad)
    }

    /// The stick drawn for a ten standing in `rect`: down its middle, short of its ends.
    public static func stick(in rect: CGRect) -> (from: CGPoint, to: CGPoint) {
        (CGPoint(x: rect.midX, y: rect.minY + stickInset), CGPoint(x: rect.midX, y: rect.maxY - stickInset))
    }

    /// The circle drawn for a one standing in `rect`, just inside it so its stroke stays in.
    public static func circle(in rect: CGRect) -> CGRect { rect.insetBy(dx: 1, dy: 1) }

    /// The number tag over `piece`, centred on it.
    public static func numberTag(on piece: CGRect, ten: Bool) -> CGRect {
        let size = ten ? tenTagSize : oneTagSize
        return CGRect(x: piece.midX - size.width / 2, y: piece.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// A bundle's arrow from the top of the box round ten ones over to the top of the new ten, at
    /// height `y`: up, across and down.
    public static func bundleArrow(from box: CGRect, to ten: CGRect, y: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: box.midX, y: box.minY - 6), CGPoint(x: box.midX, y: y),
            CGPoint(x: ten.midX, y: y), CGPoint(x: ten.midX, y: ten.minY - 6),
        ]
    }

    /// The slot a digit centred on `x` is written in, its top at `top`.
    public static func slot(centerX x: CGFloat, top: CGFloat) -> CGRect {
        CGRect(x: x - slotSize.width / 2, y: top, width: slotSize.width, height: slotSize.height)
    }

    /// One digit of a `Numeral` set in `face` as outlines, in scene units: centred on `centerX` by
    /// its advance, its baseline at `baseline`. `ink` is the outlines' bounds: what is drawn.
    /// The stage fills `path`, so the ring centred on `ink` is centred on the digit as drawn.
    public static func glyphs(_ text: String, centerX: CGFloat, baseline: CGFloat, face: CTFont) -> (path: CGPath, ink: CGRect) {
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): face])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x0 = centerX - width / 2
        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let font = attributes[kCTFontAttributeName as String].map { $0 as! CTFont } ?? face
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for (glyph, at) in zip(glyphs, positions) {
                // The face's outlines are y-up; the scene is y-down from the baseline.
                var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x0 + at.x, ty: baseline - at.y)
                if let outline = CTFontCreatePathForGlyph(font, glyph, &transform) { path.addPath(outline) }
            }
        }
        return (path, path.isEmpty ? CGRect(x: centerX, y: baseline, width: 0, height: 0) : path.boundingBoxOfPath)
    }

    /// Where the ring round digit `ring.digit` of `numeral` is centred when set in `face`: on the
    /// digit's ink, or on its slot when it is written there (a written place is ringed on its
    /// slot, a printed digit on its ink, not on the box the face reserves for it, which sits off
    /// the digit's middle).
    public static func ringCentre(_ numeral: Numeral, face: CTFont) -> CGPoint? {
        guard let ring = numeral.ring, numeral.digits.indices.contains(ring.digit) else { return nil }
        let digit = numeral.digits[ring.digit]
        if let slot = digit.slot { return CGPoint(x: slot.midX, y: slot.midY) }
        let ink = glyphs(digit.text, centerX: digit.centerX, baseline: numeral.baseline, face: face).ink
        return CGPoint(x: ink.midX, y: ink.midY)
    }

    /// The ring's ellipse round `centre`.
    public static func ring(at centre: CGPoint) -> CGRect {
        CGRect(x: centre.x - ringRadii.width, y: centre.y - ringRadii.height, width: 2 * ringRadii.width, height: 2 * ringRadii.height)
    }

    public static func ten(at origin: CGPoint) -> CGRect { CGRect(origin: origin, size: tenSize) }
    public static func one(at origin: CGPoint) -> CGRect {
        CGRect(origin: origin, size: CGSize(width: oneSide, height: oneSide))
    }

    /// The cross-out over `piece`: one line from below its left edge to above its right edge,
    /// reaching `pad` past it, as a learner crosses out on paper.
    public static func crossOut(over piece: CGRect, pad: CGFloat) -> (from: CGPoint, to: CGPoint) {
        (CGPoint(x: piece.minX - pad, y: piece.maxY + pad), CGPoint(x: piece.maxX + pad, y: piece.minY - pad))
    }

    /// A trade's arrow from the top of `piece` over to the top of `box`, at height `y`: up, across
    /// and down.
    public static func tradeArrow(from piece: CGRect, to box: CGRect, y: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: piece.midX, y: piece.minY - 8), CGPoint(x: piece.midX, y: y),
            CGPoint(x: box.midX, y: y), CGPoint(x: box.midX, y: box.minY - 8),
        ]
    }

    /// The arrow's head at `tip`, the end of its path, pointing along `direction`, a vector that
    /// need not be a unit vector. A zero or non-finite direction points down.
    public static func arrowHead(at tip: CGPoint, direction: CGVector = CGVector(dx: 0, dy: 1)) -> [CGPoint] {
        let norm = hypot(direction.dx, direction.dy)
        let u = norm > 0 && norm.isFinite ? CGVector(dx: direction.dx / norm, dy: direction.dy / norm) : CGVector(dx: 0, dy: 1)
        // `side` runs across the head and `along` runs the way the arrow travels; for a downward
        // arrow they are x and y.
        func point(side: CGFloat, along: CGFloat) -> CGPoint {
            CGPoint(x: tip.x + u.dy * side + u.dx * along, y: tip.y - u.dx * side + u.dy * along)
        }
        return [point(side: -8, along: -10), point(side: 0, along: 1), point(side: 8, along: -10)]
    }

    /// The head for an arrow along `path`, at its last point, pointing along its last segment
    /// that has length, or down when none has.
    public static func arrowHead(endingPath path: [CGPoint]) -> [CGPoint] {
        guard let tip = path.last else { return [] }
        for (a, b) in zip(path, path.dropFirst()).reversed() where a != b {
            return arrowHead(at: tip, direction: CGVector(dx: b.x - a.x, dy: b.y - a.y))
        }
        return arrowHead(at: tip)
    }

    /// The length of a path through `points`.
    public static func length(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// The part of a path through `points` from its start to `progress` of its length.
    public static func partial(_ points: [CGPoint], _ progress: Double) -> [CGPoint] {
        guard points.count > 1, progress > 0 else { return Array(points.prefix(1)) }
        if progress >= 1 { return points }
        var left = length(points) * progress
        var out = [points[0]]
        for (a, b) in zip(points, points.dropFirst()) {
            let d = hypot(b.x - a.x, b.y - a.y)
            if d >= left {
                let f = d == 0 ? 0 : left / d
                out.append(CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
                return out
            }
            left -= d
            out.append(b)
        }
        return out
    }
}
