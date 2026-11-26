import Foundation

// Narration and wording (EXP-10, EXP-19, section 14 of the format's reference): checking a
// document's entries, and filling one for a problem with its shown and spoken forms.

extension DocumentChecker {
    static let pluralCategories = ["zero", "one", "two", "few", "many", "other"]

    func checkWording() {
        guard let wording = root["wording"] else { return }
        guard case let .object(locales) = wording else {
            error(.schema, "/wording", "wording is \(wording.typeName), not an object")
            return
        }
        let source = root["sourceLocale"]?.string ?? ""
        let sourceSections = Set(locales[source]?.object?.keys ?? [])
        for (locale, sections, lp) in map(wording, "/wording", keys: DocumentNames.isLocale, what: "locale (a BCP 47 tag)") {
            guard case let .object(secs) = sections else {
                error(.schema, lp, "locale \(locale) is \(sections.typeName), not an object of sections")
                continue
            }
            if PluralRules.category(1, language: locale) == nil {
                warning(.wording, lp, "this reader has no plural rules for \(locale), so a forms entry there uses 'other'")
            }
            if locale != source && Set(secs.keys) != sourceSections {
                error(.wording, lp, "locale \(locale) does not have the same sections as \(source)")
            }
            for (section, entries, sp) in map(sections, lp) {
                guard case .object = entries else {
                    error(.schema, sp, "section \(section) is \(entries.typeName), not an object of entries")
                    continue
                }
                for (name, e, ep) in map(entries, sp, keys: DocumentNames.isEntryName, what: "entry name") {
                    checkEntry(e, ep, sections: secs, section: section)
                    if section != "shared", secs["shared"]?[name] != nil {
                        error(.wording, ep, "entry \(name) is in both shared and \(section)")
                    }
                }
            }
            if locale != source { checkTranslation(locale, secs, lp, source: source) }
        }
        checkUses(source: source)
    }

