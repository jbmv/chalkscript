#if os(macOS)
import ChalkScript
import ChalkScriptMCP
import CoreGraphics
import Foundation
import Observation

/// The state of ChalkScript Studio: the open project folder and its documents, the document
/// shown and the problem, wording and playback it is shown with, and the player that plays it.
/// The app draws it, and the helper protocol reads and edits it (`respond(to:params:client:)`).
///
/// Every document is saved as soon as it changes, so the files are what an agent reads.
@MainActor
@Observable
public final class StudioModel {
    public static let app = Implementation(name: "ChalkScript Studio", version: "0.1.0")

    /// The project folder, or nil when none is open.
    public private(set) var folder: URL?
    public private(set) var documents: [StudioDocument] = []
    public private(set) var selectedName: String?
    /// The wording and locale chosen; nil, or one the shown document lacks, takes the document's
    /// suggestion and its source locale.
    public private(set) var wording: String?
    public private(set) var locale: String?
    public private(set) var control: DocumentPlayback.Control = .paced
    /// What the shown document is previewed at: nothing, so that it is played in the pane's own
    /// area, or a ratio. A preview changes nothing in the document.
    public private(set) var preview: PreviewChoice = .none
    /// What a document is previewed at when it is first shown. The studio's window sets it to
    /// the Square preset, so that the bounds of the drawing are always seen.
    public var defaultPreview: PreviewChoice = .none
    /// The player of the shown document, or nil when it cannot be played (`refusal` says why).
    public private(set) var player: ExplainerPlayer?
    /// Changes whenever `player` is replaced, so that a view can start again with the new one.
    public private(set) var playerSerial = 0
    /// Why the shown document cannot be played for its problem.
    public private(set) var refusal: [DocumentFinding] = []
    /// The last call the helper made, in a few words, for the window's status line.
    public private(set) var activity: String?
    /// The socket the studio answers the helper on, or why it could not listen.
    public private(set) var listening: String?
    public private(set) var listenFailure: String?
    public let guide: AuthoringGuide
    /// Each accepted patch is registered here as one step.
    public var undoManager: UndoManager?

    @ObservationIgnored private var problems: [String: [String: DocumentValue]] = [:]
    /// What Undo's steps know each document by, under the document's present name. A document
    /// has one from its first step.
    @ObservationIgnored private var identities: [String: DocumentIdentity] = [:]
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var listener: StudioListener?
    @ObservationIgnored private let drivesPlayer: Bool

    /// - Parameter drivesPlayer: false makes a player whose clock moves only when it is advanced,
    ///   for tests.
    public init(guide: AuthoringGuide, drivesPlayer: Bool = true) {
        self.guide = guide
        self.drivesPlayer = drivesPlayer
    }

    /// Whether the window speaks each line as its step plays. Off, it plays with the stand-in.
    public private(set) var speaksLines = false
    /// Makes the voice that speaks, for the locale the document is played in. The app gives it;
    /// without one the window plays with the stand-in whatever `speaksLines` says.
    @ObservationIgnored public var speakingVoice: (@MainActor (_ locale: String) -> any ExplainerVoice)?

    /// Turns spoken lines on or off and plays the step shown again, so that the change is heard
    /// at once. It changes the window's voice only: nothing the helper protocol answers reads it.
    public func setSpeaksLines(_ on: Bool) {
        guard on != speaksLines else { return }
        speaksLines = on
        rebuild(keepStep: true)
    }

    /// The voice the window plays with. The stand-in says nothing and takes the time a line
    /// would take to say, so that `wait: "voice"` holds and a step lasts as it would spoken.
    func makeVoice(locale: String) -> any ExplainerVoice {
        if speaksLines, let speakingVoice { return speakingVoice(locale) }
        return EstimatedVoice()
    }

    // MARK: the project

    /// Opens a project folder and watches it for changes made by other programs.
    public func open(folder url: URL, watch: Bool = true) {
        watcher?.stop()
        watcher = nil
        forgetAllSteps()
        folder = url
        documents = []
        selectedName = nil
        reload()
        if watch {
            watcher = FolderWatcher(folder: url.resolvingSymlinksInPath()) { [weak self] in self?.reload() }
        }
    }

