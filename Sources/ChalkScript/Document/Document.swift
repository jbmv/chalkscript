import Foundation

/// An explainer document that has been read (EXP-19): its JSON, and every expression in it parsed
/// and kept by its JSON Pointer. Reading it (`ExplainerDocument.read`) also reports its findings;
/// a document with an error is kept for inspection but is not resolved or played.
public struct ExplainerDocument: Sendable {
    public static let format = "chalkscript-explainer"
    /// The version of the format this reader implements.
    public static let readerVersion = (major: 1, minor: 0)
    /// The capabilities this reader implements (section 2.3).
    public static let capabilities: Set<String> = ["components.arithmetic", "drawing.turn"]

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
    /// wording, and `notes`, `maxLength` and `of` removed from every entry left, an entry left
    /// with only `text` being written as that text. A change to another language or wording, to
    /// a translator's note, or to formatting leaves it unchanged.
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
                        // An entry left with only its text is that text, as a string entry is.
                        if e.keys == ["text"], let t = e["text"] { kept[key] = t } else { kept[key] = .object(e) }
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

    /// The profile the document is made for: the one it declares, or `open`.
    public var profileID: String { root["profile"]?.string ?? ExplainerStyle.defaultProfile }

    /// The appearances the document is made for (EXP-20): those it declares, or both.
    public var appearances: Set<Appearance> {
        guard case let .array(names)? = root["appearances"] else { return Appearance.both }
        let declared = Set(names.compactMap { $0.string.flatMap(Appearance.init(rawValue:)) })
        return declared.isEmpty ? Appearance.both : declared
    }

    /// The document's own colours by name (EXP-20): those with values, and those that name a
    /// suggested colour of the document's profile.
    public var colours: [String: DocumentColour] {
        let profile = ExplainerStyle.profiles[profileID]
        var out: [String: DocumentColour] = [:]
        for (name, c) in root["colours"]?.object?.entries ?? [] {
            let l = c["light"]?.string.flatMap(RGB.init(hexString:)), d = c["dark"]?.string.flatMap(RGB.init(hexString:))
            if l != nil || d != nil {
                out[name] = DocumentColour(name: name, light: l, dark: d)
            } else if let s = c["suggested"]?.string, let l = profile?.light.suggested[s], let d = profile?.dark.suggested[s] {
                out[name] = DocumentColour(name: name, light: l, dark: d)
            }
        }
        return out
    }

    /// The operations whose colour the document changes (EXP-6), by operation: those under
    /// `style.overrides` that give a value, in a document whose profile fixes the operation and
    /// lets a document change it. None in any other profile.
    public var overrides: [ExplainerOperation: OperationOverride] {
        guard let profile = ExplainerStyle.profiles[profileID]?.profile, profile.overrides == .explained else { return [:] }
        var out: [ExplainerOperation: OperationOverride] = [:]
        for (name, o) in root["style"]?["overrides"]?.object?.entries ?? [] {
            guard profile.fixed[name] != nil, let op = ExplainerOperation(rawValue: name) else { continue }
            let l = o["light"]?.string.flatMap(RGB.init(hexString:)), d = o["dark"]?.string.flatMap(RGB.init(hexString:))
            guard l != nil || d != nil else { continue }
            out[op] = OperationOverride(
                operation: op, colour: DocumentColour(name: name, light: l, dark: d), asked: o["asked"]?.string ?? "",
                meaning: profile.fixed[name] ?? name)
        }
        return out
    }

    /// The colour each overridden operation is drawn in, which a film gives its scenes.
    var overridingColours: [ExplainerOperation: DocumentColour] { overrides.mapValues(\.colour) }

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

/// One operation's colour as a document of the maths profile changes it (EXP-6): the colour, with
/// a value for each appearance the document is made for, and the request of the person who asked
/// for the change.
public struct OperationOverride: Hashable, Sendable {
    public let operation: ExplainerOperation
    /// The colour drawn for the operation: one value for fill and ink, with the soft form derived.
    public let colour: DocumentColour
    /// The person's request, in the person's words where possible.
    public let asked: String
    /// What the operation's colour means in the profile, such as "taking away".
    public let meaning: String

    /// Why an operation's colour is normally the same in every explainer, in a sentence a
    /// person who is not a programmer can read.
    public static let reason =
        "Operation colours are the same in every maths explainer so that a learner can rely on them, and they are chosen from research on colour vision and checked so that colour-blind viewers can tell them apart."
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
