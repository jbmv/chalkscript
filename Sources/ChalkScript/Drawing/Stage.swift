import CoreText
import SwiftUI

/// The faces an explainer is set in (EXP-13): the display face for the problem, counts and
/// lines, its body face for small labels. The app passes its own; the defaults are the
/// system's rounded face, for tests and previews. `displayFace` is the display face as a Core Text
/// font, for a number written large (`Numeral`), which is drawn as the face's outlines so that
/// the ring round a digit can be centred on the digit's ink.
public struct ExplainerFonts: Sendable {
    public var display: @Sendable (CGFloat) -> Font
    public var body: @Sendable (CGFloat) -> Font
    public var displayFace: @Sendable (CGFloat) -> CTFont

    public init(
        display: @escaping @Sendable (CGFloat) -> Font, body: @escaping @Sendable (CGFloat) -> Font,
        displayFace: @escaping @Sendable (CGFloat) -> CTFont = ExplainerFonts.systemFace
    ) {
        self.display = display
        self.body = body
        self.displayFace = displayFace
    }

    /// The system's bold face, as Core Text gives it.
    public static let systemFace: @Sendable (CGFloat) -> CTFont = { size in
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    public static let system = ExplainerFonts(
        display: { .system(size: $0, weight: .bold, design: .rounded) },
        body: { .system(size: $0) })
}

extension EnvironmentValues {
    @Entry public var explainerFonts: ExplainerFonts = .system
}

extension RGB {
    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

/// Draws a `Scene` with the shared components (EXP-13), scaled to fit while keeping the scene's
/// shape (`Scene.size`), in the palette of the environment's style for the view's colour scheme
/// (EXP-6, EXP-19). With a camera, the drawing is seen through it, inside its viewport, and what
/// is out of shot is dimmed; fixed elements stay where they are (EXP-18).
///
/// Given the area the scene was laid out for (`areaUse`), the scene is fitted inside the largest
/// area of that shape in the space, centred, so that a document laid out for a declared shape
/// other than the space's is never drawn larger than that shape (EXP-17).
public struct ExplainerStage: View {
    public var scene: Scene
    /// Nil, or an area used that is the area given, fits the scene to the whole space.
    public var areaUse: AreaUse?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.explainerFonts) private var fonts
    @Environment(\.explainerStyle) private var style

    public init(scene: Scene, areaUse: AreaUse? = nil) {
        self.scene = scene
        self.areaUse = areaUse
    }

    /// The shape of the area used, where it is not the area given.
    var usedRatio: CGFloat? {
        guard let use = areaUse, !use.isGiven, use.used.width > 0, use.used.height > 0 else { return nil }
        return use.used.width / use.used.height
    }

    public var body: some View {
        let palette = style.palette(dark: colorScheme == .dark).overriding(scene.operationColours)
        let canvas = Canvas { context, size in
            Self.draw(scene, in: &context, size: size, with: StageDrawing(palette: palette, fonts: fonts))
        }
        .aspectRatio(scene.size.width / scene.size.height, contentMode: .fit)
        if let r = usedRatio {
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(r, contentMode: .fit)
        } else {
            canvas
        }
    }

    /// The colours drawing `scenes` in a drawing area of `size` points resolves, by palette role:
    /// each scene drawn, as the stage draws it, into a real graphics context, with every role it
    /// resolves recorded. For checking that every colour comes from the style (EXP-6, EXP-19).
    @MainActor
    static func colours(drawing scenes: [Scene], palette: ExplainerPalette, size: CGSize) -> [Ink: RGB] {
        final class Record { var used: [Ink: RGB] = [:] }
        let record = Record()
        for scene in scenes {
            let drawn = palette.overriding(scene.operationColours)
            let drawing = StageDrawing(colour: { ink in
                let c = drawn.rgb(ink)
                record.used[ink] = c
                return c
            }, fonts: .system)
            let view = Canvas { context, area in
                var c = context
                draw(scene, in: &c, size: area, with: drawing)
            }
            .frame(width: size.width, height: size.height)
            _ = ImageRenderer(content: view).cgImage
        }
        return record.used
    }

