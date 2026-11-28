#if os(macOS)
import ChalkScript
import struct ChalkScript.Scene
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The small picture of a step's still, or of a moment of the step, that `step.show` returns when asked (section 6.6 of the
/// helper protocol): laid out for the area of the shape asked for whose longer side is 480
/// points, at one pixel per point because it is sent to a model, in the appearance asked for when the
/// document is made for it and otherwise in the appearance it is made for (EXP-20). For a
/// shape the document does not declare, the drawing is laid out for the nearest declared shape,
/// scaled, centred and framed inside that area (EXP-17).
enum StepPicture {
    static let longerSide: Double = 480

    struct Picture {
        var png: Data
        /// The ratio of the area the picture is laid out for.
        var ratio: Double
        /// The ratio of the shape drawn in it when that is not the same: a shape the document is
        /// not made for.
        var drawn: Double?
        /// The layout drawn.
        var layout: String
        /// The appearance asked for and the one drawn in.
        var appearance: AppearanceUse
    }

    /// The longest the stand-in player's clock moves at once on its way to a moment, in seconds.
    static let tick = 1.0 / 240

    /// The picture `moment` seconds into step `step` as the window plays it with the stand-in
    /// voice, which are the seconds of the step's timeline: the step is played, without being
    /// shown, by a player whose clock is moved to the moment, so that the clock is held for the
    /// voice as it is in the window and a moment inside a hold is the picture before the wait.
    @MainActor
    static func scene(_ shaped: ShapedExplainer, area: CGSize, step: Int, atPlayed moment: Double) -> Scene {
        let player = ExplainerPlayer(explainer: shaped, voice: EstimatedVoice(), drivesItself: false)
        player.layOut(for: area)
        player.show(step: step)
        var clock = 0.0
        while clock < moment - 1e-9, case .playing = player.phase {
            let d = min(tick, moment - clock)
            player.advance(by: d)
            clock += d
        }
        return player.scene
    }

    /// The picture of step `step`: its still, or, with `moment`, the picture that many seconds
    /// into it as played.
    @MainActor
    static func png(_ explainer: DocumentExplainer, step: Int, at moment: Double? = nil, ratio: Double, appearance asked: Appearance) -> Picture? {
        let area = Shapes.area(ratio: ratio, longerSide: longerSide)
        // As the window shows a preview: the area is the shape asked for, and a drawing laid out
        // for another shape is scaled, centred and framed in it.
        guard let laid = ShapedExplainer(explainer, ratio: ratio).laidOutExplainer(for: area) as? ShapedExplainer else { return nil }
        let used = laid.use?.used ?? area
        let scene = moment.map { scene(ShapedExplainer(explainer, ratio: ratio), area: area, step: step, atPlayed: $0) } ?? laid.still(after: step)
        let drawn = Shapes.ratio(used)
        let appearance = Appearance.use(asked: asked, madeFor: explainer.appearances)
        let palette = ExplainerStyle.standard.palette(dark: appearance.used.isDark)
        let size = CGSize(width: area.width.rounded(), height: area.height.rounded())
        let view = ExplainerStage(scene: scene)
            .frame(width: size.width, height: size.height)
            .background(palette.sheet.color)
            .environment(\.colorScheme, appearance.used.isDark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let out = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(out, image, nil)
        guard CGImageDestinationFinalize(out) else { return nil }
        let differs = drawn.map { abs($0 - ratio) >= 0.005 } ?? false
        return Picture(png: data as Data, ratio: ratio, drawn: differs ? drawn : nil, layout: laid.shown.resolved.layout, appearance: appearance)
    }
}
#endif
