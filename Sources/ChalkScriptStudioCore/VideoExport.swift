#if os(macOS)
import AVFoundation
import ChalkScript
import struct ChalkScript.Scene
import CoreGraphics
import CoreVideo
import Foundation
import SwiftUI

/// The shape of a video's frame: one of the two offered by name, or one given as two numbers.
public enum VideoShape: Equatable, Sendable {
    case widescreen
    case standard
    case custom(width: Double, height: Double)

    /// The widest and the tallest shape a video is made in.
    public static let widest = 3.0

    /// Width over height, or nil for a custom shape whose numbers are not both greater than zero.
    public var ratio: Double? {
        switch self {
        case .widescreen: 16.0 / 9
        case .standard: 4.0 / 3
        case let .custom(w, h): w > 0 && h > 0 && w.isFinite && h.isFinite ? w / h : nil
        }
    }

    /// Why no video is made in this shape, as a sentence for the person; nil when one is.
    public var refusal: String? {
        guard let ratio else { return "Type two numbers greater than zero, such as 9 and 16." }
        if ratio > Self.widest + 1e-9 { return "Choose a shape no wider than 3 to 1." }
        if ratio < 1 / Self.widest - 1e-9 { return "Choose a shape no taller than 1 to 3." }
        return nil
    }

    /// The video's size in pixels: 1080 on the shorter side, and the longer side rounded to an
    /// even number, as the encoder needs. Nil when the shape is refused.
    public var pixels: (width: Int, height: Int)? {
        guard refusal == nil, let ratio else { return nil }
        func even(_ v: Double) -> Int { Int((v / 2).rounded()) * 2 }
        return ratio >= 1 ? (even(1080 * ratio), 1080) : (1080, even(1080 / ratio))
    }
}

/// Where a video's frame puts the drawing and the caption, in points at two pixels a point: a
/// margin on every edge, the caption in a band of two lines at the foot when captions are in the
/// picture, and the drawing in what is left.
public struct VideoFrame: Equatable, Sendable {
    public static let pixelsPerPoint = 2.0
    /// The caption's size in points, as the player sets it.
    static let captionSize = 26.0

    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Whether the caption has its band.
    public let captions: Bool

    public init(pixelWidth: Int, pixelHeight: Int, captions: Bool) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.captions = captions
    }

    public var size: CGSize {
        CGSize(width: Double(pixelWidth) / Self.pixelsPerPoint, height: Double(pixelHeight) / Self.pixelsPerPoint)
    }

    /// 4.5 per cent of the frame's shorter side, to a whole point.
    public var margin: Double { (Double(min(size.width, size.height)) * 0.045).rounded() }

    public var captionBand: Double { captions ? 70 : 0 }

    /// The space between the drawing and the caption's band.
    public var captionGap: Double { captions ? 10 : 0 }

    /// What is left for the drawing, at the frame's top inside the margin.
    public var space: CGRect {
        CGRect(x: margin, y: margin, width: size.width - 2 * margin, height: size.height - 2 * margin - captionBand - captionGap)
    }

    /// The band the caption is set in, under the drawing; nil without captions.
    public var captionRect: CGRect? {
        guard captions else { return nil }
        return CGRect(x: margin, y: size.height - margin - captionBand, width: size.width - 2 * margin, height: captionBand)
    }

    /// The area the drawing is laid out for: the largest of `ratio` inside the space, centred,
    /// or the space itself for a document that declares no shapes.
    public func drawingArea(ratio: Double?) -> CGRect {
        guard let ratio else { return space }
        let area = Shapes.area(ratio: ratio, inside: space.size)
        return CGRect(
            x: space.midX - area.width / 2, y: space.midY - area.height / 2, width: area.width, height: area.height)
    }
}

/// Where a video shows the lines.
public enum VideoCaptions: String, CaseIterable, Identifiable, Sendable {
    case inPicture, subtitles, both, none

    public var id: String { rawValue }

    /// Whether each line is drawn under the drawing.
    public var inPicture: Bool { self == .inPicture || self == .both }

    /// Whether the lines are a subtitle track of the file, which the viewer turns on in a player.
    public var asSubtitles: Bool { self == .subtitles || self == .both }

    public var title: String {
        switch self {
        case .inPicture: "In the picture"
        case .subtitles: "As subtitles the viewer turns on"
        case .both: "Both"
        case .none: "None"
        }
    }
}

