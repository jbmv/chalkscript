#if os(macOS)
import ChalkScript
import Foundation

/// The document a new explainer starts as, and the name made for it from its title
/// (`docs/studio/helper-protocol.md`, section 6.8).
public enum DocumentStarter {
    /// What the format requires of a document's `id`, and so of the name made for a new one.
    public static let namePattern = "^[a-z][a-z0-9-]{0,63}$"

    /// The longest name, and so `id`, the format allows.
    static let longestName = 64

    /// Whether `name` is one a new document may be given.
    public static func isValid(name: String) -> Bool {
        name.range(of: namePattern, options: .regularExpression) != nil
    }

    /// The name made from a title: lower case, the ASCII letters and digits kept, every other run
    /// of characters turned into one hyphen, hyphens trimmed from the ends, `explainer-` put in
    /// front when the result does not begin with a letter, and cut to 64 characters. A title
    /// with no letter or digit gives `explainer`.
    public static func name(forTitle title: String) -> String {
        var out = ""
        var pendingHyphen = false
        for scalar in title.lowercased().unicodeScalars {
            let kept = (scalar.value >= 0x61 && scalar.value <= 0x7A) || (scalar.value >= 0x30 && scalar.value <= 0x39)
            if kept {
                if pendingHyphen && !out.isEmpty { out += "-" }
                pendingHyphen = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingHyphen = true
            }
        }
        if out.isEmpty { return "explainer" }
        if let first = out.unicodeScalars.first, !(first.value >= 0x61 && first.value <= 0x7A) { out = "explainer-" + out }
        return trimmed(String(out.prefix(longestName)))
    }

    /// `name` with `-2`, `-3` and so on added until `isTaken` is false, cut so that the whole
    /// stays within the longest name.
    static func available(_ name: String, isTaken: (String) -> Bool) -> String {
        if !isTaken(name) { return name }
        var n = 2
        while true {
            let suffix = "-\(n)"
            let candidate = trimmed(String(name.prefix(longestName - suffix.count))) + suffix
            if !isTaken(candidate) { return candidate }
            n += 1
        }
    }

    private static func trimmed(_ name: String) -> String {
        var s = Substring(name)
        while s.last == "-" { s = s.dropLast() }
        return String(s)
    }

    /// The smallest complete document the reader accepts without findings, which starts in the
    /// Square range: one parameterless sample, one text element, one step and its line, and one
    /// layout of 880 by 800 declared for ratios 0.9 to 1.35. Everything in it is a placeholder for
    /// the author to replace.
    static func starter(id: String, title: String) -> DocJSON {
        // The text is fixed, so a failure to parse it is a fault in this file.
        copy(of: try! DocJSON.parse(text), id: id, title: title)
    }

    /// A copy of `source` with its own `id` and `title`.
    static func copy(of source: DocJSON, id: String, title: String) -> DocJSON {
        guard case var .object(o) = source else { return source }
        o["id"] = .string(id)
        o["title"] = .string(title)
        return .object(o)
    }

    private static let text = #"""
    {
      "format": "chalkscript-explainer",
      "version": "1.0",
      "id": "untitled",
      "title": "Untitled",
      "sourceLocale": "en-US",
      "params": {},
      "samples": [{}],
      "areas": [{ "layout": "stage", "ratio": [0.9, 1.35] }],
      "layouts": { "stage": { "size": [880, 800] } },
      "elements": {
        "note": { "kind": "text", "style": "note", "at": [440, 400], "text": "placeholder" }
      },
      "sequence": ["start"],
      "steps": {
        "start": { "say": "start", "actions": { "show": { "do": "appear", "target": "note" } } }
      },
      "wording": {
        "en-US": {
          "shared": { "placeholder": { "text": "Ask Claude to make this explainer.", "visual": true } },
          "everyday": { "start": "This explainer is empty so far." }
        }
      }
    }
    """#
}

#endif