    public func close() {
        watcher?.stop()
        watcher = nil
        forgetAllSteps()
        player?.stop()
        folder = nil
        documents = []
        selectedName = nil
        rebuild(keepStep: false)
    }

    /// Reads the folder again: documents added, removed or changed on disk.
    public func reload() {
        guard let folder else { return }
        var next: [StudioDocument] = []
        var shownChanged = false
        for (name, url) in ProjectFolder.scan(folder) {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let old = documents.first(where: { $0.name == name }), old.data == data, old.url == url {
                next.append(old)
                continue
            }
            next.append(StudioDocument(name: name, url: url, data: data))
            if name == selectedName { shownChanged = true }
        }
        documents = next
        if selectedName == nil || !next.contains(where: { $0.name == selectedName }) {
            selectedName = next.first?.name
            shownChanged = true
        }
        if shownChanged { rebuild(keepStep: true) }
    }

    public func document(named name: String) -> StudioDocument? { documents.first { $0.name == name } }

    public var selected: StudioDocument? { selectedName.flatMap(document(named:)) }

    // MARK: what is shown

    public func select(_ name: String?) {
        guard name != selectedName else { return }
        selectedName = name
        preview = defaultPreview
        rebuild(keepStep: false)
    }

    public func setWording(_ name: String?) {
        wording = name
        rebuild(keepStep: true)
    }

    public func setLocale(_ tag: String?) {
        locale = tag
        rebuild(keepStep: true)
    }

    public func setControl(_ value: DocumentPlayback.Control) {
        control = value
        rebuild(keepStep: true)
    }

    /// Previews the shown document at `choice`; a ratio that is not a positive number is ignored.
    public func setPreview(_ choice: PreviewChoice) {
        if case let .ratio(r) = choice, !(r > 0 && r.isFinite) { return }
        preview = choice
        rebuild(keepStep: true)
    }

    /// The problem the shown document is played with: the one chosen if it is still within the
    /// parameters, otherwise its first sample.
    public func problem(for name: String) -> [String: DocumentValue] {
        guard let doc = document(named: name)?.document else { return [:] }
        if let p = problems[name], doc.check(problem: p).isEmpty { return p }
        return doc.samples.first ?? [:]
    }

    /// Plays the document with `values`, if they are within its parameters; otherwise returns
    /// why not and changes nothing.
    @discardableResult
    public func setProblem(_ values: [String: DocumentValue], for name: String) -> [DocumentFinding] {
        guard let doc = document(named: name)?.document else { return [] }
        let outside = doc.check(problem: values)
        guard outside.isEmpty else { return outside }
        problems[name] = values
        if name == selectedName { rebuild(keepStep: true) }
        return []
    }

    /// The shown document's explainer as the player has it, at the shape it is shown at.
    var shaped: ShapedExplainer? { player?.explainer as? ShapedExplainer }

    /// The wording the shown document is played in.
    public var playedWording: String? { shaped?.shown.resolved.wording }

    /// The names of the steps the shown document has for its problem.
    public var stepNames: [String] { shaped?.shown.resolved.stepNames ?? [] }

    // MARK: previews and layouts

    /// The shapes the shown document is made for, each as a preview (EXP-17).
    public var previewItems: [PreviewItem] {
        guard let doc = selected?.document else { return [] }
        return Shapes.previews(doc)
    }

    /// The ratio of the area the shown document is laid out for, once the window has given it one.
    public var shownRatio: Double? { shaped?.shown.areaUse.flatMap { Shapes.ratio($0.used) } }

    /// The layout the shown document is drawn in.
    public var shownLayout: String? { shaped?.shown.resolved.layout }

