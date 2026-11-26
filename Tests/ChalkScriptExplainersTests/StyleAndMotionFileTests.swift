import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

// The style file and the motion file (EXP-19). The style holds EXP-6's palette
// roles with their colours and the motion defaults; a second palette with the same roles changes
// every colour subtraction draws, with no change to its code. Subtraction's motion file holds its
// shots and timings by step, each optional and falling back to the style; both are bundled and
// read with Foundation; what is missing or unknown falls back and is reported.

@MainActor
struct StyleAndMotionFileTests {
    // MARK: the style file

    /// The bundled style with every colour changed (each value XORed with a constant, so none
    /// stays the same) and the same roles: written as a style file and read back.
    static func secondPalette() -> ExplainerStyle {
        func hex(_ c: RGB) -> String {
            let v = (UInt32((c.red * 255).rounded()) << 16 | UInt32((c.green * 255).rounded()) << 8 | UInt32((c.blue * 255).rounded())) ^ 0x2A_4C_1E
            return String(format: "\"#%06X\"", v)
        }
        func palette(_ p: ExplainerPalette) -> String {
            var fields = [
                "\"paper\": \(hex(p.paper))", "\"sheet\": \(hex(p.sheet))", "\"text\": \(hex(p.ink))", "\"muted\": \(hex(p.muted))",
                "\"line\": \(hex(p.line))", "\"pencil\": \(hex(p.pencil))", "\"onResult\": \(hex(p.onResult))",
            ]
            for op in ExplainerOperation.allCases {
                let c = p.colors(op)
                fields.append("\"\(op.rawValue)\": { \"fill\": \(hex(c.fill)), \"ink\": \(hex(c.ink)), \"soft\": \(hex(c.soft)) }")
            }
            return "{ " + fields.joined(separator: ", ") + " }"
        }
        let s = ExplainerStyle.standard
        let json = "{ \"format\": \"explainer-style\", \"version\": 1, \"palette\": { \"light\": \(palette(s.light)), \"dark\": \(palette(s.dark)) } }"
        return ExplainerStyle.read(Data(json.utf8))
    }

    /// Every colour drawing `scenes` resolves, by role, as the stage draws them.
    static func colours(_ scenes: [Scene], _ palette: ExplainerPalette) -> [Ink: RGB] {
        ExplainerStage.colours(drawing: scenes, palette: palette, size: SubtractionScreenTests.miniLandscape)
    }

    /// Subtraction's pictures, on the stage and laid out with the camera: every step's still and
    /// the middle of each step's motion, learner and parent, with and without a trade.
    static func subtractionScenes() -> [Scene] {
        var out: [Scene] = []
        for (a, b) in [(54, 26), (83, 12), (90, 89)] {
            for version in ExplainerVersion.allCases {
                let e = SubtractionExplainer(problem: try! SubtractionProblem(a, minus: b), version: version, wording: Fixture.guidedWording())
                for x in [e, e.laidOut(for: SubtractionScreenTests.miniLandscape)] {
                    out.append(x.still(after: -1))
                    for k in 0..<x.stepCount {
                        out.append(x.still(after: k))
                        out.append(x.scene(step: k, at: x.script(for: k).duration / 2))
                    }
                }
            }
            // A line the learner drew, in do it with me.
            let e = SubtractionExplainer(problem: try! SubtractionProblem(a, minus: b), version: .child, wording: Fixture.guidedWording())
            let k = e.steps.firstIndex(of: .takeTens) ?? e.steps.firstIndex(of: .count)!
            let s = e.state(after: k - 1)
            if e.steps[k] == .takeTens {
                out.append(e.read(across(e.layout.tens[e.wholeTens(s).last!]), step: k, s).motion?.end ?? e.still(after: k))
            }
        }
        return out
    }