    /// One entry's own structure and text, wherever it is used.
    func checkEntry(_ e: JSONValue, _ p: String, sections: JSONObject, section: String) {
        var visual = false
        switch e {
        case .string: break
        case let .object(o):
            object(e, p, known: ["text", "forms", "select", "cases", "spoken", "visual", "emphasis", "pronunciation", "notes", "maxLength", "of"])
            let given = ["text", "forms", "select"].filter { o[$0] != nil }
            if given.count != 1 { error(.schema, p, "an entry has exactly one of text, forms and select") }
            if (o["select"] == nil) != (o["cases"] == nil) { error(.schema, p, "select and cases are given together") }
            if o["spoken"] != nil && o["text"] == nil { error(.schema, p + "/spoken", "spoken is given only with text") }
            _ = string(o, "text", p)
            _ = string(o, "spoken", p)
            bool(o, "visual", p)
            visual = o["visual"] == .bool(true)
            _ = string(o, "notes", p)
            if let f = o["forms"] {
                if let fo = object(f, p + "/forms", known: Self.pluralCategories, required: ["other"]) {
                    for k in fo.keys { _ = string(fo, k, p + "/forms") }
                }
            }
            if let c = o["cases"] {
                if case let .object(co) = c, !co.isEmpty {
                    for k in co.keys { _ = string(co, k, p + "/cases") }
                } else {
                    error(.schema, p + "/cases", "cases is not a non-empty object")
                }
            }
            if let s = o["select"] {
                // Its names are checked where the entry is used.
                if case let .string(src) = s {
                    do { expressions[p + "/select"] = try DocumentExpression(src) } catch { self.error(.expr, p + "/select", at: error.at, error.message) }
                } else {
                    error(.schema, p + "/select", "select is \(s.typeName), not an expression")
                }
            }
            if let m = o["maxLength"] {
                if case let .number(n) = m, n >= 1, n.rounded() == n {} else { error(.schema, p + "/maxLength", "maxLength is not a positive integer") }
            }
            if let of = string(o, "of", p), of.count != 8 || !of.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) {
                error(.schema, p + "/of", "of is not 8 lowercase hexadecimal digits")
            }
            if let pr = o["pronunciation"] {
                if case let .object(po) = pr { for k in po.keys { _ = string(po, k, p + "/pronunciation") } } else {
                    error(.schema, p + "/pronunciation", "pronunciation is not an object")
                }
            }
            if let emph = string(o, "emphasis", p) {
                let names = texts(of: e).flatMap { PlaceholderText($0.text).placeholders.map(\.name) }
                if !names.contains(emph) { error(.wording, p + "/emphasis", "emphasis names {\(emph)}, which the entry does not have") }
            }
        default:
            error(.schema, p, "an entry is \(e.typeName), not a string or an object")
            return
        }
        for (key, text) in texts(of: e) {
            let tp = key.isEmpty ? p : p + "/" + key
            let parsed = PlaceholderText(text)
            for (message, at) in parsed.problems { error(.wording, tp, at: at, message) }
            for piece in parsed.pieces {
                guard case let .literal(s, at) = piece else { continue }
                if let k = Array(s.unicodeScalars).firstIndex(where: { ("0"..."9").contains($0) }) {
                    error(.wording, tp, at: at + k, "a numeral is typed into the text; every number in a line is computed from the problem")
                }
            }
            guard !visual else { continue }
            let chars = Array(text.unicodeScalars)
            for ph in parsed.placeholders where ph.entry == nil && isNumber(ph.name) {
                let before = ph.start > 0 ? chars[ph.start - 1] : nil
                let after = ph.end < chars.count ? chars[ph.end] : nil
                if let b = before, b.properties.isAlphabetic {
                    error(.wording, tp, at: ph.start, "number {\(ph.name)} follows a letter, so its spoken form cannot be derived")
                } else if let a = after, a.properties.isAlphabetic {
                    error(.wording, tp, at: ph.end, "number {\(ph.name)} is followed by letters, so its spoken form cannot be derived")
                }
            }
        }
    }

    /// Whether `name` is known to be a number before anything is evaluated: a number parameter,
    /// or a numeric local.
    func isNumber(_ name: String) -> Bool {
        if let t = params[name]?["type"]?.string { return t == "int" || t == "number" }
        if lets[name] != nil { if case .number = lets[name]! { return true } }
        return ["n", "i", "left"].contains(name)
    }

    func checkTranslation(_ locale: String, _ secs: JSONObject, _ lp: String, source: String) {
        let src = root["wording"]?[source]?.object ?? JSONObject()
        for (section, entries) in secs.entries {
            let have = entries.object ?? JSONObject()
            let want = src[section]?.object ?? JSONObject()
            for name in want.keys where have[name] == nil {
                warning(.wording, DocumentPath.join(lp, section), "\(locale) has no translation of \(name); the \(source) entry is used")
            }
            for (name, e) in have.entries {
                let ep = DocumentPath.join(lp, section, name)
                guard let s = want[name] else {
                    warning(.wording, ep, "\(name) has no entry in \(source) to translate")
                    continue
                }
                guard let of = e["of"]?.string else {
                    warning(.wording, ep, "the translation of \(name) does not say which source entry it translates (of)")
                    continue
                }
                let now = String(Canonical.hash(s).prefix(8))
                if of != now { warning(.wording, ep + "/of", "the source of \(name) has changed since it was translated (of \(of), now \(now))") }
            }
        }
    }

    /// Every entry where it is used: that each wording has it, and that each of its
    /// placeholders can be filled there.
    func checkUses(source: String) {
        guard let loc = root["wording"]?[source]?.object else { return }
        let wordings = loc.keys.filter { $0 != "shared" }
        let hasGuided = steps.values.contains { $0["act"] != nil }
        var docParts: [WordingCoverage.Part] = [.watch]
        if hasGuided { docParts.append(.guided) }
        if root["whatIf"] != nil { docParts.append(.whatIf) }
        if root["try"] != nil { docParts.append(.tryOne) }
        let lp = DocumentPath.join("/wording", source)
        // intro.guided defaults to intro.watch.
        var uses = entryUses
        if root["intro"]?["guided"] == nil, let w = root["intro"]?["watch"]?.string {
            uses.append(EntryUse(name: w, path: "/intro/watch", locals: [], part: .guided))
        }
        for wording in wordings {
            var missing: [WordingCoverage.Part: [String]] = [:]
            for use in uses {
                guard let (entry, ep) = lookup(use.name, loc, wording, lp) else {
                    if use.part == .watch {
                        error(.ref, use.path, "wording \(wording) of \(source) has no entry '\(use.name)'")
                    } else if !(missing[use.part] ?? []).contains(use.name) {
                        missing[use.part, default: []].append(use.name)
                    }
                    continue
                }
                checkFill(entry, ep, use: use, loc: loc, wording: wording, lp: lp)
            }
            let playable = docParts.filter { missing[$0] == nil }
            coverage.append(WordingCoverage(locale: source, wording: wording, playable: playable, missing: missing))
        }
    }

    func lookup(_ name: String, _ loc: JSONObject, _ wording: String, _ lp: String) -> (JSONValue, String)? {
        if let e = loc[wording]?[name] { return (e, DocumentPath.join(lp, wording, name)) }
        if let e = loc["shared"]?[name] { return (e, DocumentPath.join(lp, "shared", name)) }
        return nil
    }

    func checkFill(_ entry: JSONValue, _ ep: String, use: EntryUse, loc: JSONObject, wording: String, lp: String) {
        let runsWithText = Set(use.element.flatMap { elements[$0]?["runs"]?.object?.entries.filter { $0.value["text"] != nil }.map(\.key) } ?? [])
        let isForms = entry["forms"] != nil
        var locals = use.locals
        if isForms { locals.insert("n") }
        let scope = SlotScope(values: .all, locals: locals)
        if entry["select"] != nil, let e = expressions[ep + "/select"] { checkNames(e.root, ep + "/select", scope) }
        for (key, text) in texts(of: entry) {
            let tp = key.isEmpty ? ep : ep + "/" + key
            for ph in PlaceholderText(text).placeholders {
                if let phrase = ph.entry {
                    guard let (pe, pp) = lookup(phrase, loc, wording, lp) else {
                        error(.ref, tp, at: ph.start, "there is no phrase entry '\(phrase)' in \(wording) or shared")
                        continue
                    }
                    if pe["select"] != nil { error(.wording, tp, at: ph.start, "a phrase is a text or forms entry, and \(phrase) is a select") }
                    if texts(of: pe).contains(where: { PlaceholderText($0.text).placeholders.contains { $0.entry != nil } }) {
                        error(.wording, pp, "\(phrase) is used as a phrase, so it must not itself hold a phrase")
                    }
                    if let why = refusal(ph.name, scope) { error(.wording, tp, at: ph.start, "{\(phrase):\(ph.name)} cannot be filled: \(why)") }
                    continue
                }
                if runsWithText.contains(ph.name) { continue }
                if elements[ph.name] != nil && !locals.contains(ph.name) {
                    error(.wording, tp, at: ph.start, "{\(ph.name)} names an element, not a value, so it cannot be filled")
                } else if let why = refusal(ph.name, scope) {
                    error(.wording, tp, at: ph.start, "{\(ph.name)} cannot be filled where \(use.path) uses it: \(why)")
                }
            }
        }
    }
}