    /// What the status line says of the drawing area: the layout in use, the area shown, and,
    /// when that area is not one the document is made for, so, with the ratio it is drawn at
    /// instead. Nil when nothing is played.
    public var areaStatus: String? {
        guard let s = shaped else { return nil }
        let layout = "Layout \(s.shown.resolved.layout)"
        guard let use = s.shown.areaUse, let given = Shapes.ratio(use.given), let used = Shapes.ratio(use.used) else { return layout }
        if !Shapes.fills(use) {
            let shape = (s.ratio == nil ? "pane " : "") + Shapes.text(given)
            return "\(layout) · \(shape) is not a shape the document is made for; drawn at \(Shapes.text(used))"
        }
        guard let r = s.ratio else { return "\(layout) · pane \(Shapes.text(given))" }
        let title = Preset.allCases.first { abs($0.nominal - r) < 1e-9 }?.title ?? previewItems.first { abs($0.ratio - r) < 1e-9 }?.title
        return "\(layout) · previewing " + (title.map { "\($0) at \(Shapes.text(r))" } ?? Shapes.text(r))
    }

    /// The presets the shown document is made for (EXP-17).
    public var madeFor: Set<Preset> { selected?.document.map(Shapes.madeFor) ?? [] }

    /// Makes the shown document made for `preset`, or no longer so, as one patch of `areas`
    /// through the patch engine, so that it is checked, saved and one step of Undo. Returns why
    /// the patch was refused, or nothing.
    @discardableResult
    public func setMadeFor(_ preset: Preset, _ on: Bool) -> [DocumentFinding] {
        guard let shown = selected, let doc = shown.document else { return [] }
        var presets = Shapes.madeFor(doc)
        if on { presets.insert(preset) } else { presets.remove(preset) }
        guard let ops = Shapes.ops(doc, madeFor: presets) else { return [] }
        return apply(ops, to: shown.name, base: doc.shortHash, actionName: on ? "Made for \(preset.title)" : "Not made for \(preset.title)")
    }

    // MARK: appearances

    /// The appearance the window previews the player in (EXP-17), which the window sets. It is the
    /// window's, not the document's, and is the appearance of a picture an agent asks for without
    /// naming one.
    public var previewAppearance: Appearance = .light

    /// The appearances the shown document is made for (EXP-20): both for one that declares none.
    public var madeForAppearances: Set<Appearance> { selected?.document?.appearances ?? Appearance.both }

    /// What the last tick of an appearance added to a document, and the document as it then was.
    private var added: (name: String, hash: String, text: String)?

    /// What the status line says after a tick wrote values for colours that had none, until the
    /// document changes again or another is shown.
    public var notice: String? {
        guard let added, let shown = selected, shown.name == added.name, shown.hash == added.hash else { return nil }
        return added.text
    }

    /// What the status line says when the preview is of an appearance the shown document is not
    /// made for: that it is drawn, as a player draws it, in the one it is made for. Nil otherwise.
    public var appearanceStatus: String? {
        guard player != nil, let doc = selected?.document else { return nil }
        let use = Appearance.use(asked: previewAppearance, madeFor: doc.appearances)
        guard use.differs else { return nil }
        let (asked, used) = (use.asked.title, use.used.title.lowercased())
        return "Previewing \(asked); the explainer is made for \(used) only, so it is drawn \(used)."
    }

    /// Makes the shown document made for `appearance`, or no longer so, as one patch through the
    /// patch engine, so that it is checked, saved and one step of Undo. Making it so writes, in
    /// the same patch, a value for each colour of the document's own that has none in that
    /// appearance, which `notice` then names. The last appearance a document is made for stays.
    /// Returns why the patch was refused, or nothing.
    @discardableResult
    public func setMadeFor(_ appearance: Appearance, _ on: Bool) -> [DocumentFinding] {
        guard let shown = selected, let doc = shown.document else { return [] }
        var appearances = doc.appearances
        if on { appearances.insert(appearance) } else { appearances.remove(appearance) }
        guard let change = AppearanceTicks.change(doc, madeFor: appearances) else { return [] }
        let result = doc.patch(base: doc.shortHash, ops: change.ops)
        guard result.applied else { return result.findings }
        do {
            try replace(shown.name, with: AppearanceTicks.placed(result.document.json),
                        actionName: on ? "Made for \(appearance.title)" : "Not made for \(appearance.title)")
        } catch {
            return [.error(.patch, "", error.message)]
        }
        if !change.added.isEmpty, let hash = selected?.hash {
            var text = change.added.map { "\($0.appearance.rawValue) values for \(AppearanceTicks.list($0.colours))" }.joined(separator: " and ")
            text = "Added " + text
            if let first = change.added.first, change.added.count == 1, first.appearance != previewAppearance {
                text += "; preview \(first.appearance.title) to see them"
            }
            added = (shown.name, hash, text + ".")
        }
        return []
    }