    @Test func aSecondPaletteWithTheSameRolesChangesEveryColourSubtractionDraws() {
        let first = ExplainerStyle.standard
        let second = Self.secondPalette()
        #expect(!second.issues.contains { $0.isProblem }, "\(second.issues)")
        let scenes = Self.subtractionScenes()
        for dark in [false, true] {
            let a = Self.colours(scenes, first.palette(dark: dark))
            let b = Self.colours(scenes, second.palette(dark: dark))
            #expect(a.count >= 8, "subtraction draws \(a.keys)")
            #expect(Set(a.keys) == Set(b.keys), "the same roles are drawn")
            // Every colour drawn with the second palette is one of its values, and none is one
            // the first drew.
            #expect(Set(a.values).isDisjoint(with: Set(b.values)), "a colour stayed the same")
            for (role, colour) in b { #expect(colour == second.palette(dark: dark).rgb(role), "\(role)") }
            // The roles subtraction shows: pencil pieces, take away, trade, the answer.
            for role: Ink in [.pencil, .sheet, .text, .ink(.subtract), .ink(.trade), .ink(.result), .soft(.result)] {
                #expect(a[role] != nil, "subtraction does not draw \(role)")
            }
        }
    }

    // MARK: the bundled files and the motion file

    @Test func bothFilesAreBundledAndSubtractionsReadsCleanly() {
        #expect(ExplainerResources.data("style") != nil && ExplainerResources.data("subtraction-motion", in: ContentBundle.bundle) != nil)
        let m = SubtractionExplainer.standardMotion
        #expect(!m.issues.contains { $0.isProblem }, "\(m.issues.filter(\.isProblem))")
        // What the file leaves to the style is listed: the camera's timing, the shots' margins,
        // most easings.
        #expect(m.issues.contains(FormatIssue(.defaulted, "steps.trade.camera.duration")))
        #expect(m.issues.contains(FormatIssue(.defaulted, "shots.ones.margin")))
        #expect(Set(m.shots.keys) == ["whole", "ones", "trade", "tens", "count"])
        #expect(m.opening == "whole")
        let shots = SubtractionProblem.Step.allCases.map { m.steps[$0.rawValue]?.shot }
        #expect(shots == ["whole", "ones", "trade", "ones", "ones", "tens", "whole"], "\(shots)")
        #expect(m.steps["count"]?.doShot == "count")
        // The timings.
        #expect(m.seconds("show", "tenDrop") == 0.32 && m.seconds("trade", "travel") == 1.5 && m.seconds("count", "tapTag") == 1.1)
        #expect(m.easing("trade", "travel") == .cubic(0.42, 0, 0.58, 1) && m.easing("count", "copy") == .cubic(0.3, 0.7, 0.2, 1))
        #expect(m.steps["takeOnes"]?.camera == CameraMove(at: 0, duration: 0.9, easingName: "smooth", easing: .cubic(0.45, 0, 0.2, 1)))
    }

    @Test func aMissingOrUnknownValueFallsBackAndIsReported() {
        let style = ExplainerStyle.standard
        let json = """
            { "format": "explainer-motion", "version": 1, "explainer": "subtraction",
              "shots": { "ones": { "frame": ["ones", "elbows"], "margin": 20 }, "far": { "frame": [] } },
              "opening": "nowhere",
              "steps": {
                "show": { "shot": "ones", "wobble": 3, "durations": { "tenDrop": 0.5, "tenSpin": 1 } },
                "trade": { "shot": "zoomed", "camera": { "duration": 1.5, "easing": "bouncy" }, "durations": { "travel": -1 } },
                "takeOnes": { "easings": { "takeCross": "springy", "takeEvery": "smooth" } },
                "dance": { }
              } }
            """
        let m = SubtractionExplainer.motion(Data(json.utf8))
        func has(_ kind: FormatIssue.Kind, _ path: String) -> Bool { m.issues.contains { $0.kind == kind && $0.path == path } }
        // Left out: the style's default for its kind, listed.
        #expect(m.seconds("show", "tenEvery") == style.durations[.lag] && has(.defaulted, "steps.show.durations.tenEvery"))
        #expect(m.seconds("count", "copy") == style.durations[.travel] && has(.defaulted, "steps.count.durations.copy"))
        #expect(m.steps["count"]?.camera.duration == style.camera.duration && has(.defaulted, "steps.count.camera.duration"))
        #expect(m.shots["far"]?.margin == style.camera.margin)
        // Given: used.
        #expect(m.seconds("show", "tenDrop") == 0.5 && m.steps["trade"]?.camera.duration == 1.5 && m.shots["ones"]?.margin == 20)
        // Unknown keys and names: ignored, the default used, listed.
        #expect(has(.unknown, "steps.show.wobble") && has(.unknown, "steps.show.durations.tenSpin") && has(.unknown, "steps.dance"))
        #expect(has(.unknown, "shots.ones.frame") && m.shots["ones"]?.frame == ["ones"], "a part subtraction does not have")
        #expect(has(.unknown, "opening") && m.opening == nil)
        #expect(has(.unknown, "steps.trade.shot") && m.steps["trade"]?.shot == nil, "the camera stays where it is")
        #expect(has(.unknown, "steps.trade.camera.easing") && m.steps["trade"]?.camera.easingName == style.camera.easing)
        #expect(has(.unknown, "steps.takeOnes.easings.takeCross") && m.easing("takeOnes", "takeCross") == style.easing(for: .draw))
        #expect(has(.unknown, "steps.takeOnes.easings.takeEvery"), "a lag is not eased")
        // Unreadable: the default used, listed.
        #expect(has(.invalid, "steps.trade.durations.travel") && m.seconds("trade", "travel") == style.durations[.travel])
        #expect(has(.invalid, "shots.far.frame"), "a shot that frames nothing")

        // The explainer plays the file it is given, with no change to its code: its trade now
        // timed by the style's defaults.
        let e = SubtractionExplainer(problem: try! SubtractionProblem(54, minus: 26), version: .child, wording: Fixture.wording(), motion: m)
        let standard = Fixture.explainer(54, 26)
        let trade = e.steps.firstIndex(of: .trade)!
        #expect(e.sec(.trade, .travel) == 1.2 && e.script(for: trade).duration != standard.script(for: trade).duration)
        // A file that is not JSON at all: every value defaults, and it says why.
        let broken = SubtractionExplainer.motion(Data("not json".utf8))
        #expect(broken.issues.first?.kind == .invalid && broken.seconds("trade", "travel") == style.durations[.travel])
    }

    @Test func theVersionCoversTheMotionFile() {
        let w = Fixture.wording()
        let standard = SubtractionExplainer.currentRevision(.child, wording: w)
        var json = CameraTests.bundledMotion
        json = json.replacingOccurrences(of: "\"tens\": { \"frame\": [\"tens\"] }", with: "\"tens\": { \"frame\": [\"tens\"], \"margin\": 30 }")
        let moved = SubtractionExplainer.currentRevision(.child, wording: w, motion: SubtractionExplainer.motion(Data(json.utf8)))
        #expect(moved != standard, "a shot's margin changes what the child sees, so the version")
        #expect(SubtractionExplainer.currentRevision(.child, wording: w) == standard, "and is stable")
    }
}