    /// Draws `scene` into `context`, a drawing area of `size` points.
    static func draw(_ scene: Scene, in context: inout GraphicsContext, size: CGSize, with drawing: StageDrawing) {
        let (s, origin) = scene.fit(in: size)
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: s, y: s)
        var seen = context
        if let camera = scene.camera {
            seen.clip(to: Path(camera.viewport))
            seen.concatenate(camera.transform)
        }
        for element in scene.elements where element.isVisible {
            var layer = element.fixed ? context : seen
            layer.opacity = element.opacity * (1 - (scene.camera?.dimming(of: element) ?? 0))
            if element.transform != .identity { layer.concatenate(element.transform) }
            drawing.draw(element.kind, strokeWidth: element.strokeWidth, in: &layer)
        }
    }
}

/// How each component is drawn. One place, so every explainer draws a ten, a cross-out or a box
/// the same way (EXP-13).
struct StageDrawing {
    /// Every colour drawn is a palette role resolved here (EXP-6), so a style swapped in changes
    /// every one of them, and a test can see which roles a scene draws.
    let colour: (Ink) -> RGB
    let fonts: ExplainerFonts

    init(palette: ExplainerPalette, fonts: ExplainerFonts) {
        self.colour = { palette.rgb($0) }
        self.fonts = fonts
    }

    init(colour: @escaping (Ink) -> RGB, fonts: ExplainerFonts) {
        self.colour = colour
        self.fonts = fonts
    }

    private func c(_ ink: Ink) -> RGB { colour(ink) }