    // MARK: an operation's colour changed

    /// What the window says of one operation whose colour the shown document changes (EXP-6).
    public struct OverrideNotice: Equatable, Identifiable, Sendable {
        public let operation: ExplainerOperation
        /// What the operation's colour means, such as "taking away".
        public let meaning: String
        /// That the document changes the colour, naming the operation by what it means.
        public let title: String
        /// Why an operation's colour is normally fixed.
        public let reason: String
        /// The request the document records, or nil when it records none.
        public let asked: String?
        public var id: String { operation.rawValue }
    }

    /// The label of the control that removes an override, and the name of its step of Undo.
    public static let standardColourTitle = "Use the Standard Colour"

    /// A notice for each operation whose colour the shown document changes, in the operations'
    /// order. The notices inform: nothing waits on them.
    public var overrideNotices: [OverrideNotice] {
        guard let overrides = selected?.document?.overrides, !overrides.isEmpty else { return [] }
        return ExplainerOperation.allCases.compactMap { op in
            overrides[op].map {
                let asked = $0.asked.trimmingCharacters(in: .whitespacesAndNewlines)
                return OverrideNotice(
                    operation: op, meaning: $0.meaning, title: "This explainer changes the colour for \($0.meaning).",
                    reason: OperationOverride.reason, asked: asked.isEmpty ? nil : asked)
            }
        }
    }

    /// Removes the shown document's override of `operation`, so that it is drawn in the standard
    /// colour again, as one patch through the patch engine: checked, saved and one step of Undo.
    /// An `overrides` left empty is removed with it, and a `style` left empty after that. Returns
    /// why the patch was refused, or nothing.
    @discardableResult
    public func useStandardColour(for operation: ExplainerOperation) -> [DocumentFinding] {
        guard let shown = selected, let doc = shown.document,
            let style = doc.json["style"]?.object, let overrides = style["overrides"]?.object, overrides[operation.rawValue] != nil
        else { return [] }
        let path = overrides.keys.count > 1 ? "/style/overrides/\(operation.rawValue)" : style.keys.count > 1 ? "/style/overrides" : "/style"
        let op = DocJSON.object(DocObject([("op", .string("remove")), ("path", .string(path))]))
        return apply([op], to: shown.name, base: doc.shortHash, actionName: Self.standardColourTitle)
    }

    private func apply(_ ops: [DocJSON], to name: String, base: String, actionName: String) -> [DocumentFinding] {
        do {
            let result = try patch(name, base: base, ops: ops, actionName: actionName)
            return result.applied ? [] : result.findings
        } catch {
            return [.error(.patch, "", error.message)]
        }
    }

    var effectiveWording: String? {
        guard let w = wording, let doc = selected?.document, doc.wordings.contains(w) else { return nil }
        return w
    }

    var effectiveLocale: String? {
        guard let l = locale, let doc = selected?.document, doc.locales.contains(l) else { return nil }
        return l
    }

    /// Makes the player again for the shown document, laid out for the same drawing area. With
    /// `keepStep`, the step the old player was on is played again if the problem still has it,
    /// so that an edit is seen at once.
    func rebuild(keepStep: Bool) {
        let old = player
        let area = old?.drawingArea
        var stepName: String?
        if keepStep, let old, let k = old.currentStep, let e = (old.explainer as? ShapedExplainer)?.shown, e.resolved.steps.indices.contains(k) {
            stepName = e.resolved.steps[k].name
        }
        old?.stop()
        player = nil
        refusal = []
        defer { playerSerial += 1 }
        guard let shown = selected else { return }
        guard let doc = shown.document else {
            refusal = shown.findings.errors
            return
        }
        do {
            let e = try DocumentExplainer(
                document: doc, problem: problem(for: shown.name), wording: effectiveWording, locale: effectiveLocale,
                playback: DocumentPlayback(control: control))
            var ratio: Double?
            if case let .ratio(r) = preview { ratio = r }
            let p = ExplainerPlayer(explainer: ShapedExplainer(e, ratio: ratio), voice: makeVoice(locale: e.resolved.locale), drivesItself: drivesPlayer)
            if let area { p.layOut(for: area) }
            if let stepName, let k = e.resolved.stepNames.firstIndex(of: stepName) { p.show(step: k) }
            player = p
        } catch {
            refusal = error.findings
        }
    }

