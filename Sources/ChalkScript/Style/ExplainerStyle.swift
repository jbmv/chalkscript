import Foundation
import SwiftUI

/// What a duration in a motion file times, so that a value the file leaves out falls back to the
/// style's default for its kind (EXP-19): a piece or mark appearing, a line or outline being
/// drawn on, a fade to a ghost, a piece travelling to a new place, the lag between one piece and
/// the next, and a hold where nothing moves.
public enum MotionKind: String, CaseIterable, Sendable {
    case appear, draw, fade, travel, lag, hold

    /// Whether a value of this kind is eased: a lag or a hold is a wait, not a motion.
    public var takesEasing: Bool { self != .lag && self != .hold }
}

/// The camera's defaults in a style (EXP-18, EXP-19): when a move starts after its step begins,
/// how long it takes and its curve, the margin round a shot's parts, in the drawing's units, and
/// how strongly what is out of shot is dimmed (0 none, 1 gone).
public struct CameraDefaults: Equatable, Sendable {
    public var at: Double
    public var duration: Double
    public var easing: String
    public var margin: Double
    public var dim: Double

    public init(at: Double, duration: Double, easing: String, margin: Double, dim: Double) {
        self.at = at
        self.duration = duration
        self.easing = easing
        self.margin = margin
        self.dim = dim
    }
}

/// What a style profile fixes (EXP-20): the roles whose meaning it fixes, each with a sentence
/// saying what it means, and how a document may change an operation's colour: with an explanation
/// (`explained`) or without one (`free`).
public struct StyleProfile: Equatable, Sendable {
    public enum Overrides: String, Sendable { case explained, free }

    /// The name a document declares.
    public var id: String
    public var title: String
    public var fixed: [String: String]
    public var overrides: Overrides
}

/// A style file (EXP-19): the EXP-6 palette roles with their colours, in light and dark; the
/// easing curves by name; and the motion defaults every explainer's motion file falls back to
/// (a duration and an easing per kind of motion, and the camera's). The roles are fixed by EXP-6;
/// a style only gives them values, so a palette is swapped by swapping the file.
///
/// The format, which `docs/spec/explainers.md` (EXP-19) sets out in full:
///
///     { "format": "explainer-style", "version": 1,
///       "palette": { "light": { "paper": "#F3F5F4", "sheet": "#FFFFFF", "text": "#23282B",
///                               "muted": "#637078", "line": "#D7DEDB", "pencil": "#2C3236",
///                               "onResult": "#FFFFFF",
///                               "subtract": { "fill": "#D55E00", "ink": "#D55E00", "soft": "#FBE6D9" },
///                               ... trade, result, add, multiply, divide },
///                    "dark": { ... } },
///       "easings": { "easeOut": [0, 0, 0.58, 1], ... },
///       "motion": { "durations": { "appear": 0.3, ... },
///                   "easings": { "draw": "easeOut", ... },
///                   "camera": { "at": 0, "duration": 0.9, "easing": "smooth", "margin": 12, "dim": 0.45 } } }
public struct ExplainerStyle: Equatable, Sendable {
    public var light: ExplainerPalette
    public var dark: ExplainerPalette
    /// Named curves, each a CSS cubic-bezier; `linear` is always there.
    public var easings: [String: Easing]
    /// The default duration of each kind of motion, in seconds.
    public var durations: [MotionKind: Double]
    /// The default curve of each kind of motion that is eased, by name.
    public var kindEasings: [MotionKind: String]
    public var camera: CameraDefaults
    /// The profile the file declares, when it is a profile's file (EXP-20).
    public var profile: StyleProfile? = nil
    /// What reading the file noticed (EXP-19): values left to their defaults, unknown keys and
    /// names, unreadable values.
    public var issues: [FormatIssue]

    public func palette(dark: Bool) -> ExplainerPalette { dark ? self.dark : light }

    /// The curve called `name`, or nil when the style has none by that name.
    public func easing(named name: String) -> Easing? { name == "linear" ? .linear : easings[name] }

    /// The default curve for a kind of motion.
    public func easing(for kind: MotionKind) -> Easing {
        guard kind.takesEasing, let name = kindEasings[kind] else { return .linear }
        return easing(named: name) ?? .linear
    }

