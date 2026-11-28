import AVFoundation
import ChalkScript
import CoreGraphics
import Foundation
import Testing
@testable import ChalkScriptStudioCore

/// A folder in the temporary folder for a test's videos, removed afterwards.
final class VideoFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("video-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    var files: [String] { (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [] }
}

/// The task a test cancels from inside the export's progress.
@MainActor
final class RunningExport {
    var task: Task<VideoExportResult, Error>?
}

@MainActor
func exportSource(_ model: StudioModel, _ name: String, _ problem: [String: DocumentValue]) throws -> VideoExportSource {
    model.select(name)
    #expect(model.setProblem(problem, for: name).isEmpty)
    return try #require(model.videoExportSource)
}

/// The mean colour of the picture's top left corner, 16 pixels square, in 0 to 255.
func cornerColour(_ image: CGImage) throws -> [Int] {
    var pixel = [UInt8](repeating: 0, count: 4)
    let corner = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: 16, height: 16)))
    let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let c = CGContext(
            data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        c.interpolationQuality = .high
        c.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return true
    }
    #expect(drawn)
    return pixel.prefix(3).map(Int.init)
}

func near(_ colour: [Int], _ wanted: RGB, within tolerance: Int = 6) -> Bool {
    let want = [wanted.red, wanted.green, wanted.blue].map { Int(($0 * 255).rounded()) }
    return zip(colour, want).allSatisfy { abs($0 - $1) <= tolerance }
}

/// The studio writes a video of a document's watched steps (EXP-21).
@MainActor
struct VideoExportTests {
    @Test func theVideoOfEqualGroupsIsOneTrackOf1080pAt30FramesASecondAndLastsWhatItsStepsLast() async throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let source = try exportSource(model, "equal-groups", ["a": .number(3), "b": .number(4)])
        let plan = try VideoExportPlan(source)
        #expect(plan.drawingShape?.title == "Wide")

        // The length expected is worked out from the steps' timelines, not from the export's clock.
        let explainer = try DocumentExplainer(document: source.document, problem: source.problem)
        let laid = try #require(explainer.laidOutExplainer(for: plan.frame.drawingArea(ratio: Preset.wide.nominal).size) as? DocumentExplainer)
        let steps = (0..<laid.stepCount).map { StepTimeline.make(laid, step: $0).length }
        let introHold = max(2, ReadingTime.seconds(explainer.intro))
        let expected = introHold + steps.reduce(0, +) + 2
        #expect(abs(plan.length - expected) < 1e-9)

        let folder = try VideoFolder()
        let url = folder.url.appendingPathComponent("equal-groups.mp4")
        var reported: [Double] = []
        let result = try await VideoExport.write(plan, to: url) { made, whole in
            reported.append(made / whole)
        }
        #expect(folder.files == ["equal-groups.mp4"])
        #expect(reported.last == 1)
        #expect(reported == reported.sorted())

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        #expect(tracks.count == 1)
        let video = try #require(tracks.first)
        #expect(video.mediaType == .video)
        let (size, rate) = try await video.load(.naturalSize, .nominalFrameRate)
        #expect(size == CGSize(width: 1920, height: 1080))
        #expect(abs(rate - 30) < 0.01)
        let duration = try await asset.load(.duration).seconds
        let frame = 1.0 / 30
        #expect(abs(duration - expected) <= Double(steps.count) * frame, "\(duration) against \(expected)")
        #expect(abs(duration - result.length) < 0.001)

