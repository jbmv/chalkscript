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

        func cancelled(_ url: URL, _ plan: VideoExportPlan = plan) async {
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

        // The same with a subtitle track being written beside the pictures.
        var settings = VideoExportSettings()
        settings.captions = .both
        let subtitled = try VideoExportPlan(try #require(model.videoExportSource), settings: settings)
        await cancelled(url, subtitled)
        #expect(folder.files == ["kept.mp4"])
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

    // MARK: the choices

    @Test func aCustomShapeIs1080OnItsShorterSideAndIsRefusedBeyond3To1() {
        func size(_ w: Double, _ h: Double) -> [Int]? { VideoShape.custom(width: w, height: h).pixels.map { [$0.width, $0.height] } }
        #expect(size(9, 16) == [1080, 1920])
        #expect(size(2.35, 1) == [2538, 1080])
        #expect(size(1, 1) == [1080, 1080])
        #expect(size(16, 9) == [1920, 1080])
        #expect(size(3, 1) == [3240, 1080])
        #expect(size(1, 3) == [1080, 3240])
        #expect(VideoShape.custom(width: 3, height: 1).refusal == nil)
        #expect(size(5, 1) == nil)
        #expect(VideoShape.custom(width: 5, height: 1).refusal == "Choose a shape no wider than 3 to 1.")
        #expect(VideoShape.custom(width: 1, height: 5).refusal == "Choose a shape no taller than 1 to 3.")
        #expect(VideoShape.custom(width: 0, height: 9).refusal == "Type two numbers greater than zero, such as 9 and 16.")
        #expect(VideoShape.custom(width: .nan, height: 9).pixels == nil)
        #expect(VideoShape.widescreen.refusal == nil && VideoShape.standard.refusal == nil)
    }

    @Test func theLineUnderTheControlsGivesTheSizeAndTheLengthAsTheyChange() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let source = try exportSource(model, "subtraction", ["a": .number(54), "b": .number(26)])
        var settings = VideoExportSettings()
        #expect(try VideoExportPlan(source, settings: settings).summary == "1920 × 1080 pixels · about 38 seconds")
        settings.pause = 1
        #expect(try VideoExportPlan(source, settings: settings).summary == "1920 × 1080 pixels · about 43 seconds")
        settings.shapeChoice = .standard
        #expect(try VideoExportPlan(source, settings: settings).summary == "1440 × 1080 pixels · about 43 seconds")
        settings.shapeChoice = .custom
        (settings.customWidth, settings.customHeight) = (9, 16)
        settings.pause = 2
        let upright = try VideoExportPlan(source, settings: settings)
        // The tall layout's steps are longer, and there are five pauses of two seconds.
        #expect(upright.drawingShape?.title == "Tall")
        #expect(upright.summary == "1080 × 1920 pixels · about 50 seconds")
        settings.customWidth = 5
        settings.customHeight = 1
        #expect(throws: VideoExportError("Choose a shape no wider than 3 to 1.")) { try VideoExportPlan(source, settings: settings) }
    }

    @Test func theChosenDrawingShapeAppearanceAndCaptionsAreThePlans() throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let source = try exportSource(model, "subtraction", ["a": .number(54), "b": .number(26)])
        var settings = VideoExportSettings()
        settings.shapeChoice = .standard
        settings.drawingShape = "Square"
        settings.appearance = .dark
        settings.captions = .subtitles
        let plan = try VideoExportPlan(source, settings: settings)
        #expect(plan.drawingShape?.title == "Square")
        #expect(plan.appearance.used == .dark)
        #expect(plan.subtitles)
        // Without the caption's band the drawing has the whole frame inside the margin.
        #expect(plan.frame.captionRect == nil)
        #expect(plan.frame.space == CGRect(x: 24, y: 24, width: 672, height: 492))
        #expect(plan.drawingArea.height == 492)
        // A shape the document is not made for is not taken: the nearest to the space is, which
        // without the caption's band is Square in a 4:3 frame.
        settings.drawingShape = "Round"
        #expect(try VideoExportPlan(source, settings: settings).drawingShape?.title == "Square")
        for captions in VideoCaptions.allCases {
            settings.captions = captions
            let plan = try VideoExportPlan(source, settings: settings)
            #expect(plan.frame.captions == (captions == .inPicture || captions == .both))
            #expect(plan.subtitles == (captions == .subtitles || captions == .both))
        }
    }

    @Test func theChoicesAreRememberedExceptTheDrawingsShapeAndTheAppearance() throws {
        let suite = "video-export-\(UUID().uuidString.prefix(8))"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(VideoExportSettings(defaults: defaults) == VideoExportSettings())

        var chosen = VideoExportSettings()
        chosen.shapeChoice = .custom
        (chosen.customWidth, chosen.customHeight) = (9, 16)
        chosen.captions = .both
        chosen.pause = 0.5
        chosen.drawingShape = "Tall"
        chosen.appearance = .dark
        chosen.save(to: defaults)

        let read = VideoExportSettings(defaults: try #require(UserDefaults(suiteName: suite)))
        #expect(read.shape == .custom(width: 9, height: 16))
        #expect(read.captions == .both)
        #expect(read.pause == 0.5)
        #expect(read.drawingShape == nil)
        #expect(read.appearance == nil)

        // The custom shape's numbers are kept while another shape is chosen.
        var next = read
        next.shapeChoice = .widescreen
        next.save(to: defaults)
        let later = VideoExportSettings(defaults: defaults)
        #expect(later.shape == .widescreen)
        #expect(later.customWidth == 9 && later.customHeight == 16)
    }

    @Test func aPauseOfOneSecondLengthensTheVideoByOneSecondForEachStepChange() async throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let source = try exportSource(model, "equal-groups", ["a": .number(3), "b": .number(4)])
        var settings = VideoExportSettings()
        let straight = try VideoExportPlan(source, settings: settings)
        settings.pause = 1
        let paused = try VideoExportPlan(source, settings: settings)
        let changes = straight.stepLengths.count - 1
        #expect(changes == 2)
        #expect(abs(paused.length - straight.length - Double(changes)) < 1e-9)
        #expect(try VideoExport.Timing(paused).frames - VideoExport.Timing(straight).frames == 30 * changes)

        let folder = try VideoFolder()
        let url = folder.url.appendingPathComponent("paused.mp4")
        let result = try await VideoExport.write(paused, to: url)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - (Double(try VideoExport.Timing(straight).frames) / 30 + Double(changes))) < 0.001)
        // Each step but the first begins a second after the one before it has ended.
        let unpaused = try VideoExport.Timing(straight).stepStarts
        for k in result.stepStarts.indices {
            #expect(abs(result.stepStarts[k] - unpaused[k] - Double(k)) < 0.001, "step \(k)")
        }
    }

    @Test func theSubtitleTrackOfTheSubtractionExampleHoldsItsLinesWithTheTimesThePlayerShowsThem() async throws {
        let project = try TemporaryProject()
        let model = try openModel(project)
        let source = try exportSource(model, "subtraction", ["a": .number(54), "b": .number(26)])
        var settings = VideoExportSettings()
        settings.captions = .subtitles
        let plan = try VideoExportPlan(source, settings: settings)
        let folder = try VideoFolder()
        let url = folder.url.appendingPathComponent("subtitled.mp4")
        let result = try await VideoExport.write(plan, to: url)

        // The lines the player shows: the intro's, then each line a step captions, in order.
        let explainer = try DocumentExplainer(document: source.document, problem: source.problem)
        let laid = try #require(explainer.laidOutExplainer(for: plan.drawingArea.size) as? DocumentExplainer)
        var lines = [explainer.intro.display]
        var firstOfStep: [Int] = []
        for k in 0..<laid.stepCount {
            firstOfStep.append(lines.count)
            for event in laid.script(for: k).events {
                if case let .say(line, true) = event.action, line.display != lines.last { lines.append(line.display) }
            }
        }
        #expect(lines.count == 9)
        #expect(lines.first == "54 minus 26. Let's see how!")
        #expect(lines.last == "54 minus 26 is 28!")
        #expect(result.captions.map(\.text) == lines)

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        #expect(tracks.map(\.mediaType) == [.video, .subtitle])
        let track = try #require(tracks.last)
        #expect(try await track.load(.isEnabled) == false)
        #expect(try await track.load(.extendedLanguageTag) == "en-US")
        // A player is offered the track among the subtitles to turn on, and may show none. The
        // system also offers every subtitle track as one of forced subtitles only.
        let group = try #require(try await asset.loadMediaSelectionGroup(for: .legible))
        let offered = group.options.filter { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }
        #expect(offered.count == 1)
        #expect(offered.first?.isPlayable == true)
        #expect(offered.first?.extendedLanguageTag == "en-US")
        #expect(group.allowsEmptySelection)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        let provider = reader.outputProvider(for: output)
        try reader.start()
        var read: [VideoCaption] = []
        while let sample = try await provider.next() {
            // The reader also gives markers, which hold no text.
            guard let held = CMReadySampleBuffer<CMReadOnlyDataBlockBuffer>(sample) else { continue }
            let data = Data(held.content)
            #expect(data.count >= 2)
            let count = Int(data[data.startIndex]) << 8 | Int(data[data.startIndex + 1])
            let text = try #require(String(data: data.dropFirst(2).prefix(count), encoding: .utf8))
            let start = sample.presentationTimeStamp.seconds
            if !text.isEmpty { read.append(VideoCaption(start: start, end: start + sample.duration.seconds, text: text)) }
        }
        #expect(read.map(\.text) == lines)
        for (inFile, shown) in zip(read, result.captions) {
            #expect(abs(inFile.start - shown.start) < 0.001, "\(shown.text)")
            #expect(abs(inFile.end - shown.end) < 0.001, "\(shown.text)")
        }
        // The intro's line is shown for the intro's hold, and each step's first line from within
        // the step; the last line stays to the video's end.
        let frame = 1.0 / 30
        #expect(read[0].start == 0)
        #expect(abs(read[0].end - plan.introHold) <= frame)
        for (k, first) in firstOfStep.enumerated() where first < read.count {
            #expect(read[first].start >= result.stepStarts[k] - frame, "step \(k)")
            #expect(read[first].start < result.stepStarts[k] + plan.stepLengths[k], "step \(k)")
        }
        #expect(abs(try #require(read.last).end - result.length) < 0.001)
        // No line is drawn in the picture: the frame has no band for one.
        #expect(plan.frame.captionRect == nil)
    }
}
