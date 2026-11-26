import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import ChalkScript
import struct ChalkScript.Scene

// The app's choice of arrangement round the drawing (EXP-17): automatic, the caption below and
// the caption beside; the drawing area the screen says it gives for each, against the area the
// view gives the player when it is drawn; and a document laid out for a declared shape other
// than its area's, drawn inside the area the player used.

@MainActor
struct ArrangementTests {
    static let labels = ExplainerLabels(
        watch: "Watch", next: "Next", watchAgain: "Watch again", again: "Again", progress: { "Step \($0) of \($1)" })

    static let tall = CGSize(width: 700, height: 1000)
    static let square = CGSize(width: 900, height: 900)
    static let wide = CGSize(width: 1400, height: 800)
    /// A phone in landscape: too short for the drawing.
    static let short = CGSize(width: 800, height: 360)

    /// The tiny document with a shape filling its stage (1000 by 540) in `divide.fill`, a colour
    /// nothing else on the screen is drawn in, and `areas` when given.
    static func document(areas: String?) -> ExplainerDocument {
        var d = DocumentFixture.tiny
            .setting("/requires", try! JSONValue.parse(#"["components.arithmetic"]"#))
            .setting("/elements/back", try! JSONValue.parse(#"{"kind": "shape", "rect": [0, 0, 1000, 540], "fill": "divide.fill"}"#))
        if let areas { d = d.setting("/areas", try! JSONValue.parse(areas)) }
        return read(d).document!
    }

    static func player(areas: String? = nil) throws -> ExplainerPlayer {
        let e = try DocumentExplainer(document: document(areas: areas), problem: ["a": .number(1)])
        return ExplainerPlayer(explainer: e, voice: RecordingVoice(), drivesItself: false)
    }

    /// Draws `view` in a space of `size` points, at one pixel per point, in the light palette.
    static func render(_ view: some View, _ size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
        renderer.scale = 1
        return renderer.cgImage
    }

    /// The smallest rectangle holding every pixel of `image` within 3 of `colour` in each channel.
    static func bounds(of colour: RGB, in image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let c = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        let want = [colour.red, colour.green, colour.blue].map { Int(($0 * 255).rounded()) }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                guard pixels[i + 3] == 255, (0..<3).allSatisfy({ abs(Int(pixels[i + $0]) - want[$0]) <= 3 }) else { continue }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        // The bitmap's rows run from the top, as the view's do.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func near(_ a: CGRect, _ b: CGRect, within d: CGFloat = 1.5) -> Bool {
        abs(a.minX - b.minX) <= d && abs(a.minY - b.minY) <= d && abs(a.maxX - b.maxX) <= d && abs(a.maxY - b.maxY) <= d
    }

    static func near(_ a: CGSize?, _ b: CGSize?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    // MARK: the arrangements

    @Test func automaticIsChosenByTheSpaceAndTheOthersInAnySpace() {
        func plan(_ size: CGSize, _ a: ScreenArrangement, _ hand: WritingHand = .right) -> ScreenPlan {
            ScreenPlan.choose(for: size, hand: hand, arrangement: a)
        }
        #expect(plan(Self.tall, .automatic) == .stacked)
        #expect(plan(Self.square, .automatic) == .stacked, "a square space is not wider than tall")
        #expect(plan(Self.wide, .automatic) == .column(width: 600, onLeft: false))
        #expect(plan(Self.wide, .automatic, .left) == .column(width: 600, onLeft: true))
        for size in [Self.tall, Self.square, Self.wide] {
            #expect(plan(size, .captionBelow) == .stacked, "\(size)")
            guard case let .column(width, onLeft) = plan(size, .captionBeside, .left) else {
                Issue.record("\(size): the caption is not beside the drawing")
                continue
            }
            #expect(onLeft && width == ScreenPlan.columnWidth(for: size))
        }
        // Too short for the drawing, every arrangement scrolls; the caption beside stays beside.
        #expect(plan(Self.short, .automatic) == .scroll)
        #expect(plan(Self.short, .captionBelow) == .scroll)
        #expect(plan(Self.short, .captionBeside) == .scrollingColumn(width: 360, onLeft: false))
    }

    @Test func theDrawingAreaTheScreenSaysItGivesIsTheOneItGives() throws {
        let stage = Scene.stage.height / Scene.stage.width
        let expected: [(CGSize, ScreenArrangement, CGSize)] = [
            // The caption below: the space less the fixed bands above and below the drawing.
            (Self.tall, .automatic, CGSize(width: 700, height: 1000 - ScreenPlan.stackedChrome)),
            (Self.square, .automatic, CGSize(width: 900, height: 900 - ScreenPlan.stackedChrome)),
            (Self.tall, .captionBelow, CGSize(width: 700, height: 1000 - ScreenPlan.stackedChrome)),
            (Self.square, .captionBelow, CGSize(width: 900, height: 900 - ScreenPlan.stackedChrome)),
            (Self.wide, .captionBelow, CGSize(width: 1400, height: 800 - ScreenPlan.stackedChrome)),
            // The caption beside: the width less the column, its rule and the drawing's padding.
            (Self.wide, .automatic, CGSize(width: 1400 - 600 - 25.5, height: 776)),
            (Self.tall, .captionBeside, CGSize(width: 700 - 315 - 25.5, height: 976)),
            (Self.square, .captionBeside, CGSize(width: 900 - 340 - 25.5, height: 876)),
            (Self.wide, .captionBeside, CGSize(width: 1400 - 600 - 25.5, height: 776)),
            // Too short: the stage's shape below, or the column laid out at the least height.
            (Self.short, .automatic, CGSize(width: 800, height: 800 * stage)),
            (Self.short, .captionBelow, CGSize(width: 800, height: 800 * stage)),
            (Self.short, .captionBeside, CGSize(width: 800 - 360 - 25.5, height: ScreenPlan.scrollBelow - 24)),
        ]
        for (space, arrangement, area) in expected {
            let said = ExplainerScreen.drawingArea(for: space, arrangement: arrangement)
            #expect(Self.near(said, area), "\(arrangement) at \(space): said \(String(describing: said))")
            // Drawing the screen gives the player the area it said.
            let player = try Self.player()
            _ = Self.render(ExplainerView(player: player, labels: Self.labels, arrangement: arrangement), space)
            #expect(Self.near(player.drawingArea, said), "\(arrangement) at \(space): gave \(String(describing: player.drawingArea))")
        }
        #expect(ExplainerScreen.drawingArea(for: .zero) == nil)
    }

    @Test func theChildVersionTakesTheArrangementToo() {
        for (space, arrangement) in [(Self.tall, ScreenArrangement.captionBeside), (Self.wide, .captionBelow), (Self.wide, .automatic)] {
            let player = GuidedPlayer(lesson: BarExplainer.lesson(), voice: RecordingVoice(), labels: Fixture.guidedLabels, drivesItself: false)
            _ = Self.render(GuidedView(player: player, arrangement: arrangement), space)
            let area = try? #require(player.drawingArea)
            let watched = ExplainerScreen.drawingArea(for: space, arrangement: arrangement)!
            if arrangement == .captionBelow {
                // Its line, with a hint and a tally, is taller than the watched steps' line.
                #expect(area?.width == space.width && (area?.height ?? .infinity) < watched.height, "\(space)")
            } else {
                #expect(Self.near(area, watched), "\(arrangement) at \(space): \(String(describing: area))")
            }
        }
    }

    // MARK: a document laid out for a declared shape other than its area's

    /// The stage's own shape, 1000 by 540 (1.85), is outside its declared range of 0.9 to 1.5.
    static let narrowStage = #"[{"layout": "stage", "ratio": [0.9, 1.5]}]"#

    /// Where the drawing is in the stacked arrangement of the watched steps: under the header band.
    static func stackedDrawing(_ space: CGSize) -> CGRect {
        let top = 14 + ScreenPlan.headerBand + 8
        return CGRect(x: 0, y: top, width: space.width, height: space.height - ScreenPlan.stackedChrome)
    }

    /// Where `scene` is drawn fitted into `area`, a rectangle in the view.
    static func fitted(_ scene: Scene, in area: CGRect) -> CGRect {
        let (s, o) = scene.fit(in: area.size)
        return CGRect(x: area.minX + o.x, y: area.minY + o.y, width: scene.size.width * s, height: scene.size.height * s)
    }

    @Test func aStageOutsideItsDeclaredRangeIsDrawnInsideTheAreaUsed() throws {
        let fill = ExplainerStyle.standard.palette(dark: false).rgb(.fill(.divide))
        // A drawing of 1400 by 546 (2.56) with the caption below: laid out for 1.5, 819 by 546.
        let space = CGSize(width: 1400, height: 800)
        let player = try Self.player(areas: Self.narrowStage)
        let image = try #require(Self.render(ExplainerView(player: player, labels: Self.labels, arrangement: .captionBelow), space))
        let use = try #require(player.areaUse)
        let drawing = Self.stackedDrawing(space)
        #expect(Self.near(use.given, drawing.size) && !use.isGiven && abs(use.used.width / use.used.height - 1.5) < 1e-9)
        let used = CGRect(
            x: drawing.midX - use.used.width / 2, y: drawing.midY - use.used.height / 2, width: use.used.width, height: use.used.height)
        let drawn = try #require(Self.bounds(of: fill, in: image))
        #expect(used.insetBy(dx: -1, dy: -1).contains(drawn), "drawn at \(drawn), the area used is \(used)")
        #expect(Self.near(drawn, Self.fitted(player.scene, in: used)), "centred in the area used: \(drawn)")
        // Fitted to the whole drawing area instead, it would be 1011 points wide.
        #expect(drawn.width <= use.used.width + 1)

        // The stage alone, as an app that builds its own screen draws it, in an area of 2.4.
        let area = CGSize(width: 1200, height: 500)
        player.layOut(for: area)
        let own = try #require(player.areaUse)
        let stage = try #require(Self.render(ExplainerStage(scene: player.scene, areaUse: own), area))
        let ownUsed = CGRect(x: (1200 - own.used.width) / 2, y: 0, width: own.used.width, height: own.used.height)
        let ownDrawn = try #require(Self.bounds(of: fill, in: stage))
        #expect(own.used.width == 750 && Self.near(ownDrawn, Self.fitted(player.scene, in: ownUsed)), "\(ownDrawn)")
    }

    @Test func aDocumentWithoutAreasAndADeclaredShapeAreDrawnAsBefore() throws {
        let fill = ExplainerStyle.standard.palette(dark: false).rgb(.fill(.divide))
        // Without areas: fitted to the whole drawing area, as the stage always was.
        let space = CGSize(width: 1400, height: 800)
        let plain = try Self.player()
        let image = try #require(Self.render(ExplainerView(player: plain, labels: Self.labels, arrangement: .captionBelow), space))
        #expect(plain.areaUse?.isGiven == true)
        let drawn = try #require(Self.bounds(of: fill, in: image))
        #expect(Self.near(drawn, Self.fitted(plain.scene, in: Self.stackedDrawing(space))), "\(drawn)")
        // A declared shape: a drawing of 700 by 446 (1.57) is inside 0.9 to 1.6.
        let narrow = CGSize(width: 700, height: 700)
        let declared = try Self.player(areas: #"[{"layout": "stage", "ratio": [0.9, 1.6]}]"#)
        let image2 = try #require(Self.render(ExplainerView(player: declared, labels: Self.labels, arrangement: .captionBelow), narrow))
        #expect(declared.areaUse?.isGiven == true)
        let drawn2 = try #require(Self.bounds(of: fill, in: image2))
        #expect(Self.near(drawn2, Self.fitted(declared.scene, in: Self.stackedDrawing(narrow))), "\(drawn2)")
    }
}
