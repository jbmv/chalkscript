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
/// shape the document does not declare, it is the area the player uses instead, the nearest
/// declared shape inside that area (EXP-17).
enum StepPicture {
    static let longerSide: Double = 480

    /// The picture, the ratio of the area it is laid out for, and the layout drawn there.
    @MainActor
    static func png(_ explainer: DocumentExplainer, step: Int, ratio: Double) -> (png: Data, ratio: Double, layout: String)? {
        let area = Shapes.area(ratio: ratio, longerSide: longerSide)
        let laid = explainer.laidOutExplainer(for: area) as? DocumentExplainer ?? explainer
        let used = laid.areaUse?.used ?? area
        let scene = laid.still(after: step)
        let palette = ExplainerStyle.standard.palette(dark: false)
        let size = CGSize(width: used.width.rounded(), height: used.height.rounded())
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
        return (data as Data, Double(used.width / used.height), laid.resolved.layout)
    }
}
#endif