    // MARK: edits

    /// Applies a patch to a document and saves it (section 6.4 of the helper protocol). An
    /// accepted patch is shown at once and is one step of `undoManager`.
    func patch(_ name: String, base: String, ops: [DocJSON], actionName: String = "Edit by Agent") throws(MethodError) -> PatchResult {
        let shown = try existing(name)
        guard let doc = shown.document else { throw MethodError.unreadable(shown) }
        let result = doc.patch(base: base, ops: ops)
        guard result.applied else { return result }
        try replace(name, with: result.document.json, actionName: actionName)
        return result
    }

    /// Writes `json` as the document's file and reads it again, registering the change with the
    /// undo manager under `actionName`.
    func replace(_ name: String, with json: DocJSON, actionName: String) throws(MethodError) {
        let shown = try existing(name)
        let before = shown.document?.json
        let data = Data(DocumentText.format(json).utf8)
        do {
            try data.write(to: shown.url, options: .atomic)
        } catch {
            throw MethodError(code: Studio.ErrorCode.failed, "The studio could not save \(name): \(error.localizedDescription)")
        }
        if let i = documents.firstIndex(where: { $0.name == name }) {
            documents[i] = StudioDocument(name: name, url: shown.url, data: data)
        }
        if let before, let undoManager {
            let identity = identities[name] ?? DocumentIdentity()
            identities[name] = identity
            let renames = identity.renames
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: identity) { [weak self] identity in
                MainActor.assumeIsolated { self?.restore(identity, to: before, renames: renames, actionName: actionName) }
            }
            undoManager.setActionName(actionName)
            undoManager.endUndoGrouping()
        }
        if selectedName == name {
            rebuild(keepStep: true)
        } else {
            select(name)
        }
    }

    /// Does one of Undo's steps: writes `json`, a document's earlier content, to the document the
    /// step was made on, under whatever name it has now. If the document has been renamed since
    /// (`renames` is its count when the step was made), it keeps its present `id` and `title`.
    /// A step whose document is gone does nothing.
    private func restore(_ identity: DocumentIdentity, to json: DocJSON, renames: Int, actionName: String) {
        guard let name = identities.first(where: { $0.value === identity })?.key, let present = document(named: name) else { return }
        var json = json
        if identity.renames != renames {
            let now = present.document?.json
            let leaf = String(name.split(separator: "/").last ?? Substring(name))
            json = DocumentStarter.copy(
                of: json, id: now?["id"]?.string ?? leaf, title: now?["title"]?.string ?? json["title"]?.string ?? leaf)
        }
        try? replace(name, with: json, actionName: actionName)
    }

    /// Forgets Undo's steps on the document of that name, and leaves those on the others.
    private func forgetSteps(of name: String) {
        guard let identity = identities.removeValue(forKey: name) else { return }
        undoManager?.removeAllActions(withTarget: identity)
    }

    /// Forgets every step, as when another project is opened, whose documents may have the
    /// same names.
    private func forgetAllSteps() {
        for identity in identities.values { undoManager?.removeAllActions(withTarget: identity) }
        identities = [:]
    }

    func existing(_ name: String) throws(MethodError) -> StudioDocument {
        guard folder != nil else { throw MethodError.noProject }
        guard let d = document(named: name) else { throw MethodError.noDocument(name, in: self) }
        return d
    }

    // MARK: making a document

    /// Makes a document in the project folder's top level, reads the folder again at once rather
    /// than waiting for the watcher, and selects and plays its first step (section 6.8 of the
    /// helper protocol).
    ///
    /// - Parameters:
    ///   - title: The new document's `title`; the name and `id` are made from it.
    ///   - name: The name to give it instead; refused if it is taken or is not a valid `id`.
    ///   - from: The name of a document of the project to copy, with its own `id` and `title`;
    ///     without it, the studio's starter.
    /// - Returns: The new document, as read back from its file.
    /// - Throws: An error whose description says why nothing was made.
    @discardableResult
    public func createDocument(title: String, name: String? = nil, from source: String? = nil) throws -> StudioDocument {
        try make(title: title, name: name, from: source)
    }

    func make(title: String, name requested: String?, from source: String?) throws(MethodError) -> StudioDocument {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MethodError(code: Studio.RPCError.invalidParams, "The parameter title must not be empty.")
        }
        guard let folder else { throw MethodError.noProject }
        // Another program may have added files since the folder was last read.
        reload()
        let copied: DocJSON?
        if let source {
            let original = try existing(source)
            guard let doc = original.document else { throw MethodError.unreadable(original) }
            copied = doc.json
        } else {
            copied = nil
        }
        func target(_ name: String) -> URL { folder.appendingPathComponent(name + "." + ProjectFolder.fileExtension) }
        func isTaken(_ name: String) -> Bool {
            documents.contains { $0.name == name } || FileManager.default.fileExists(atPath: target(name).path)
        }
        let name: String
        if let requested {
            guard DocumentStarter.isValid(name: requested) else {
                throw MethodError(code: Studio.ErrorCode.failed,
                                  "The name \(requested) is not valid; a name is lower case letters, digits and hyphens, "
                                  + "begins with a letter and has at most 64 characters, as in reading-the-clock.")
            }
            guard !isTaken(requested) else {
                throw MethodError(code: Studio.ErrorCode.failed, "A document named \(requested) is already in the project.")
            }
            name = requested
        } else {
            name = DocumentStarter.available(DocumentStarter.name(forTitle: title), isTaken: isTaken)
        }
        let json = copied.map { DocumentStarter.copy(of: $0, id: name, title: title) }
            ?? DocumentStarter.starter(id: name, title: title)
        do {
            try Data(DocumentText.format(json).utf8).write(to: target(name), options: .atomic)
        } catch {
            throw MethodError(code: Studio.ErrorCode.failed, "The studio could not save \(name): \(error.localizedDescription)")
        }
        // A step made on an earlier document of this name is not this document's.
        forgetSteps(of: name)
        reload()
        guard let made = document(named: name) else {
            throw MethodError(code: Studio.ErrorCode.failed, "The studio saved \(name) but could not find it in the project folder.")
        }
        if selectedName == name {
            // The folder's first document is selected when none was, and then keeps the old preview.
            preview = defaultPreview
            rebuild(keepStep: false)
        } else {
            select(name)
        }
        player?.show(step: 0)
        return made
    }

    // MARK: renaming, duplicating and removing a document

    /// Moves a file to the Trash. The system's Trash by default, from which Finder can put the
    /// file back; a test gives another, so that it leaves nothing in the Trash.
    @ObservationIgnored public var moveToTrash: (URL) throws -> Void = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }

    /// Gives a document another title, and with it the name and `id` made from that title: the
    /// file is written and renamed in its folder before the folder is read again, so the project
    /// never lists it half renamed. A name another document has gets a number added. The
    /// document stays shown if it was, with its problem. The rename is not one of Undo's steps,
    /// and the steps made on the document before it follow the document to its new name.
    ///
    /// - Returns: The document under its new name, as read back from its file.
    /// - Throws: An error whose description says why nothing was changed.
    @discardableResult
    public func renameDocument(_ name: String, title: String) throws -> StudioDocument {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw MethodError(code: Studio.RPCError.invalidParams, "A title must not be empty.")
        }
        // Another program may have added files since the folder was last read.
        reload()
        let old = try present(name)
        guard let doc = old.document else {
            throw MethodError(code: Studio.ErrorCode.failed, "\(name) cannot be read as a document, so it cannot be renamed.")
        }
        let directory = old.url.deletingLastPathComponent()
        let prefix = name.lastIndex(of: "/").map { String(name[...$0]) } ?? ""
        func target(_ leaf: String) -> URL { directory.appendingPathComponent(leaf + "." + ProjectFolder.fileExtension) }
        func fileNumber(_ url: URL) -> NSNumber? {
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? NSNumber
        }
        let ownFile = fileNumber(old.url)
        func isTaken(_ leaf: String) -> Bool {
            if prefix + leaf == name { return false }
            if documents.contains(where: { $0.name == prefix + leaf }) { return true }
            // Where case is not told apart, a name differing only in case is this document's own file.
            guard let found = fileNumber(target(leaf)) else { return false }
            return found != ownFile
        }
        let leaf = DocumentStarter.available(DocumentStarter.name(forTitle: title), isTaken: isTaken)
        let newName = prefix + leaf
        let data = Data(DocumentText.format(DocumentStarter.copy(of: doc.json, id: leaf, title: title)).utf8)
        do {
            try data.write(to: old.url, options: .atomic)
            if newName != name {
                do {
                    try FileManager.default.moveItem(at: old.url, to: target(leaf))
                } catch {
                    try? old.data.write(to: old.url, options: .atomic)
                    throw error
                }
            }
        } catch {
            throw MethodError(code: Studio.ErrorCode.failed, "The studio could not rename \(name): \(error.localizedDescription)")
        }
        if let problem = problems.removeValue(forKey: name) { problems[newName] = problem }
        if newName != name { forgetSteps(of: newName) }
        if let identity = identities.removeValue(forKey: name) {
            identity.renames += 1
            identities[newName] = identity
        }
        if selectedName == name { selectedName = newName }
        reload()
        guard let renamed = document(named: newName) else {
            throw MethodError(code: Studio.ErrorCode.failed, "The studio renamed \(name) but could not find it in the project folder.")
        }
        return renamed
    }

    /// Makes a copy of a document beside the others, titled as the original with "copy" added,
    /// and a number after that when the project has such a title already; selects and plays it.
    ///
    /// - Throws: An error whose description says why nothing was made.
    @discardableResult
    public func duplicateDocument(_ name: String) throws -> StudioDocument {
        let original = try present(name)
        let base = (original.title ?? String(name.split(separator: "/").last ?? "Explainer")) + " copy"
        let titles = Set(documents.compactMap(\.title))
        var title = base
        var n = 2
        while titles.contains(title) {
            title = "\(base) \(n)"
            n += 1
        }
        return try make(title: title, name: nil, from: name)
    }

    /// Moves a document's file to the Trash and, if it was the one shown, shows the document
    /// that follows it in the list, or the last when it was the last. Undo's steps on it are
    /// forgotten, and those on other documents are kept.
    ///
    /// - Throws: An error whose description says why the file was not moved.
    public func trashDocument(_ name: String) throws {
        let gone = try present(name)
        do {
            try moveToTrash(gone.url)
        } catch {
            throw MethodError(code: Studio.ErrorCode.failed, "The studio could not move \(name) to the Trash: \(error.localizedDescription)")
        }
        problems[name] = nil
        forgetSteps(of: name)
        guard selectedName == name else { return reload() }
        let rest = documents.filter { $0.name != name }
        let place = documents.firstIndex { $0.name == name } ?? 0
        selectedName = rest.isEmpty ? nil : rest[min(place, rest.count - 1)].name
        preview = defaultPreview
        reload()
        rebuild(keepStep: false)
    }

    /// The document of that name, for a command of the window.
    private func present(_ name: String) throws(MethodError) -> StudioDocument {
        guard folder != nil else { throw MethodError(code: Studio.ErrorCode.noProject, "No project folder is open.") }
        guard let d = document(named: name) else {
            throw MethodError(code: Studio.ErrorCode.noDocument, "\(name) is not in the project folder any more.")
        }
        return d
    }

    // MARK: showing a step

    /// Shows the document and plays a step of it (section 6.6). Returns the step's name and
    /// place among the problem's steps, from 0.
    func show(_ name: String, step: String?, problem: [String: DocumentValue]?) throws(MethodError) -> (step: String, index: Int, count: Int) {
        let shown = try existing(name)
        guard let doc = shown.document else { throw MethodError.unreadable(shown) }
        if let problem {
            let outside = doc.check(problem: problem)
            guard outside.isEmpty else {
                throw MethodError(code: Studio.ErrorCode.failed,
                                  "The problem is outside \(name)'s parameters: " + outside.map(\.message).joined(separator: "; ") + ".")
            }
            problems[name] = problem
        }
        if selectedName != name {
            selectedName = name
            preview = defaultPreview
        }
        rebuild(keepStep: false)
        guard let player, let e = shaped?.shown else {
            throw MethodError(code: Studio.ErrorCode.failed,
                              "\(name) cannot be played for this problem: " + refusal.map(\.description).joined(separator: "; "))
        }
        let names = e.resolved.stepNames
        let k: Int
        if let step {
            guard let found = names.firstIndex(of: step) else {
                let known = doc.sequence.contains(step) ? "This problem does not have the step \(step)" : "\(name) has no step \(step)"
                throw MethodError(code: Studio.ErrorCode.noStep, "\(known); its steps are \(names.joined(separator: ", ")).")
            }
            k = found
        } else {
            k = 0
        }
        player.show(step: k)
        return (names[k], k, names.count)
    }

    /// Plays the shown document's step of that name, if its problem has it.
    public func play(stepNamed name: String) {
        guard let player, let k = stepNames.firstIndex(of: name) else { return }
        player.show(step: k)
    }

    // MARK: export

    /// What a video of the shown document is made from: the document as the window plays it, with
    /// its problem, wording and language, and the appearance the window previews. Nil when the
    /// document cannot be played.
    public var videoExportSource: VideoExportSource? {
        guard player != nil, let shown = selected, let doc = shown.document else { return nil }
        return VideoExportSource(
            title: shown.title ?? shown.name, document: doc, problem: problem(for: shown.name), wording: effectiveWording,
            locale: effectiveLocale, appearance: previewAppearance)
    }

    // MARK: the socket

    /// Starts answering the helper on the socket at `path`. Fails when another studio is
    /// listening there.
    public func startListening(path: String = StudioSocket.defaultPath) throws {
        stopListening()
        let l = StudioListener(path: path, app: Self.app, handler: StudioService(model: self))
        do {
            try l.start()
        } catch {
            listenFailure = "\(error)"
            throw error
        }
        listener = l
        listening = path
        listenFailure = nil
    }

    public func stopListening() {
        listener?.stop()
        listener = nil
        listening = nil
    }

    func note(_ text: String, client: Implementation?) {
        activity = (client.map { $0.name + ": " } ?? "") + text
    }
}

