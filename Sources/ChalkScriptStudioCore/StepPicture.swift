#if os(macOS)
import ChalkScript
import struct ChalkScript.Scene
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The small picture of a step's still that `step.show` returns when asked (section 6.6 of the
/// helper protocol): about 480 by 260 points at one pixel per point, because it is sent to a
/// model, in the light palette.
enum StepPicture {
    static let size = CGSize(width: 480, height: 260)

    @MainActor
    static func png(_ explainer: DocumentExplainer, step: Int) -> Data? {
        let laid = explainer.laidOutExplainer(for: size)
        let scene = laid.still(after: step)
        let palette = ExplainerStyle.standard.palette(dark: false)
        let height = (size.width * scene.size.height / scene.size.width).rounded()
        let view = ExplainerStage(scene: scene)
            .frame(width: size.width, height: height)
            .background(palette.sheet.color)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let out = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(out, image, nil)
        guard CGImageDestinationFinalize(out) else { return nil }
        return data as Data
    }
}
#endif
