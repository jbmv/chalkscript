// Renders the still picture of every step of an explainer document's watched part to PNG files,
// each with the step's line under it (EXP-11, EXP-19), from a terminal with no window.
#if os(macOS)
import ChalkScript
import struct ChalkScript.Scene
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let usage = """
    usage: chalkscript-render DOCUMENT OUTPUT-DIRECTORY NAME=VALUE ... [options]

    Writes one PNG file per step of DOCUMENT's watched part, played for the problem the
    NAME=VALUE arguments give, into OUTPUT-DIRECTORY: 00-intro.png, the picture before the
    first step with the introduction's line, then 01-<step>.png and so on, each the step's
    finished picture with its line under it.

    options:
      --wording NAME         the wording to play (default: the document's suggestion, or its first)
      --locale TAG           the language to play (default: the document's source locale)
      --playback paced|skippable
      --counts spoken|shown
      --count-pace NUMBER
      --area WIDTHxHEIGHT    the drawing area in points, from which the layout is chosen
                             (default: the stage, 1000x540)
      --ratio NUMBER         the shape of the drawing area, its width over its height, with a
                             longer side of 1000 points; the layout is the one the player would
                             use at that shape. Not with --area.
      --scale NUMBER         pixels per point (default: 2)
      --dark                 draw in the style's dark palette

    """

func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("chalkscript-render: \(message)\n".utf8))
    exit(code)
}

var positional: [String] = []
var wording: String?
var locale: String?
var playback = DocumentPlayback()
var area: CGSize?
var ratio: Double?
var scale = 2.0
var dark = false
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    func value() -> String {
        guard let v = arguments.popFirst() else { fail("\(argument) needs a value\n\n\(usage)") }
        return v
    }
    switch argument {
    case "--wording": wording = value()
    case "--locale": locale = value()
    case "--playback":
        guard let c = DocumentPlayback.Control(rawValue: value()) else { fail("--playback is paced or skippable") }
        playback.control = c
    case "--counts":
        guard let c = DocumentPlayback.Counts(rawValue: value()) else { fail("--counts is spoken or shown") }
        playback.counts = c
    case "--count-pace":
        guard let p = Double(value()), p > 0 else { fail("--count-pace is a positive number") }
        playback.countPace = p
    case "--area":
        let parts = value().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { fail("--area is WIDTHxHEIGHT, such as 660x760") }
        area = CGSize(width: parts[0], height: parts[1])
    case "--ratio":
        guard let r = Double(value()), r > 0, r.isFinite else { fail("--ratio is a positive number, such as 0.75") }
        ratio = r
    case "--scale":
        guard let s = Double(value()), s > 0 else { fail("--scale is a positive number") }
        scale = s
    case "--dark": dark = true
    case "--help", "-h":
        print(usage, terminator: "")
        exit(0)
    default:
        if argument.hasPrefix("--") { fail("unknown option \(argument)\n\n\(usage)") }
        positional.append(argument)
    }
}
if let ratio {
    guard area == nil else { fail("--ratio and --area are given together; give one") }
    area = ratio >= 1 ? CGSize(width: 1000, height: 1000 / ratio) : CGSize(width: 1000 * ratio, height: 1000)
}
guard positional.count >= 2 else { fail("a document and an output directory are needed\n\n\(usage)") }

let reading = ExplainerDocument.read(contentsOf: URL(fileURLWithPath: positional[0]))
for f in reading.findings { FileHandle.standardError.write(Data("\(f)\n".utf8)) }
guard let document = reading.document else { fail("\(positional[0]) cannot be read", code: 65) }

// The problem: each NAME=VALUE, a number, true or false, or else a string.
var problem: [String: DocumentValue] = [:]
for pair in positional.dropFirst(2) {
    let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { fail("\(pair) is not NAME=VALUE") }
    if let n = Double(parts[1]) {
        problem[parts[0]] = .number(n)
    } else if parts[1] == "true" || parts[1] == "false" {
        problem[parts[0]] = .truth(parts[1] == "true")
    } else {
        problem[parts[0]] = .string(parts[1])
    }
}

let explainer: DocumentExplainer
do {
    explainer = try DocumentExplainer(document: document, problem: problem, wording: wording, locale: locale, playback: playback, area: area)
} catch {
    fail("the document cannot be played for this problem:\n\(error)", code: 65)
}

if let use = explainer.areaUse, !use.isGiven {
    FileHandle.standardError.write(Data(
        "note: the document does not declare this shape; laid out for \(Int(use.used.width.rounded())) by \(Int(use.used.height.rounded())) points inside \(Int(use.given.width.rounded())) by \(Int(use.given.height.rounded()))\n".utf8))
}

let directory = URL(fileURLWithPath: positional[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
} catch {
    fail("\(directory.path) cannot be made: \(error.localizedDescription)", code: 73)
}

/// One picture: the scene drawn on its sheet, at the drawing area's size, with the line under it.
struct Still: View {
    var scene: Scene
    var line: Line
    var width: CGFloat
    var palette: ExplainerPalette

    var body: some View {
        VStack(spacing: 0) {
            ExplainerStage(scene: scene)
                .frame(width: width, height: width * scene.size.height / scene.size.width)
                .background(palette.sheet.color)
            Text(caption)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(palette.ink.color)
                .multilineTextAlignment(.center)
                .frame(width: width - 48)
                .padding(.vertical, 20)
        }
        .background(palette.paper.color)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    /// The line, with its emphasis (the answer) in the result colour, as the player shows it.
    var caption: AttributedString {
        var text = AttributedString(line.display)
        if let range = line.emphasisRange, let lower = AttributedString.Index(range.lowerBound, within: text),
            let upper = AttributedString.Index(range.upperBound, within: text)
        {
            text[lower..<upper].foregroundColor = palette.colors(.result).ink.color
        }
        return text
    }
}

@MainActor
func render() {
    let palette = ExplainerStyle.standard.palette(dark: dark)
    let width = explainer.areaUse?.used.width ?? Scene.stage.width
    var pictures: [(String, Scene, Line)] = [("00-intro", explainer.still(after: -1), explainer.intro)]
    for k in 0..<explainer.stepCount {
        pictures.append((String(format: "%02d-%@", k + 1, explainer.resolved.steps[k].name), explainer.still(after: k), explainer.resolved.steps[k].line.line))
    }
    for (name, scene, line) in pictures {
        let renderer = ImageRenderer(content: Still(scene: scene, line: line, width: width, palette: palette))
        renderer.scale = scale
        guard let image = renderer.cgImage else { fail("\(name): the picture could not be drawn", code: 70) }
        let url = directory.appendingPathComponent(name + ".png")
        guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fail("\(url.path) cannot be written", code: 73)
        }
        CGImageDestinationAddImage(out, image, nil)
        guard CGImageDestinationFinalize(out) else { fail("\(url.path) cannot be written", code: 73) }
        print(url.path)
    }
}

MainActor.assumeIsolated { render() }
#else
print("chalkscript-render runs on macOS only.")
#endif
