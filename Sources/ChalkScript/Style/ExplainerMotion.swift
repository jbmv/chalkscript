import CoreGraphics
import Foundation

/// What an explainer's motion file may hold (EXP-19), declared by the explainer's code: the
/// timed values each step reads, each with the kind of motion it times (which gives its default
/// when the file leaves it out), and the parts of its drawing a shot may frame.
public struct MotionVocabulary: Sendable {
    public struct StepValues: Sendable {
        public var step: String
        public var values: [(name: String, kind: MotionKind)]

        public init(_ step: String, _ values: [(String, MotionKind)]) {
            self.step = step
            self.values = values.map { (name: $0.0, kind: $0.1) }
        }
    }

    public var steps: [StepValues]
    public var parts: [String]

    public init(steps: [StepValues], parts: [String]) {
        self.steps = steps
        self.parts = parts
    }
}

/// A shot (EXP-18): the region of the drawing the camera frames, as the parts it shows (named by
/// the explainer, such as `ones` or `count`) and, or, a rectangle in the drawing's own units,
/// with a margin round them, in the same units.
public struct ShotSpec: Equatable, Sendable {
    public var frame: [String]
    public var region: CGRect?
    public var margin: Double

    public init(frame: [String], region: CGRect? = nil, margin: Double) {
        self.frame = frame
        self.region = region
        self.margin = margin
    }
}

/// How the camera moves to a step's shot (EXP-18): `at` seconds after the step begins, over
/// `duration` seconds, along the curve named `easingName`.
public struct CameraMove: Equatable, Sendable {
    public var at: Double
    public var duration: Double
    public var easingName: String
    public var easing: Easing

    public init(at: Double, duration: Double, easingName: String, easing: Easing) {
        self.at = at
        self.duration = duration
        self.easingName = easingName
        self.easing = easing
    }

    /// When the camera has landed, after the step begins.
    public var end: Double { at + duration }

    /// How far the move has got at `t` seconds into the step, eased, 0 to 1.
    public func fraction(at t: Double) -> Double { progress(t, start: at, duration: duration, easing) }
}

/// One step's motion, resolved: the shot it plays in, the shot the child acts in where that
/// differs (do it with me, EXP-14), how the camera moves, and its timed values.
public struct StepMotion: Equatable, Sendable {
    public var shot: String?
    public var doShot: String?
    public var camera: CameraMove
    public var durations: [String: Double]
    public var easings: [String: Easing]
    public var easingNames: [String: String]
}

/// An explainer's motion file, read and resolved against a style (EXP-19): its shots and, step by
/// step, the shot each plays in, how the camera moves to it, and its durations and easings. Every
/// value is optional: one left out takes the style's default for its kind, and `issues` lists it,
/// with any key or name the file has that the format or the explainer does not.
///
/// The format, which `docs/spec/explainers.md` (EXP-19) sets out in full:
///
///     { "format": "explainer-motion", "version": 1, "explainer": "subtraction",
///       "shots": { "ones": { "frame": ["ones"], "margin": 12 }, ... },
///       "opening": "whole",
///       "steps": { "takeOnes": { "shot": "ones",
///                                "camera": { "at": 0, "duration": 0.9, "easing": "smooth" },
///                                "durations": { "takeCross": 0.28, ... },
///                                "easings": { "takeCross": "easeOut" } }, ... } }
public struct ExplainerMotion: Equatable, Sendable {
    public var explainer: String
    public var shots: [String: ShotSpec]
    /// The shot before the first step.
    public var opening: String?
    public var steps: [String: StepMotion]
    /// How strongly what is out of shot is dimmed: the style's (EXP-18).
    public var dim: Double
    /// The style's margin round a shot, which the whole drawing is also given.
    public var margin: Double
    public var issues: [FormatIssue]

    /// Step `step`'s value `name`, in seconds.
    public func seconds(_ step: String, _ name: String) -> Double {
        guard let v = steps[step]?.durations[name] else { preconditionFailure("\(explainer) has no value \(step).\(name)") }
        return v
    }

    /// The curve step `step`'s value `name` is eased along.
    public func easing(_ step: String, _ name: String) -> Easing { steps[step]?.easings[name] ?? .linear }

    /// Every resolved value as text, in a fixed order: what the explainer's version covers, so a
    /// change to a shot, a camera move or a timing changes the version (EXP-1).
    public var summary: String {
        var lines = ["opening \(opening ?? "-") dim \(dim) margin \(margin)"]
        for name in shots.keys.sorted() {
            let s = shots[name]!
            let region = s.region.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" } ?? "-"
            lines.append("shot \(name) \(s.frame.joined(separator: "+")) \(region) \(s.margin)")
        }
        for id in steps.keys.sorted() {
            let s = steps[id]!
            lines.append("step \(id) \(s.shot ?? "-") \(s.doShot ?? "-") \(s.camera.at) \(s.camera.duration) \(s.camera.easingName)")
            for v in s.durations.keys.sorted() { lines.append("  \(v) \(s.durations[v]!) \(s.easingNames[v] ?? "-")") }
        }
        return lines.joined(separator: "\n")
    }

