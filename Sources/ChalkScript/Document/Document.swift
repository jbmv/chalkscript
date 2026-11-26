import Foundation

/// An explainer document that has been read (EXP-19): its JSON, and every expression in it parsed
/// and kept by its JSON Pointer. Reading it (`ExplainerDocument.read`) also reports its findings;
/// a document with an error is kept for inspection but is not resolved or played.
public struct ExplainerDocument: Sendable {
    public static let format = "chalkscript-explainer"
    /// The version of the format this reader implements.
    public static let readerVersion = (major: 1, minor: 0)
    /// The capabilities this reader implements (section 2.3).
    public static let capabilities: Set<String> = ["components.arithmetic"]

    public let json: JSONValue
    /// The document's findings when it was read.
    public let findings: [DocumentFinding]
    /// For each locale and wording, which parts of the explainer it can play.
    public let coverage: [WordingCoverage]
    let expressions: [String: DocumentExpression]
    let root: JSONObject

    init(json: JSONValue, findings: [DocumentFinding], coverage: [WordingCoverage], expressions: [String: DocumentExpression]) {
        self.json = json
        self.root = json.object ?? JSONObject()
        self.findings = findings
        self.coverage = coverage
        self.expressions = expressions
    }

    /// Whether the document conforms: a reader found no error in it (section 22).
    public var conforms: Bool { !findings.hasErrors }

    /// The expression at JSON Pointer `path`, as parsed when the document was read.
    public func expression(at path: String) -> DocumentExpression? { expressions[path] }

    // MARK: identity (section 19)

    /// The hash of the whole document: SHA-256 of its canonical form, in lowercase hexadecimal.
    public var hash: String { Canonical.hash(json) }

    /// The first 12 digits of the hash, which a patch names as its `base`.
    public var shortHash: String { Canonical.shortHash(json) }

    /// The revision of the document for one wording and locale: the short hash of the document
    /// with `about` removed, `wording` reduced to that locale's `shared` section and that
    /// wording, and `notes`, `maxLength` and `of` removed from every entry left. A change to
    /// another language or wording, or to formatting, leaves it unchanged.
    public func revision(wording: String, locale: String) -> String {
        Canonical.shortHash(.object(revisionForm(wording: wording, locale: locale)))
    }

    func revisionForm(wording name: String, locale: String) -> JSONObject {
        var doc = root
        doc["about"] = nil
        var sections = JSONObject()
        if let loc = root["wording"]?[locale]?.object {
            for section in ["shared", name] {
                guard let entries = loc[section]?.object else { continue }
                var kept = JSONObject()
                for (key, entry) in entries.entries {
                    if case var .object(e) = entry {
                        e["notes"] = nil
                        e["maxLength"] = nil
                        e["of"] = nil
                        kept[key] = .object(e)
                    } else {
                        kept[key] = entry
                    }
                }
                sections[section] = .object(kept)
            }
        }
        doc["wording"] = .object(JSONObject([(locale, .object(sections))]))
        return doc
    }

    /// The first 8 digits of the hash of the source locale's entry `name` in `section`, which
    /// a translation of it records as `of` (section 14.7).
    public func sourceHash(section: String, entry name: String) -> String? {
        guard let e = root["wording"]?[sourceLocale]?[section]?[name] else { return nil }
        return String(Canonical.hash(e).prefix(8))
    }

    // MARK: what the document declares

    public var id: String { root["id"]?.string ?? "" }
    public var title: String { root["title"]?.string ?? "" }
    public var sourceLocale: String { root["sourceLocale"]?.string ?? "" }
    public var requires: [String] { root["requires"]?.array?.compactMap(\.string) ?? [] }
    public var sequence: [String] { root["sequence"]?.array?.compactMap(\.string) ?? [] }
    /// The locales `wording` holds, the source locale first.
    public var locales: [String] {
        let all = root["wording"]?.object?.keys ?? []
        return all.filter { $0 == sourceLocale } + all.filter { $0 != sourceLocale }
    }
    /// The wordings of the source locale, in the order the document gives them.
    public var wordings: [String] {
        (root["wording"]?[sourceLocale]?.object?.keys ?? []).filter { $0 != "shared" }
    }
    /// The parameters, by name, in the order the document gives them.
    public var parameterNames: [String] { root["params"]?.object?.keys ?? [] }
    /// The wording the document suggests for a control (section 17), if it suggests one.
    public func suggestedWording(for control: DocumentPlayback.Control) -> String? {
        root["plays"]?[control.rawValue]?.string
    }

    /// The problems a reviewer is shown (section 5.4).
    public var samples: [[String: DocumentValue]] {
        (root["samples"]?.array ?? []).compactMap { s in
            s.object.map { o in Dictionary(uniqueKeysWithValues: o.entries.compactMap { k, v in DocumentValue(json: v).map { (k, $0) } }) }
        }
    }
}

/// Which parts of an explainer one wording of one locale can play (section 14.5): every entry
/// the watched part needs must be there, but an entry needed only by do it with me, What if?
/// or try one may be absent, and then that part is not played with this wording.
public struct WordingCoverage: Equatable, Sendable {
    public enum Part: String, Sendable, CaseIterable { case watch, guided, whatIf, tryOne }

    public var locale: String
    public var wording: String
    /// The parts the document has that this wording can play.
    public var playable: [Part]
    /// The entries missing for each part it cannot play.
    public var missing: [Part: [String]]
}

/// The options whoever plays a document chooses (section 17).
public struct DocumentPlayback: Equatable, Hashable, Sendable {
    public enum Control: String, Sendable, CaseIterable {
        /// No step starts until the viewer asks, and none is cut short.
        case paced
        /// The viewer may finish a step at once and jump to any step; only the watched part is
        /// played.
        case skippable
    }

    public enum Counts: String, Sendable {
        case spoken, shown
    }

    public var control: Control
    public var counts: Counts
    /// Multiplies every time in a step marked `counts`; positive, by default 1.
    public var countPace: Double

    public init(control: Control = .paced, counts: Counts = .spoken, countPace: Double = 1) {
        self.control = control
        self.counts = counts
        self.countPace = countPace
    }
}
