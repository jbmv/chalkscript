#if os(macOS)
import ChalkScript
import struct ChalkScript.Scene
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The small picture of a step's still that `step.show` returns when asked (section 6.6 of the
/// helper protocol): laid out for the area of the shape asked for whose longer side is 480
/// points, at one pixel per point because it is sent to a model, in the light palette. For a
/// shape the document does not declare, the drawing is laid out for the nearest declared shape,
/// scaled, centred and framed inside that area (EXP-17).
enum StepPicture {
    static let longerSide: Double = 480

    /// The picture, the ratio of the area it is laid out for, the ratio of the shape drawn in it
    /// when that is not the same (a shape the document is not made for), and the layout drawn.
    @MainActor
    static func png(_ explainer: DocumentExplainer, step: Int, ratio: Double) -> (png: Data, ratio: Double, drawn: Double?, layout: String)? {
        let area = Shapes.area(ratio: ratio, longerSide: longerSide)
        // As the window shows a preview: the area is the shape asked for, and a drawing laid out
        // for another shape is scaled, centred and framed in it.
        guard let laid = ShapedExplainer(explainer, ratio: ratio).laidOutExplainer(for: area) as? ShapedExplainer else { return nil }
        let used = laid.use?.used ?? area
        let scene = laid.still(after: step)
        let drawn = Shapes.ratio(used)
        let palette = ExplainerStyle.standard.palette(dark: false)
        let size = CGSize(width: area.width.rounded(), height: area.height.rounded())
        let view = ExplainerStage(scene: scene)
            .frame(width: size.width, height: size.height)
            .background(palette.sheet.color)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let out = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(out, image, nil)
        guard CGImageDestinationFinalize(out) else { return nil }
        let differs = drawn.map { abs($0 - ratio) >= 0.005 } ?? false
        return (data as Data, ratio, differs ? drawn : nil, laid.shown.resolved.layout)
    }
}
#endif