/// One line filled for a problem (section 14.3 and 14.4): what is shown, what is said, and the
/// part of the shown line set in the `result` role.
public struct FilledEntry: Equatable, Sendable {
    public var entry: String
    public var shown: String
    /// The spoken form; nil for a `visual` entry.
    public var spoken: String?
    /// The value of the entry's `emphasis` placeholder, as shown.
    public var emphasis: String?
    /// Word to respelling, for the voice.
    public var pronunciation: [String: String]
    /// The locale the entry came from: the one asked for, or the source locale when the
    /// translation lacks it.
    public var locale: String

    /// The line as the players take one (EXP-10).
    public var line: Line { Line(key: entry, display: shown, spoken: spoken, emphasis: emphasis) }
}

/// Fills entries of one locale and wording.
struct EntryFiller {
    let wording: JSONObject
    let locale: String
    let source: String
    let section: String

    struct Failure: Error {
        var path: String
        var at: Int?
        var message: String
        var code: DocumentFinding.Code = .wording
    }

    init(document: ExplainerDocument, locale: String, wording: String) {
        self.wording = document.root["wording"]?.object ?? JSONObject()
        self.locale = locale
        self.source = document.sourceLocale
        self.section = wording
    }

    /// The entry `name`: in the wording being played, then in `shared`, in the locale asked for
    /// and then in the source locale.
    func lookup(_ name: String) -> (entry: JSONValue, path: String, locale: String)? {
        var locales = [locale]
        if locale != source { locales.append(source) }
        for loc in locales {
            for s in [section, "shared"] {
                let found: JSONValue? = wording[loc]?[s]?[name]
                if found != nil { return (found!, DocumentPath.join("/wording", loc, s, name), loc) }
            }
        }
        return nil
    }