    /// The colour roles of EXP-6 a palette in the file gives, besides the operations'.
    public static let roles = ["paper", "sheet", "text", "muted", "line", "pencil", "onResult"]
    /// Each operation's three values.
    public static let operationRoles = ["fill", "ink", "soft"]

    /// The style the app uses: the bundled `style.json`. Read once.
    public static let standard: ExplainerStyle = {
        guard let data = ExplainerResources.data("style") else {
            var s = ExplainerStyle.lastResort
            s.issues = [FormatIssue(.invalid, "", "the bundled style.json could not be read; the last-resort style is used")]
            return s
        }
        return read(data, over: .lastResort)
    }()

    /// The bundled profile files, by id (EXP-20), each read over the standard style. A document
    /// that declares none is read as `open`.
    public static let profiles: [String: ExplainerStyle] = {
        // The build process flattens the resources folder, so a profile is found by its `profile` key.
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        var out: [String: ExplainerStyle] = [:]
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let style = read(data, over: .standard)
            if let id = style.profile?.id { out[id] = style }
        }
        return out
    }()

    /// The id of the profile a document with no `profile` is made for.
    public static let defaultProfile = "open"

    /// Used only for values a file leaves out with nothing else to fall back to: plain grey and
    /// one even pace, so a missing value shows. The bundled style gives every value (a test holds
    /// it to that), so the app never shows these.
    public static let lastResort: ExplainerStyle = {
        let grey = RGB(hex: 0x808080)
        let ops = ExplainerPalette.OperationColors(fill: grey, ink: grey, soft: grey)
        let palette = ExplainerPalette(
            paper: grey, sheet: grey, ink: grey, muted: grey, line: grey, pencil: grey, onResult: grey,
            operations: Dictionary(uniqueKeysWithValues: ExplainerOperation.allCases.map { ($0, ops) }))
        var dark = palette
        dark.isDark = true
        return ExplainerStyle(
            light: palette, dark: dark, easings: [:],
            durations: Dictionary(uniqueKeysWithValues: MotionKind.allCases.map { ($0, 0.5) }), kindEasings: [:],
            camera: CameraDefaults(at: 0, duration: 0.5, easing: "linear", margin: 0, dim: 0), issues: [])
    }()

    /// Reads a style file. A value it leaves out takes `base`'s (the bundled style, for a palette
    /// swapped in; the last resort, for the bundled file itself); every such value, unknown key
    /// and unreadable value is listed in `issues`.
    public static func read(_ data: Data, over base: ExplainerStyle = .standard) -> ExplainerStyle {
        let log = FormatLog()
        let tree: FormatValue?
        do { tree = try FormatValue.parse(data) } catch {
            log.add(.invalid, "", "not JSON: \(error.localizedDescription)")
            tree = nil
        }
        let top = FormatReader(tree, path: "", log: log)
        if let f = top.string("format", reportDefault: false), f != "explainer-style" {
            log.add(.invalid, "format", "\"\(f)\" is not \"explainer-style\"")
        }
        _ = top.number("version", min: 1, max: 1, reportDefault: false)

        let profile = readProfile(top.object("profile"), over: base.profile, log: log)

        let palettes = top.object("palette")
        var light = readPalette(palettes.object("light"), over: base.light, log: log)
        var dark = readPalette(palettes.object("dark"), over: base.dark, log: log)
        light.isDark = false
        dark.isDark = true
        palettes.finish()

        let curves = top.object("easings")
        var easings = base.easings
        for name in curves.keys {
            if name == "linear" {
                _ = curves.raw(name)
                continue
            }
            guard let c = curves.numbers(name, count: 4) else { continue }
            guard c[0] >= 0, c[0] <= 1, c[2] >= 0, c[2] <= 1 else {
                log.add(.invalid, curves.key(name), "a curve's x values must be from 0 to 1")
                continue
            }
            easings[name] = .cubic(c[0], c[1], c[2], c[3])
        }
        curves.finish()

        let motion = top.object("motion")
        let d = motion.object("durations")
        var durations = base.durations
        for kind in MotionKind.allCases {
            if let v = d.number(kind.rawValue, max: 30) { durations[kind] = v }
        }
        d.finish()
        let e = motion.object("easings")
        var kindEasings = base.kindEasings
        for kind in MotionKind.allCases where kind.takesEasing {
            guard let name = e.string(kind.rawValue) else { continue }
            if name == "linear" || easings[name] != nil { kindEasings[kind] = name } else {
                log.add(.unknown, e.key(kind.rawValue), "no easing named \"\(name)\"; \(kindEasings[kind] ?? "linear") is used")
            }
        }
        e.finish()
        let c = motion.object("camera")
        var camera = base.camera
        if let v = c.number("at", max: 30) { camera.at = v }
        if let v = c.number("duration", max: 30) { camera.duration = v }
        if let name = c.string("easing") {
            if name == "linear" || easings[name] != nil { camera.easing = name } else {
                log.add(.unknown, c.key("easing"), "no easing named \"\(name)\"; \(camera.easing) is used")
            }
        }
        if let v = c.number("margin", max: 1000) { camera.margin = v }
        if let v = c.number("dim", max: 1) { camera.dim = v }
        c.finish()
        motion.finish()
        top.finish()
        return ExplainerStyle(
            light: light, dark: dark, easings: easings, durations: durations, kindEasings: kindEasings, camera: camera,
            profile: profile, issues: log.issues)
    }

    private static func readProfile(_ r: FormatReader, over base: StyleProfile?, log: FormatLog) -> StyleProfile? {
        guard r.keys.isEmpty == false else { return base }
        var profile = base ?? StyleProfile(id: "", title: "", fixed: [:], overrides: .explained)
        if let id = r.string("id", reportDefault: false) {
            if id.count >= 2, id.allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }) { profile.id = id } else {
                log.add(.invalid, r.key("id"), "\"\(id)\" is not two or more lowercase letters")
            }
        }
        if let t = r.string("title", reportDefault: false) { profile.title = t }
        if let o = r.string("overrides", reportDefault: false) {
            if let v = StyleProfile.Overrides(rawValue: o) { profile.overrides = v } else {
                log.add(.invalid, r.key("overrides"), "\"\(o)\" is not explained or free")
            }
        }
        let fixed = r.object("fixed")
        for role in fixed.keys {
            if let meaning = fixed.string(role, reportDefault: false) { profile.fixed[role] = meaning }
        }
        fixed.finish()
        r.finish()
        return profile.id.isEmpty ? nil : profile
    }

    private static func readPalette(_ r: FormatReader, over base: ExplainerPalette, log: FormatLog) -> ExplainerPalette {
        var p = base
        func colour(_ reader: FormatReader, _ key: String) -> RGB? {
            guard let s = reader.string(key) else { return nil }
            guard let c = RGB(hexString: s) else {
                log.add(.invalid, reader.key(key), "\"\(s)\" is not a colour written #RRGGBB")
                return nil
            }
            return c
        }
        if let c = colour(r, "paper") { p.paper = c }
        if let c = colour(r, "sheet") { p.sheet = c }
        if let c = colour(r, "text") { p.ink = c }
        if let c = colour(r, "muted") { p.muted = c }
        if let c = colour(r, "line") { p.line = c }
        if let c = colour(r, "pencil") { p.pencil = c }
        if let c = colour(r, "onResult") { p.onResult = c }
        let suggested = r.object("suggested")
        for name in suggested.keys {
            if let c = colour(suggested, name) { p.suggested[name] = c }
        }
        suggested.finish()
        for op in ExplainerOperation.allCases {
            let o = r.object(op.rawValue)
            var colors = p.colors(op)
            if let c = colour(o, "fill") { colors.fill = c }
            if let c = colour(o, "ink") { colors.ink = c }
            if let c = colour(o, "soft") { colors.soft = c }
            o.finish()
            p.operations[op] = colors
        }
        r.finish()
        return p
    }
}

extension EnvironmentValues {
    /// The style the explainers are drawn in (EXP-19): the bundled one unless a view sets another,
    /// as an authoring tool may to try a palette.
    @Entry public var explainerStyle: ExplainerStyle = .standard
}