        // Each step starts when the intro and the steps before it have lasted.
        #expect(result.stepStarts.count == steps.count)
        var start = introHold
        for (k, length) in steps.enumerated() {
            #expect(abs(result.stepStarts[k] - start) <= Double(k + 1) * frame, "step \(k)")
            start += length
        }
        // The lines shown are the intro's and then each line the steps caption, in order.
        #expect(result.captions.first?.text == explainer.intro.display)
        #expect(result.captions.first?.start == 0)
        #expect(result.captions.last?.end == result.length)
    }

    @Test(arguments: [
        (VideoShape.widescreen, 1920, 1080), (.standard, 1440, 1080), (.custom(width: 9, height: 16), 1080, 1920),
    ])
    func theDrawingIsInsideTheFrameLessTheMarginAndTheCaptionBand(shape: VideoShape, width: Int, height: Int) throws {
        let pixels = try #require(shape.pixels)
        #expect(pixels.width == width)
        #expect(pixels.height == height)
        let frame = VideoFrame(pixelWidth: width, pixelHeight: height, captions: true)
        #expect(frame.size == CGSize(width: width / 2, height: height / 2))
        // 4.5 per cent of the shorter side, 540 points.
        #expect(frame.margin == 24)
        let inside = CGRect(origin: .zero, size: frame.size).insetBy(dx: frame.margin, dy: frame.margin)
        let band = try #require(frame.captionRect)
        #expect(band.height == 70)
        #expect(inside.contains(band))
        #expect(band.maxY == inside.maxY)
        #expect(inside.contains(frame.space))
        #expect(frame.space.maxY == band.minY - 10)
        for ratio in [Preset.tall.nominal, Preset.square.nominal, Preset.wide.nominal] {
            let area = frame.drawingArea(ratio: ratio)
            #expect(frame.space.insetBy(dx: -1e-6, dy: -1e-6).contains(area), "\(shape) at \(ratio)")
            #expect(!area.intersects(band))
            #expect(abs(Double(area.width / area.height) - ratio) < 1e-9)
            // The largest of its shape: it touches the space on two sides.
            #expect(abs(area.width - frame.space.width) < 1e-6 || abs(area.height - frame.space.height) < 1e-6)
            #expect(abs(area.midX - frame.space.midX) < 1e-6)
        }
        #expect(frame.drawingArea(ratio: nil) == frame.space)
    }

    @Test func theDrawingsShapeIsTheOneNearestTheSpaceAmongThoseTheDocumentIsMadeFor() throws {
        let doc = try #require(ExplainerDocument.read(contentsOf: examples[0]).document)
        let shapes = VideoExportPlan.drawingShapes(doc)
        #expect(shapes.map(\.title) == ["Tall", "Square", "Wide"])
        func nearest(_ shape: VideoShape) throws -> String? {
            let p = try #require(shape.pixels)
            return VideoExportPlan.nearestShape(shapes, to: VideoFrame(pixelWidth: p.width, pixelHeight: p.height, captions: true))?.title
        }
        #expect(try nearest(.widescreen) == "Wide")
        #expect(try nearest(.standard) == "Wide")
        #expect(try nearest(.custom(width: 9, height: 16)) == "Tall")
        #expect(try nearest(.custom(width: 1, height: 1)) == "Square")
    }

    @Test func aCancelledExportLeavesNoFileAndKeepsAFileAlreadyThere() async throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let plan = try VideoExportPlan(try exportSource(model, "equal-groups", ["a": .number(3), "b": .number(4)]))
        let folder = try VideoFolder()

        func cancelled(_ url: URL) async {
            let running = RunningExport()
            var most = 0.0
            let task = Task { @MainActor in
                try await VideoExport.write(plan, to: url) { made, _ in
                    most = made
                    if made > 0.5 { running.task?.cancel() }
                }
            }
            running.task = task
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(most > 0.5 && most < plan.length - 1)
        }

        let url = folder.url.appendingPathComponent("cancelled.mp4")
        await cancelled(url)
        #expect(folder.files.isEmpty)

        let kept = folder.url.appendingPathComponent("kept.mp4")
        try Data("an earlier video".utf8).write(to: kept)
        await cancelled(kept)
        #expect(folder.files == ["kept.mp4"])
        #expect(try Data(contentsOf: kept) == Data("an earlier video".utf8))
    }

    @Test func aDarkOnlyDocumentExportsDarkWhateverTheWindowShows() async throws {
        let project = try DarkClock.project(try DarkClock.text())
        let model = try openModel(project)
        model.select(DarkClock.name)
        model.previewAppearance = .light
        let source = try #require(model.videoExportSource)
        #expect(source.appearance == .light)
        let plan = try VideoExportPlan(source)
        #expect(plan.appearance.asked == .light && plan.appearance.used == .dark)

        let folder = try VideoFolder()
        let url = folder.url.appendingPathComponent("clock.mp4")
        let result = try await VideoExport.write(plan, to: url)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let dark = DarkClock.palette(.dark).sheet, light = DarkClock.palette(.light).sheet
        for seconds in [0, result.stepStarts[0] + 0.5, result.length - 0.1] {
            let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
            let corner = try cornerColour(image)
            #expect(near(corner, dark), "\(corner) at \(seconds) s")
            #expect(!near(corner, light))
        }
    }

    @Test func aDocumentMadeForBothIsExportedInTheAppearanceTheWindowShows() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        model.previewAppearance = .dark
        let plan = try VideoExportPlan(try exportSource(model, "subtraction", ["a": .number(54), "b": .number(26)]))
        #expect(plan.appearance.asked == .dark && plan.appearance.used == .dark)
        var clock = VideoExport.Clock(plan)
        _ = clock.advanceFrame()
        let image = try #require(FrameView.image(plan, scene: clock.player.scene, areaUse: clock.player.areaUse, caption: clock.caption))
        #expect(image.width == 1920 && image.height == 1080)
        #expect(near(try cornerColour(image), DarkClock.palette(.dark).sheet, within: 1))
    }

    @Test func theFileIsNamedForTheDocumentAndItsProblem() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let source = try exportSource(model, "subtraction", ["a": .number(54), "b": .number(26)])
        #expect(source.fileName == "Two-digit subtraction by trading a ten (54, 26).mp4")
    }
}
