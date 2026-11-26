import Foundation

/// An explainer's revision (EXP-1): a fingerprint of what the explainer does and says,
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