    /// Reads `explainer`'s motion file against `style`, with `vocabulary` saying which values its
    /// steps read and which parts a shot may frame.
    public static func read(_ data: Data, explainer: String, vocabulary: MotionVocabulary, style: ExplainerStyle) -> ExplainerMotion {
        let log = FormatLog()
        let tree: FormatValue?
        do { tree = try FormatValue.parse(data) } catch {
            log.add(.invalid, "", "not JSON: \(error.localizedDescription)")
            tree = nil
        }
        let top = FormatReader(tree, path: "", log: log)
        if let f = top.string("format", reportDefault: false), f != "explainer-motion" {
            log.add(.invalid, "format", "\"\(f)\" is not \"explainer-motion\"")
        }
        _ = top.number("version", min: 1, max: 1, reportDefault: false)
        if let e = top.string("explainer", reportDefault: false), e != explainer {
            log.add(.invalid, "explainer", "the file is for \"\(e)\", not \"\(explainer)\"")
        }

        // Shots.
        let shotsReader = top.object("shots")
        var shots: [String: ShotSpec] = [:]
        for name in shotsReader.keys {
            let r = shotsReader.object(name)
            var frame: [String] = []
            for part in r.strings("frame") ?? [] {
                if vocabulary.parts.contains(part) { frame.append(part) } else {
                    log.add(.unknown, r.key("frame"), "\(explainer) has no part \"\(part)\"; left out of the shot")
                }
            }
            var region: CGRect?
            if let n = r.numbers("region", count: 4) {
                if n[2] > 0, n[3] > 0 { region = CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) } else {
                    log.add(.invalid, r.key("region"), "a region needs a width and a height above 0")
                }
            }
            if frame.isEmpty && region == nil { log.add(.invalid, r.key("frame"), "the shot frames nothing; the whole drawing is shown") }
            let margin = r.number("margin", max: 1000) ?? style.camera.margin
            r.finish()
            shots[name] = ShotSpec(frame: frame, region: region, margin: margin)
        }
        shotsReader.finish()
        func shotName(_ r: FormatReader, _ key: String, reportDefault: Bool) -> String? {
            guard let name = r.string(key, reportDefault: reportDefault) else { return nil }
            guard shots[name] != nil else {
                log.add(.unknown, r.key(key), "no shot named \"\(name)\"; the camera stays where it is")
                return nil
            }
            return name
        }
        let opening = shotName(top, "opening", reportDefault: true)

        // Steps.
        let stepsReader = top.object("steps")
        var steps: [String: StepMotion] = [:]
        for declared in vocabulary.steps {
            let r = stepsReader.object(declared.step)
            let shot = shotName(r, "shot", reportDefault: true)
            let doShot = shotName(r, "doShot", reportDefault: false)
            let c = r.object("camera")
            let at = c.number("at", max: 30) ?? style.camera.at
            let duration = c.number("duration", max: 30) ?? style.camera.duration
            var cameraEasing = style.camera.easing
            if let name = c.string("easing") {
                if style.easing(named: name) != nil { cameraEasing = name } else {
                    log.add(.unknown, c.key("easing"), "no easing named \"\(name)\"; \(cameraEasing) is used")
                }
            }
            c.finish()
            let d = r.object("durations")
            let e = r.object("easings")
            var durations: [String: Double] = [:]
            var easings: [String: Easing] = [:]
            var easingNames: [String: String] = [:]
            for (name, kind) in declared.values {
                durations[name] = d.number(name, max: 30) ?? style.durations[kind] ?? 0
                guard kind.takesEasing else { continue }
                var curve = style.kindEasings[kind] ?? "linear"
                if let n = e.string(name, reportDefault: false) {
                    if style.easing(named: n) != nil { curve = n } else {
                        log.add(.unknown, e.key(name), "no easing named \"\(n)\"; \(curve) is used")
                    }
                }
                easingNames[name] = curve
                easings[name] = style.easing(named: curve) ?? .linear
            }
            d.finish()
            e.finish()
            r.finish()
            steps[declared.step] = StepMotion(
                shot: shot, doShot: doShot,
                camera: CameraMove(at: at, duration: duration, easingName: cameraEasing, easing: style.easing(named: cameraEasing) ?? .linear),
                durations: durations, easings: easings, easingNames: easingNames)
        }
        stepsReader.finish()
        top.finish()
        return ExplainerMotion(
            explainer: explainer, shots: shots, opening: opening, steps: steps, dim: style.camera.dim, margin: style.camera.margin,
            issues: log.issues)
    }

    /// Reads the motion file bundled with the package for `explainer` (`<explainer>-motion.json`).
    public static func bundled(_ explainer: String, vocabulary: MotionVocabulary, style: ExplainerStyle = .standard) -> ExplainerMotion {
        guard let data = ExplainerResources.data("\(explainer)-motion") else {
            var m = read(Data("{}".utf8), explainer: explainer, vocabulary: vocabulary, style: style)
            m.issues.insert(FormatIssue(.invalid, "", "the bundled \(explainer)-motion.json could not be read; defaults are used"), at: 0)
            return m
        }
        return read(data, explainer: explainer, vocabulary: vocabulary, style: style)
    }
}