    /// Fills entry `name`. `value` gives the value of a name in scope where it is said; `runs`
    /// gives the text of a text element's runs that have one.
    func fill(
        _ name: String, value: (String) throws(ExpressionError) -> DocumentValue?, evaluate: (DocumentExpression) throws(ExpressionError) -> DocumentValue,
        runs: [String: String] = [:], n: DocumentValue? = nil
    ) throws(Failure) -> FilledEntry {
        guard let (entry, path, loc) = lookup(name) else {
            throw Failure(path: DocumentPath.join("/wording", locale, section), message: "there is no entry '\(name)'", code: .ref)
        }
        let o = entry.object ?? JSONObject()
        let visual = o["visual"] == .bool(true)
        func valueOf(_ x: String) throws(ExpressionError) -> DocumentValue? {
            if x == "n", let n { return n }
            return try value(x)
        }
        var text: String
        var textPath = path
        if case let .string(s) = entry {
            text = s
        } else if let s = o["text"]?.string {
            text = s
            textPath = path + "/text"
        } else if let forms = o["forms"]?.object {
            let nv: DocumentValue?
            do { nv = try valueOf("n") } catch { throw Failure(path: path, message: error.message, code: .eval) }
            guard let k = nv?.integer else { throw Failure(path: path, message: "a forms entry is filled with an integer n, not \(nv.map(\.description) ?? "nothing")", code: .eval) }
            let category = PluralRules.category(k, language: loc) ?? "other"
            let key = forms[category] != nil ? category : "other"
            text = forms[key]?.string ?? ""
            textPath = path + "/forms/" + key
        } else if let sel = o["select"]?.string, let cases = o["cases"]?.object {
            let v: DocumentValue
            do { v = try evaluate(try DocumentExpression(sel)) } catch { throw Failure(path: path + "/select", at: error.at, message: error.message, code: .eval) }
            let key: String
            switch v {
            case let .truth(b): key = b ? "true" : "false"
            case let .string(s): key = s
            default:
                guard let k = v.integer else { throw Failure(path: path + "/select", message: "select gives \(v), which no case can match", code: .eval) }
                key = String(k)
            }
            guard let t = cases[key]?.string ?? cases["*"]?.string else {
                throw Failure(path: path + "/cases", message: "select gives \(v), and there is no case \(key) or *", code: .eval)
            }
            text = t
            textPath = path + "/cases/" + DocumentPath.escape(cases[key] != nil ? key : "*")
        } else {
            throw Failure(path: path, message: "entry \(name) has no text")
        }
        let spokenText = o["spoken"]?.string ?? text
        let shown = try render(text, textPath, spoken: false, visual: visual, valueOf: valueOf, evaluate: evaluate, runs: runs)
        let spoken = visual ? nil : try render(spokenText, o["spoken"] != nil ? path + "/spoken" : textPath, spoken: true, visual: false, valueOf: valueOf, evaluate: evaluate, runs: runs)
        var emphasis: String?
        if let e = o["emphasis"]?.string {
            let v: DocumentValue?
            do { v = try valueOf(e) } catch { throw Failure(path: path + "/emphasis", message: error.message, code: .eval) }
            emphasis = runs[e] ?? v.flatMap(Self.shown)
        }
        var pron: [String: String] = [:]
        for (k, v) in o["pronunciation"]?.object?.entries ?? [] { pron[k] = v.string }
        return FilledEntry(entry: name, shown: shown, spoken: spoken, emphasis: emphasis, pronunciation: pron, locale: loc)
    }

    static func shown(_ v: DocumentValue) -> String? {
        if case let .string(s) = v { return s }
        return v.integer.map { String($0) }
    }