    /// Draws `kind`; `strokeWidth`, when given, replaces the width of the stroke of an arrow, a box
    /// or a hint (a shape's is in its paint).
    func draw(_ kind: SceneElement.Kind, strokeWidth: CGFloat? = nil, in context: inout GraphicsContext) {
        switch kind {
        case let .ten(rect, style), let .one(rect, style):
            piece(rect, style, in: &context)
        case let .stick(rect, style):
            let line = Components.stick(in: rect)
            stroke([line.from, line.to], color: pieceInk(style), width: Components.stickWidth, in: &context)
        case let .circle(rect, style):
            let path = Path(ellipseIn: Components.circle(in: rect))
            context.fill(path, with: .color((style == .counted ? c(.soft(.result)) : c(.sheet)).color))
            context.stroke(path, with: .color(pieceInk(style).color), lineWidth: Components.pencilWidth)
        case let .numberTag(text, rect, scale):
            tag(text, in: rect, scale: scale, hue: .result, in: &context)
        case let .hueTag(text, rect, scale, hue):
            tag(text, in: rect, scale: scale, hue: hue, in: &context)
        case let .numeral(numeral):
            self.numeral(numeral, in: &context)
        case let .text(text, at, style):
            let (font, color): (Font, RGB) =
                switch style {
                case .label: (fonts.body(Components.labelSize), c(.muted))
                case .heading: (fonts.display(Components.headingSize), c(.text))
                case .worked: (fonts.display(Components.workedSize), c(.muted))
                case .problem: (fonts.display(Components.problemSize), c(.text))
                case .note: (fonts.display(Components.noteSize), c(.muted))
                }
            let t = context.resolve(Text(verbatim: text).font(font).foregroundStyle(color.color))
            context.draw(t, at: at, anchor: .bottom)
        case let .rule(from, to):
            var layer = context
            layer.opacity *= Components.ruleOpacity
            stroke([from, to], color: c(.pencil), width: Components.ruleWidth, in: &layer)
        case let .ink(points, op):
            stroke(points, color: op.map { c(.ink(.operation($0))) } ?? c(.muted),
                width: op == nil ? Components.liveInkWidth : Components.inkWidth, in: &context)
        case let .hint(rect, p):
            let path = Path(roundedRect: rect, cornerRadius: Components.hintCorner).trimmedPath(from: 0, to: p)
            var layer = context
            layer.opacity *= Components.hintOpacity
            layer.stroke(path, with: .color(c(.muted).color),
                style: StrokeStyle(lineWidth: strokeWidth ?? Components.hintWidth, lineCap: .round, dash: Components.hintDash))
        case let .target(rect):
            context.stroke(Path(roundedRect: rect, cornerRadius: Components.targetCorner),
                with: .color(c(.fill(.result)).color),
                style: StrokeStyle(lineWidth: Components.targetWidth, lineCap: .round, dash: Components.targetDash))
        case let .shape(outline, paint):
            let path = Self.path(outline)
            if let fill = paint.fill { context.fill(path, with: .color(c(fill).color)) }
            if let stroke = paint.stroke, paint.progress > 0 {
                context.stroke(path.trimmedPath(from: 0, to: min(1, paint.progress)), with: .color(c(stroke).color),
                    style: StrokeStyle(lineWidth: paint.width, lineCap: .round, lineJoin: .round, dash: paint.dash))
            }
        case let .words(text, set):
            let font = set.display ? fonts.display(set.size) : fonts.body(set.size)
            let t = context.resolve(Text(verbatim: text).font(font).foregroundStyle(c(set.ink).color))
            let anchor: UnitPoint =
                switch set.anchor {
                case .leading: .bottomLeading
                case .center: .bottom
                case .trailing: .bottomTrailing
                }
            context.draw(t, at: set.at, anchor: anchor)
        case let .crossOut(from, to, p):
            stroke(Components.partial([from, to], p), color: c(.ink(.subtract)),
                width: Components.crossWidth, in: &context)
        case let .arrow(points, p, op):
            let ink = c(.ink(op))
            let width = strokeWidth ?? Components.tradeWidth
            stroke(Components.partial(points, p), color: ink, width: width, in: &context)
            if p >= 1 {
                stroke(Components.arrowHead(endingPath: points, scale: Components.arrowHeadScale(forWidth: width)), color: ink, width: width,
                    in: &context)
            }
        case let .box(rect, p, op):
            let path = Path(roundedRect: rect, cornerRadius: Components.boxCorner).trimmedPath(from: 0, to: p)
            context.stroke(path, with: .color(c(.ink(op)).color),
                style: StrokeStyle(lineWidth: strokeWidth ?? Components.tradeWidth, lineCap: .round, lineJoin: .round))
        case let .divider(from, to):
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(c(.line).color),
                style: StrokeStyle(lineWidth: Components.dividerWidth, dash: Components.dividerDash))
        case let .label(text, at):
            let t = context.resolve(Text(verbatim: text).font(fonts.body(Components.labelSize))
                .foregroundStyle(c(.muted).color))
            context.draw(t, at: at, anchor: .bottomLeading)
        case let .equation(line):
            equation(line, in: &context)
        case let .count(text, at):
            let t = context.resolve(Text(verbatim: text).font(fonts.display(Components.countSize))
                .foregroundStyle(c(.ink(.result)).color))
            context.draw(t, at: at, anchor: .bottom)
        case let .total(text, at, scale):
            let t = context.resolve(Text(verbatim: text).font(fonts.display(Components.totalSize))
                .foregroundStyle(c(.ink(.result)).color))
            var layer = context
            layer.translateBy(x: at.x, y: at.y)
            layer.scaleBy(x: scale, y: scale)
            layer.draw(t, at: .zero, anchor: .bottom)
        }
    }

    /// A number card in `rect`, in `hue`, grown by `scale` about its centre.
    private func tag(_ text: String, in rect: CGRect, scale: Double, hue: Hue, in context: inout GraphicsContext) {
        var layer = context
        layer.translateBy(x: rect.midX, y: rect.midY)
        layer.scaleBy(x: scale, y: scale)
        let card = Path(
            roundedRect: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height),
            cornerRadius: Components.tagCorner)
        let ink = c(.ink(hue))
        layer.fill(card, with: .color(c(.sheet).color))
        layer.stroke(card, with: .color(ink.color), lineWidth: Components.tagWidth)
        let t = layer.resolve(Text(verbatim: text).font(fonts.display(Components.tagTextSize)).foregroundStyle(ink.color))
        layer.draw(t, at: .zero, anchor: .center)
    }

    /// An explainer's own outline as a path.
    static func path(_ outline: Outline) -> Path {
        switch outline {
        case let .rect(r, corner): return corner > 0 ? Path(roundedRect: r, cornerRadius: corner) : Path(r)
        case let .ellipse(r): return Path(ellipseIn: r)
        case let .lines(points, closed):
            var p = Path()
            p.addLines(points)
            if closed { p.closeSubpath() }
            return p
        case let .path(segments):
            var p = Path()
            for s in segments {
                switch s {
                case let .move(to): p.move(to: to)
                case let .line(to): p.addLine(to: to)
                case let .quad(to, control): p.addQuadCurve(to: to, control: control)
                case let .curve(to, c1, c2): p.addCurve(to: to, control1: c1, control2: c2)
                case .close: p.closeSubpath()
                }
            }
            return p
        }
    }

    private func piece(_ rect: CGRect, _ style: PieceStyle, in context: inout GraphicsContext) {
        let path = Path(roundedRect: rect, cornerRadius: Components.pieceCorner)
        let (fill, ink, width): (RGB, RGB, CGFloat) =
            switch style {
            case .pencil: (c(.sheet), c(.pencil), Components.pencilWidth)
            case .traded: (c(.sheet), c(.ink(.trade)), Components.pencilWidth)
            case .counted: (c(.soft(.result)), c(.ink(.result)), Components.countedWidth)
            }
        context.fill(path, with: .color(fill.color))
        context.stroke(path, with: .color(ink.color), lineWidth: width)
    }

    /// The ink a piece is drawn in, by its style.
    private func pieceInk(_ style: PieceStyle) -> RGB {
        switch style {
        case .pencil: c(.pencil)
        case .traded: c(.ink(.trade))
        case .counted: c(.ink(.result))
        }
    }

    /// A number written large: each digit as the face's outlines, its slot when it is to be
    /// written, and the pencil ring centred on the ringed digit's ink (or its slot), with the
    /// place's name under it.
    private func numeral(_ numeral: Numeral, in context: inout GraphicsContext) {
        let face = fonts.displayFace(CGFloat(numeral.size))
        for digit in numeral.digits {
            if let slot = digit.slot {
                context.stroke(
                    Path(roundedRect: slot, cornerRadius: Components.slotCorner), with: .color(c(.line).color),
                    style: StrokeStyle(lineWidth: Components.slotWidth, dash: Components.slotDash))
            }
            let color: RGB =
                switch digit.role {
                case .printed: c(.text)
                case .answer: c(.ink(.result))
                case .unknown: c(.muted)
                }
            var layer = context
            layer.opacity *= digit.opacity
            let glyphs = Components.glyphs(digit.text, centerX: digit.centerX, baseline: numeral.baseline, face: face)
            layer.fill(Path(glyphs.path), with: .color(color.color))
        }
        guard let ring = numeral.ring, let centre = Components.ringCentre(numeral, face: face) else { return }
        let outline = Path(ellipseIn: Components.ring(at: centre)).trimmedPath(from: 0, to: ring.progress)
        context.stroke(outline, with: .color(c(.pencil).color), style: StrokeStyle(lineWidth: Components.ringWidth, lineCap: .round))
        var layer = context
        layer.opacity *= ring.wordOpacity
        let word = layer.resolve(Text(verbatim: ring.word).font(fonts.display(Components.placeWordSize)).foregroundStyle(c(.pencil).color))
        layer.draw(word, at: CGPoint(x: centre.x, y: numeral.wordBaseline), anchor: .bottom)
    }

    private func stroke(_ points: [CGPoint], color: RGB, width: CGFloat, in context: inout GraphicsContext) {
        guard points.count > 1 else { return }
        var path = Path()
        path.addLines(points)
        context.stroke(path, with: .color(color.color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// The problem, run by run, centred; the marked run takes its action's colour and sits on a
    /// pale tint that grows in (EXP-5).
    private func equation(_ line: EquationLine, in context: inout GraphicsContext) {
        let font = fonts.display(line.size)
        let resolved = line.runs.enumerated().map { i, run -> (GraphicsContext.ResolvedText, CGSize) in
            let color: RGB =
                if let mark = line.mark, mark.run == i {
                    c(.ink(mark.op))
                } else {
                    switch run.role {
                    case .answer: c(.ink(.result))
                    case let .hue(hue): c(.ink(hue))
                    case .plain: c(.text)
                    }
                }
            let text = context.resolve(Text(verbatim: run.text).font(font).foregroundStyle(color.color))
            return (text, text.measure(in: CGSize(width: 10_000, height: 10_000)))
        }
        let width = resolved.reduce(0) { $0 + $1.1.width }
        var x = line.center.x - width / 2
        for (i, (text, size)) in resolved.enumerated() {
            if let mark = line.mark, mark.run == i, mark.progress > 0 {
                let box = CGRect(x: x - 8, y: line.center.y - size.height + 4, width: size.width + 16, height: size.height)
                let p = mark.progress
                let scaled = box.insetBy(dx: box.width * (1 - (0.6 + 0.4 * p)) / 2, dy: box.height * (1 - (0.6 + 0.4 * p)) / 2)
                var layer = context
                layer.opacity = p
                layer.fill(Path(roundedRect: scaled, cornerRadius: 10), with: .color(c(.soft(mark.op)).color))
            }
            var layer = context
            layer.opacity = line.runs[i].opacity
            layer.draw(text, at: CGPoint(x: x, y: line.center.y), anchor: .bottomLeading)
            x += size.width
        }
    }
}
