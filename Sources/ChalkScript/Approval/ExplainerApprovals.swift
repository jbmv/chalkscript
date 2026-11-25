import Foundation

/// The explainers an approval can be recorded for (EXP-1): one per explainer this package draws.
/// The raw value is the id written in the approvals file the app supplies. The order is the
/// order the consuming app lists them in.
public enum ExplainerID: String, CaseIterable, Sendable {
    case subtraction
    case addition
    case compareTape = "compare-tape"
    case compareGraph = "compare-graph"
    case makeTen = "make-ten"
    case threeCards = "three-cards"
    case tensOnesReading = "tens-ones-reading"
    case tensOnesWriting = "tens-ones-writing"

    /// Whether the explainer has a parent version (EXP-9). The others have only the child's.
    public var hasParentVersion: Bool {
        switch self {
        case .subtraction, .tensOnesReading, .tensOnesWriting: true
        case .addition, .compareTape, .compareGraph, .makeTen, .threeCards: false
        }
    }
}

/// One recorded approval (EXP-1): a reviewer approved `version` of `explainer`'s `audience`
/// version, on `approvedOn`.
public struct ExplainerApproval: Equatable, Sendable {
    public var explainer: String
    public var audience: ExplainerVersion
    public var version: String
    public var approvedBy: String
    public var approvedOn: String

    public init(explainer: String, audience: ExplainerVersion, version: String, approvedBy: String, approvedOn: String) {
        self.explainer = explainer
        self.audience = audience
        self.version = version
        self.approvedBy = approvedBy
        self.approvedOn = approvedOn
    }
}

/// The approvals file, which the app supplies: which version of which explainer a reviewer has
/// approved for the child and for the parent. An explainer is shown only when its
/// current version (`ExplainerFingerprint`) is the one approved for that audience (EXP-1), so a
/// change to its steps or narration withdraws the approval until the new version is approved.
///
/// The file is a list of entries under `approvals:`, each with the keys `explainer`, `audience`
/// (`child` or `parent`), `version`, `approved-by` and `approved-on`; `approvals: []` is the empty
/// file. `#` starts a comment.
public struct ExplainerApprovals: Equatable, Sendable {
    public enum ParseError: Error, Equatable, Sendable {
        case notAnApprovalsFile
        case line(Int, String)
        case incomplete(entry: Int, missing: String)
    }

    public var entries: [ExplainerApproval]

    public init(entries: [ExplainerApproval] = []) { self.entries = entries }

    public static let none = ExplainerApprovals()

    /// Whether `version` of `explainer` for `audience` is approved. An approval is for exactly one
    /// version: a later version needs its own.
    public func isApproved(_ explainer: ExplainerID, _ audience: ExplainerVersion, version: String) -> Bool {
        entries.contains { $0.explainer == explainer.rawValue && $0.audience == audience && $0.version == version }
    }

    /// Reads the file's text.
    public init(yaml: String) throws(ParseError) {
        var entries: [ExplainerApproval] = []
        var fields: [String: String]?
        var sawHeader = false
        var count = 0

        func close() throws(ParseError) {
            guard let f = fields else { return }
            count += 1
            func need(_ key: String) throws(ParseError) -> String {
                guard let v = f[key], !v.isEmpty else { throw .incomplete(entry: count, missing: key) }
                return v
            }
            let audience = try need("audience")
            guard let a = ExplainerVersion(rawValue: audience) else { throw .incomplete(entry: count, missing: "audience") }
            entries.append(
                ExplainerApproval(
                    explainer: try need("explainer"), audience: a, version: try need("version"),
                    approvedBy: try need("approved-by"), approvedOn: try need("approved-on")))
            fields = nil
        }

        for (index, raw) in yaml.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var text = String(raw)
            if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
            let line = text.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if !sawHeader {
                guard line == "approvals:" || line == "approvals: []" else { throw .notAnApprovalsFile }
                sawHeader = true
                continue
            }
            var body = line
            if body.hasPrefix("- ") {
                try close()
                fields = [:]
                body = String(body.dropFirst(2))
            }
            guard fields != nil, let colon = body.firstIndex(of: ":") else { throw .line(index + 1, line) }
            let key = body[..<colon].trimmingCharacters(in: .whitespaces)
            var value = body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q { value = String(value.dropFirst().dropLast()) }
            fields?[key] = value
        }
        guard sawHeader else { throw .notAnApprovalsFile }
        try close()
        self.entries = entries
    }
}