/// What a person chooses for a video besides the document and its problem.
public struct VideoExportSettings: Equatable, Sendable {
    public enum ShapeChoice: String, CaseIterable, Identifiable, Sendable {
        case widescreen, standard, custom

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .widescreen: "Widescreen 16:9"
            case .standard: "Standard 4:3"
            case .custom: "Custom"
            }
        }
    }

    public var shapeChoice: ShapeChoice = .widescreen
    /// The two numbers of the custom shape, kept while another shape is chosen.
    public var customWidth = 16.0
    public var customHeight = 9.0
    /// The title of the shape the drawing is laid out at, among those the document is made for;
    /// nil takes the one nearest the frame's drawing space.
    public var drawingShape: String?
    /// Nil takes the appearance the window shows.
    public var appearance: Appearance?
    public var captions: VideoCaptions = .inPicture
    /// Seconds each step's finished picture is held before the next step begins.
    public var pause: Double = 0

    /// The pauses offered, in seconds, with their names.
    public static let pauses: [(seconds: Double, title: String)] = [
        (0, "None"), (0.5, "Half a second"), (1, "One second"), (2, "Two seconds"),
    ]

    public init() {}

    public var shape: VideoShape {
        switch shapeChoice {
        case .widescreen: .widescreen
        case .standard: .standard
        case .custom: .custom(width: customWidth, height: customHeight)
        }
    }

    // MARK: remembered choices

    enum Key {
        static let shape = "ExportVideoShape"
        static let customWidth = "ExportVideoCustomWidth"
        static let customHeight = "ExportVideoCustomHeight"
        static let captions = "ExportVideoCaptions"
        static let pause = "ExportVideoPause"
    }

    /// The choices as last saved. The drawing's shape and the appearance are not kept: each
    /// starts from the video's shape and from the window.
    public init(defaults: UserDefaults) {
        if let shape = defaults.string(forKey: Key.shape).flatMap(ShapeChoice.init(rawValue:)) { shapeChoice = shape }
        let width = defaults.double(forKey: Key.customWidth), height = defaults.double(forKey: Key.customHeight)
        if width > 0, height > 0 { (customWidth, customHeight) = (width, height) }
        if let captions = defaults.string(forKey: Key.captions).flatMap(VideoCaptions.init(rawValue:)) { self.captions = captions }
        let pause = defaults.double(forKey: Key.pause)
        if Self.pauses.contains(where: { $0.seconds == pause }) { self.pause = pause }
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(shapeChoice.rawValue, forKey: Key.shape)
        if customWidth > 0, customHeight > 0, customWidth.isFinite, customHeight.isFinite {
            defaults.set(customWidth, forKey: Key.customWidth)
            defaults.set(customHeight, forKey: Key.customHeight)
        }
        defaults.set(captions.rawValue, forKey: Key.captions)
        defaults.set(pause, forKey: Key.pause)
    }
}

/// What a video is made from: a document as the window shows it.
public struct VideoExportSource: Sendable {
    public var title: String
    public var document: ExplainerDocument
    public var problem: [String: DocumentValue]
    /// Nil takes the document's suggestion, and its source locale.
    public var wording: String?
    public var locale: String?
    /// The appearance the window previews the player in.
    public var appearance: Appearance

    public init(
        title: String, document: ExplainerDocument, problem: [String: DocumentValue], wording: String? = nil,
        locale: String? = nil, appearance: Appearance = .light
    ) {
        self.title = title
        self.document = document
        self.problem = problem
        self.wording = wording
        self.locale = locale
        self.appearance = appearance
    }

    /// The problem's values in parameter order, as the window's Samples menu writes a problem.
    public static func describe(_ problem: [String: DocumentValue], in document: ExplainerDocument) -> String {
        document.parameterOrder.compactMap { name in problem[name].map { "\(name) = \($0)" } }.joined(separator: ", ")
    }

    /// The name offered for the file: the document's title and the problem's values, without the
    /// characters a file name cannot hold.
    public var fileName: String {
        let values = document.parameterOrder.compactMap { name in problem[name].map { "\($0)" } }.joined(separator: ", ")
        let name = values.isEmpty ? title : "\(title) (\(values))"
        return name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".mp4"
    }
}

/// Why a video was not made, as a sentence for the person.
public struct VideoExportError: Error, LocalizedError, Equatable {
    public var message: String
    public var errorDescription: String? { message }