/// What Undo's steps know a document by. A step is registered on it, not on the document's name,
/// so the step follows the document through a rename and is never done to another document
/// that takes the name.
@MainActor
final class DocumentIdentity {
    /// How many times the document has been renamed since its first step.
    var renames = 0
}

/// A request the studio cannot carry out, as an error code of the helper protocol and one
/// sentence for the agent.
struct MethodError: Error, LocalizedError {
    var errorDescription: String? { message }

    var code: Int
    var message: String

    init(code: Int, _ message: String) {
        self.code = code
        self.message = message
    }

    static let noProject = MethodError(code: Studio.ErrorCode.noProject, "No project is open in ChalkScript Studio; ask the person to open one.")

    @MainActor
    static func noDocument(_ name: String, in model: StudioModel) -> MethodError {
        MethodError(code: Studio.ErrorCode.noDocument, "No document named \(name) is in the project; list gives the names.")
    }

    static func unreadable(_ d: StudioDocument) -> MethodError {
        let why = d.findings.first.map { ": " + $0.description } ?? ""
        return MethodError(code: Studio.ErrorCode.failed,
                           "\(d.name) cannot be read as a document\(why). Ask the person to fix the file in a text editor.")
    }
}

/// The studio's end of the socket: hands each request to the model on the main actor.
final class StudioService: StudioHandler {
    let model: StudioModel

    init(model: StudioModel) { self.model = model }

    func respond(to method: String, params: ChalkScriptMCP.JSONObject, client: Implementation?) -> StudioReply {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { model.respond(to: method, params: params, client: client) }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { model.respond(to: method, params: params, client: client) }
        }
    }
}
#endif