/// An explainer's current version (EXP-1): a fingerprint of what the explainer does and says,
/// computed from the explainers themselves, so a change to a template's steps, timing or
/// narration changes it and nobody has to remember to bump a number. 16 hex digits of FNV-1a over
/// a fixed text, which is stable across runs and platforms.
public enum ExplainerFingerprint {
    /// The fingerprint of `explainers`: each one's step count, intro, and every step's duration
    /// and events (the lines' keys, shown text, spoken text and emphasis, and when they happen).
    /// `extra` is text the caller adds, such as the steps' names.
    public static func of(_ explainers: [any Explainer], extra: [String] = []) -> String {
        var text = ""
        for (i, e) in explainers.enumerated() {
            text += "explainer \(i) \(e.version.rawValue) steps \(e.stepCount)\n"
            if i < extra.count { text += extra[i] + "\n" }
            text += describe(e.intro) + "\n"
            for s in 0..<e.stepCount {
                let script = e.script(for: s)
                text += "step \(s) \(script.duration)\n"
                for ev in script.events {
                    switch ev.action {
                    case let .say(line, caption): text += "\(ev.time) say \(caption) \(describe(line))\n"
                    case .waitForVoice: text += "\(ev.time) wait\n"
                    }
                }
            }
        }
        return hex(fnv1a(text))
    }

    static func describe(_ l: Line) -> String {
        "\(l.key)|\(l.display)|\(l.spoken ?? "-")|\(l.emphasis ?? "-")"
    }

    static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h
    }

    static func hex(_ v: UInt64) -> String {
        let s = String(v, radix: 16)
        return String(repeating: "0", count: 16 - s.count) + s
    }
}

extension SubtractionExplainer {
    /// The problems whose explainers the version is computed over: the range's edges and
    /// examples of every shape of step list and the widest count.
    public static let versionSamples: [(Int, Int)] = [
        (10, 1), (10, 9), (10, 10), (11, 1), (19, 9), (20, 1), (20, 11), (50, 20), (54, 26), (83, 12),
        (44, 5), (90, 89), (91, 9), (98, 20), (99, 1), (99, 9), (99, 10), (99, 90), (99, 98), (99, 99),
    ]

    /// The current version of the subtraction explainer for `audience` with `wording` (EXP-1):
    /// its steps, timings and lines, and its motion file's shots and camera moves (EXP-19), so a
    /// change to how the camera frames a step changes the version as a change to a line does.
    public static func currentVersion(
        _ audience: ExplainerVersion, wording: SubtractionWording, motion: ExplainerMotion = SubtractionExplainer.standardMotion
    ) -> String {
        let all = versionSamples.compactMap {
            try? SubtractionExplainer(problem: SubtractionProblem($0.0, minus: $0.1), version: audience, wording: wording, motion: motion)
        }
        return ExplainerFingerprint.of(all, extra: all.map { String(describing: $0.steps) + "\n" + motion.summary })
    }
}

extension TensOnesExplainer {
    public static let readingSamples = [10, 11, 19, 20, 40, 47, 90, 99]
    public static let writingSamples: [(Int, Int)] = [
        (1, 0), (1, 1), (1, 9), (1, 10), (1, 19), (3, 5), (4, 7), (4, 0), (3, 13), (8, 19), (9, 0), (9, 9), (5, 10),
    ]

    /// The current version of the explainer `id` (one of the tens-and-ones ones) for `audience`
    /// with `wording` (EXP-1), over both drawings; nil for an `id` this template does not play.
    public static func currentVersion(_ id: ExplainerID, _ audience: ExplainerVersion, wording: TensOnesWording) -> String? {
        var all: [TensOnesExplainer] = []
        for d in PlaceValueDrawing.allCases {
            switch id {
            case .tensOnesReading:
                all += readingSamples.compactMap { try? TensOnesReading($0, drawing: d) }
                    .map { TensOnesExplainer(reading: $0, version: audience, wording: wording) }
            case .tensOnesWriting:
                all += writingSamples.compactMap { try? TensOnesWriting(tens: $0.0, ones: $0.1, drawing: d) }
                    .map { TensOnesExplainer(writing: $0, version: audience, wording: wording) }
            default: return nil
            }
        }
        return ExplainerFingerprint.of(all, extra: all.map { String(describing: $0.steps) })
    }
}