    func render(
        _ text: String, _ path: String, spoken: Bool, visual: Bool, valueOf: (String) throws(ExpressionError) -> DocumentValue?,
        evaluate: (DocumentExpression) throws(ExpressionError) -> DocumentValue, runs: [String: String]
    ) throws(Failure) -> String {
        var out = ""
        let parsed = PlaceholderText(text)
        if let (message, at) = parsed.problems.first { throw Failure(path: path, at: at, message: message) }
        let chars = Array(text.unicodeScalars)
        for piece in parsed.pieces {
            switch piece {
            case let .literal(s, _):
                out += s
            case let .placeholder(ph):
                if let phrase = ph.entry {
                    let nv: DocumentValue?
                    do { nv = try valueOf(ph.name) } catch { throw Failure(path: path, at: ph.start, message: error.message, code: .eval) }
                    guard let nv else { throw Failure(path: path, at: ph.start, message: "{\(phrase):\(ph.name)}: '\(ph.name)' is not in scope") }
                    let filled = try fill(phrase, value: valueOf, evaluate: evaluate, n: nv)
                    out += spoken ? (filled.spoken ?? filled.shown) : filled.shown
                    continue
                }
                if let r = runs[ph.name] {
                    out += r
                    continue
                }
                let v: DocumentValue?
                do { v = try valueOf(ph.name) } catch { throw Failure(path: path, at: ph.start, message: error.message, code: .eval) }
                guard let v else { throw Failure(path: path, at: ph.start, message: "{\(ph.name)} is not in scope here") }
                switch v {
                case let .string(s):
                    if !visual && s.unicodeScalars.contains(where: { ("0"..."9").contains($0) }) {
                        throw Failure(path: path, at: ph.start, message: "{\(ph.name)} inserts '\(s)', which has a digit, so its spoken form cannot be derived")
                    }
                    out += s
                case .number:
                    guard let k = v.integer else {
                        throw Failure(path: path, at: ph.start, message: "{\(ph.name)} is \(v), which is not an integer and cannot be shown", code: .eval)
                    }
                    if !visual {
                        let before = ph.start > 0 ? chars[ph.start - 1] : nil
                        let after = ph.end < chars.count ? chars[ph.end] : nil
                        if before?.properties.isAlphabetic == true || after?.properties.isAlphabetic == true {
                            throw Failure(path: path, at: ph.start, message: "number {\(ph.name)} is next to a letter, so its spoken form cannot be derived")
                        }
                    }
                    out += spoken ? SpellOut.words(k, locale: locale) : String(k)
                default:
                    throw Failure(path: path, at: ph.start, message: "{\(ph.name)} is \(v.typeName), which cannot fill a line", code: .eval)
                }
            }
        }
        return out
    }
}

/// Numbers in words by the locale's spell-out rules: Foundation's `.spellOut` style, which
/// follows CLDR's rule-based number format (28 is "twenty-eight" in English).
enum SpellOut {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: NumberFormatter] = [:]

    static func words(_ n: Int, locale: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let f: NumberFormatter
        if let cached = formatters[locale] {
            f = cached
        } else {
            f = NumberFormatter()
            f.locale = Locale(identifier: locale)
            f.numberStyle = .spellOut
            formatters[locale] = f
        }
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
}

/// CLDR's cardinal plural categories for integers (Unicode Technical Standard #35), for the
/// languages this reader knows.
public enum PluralRules {
    /// The category of integer `n` in `language` (a BCP 47 tag), or nil when the reader has no
    /// rules for it.
    public static func category(_ n: Int, language: String) -> String? {
        let lang = language.split(separator: "-").first.map { $0.lowercased() } ?? ""
        let i = abs(n)
        let m10 = i % 10
        let m100 = i % 100
        let million = i != 0 && i % 1_000_000 == 0
        switch lang {
        case "en", "de", "nl", "sv", "da", "nb", "nn", "no", "fi", "et", "el", "hu", "tr", "bg", "sw", "ur", "af", "eu", "gl":
            return i == 1 ? "one" : "other"
        case "es":
            return i == 1 ? "one" : million ? "many" : "other"
        case "it", "ca":
            return i == 1 ? "one" : million ? "many" : "other"
        case "fr":
            return i == 0 || i == 1 ? "one" : million ? "many" : "other"
        case "pt":
            return i == 0 || i == 1 ? "one" : million ? "many" : "other"
        case "ru", "uk", "be":
            if m10 == 1 && m100 != 11 { return "one" }
            if (2...4).contains(m10) && !(12...14).contains(m100) { return "few" }
            return "many"
        case "pl":
            if i == 1 { return "one" }
            if (2...4).contains(m10) && !(12...14).contains(m100) { return "few" }
            return "many"
        case "cs", "sk":
            return i == 1 ? "one" : (2...4).contains(i) ? "few" : "other"
        case "ar":
            if i == 0 { return "zero" }
            if i == 1 { return "one" }
            if i == 2 { return "two" }
            if (3...10).contains(m100) { return "few" }
            if (11...99).contains(m100) { return "many" }
            return "other"
        case "he":
            return i == 1 ? "one" : i == 2 ? "two" : "other"
        case "hi", "bn", "fa", "gu", "kn", "mr", "zu", "am":
            return i == 0 || i == 1 ? "one" : "other"
        case "ja", "zh", "ko", "th", "vi", "id", "ms", "lo", "my", "km":
            return "other"
        default:
            return nil
        }
    }
}