    init(_ message: String) { self.message = message }

    static func unplayable(_ findings: [DocumentFinding]) -> VideoExportError {
        VideoExportError("The explainer cannot be played for this problem" + (findings.first.map { ": \($0.message)" } ?? "."))
    }
}

/// One video, worked out before any frame is drawn: the frame, the shape and appearance the
/// drawing is drawn in, and how long each part lasts.
@MainActor
public struct VideoExportPlan {
    public static let framesPerSecond = 30
    /// The least time the intro is held, and the time the last picture is held, in seconds.
    public static let introLeast = 2.0
    public static let endHold = 2.0

    public let frame: VideoFrame
    /// The shape the drawing is laid out at, or nil for a document that declares none.
    public let drawingShape: PreviewItem?
    /// The appearance the window shows and the one the video is drawn in, which differ for a
    /// document not made for the window's.
    public let appearance: AppearanceUse
    public let pause: Double
    /// Whether the lines are also written as a subtitle track.
    public let subtitles: Bool
    /// The intro is held for its line's estimated time, and at least `introLeast`.
    public let introHold: Double
    /// Each step's length as the window plays it with the stand-in voice (`StepTimeline`).
    public let stepLengths: [Double]
    /// The explainer as made, before it is laid out for the drawing's area.
    let explainer: DocumentExplainer

    /// The video's length in seconds, before it is made: within a frame for each step of the
    /// length it is made at.
    public var length: Double {
        introHold + stepLengths.reduce(0, +) + pause * Double(max(0, stepLengths.count - 1)) + Self.endHold
    }

    /// The shapes a document is made for, among which the drawing's is chosen (EXP-17).
    public static func drawingShapes(_ document: ExplainerDocument) -> [PreviewItem] { Shapes.previews(document) }

    /// The shape nearest the frame's drawing space, by the logarithm of the ratio.
    public static func nearestShape(_ shapes: [PreviewItem], to frame: VideoFrame) -> PreviewItem? {
        guard let space = Shapes.ratio(frame.space.size) else { return shapes.first }
        return shapes.min { abs(log($0.ratio / space)) < abs(log($1.ratio / space)) }
    }

    /// - Throws: `VideoExportError` when the shape is refused or the document cannot be played
    ///   for the problem.
    public init(_ source: VideoExportSource, settings: VideoExportSettings = VideoExportSettings()) throws {
        guard let pixels = settings.shape.pixels else {
            throw VideoExportError(settings.shape.refusal ?? "The video's shape cannot be used.")
        }
        frame = VideoFrame(pixelWidth: pixels.width, pixelHeight: pixels.height, captions: settings.captions.inPicture)
        let shapes = Self.drawingShapes(source.document)
        drawingShape = shapes.first { $0.title == settings.drawingShape } ?? Self.nearestShape(shapes, to: frame)
        appearance = Appearance.use(asked: settings.appearance ?? source.appearance, madeFor: source.document.appearances)
        pause = max(0, settings.pause)
        subtitles = settings.captions.asSubtitles
        do {
            // The learner's version: the same steps as the parent's, played without its controls.
            explainer = try DocumentExplainer(
                document: source.document, problem: source.problem, wording: source.wording, locale: source.locale,
                playback: DocumentPlayback(control: .paced))
        } catch {
            throw VideoExportError.unplayable(error.findings)
        }
        introHold = max(Self.introLeast, ReadingTime.seconds(explainer.intro))
        let area = frame.drawingArea(ratio: drawingShape?.ratio).size
        let laid = explainer.laidOutExplainer(for: area) as? DocumentExplainer ?? explainer
        stepLengths = (0..<laid.stepCount).map { StepTimeline.make(laid, step: $0).length }
    }

    /// Where the drawing is laid out in the frame.
    public var drawingArea: CGRect { frame.drawingArea(ratio: drawingShape?.ratio) }

    /// The language of the lines, as a BCP 47 tag.
    var locale: String { explainer.resolved.locale }

    /// The video's size and length in a line: "1920 × 1080 pixels · about 38 seconds".
    public var summary: String {
        let seconds = Int(length.rounded())
        func count(_ n: Int, _ unit: String) -> String { "\(n) \(unit)" + (n == 1 ? "" : "s") }
        var time = count(seconds % 60, "second")
        if seconds >= 60 { time = count(seconds / 60, "minute") + (seconds % 60 == 0 ? "" : " " + time) }
        return "\(frame.pixelWidth) × \(frame.pixelHeight) pixels · about \(time)"
    }
}

/// A line of the video, and the seconds from the video's start between which it is shown.
public struct VideoCaption: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
}

/// A finished video.
public struct VideoExportResult: Sendable {
    public var url: URL
    public var frames: Int
    /// The video's length in seconds.
    public var length: Double
    /// When each step begins, in seconds from the video's start.
    public var stepStarts: [Double]
    /// Each line shown, in order, with the time it is shown for.
    public var captions: [VideoCaption]
}

/// Writes an mp4 of a document's watched steps for one problem, played straight through (EXP-21):
/// the intro held, each step as the player plays it with the stand-in voice, and the last picture
/// held. The video is H.264 at 30 frames a second and has no audio track. The lines can also be a
/// subtitle track of the file, in the 3GPP timed text form that mp4 players read.
///
/// Each frame is the player's scene drawn by the engine's stage, with the caption under it as the
/// player's screen sets it, on the sheet colour of the appearance. The export has a player of its
/// own on a clock it moves itself, so the window's player is not touched.
@MainActor
public enum VideoExport {
    /// The longest the player's clock moves at once, in seconds, as for a step's picture.
    static let tick = StepPicture.tick
    /// A video longer than this many seconds is not made: a step that never ends would fill the disk.
    static let longest = 1200.0

    /// Writes the video to `url`, replacing a file there only once the whole video is made. A
    /// cancelled task or an error leaves no file, and leaves a file already at `url` as it was.
    ///
    /// - Parameter progress: Called as frames are made, with the seconds of video made and the
    ///   video's whole length.
    /// - Throws: `CancellationError` when the task is cancelled, and otherwise `VideoExportError`.
    public static func write(
        _ plan: VideoExportPlan, to url: URL, progress: @MainActor (_ made: Double, _ whole: Double) -> Void = { _, _ in }
    ) async throws -> VideoExportResult {
        // The clock is run once without drawing, which gives the number of frames for the
        // progress shown, the time each step starts and the time each line is shown.
        let timing = try Timing(plan)
        let fps = VideoExportPlan.framesPerSecond
        let folder: URL
        do {
            folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        } catch {
            throw VideoExportError("The video could not be saved there. \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let partial = folder.appendingPathComponent(url.lastPathComponent)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: partial, fileType: .mp4)
        } catch {
            throw VideoExportError(error.localizedDescription)
        }
        let frame = plan.frame
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: frame.pixelWidth,
            AVVideoHeightKey: frame.pixelHeight,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
            ],
        ])
        let attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: frame.pixelWidth, height: frame.pixelHeight))
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
        var subtitles: Subtitles?
        do {
            if plan.subtitles { subtitles = try Subtitles(timing.captions, plan: plan, length: Double(timing.frames) / Double(fps), writer: writer) }
            try writer.start()
        } catch let error as VideoExportError {
            throw error
        } catch {
            throw VideoExportError(error.localizedDescription)
        }
        writer.startSession(atSourceTime: .zero)

        var clock = Clock(plan)
        var count = 0
        var yielded = ContinuousClock.now
        do {
            while true {
                try Task.checkCancellation()
                guard let image = FrameView.image(plan, scene: clock.player.scene, areaUse: clock.player.areaUse, caption: clock.caption) else {
                    throw VideoExportError("A picture of the video could not be drawn.")
                }
                guard let pool = receiver.pixelBufferPool else { throw failure(writer) }
                do {
                    let buffer = try pixelBuffer(of: image, from: pool, frame: frame)
                    // The writer takes a picture only when it has the lines up to that picture's
                    // time, and a line only once the pictures have reached it. Neither is waited
                    // for alone, which would stop both tracks: each is offered until it is taken.
                    let time = CMTime(value: CMTimeValue(count), timescale: CMTimeScale(fps))
                    let asked = ContinuousClock.now
                    while true {
                        try subtitles?.offer()
                        if try receiver.appendImmediately(buffer, with: time) { break }
                        guard writer.status == .writing, asked.duration(to: .now) < .seconds(30) else { throw failure(writer) }
                        try await Task.sleep(for: .milliseconds(1))
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw VideoExportError(writer.error?.localizedDescription ?? error.localizedDescription)
                }
                count += 1
                let finished = clock.advanceFrame()
                // The frames are drawn on the main actor, as the player and the renderer need, so
                // the window is given a moment between them.
                if finished || yielded.duration(to: .now) > .milliseconds(12) {
                    progress(Double(count) / Double(fps), Double(timing.frames) / Double(fps))
                    try await Task.sleep(for: .milliseconds(1))
                    yielded = .now
                }
                if finished { break }
            }
            try Task.checkCancellation()
        } catch {
            writer.cancelWriting()
            throw error
        }
        receiver.finish()
        do {
            let asked = ContinuousClock.now
            while try subtitles?.offer() == false {
                guard writer.status == .writing, asked.duration(to: .now) < .seconds(30) else { throw failure(writer) }
                try await Task.sleep(for: .milliseconds(1))
            }
        } catch {
            writer.cancelWriting()
            throw error
        }
        let end = CMTime(value: CMTimeValue(count), timescale: CMTimeScale(fps))
        writer.endSession(atSourceTime: end)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            writer.finishWriting { done.resume() }
        }
        guard writer.status == .completed else { throw failure(writer) }
        do {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: partial)
            } else {
                try FileManager.default.moveItem(at: partial, to: url)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VideoExportError(error.localizedDescription)
        }
        return VideoExportResult(
            url: url, frames: count, length: Double(count) / Double(fps), stepStarts: timing.stepStarts, captions: timing.captions)
    }

    private static func failure(_ writer: AVAssetWriter) -> VideoExportError {
        VideoExportError(writer.error?.localizedDescription ?? "The video could not be written.")
    }

    /// `image` drawn into a buffer of the encoder's.
    private static func pixelBuffer(of image: CGImage, from pool: CVMutablePixelBuffer.Pool, frame: VideoFrame) throws -> CVReadOnlyPixelBuffer {
        let buffer = try pool.makeMutablePixelBuffer()
        let drawn = buffer.withUnsafeBuffer { pixels -> Bool in
            CVPixelBufferLockBaseAddress(pixels, [])
            defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: CVPixelBufferGetBaseAddress(pixels), width: frame.pixelWidth, height: frame.pixelHeight, bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: frame.pixelWidth, height: frame.pixelHeight))
            return true
        }
        guard drawn else { throw VideoExportError("A picture of the video could not be drawn.") }
        return CVReadOnlyPixelBuffer(buffer)
    }

    /// The lines as a subtitle track: one sample of timed text for each line, and an empty one
    /// wherever no line is shown, so that the samples follow one another without a gap.
    @MainActor
    struct Subtitles {
        private let receiver: AVAssetWriterInput.SampleBufferReceiver
        private let format: CMFormatDescription
        private var samples: [(start: Double, end: Double, text: String)] = []
        private var next = 0
        private var finished = false

        init(_ captions: [VideoCaption], plan: VideoExportPlan, length: Double, writer: AVAssetWriter) throws {
            let frame = plan.frame
            // The text's box is the foot of the picture, where a player sets the line.
            let colour: [CFString: Any] = [
                kCMTextFormatDescriptionColor_Red: 1.0, kCMTextFormatDescriptionColor_Green: 1.0,
                kCMTextFormatDescriptionColor_Blue: 1.0, kCMTextFormatDescriptionColor_Alpha: 1.0,
            ]
            let clear: [CFString: Any] = [
                kCMTextFormatDescriptionColor_Red: 0.0, kCMTextFormatDescriptionColor_Green: 0.0,
                kCMTextFormatDescriptionColor_Blue: 0.0, kCMTextFormatDescriptionColor_Alpha: 0.0,
            ]
            let extensions: [CFString: Any] = [
                kCMTextFormatDescriptionExtension_DisplayFlags: 0,
                kCMTextFormatDescriptionExtension_BackgroundColor: clear,
                kCMTextFormatDescriptionExtension_HorizontalJustification: 1,
                kCMTextFormatDescriptionExtension_VerticalJustification: -1,
                kCMTextFormatDescriptionExtension_DefaultTextBox: [
                    kCMTextFormatDescriptionRect_Top: 0, kCMTextFormatDescriptionRect_Left: 0,
                    kCMTextFormatDescriptionRect_Bottom: frame.pixelHeight * 3 / 20, kCMTextFormatDescriptionRect_Right: frame.pixelWidth,
                ] as [CFString: Any],
                kCMTextFormatDescriptionExtension_DefaultStyle: [
                    kCMTextFormatDescriptionStyle_StartChar: 0, kCMTextFormatDescriptionStyle_EndChar: 0,
                    kCMTextFormatDescriptionStyle_Font: 1, kCMTextFormatDescriptionStyle_FontFace: 0,
                    kCMTextFormatDescriptionStyle_FontSize: frame.pixelHeight / 20,
                    kCMTextFormatDescriptionStyle_ForegroundColor: colour,
                ] as [CFString: Any],
                kCMTextFormatDescriptionExtension_FontTable: ["1": "Helvetica"],
            ]
            var made: CMFormatDescription?
            CMFormatDescriptionCreate(
                allocator: nil, mediaType: kCMMediaType_Subtitle, mediaSubType: kCMSubtitleFormatType_3GText,
                extensions: extensions as CFDictionary, formatDescriptionOut: &made)
            guard let made else { throw VideoExportError("The subtitles could not be written.") }
            format = made
            let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: made)
            input.extendedLanguageTag = plan.locale
            input.languageCode = Locale(identifier: plan.locale).language.languageCode?.identifier(.alpha3)
            // The track is in the file and is off until the viewer turns it on.
            input.marksOutputTrackAsEnabled = false
            input.naturalSize = CGSize(width: frame.pixelWidth, height: frame.pixelHeight)
            guard writer.canAdd(input) else { throw VideoExportError("The subtitles could not be written.") }
            receiver = writer.inputReceiver(for: input)

            var at = 0.0
            for caption in captions where caption.end > caption.start {
                if caption.start > at + 1e-9 { samples.append((at, caption.start, "")) }
                samples.append((caption.start, caption.end, caption.text))
                at = caption.end
            }
            if length > at + 1e-9 { samples.append((at, length, "")) }
        }

        /// Hands the writer the samples it will take now, in order, and returns whether it has
        /// taken them all. The track is ended with its last sample: the writer would otherwise
        /// hold the pictures after that sample's start back, waiting for another line.
        @discardableResult
        mutating func offer() throws -> Bool {
            guard !finished else { return true }
            while next < samples.count {
                let sample = samples[next]
                // Timed text: the count of the text's bytes in two bytes, then the text in UTF-8.
                let text = Data(sample.text.utf8)
                var data = Data([UInt8(text.count >> 8 & 0xFF), UInt8(text.count & 0xFF)])
                data.append(text)
                let timing = CMSampleTimingInfo(
                    duration: CMTime(seconds: sample.end - sample.start, preferredTimescale: 600),
                    presentationTimeStamp: CMTime(seconds: sample.start, preferredTimescale: 600), decodeTimeStamp: .invalid)
                let buffer = CMReadySampleBuffer<CMReadOnlyDataBlockBuffer>(
                    dataBuffer: CMReadOnlyDataBlockBuffer(data), formatDescription: format,
                    sampleProperties: .init(sampleCount: 1, sizes: .uniform(data.count), timings: .distinct([timing])))
                guard try receiver.appendImmediately(CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(buffer)) else { return false }
                next += 1
            }
            receiver.finish()
            finished = true
            return true
        }
    }

    /// The video's clock: a player of the export's own, moved a frame at a time. The player has
    /// no intro of its own and waits after each step, so the clock holds the intro, presses Next
    /// as each step ends, or after the pause, and holds the last picture.
    @MainActor
    struct Clock {
        enum Stage {
            case intro(Double)
            case playing
            case pausing(Double)
            case ending(Double)
            case done
        }

        let player: ExplainerPlayer
        let intro: Line
        let pause: Double
        let last: Int
        private(set) var stage: Stage
        /// Seconds from the video's start.
        private(set) var time = 0.0
        private(set) var stepStarts: [Double] = []
        private let ticks: Int
        private let tickLength: Double

        init(_ plan: VideoExportPlan) {
            player = ExplainerPlayer(explainer: plan.explainer, voice: EstimatedVoice(), drivesItself: false)
            player.layOut(for: plan.drawingArea.size)
            intro = plan.explainer.intro
            pause = plan.pause
            last = plan.explainer.stepCount - 1
            stage = .intro(plan.introHold)
            let frame = 1.0 / Double(VideoExportPlan.framesPerSecond)
            ticks = max(1, Int((frame / VideoExport.tick).rounded()))
            tickLength = frame / Double(ticks)
        }

        /// The line shown now: the intro's until the first step begins.
        var caption: Line {
            if case .intro = stage { return intro }
            return player.caption
        }

        /// Moves the clock on by one frame, and returns whether the video has ended.
        mutating func advanceFrame() -> Bool {
            for _ in 0..<ticks {
                time += tickLength
                switch stage {
                case let .intro(left), let .pausing(left):
                    if left - tickLength <= 1e-9 {
                        player.primary()
                        stepStarts.append(time)
                        stage = .playing
                    } else if case .intro = stage {
                        stage = .intro(left - tickLength)
                    } else {
                        stage = .pausing(left - tickLength)
                    }
                case .playing:
                    player.advance(by: tickLength)
                    guard case let .paused(k) = player.phase else { break }
                    if k >= last {
                        stage = .ending(VideoExportPlan.endHold)
                    } else if pause > 0 {
                        stage = .pausing(pause)
                    } else {
                        player.primary()
                        stepStarts.append(time)
                    }
                case let .ending(left):
                    if left - tickLength <= 1e-9 {
                        stage = .done
                        return true
                    }
                    stage = .ending(left - tickLength)
                case .done:
                    return true
                }
            }
            return false
        }
    }

    /// What the clock gives when run without drawing.
    @MainActor
    struct Timing {
        var frames = 0
        var stepStarts: [Double]
        var captions: [VideoCaption] = []

        init(_ plan: VideoExportPlan) throws {
            let fps = Double(VideoExportPlan.framesPerSecond)
            var clock = Clock(plan)
            var shown: Line?
            while true {
                let line = clock.caption
                if line != shown {
                    let now = Double(frames) / fps
                    if !captions.isEmpty { captions[captions.count - 1].end = now }
                    captions.append(VideoCaption(start: now, end: now, text: line.display))
                    shown = line
                }
                frames += 1
                if clock.advanceFrame() { break }
                guard Double(frames) / fps < VideoExport.longest else {
                    throw VideoExportError("The video would be longer than 20 minutes, so it was not made.")
                }
            }
            if !captions.isEmpty { captions[captions.count - 1].end = Double(frames) / fps }
            captions.removeAll { $0.text.isEmpty }
            stepStarts = clock.stepStarts
        }
    }
}

/// One frame of the video: the scene in the area it is laid out for, centred in the drawing's
/// space, and the caption in its band, on the sheet colour.
struct FrameView: View {
    let frame: VideoFrame
    let area: CGSize
    let scene: Scene
    let areaUse: AreaUse?
    let caption: Line?
    let palette: ExplainerPalette
    let dark: Bool

    var body: some View {
        VStack(spacing: frame.captionGap) {
            ExplainerStage(scene: scene, areaUse: areaUse)
                .frame(width: area.width, height: area.height)
                .frame(width: frame.space.width, height: frame.space.height)
            if let band = frame.captionRect {
                // As the player's screen sets its line: in room for two lines, and set smaller
                // rather than cut.
                Text(text)
                    .font(ExplainerFonts.system.display(VideoFrame.captionSize))
                    .foregroundStyle(palette.ink.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.7)
                    .frame(width: band.width, height: band.height)
            }
        }
        .padding(frame.margin)
        .frame(width: frame.size.width, height: frame.size.height)
        .background(palette.sheet.color)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    /// The line, with its emphasis in the result colour.
    private var text: AttributedString {
        guard let line = caption else { return AttributedString("") }
        var text = AttributedString(line.display)
        if let range = line.emphasisRange, let lower = AttributedString.Index(range.lowerBound, within: text),
           let upper = AttributedString.Index(range.upperBound, within: text) {
            text[lower..<upper].foregroundColor = palette.colors(.result).ink.color
        }
        return text
    }

    /// The frame as an image of the video's size in pixels.
    @MainActor
    static func image(_ plan: VideoExportPlan, scene: Scene, areaUse: AreaUse?, caption: Line?) -> CGImage? {
        let dark = plan.appearance.used.isDark
        let view = FrameView(
            frame: plan.frame, area: plan.drawingArea.size, scene: scene, areaUse: areaUse, caption: caption,
            palette: ExplainerStyle.standard.palette(dark: dark), dark: dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = VideoFrame.pixelsPerPoint
        return renderer.cgImage
    }
}
#endif
