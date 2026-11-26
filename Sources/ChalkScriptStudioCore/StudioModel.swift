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
    /// The shape the shown document is played at: the window's, or a ratio chosen to preview.
    public private(set) var shape: ShapeChoice = .window
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
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var listener: StudioListener?
    @ObservationIgnored private let drivesPlayer: Bool

    /// - Parameter drivesPlayer: false makes a player whose clock moves only when it is advanced,
    ///   for tests.
    public init(guide: AuthoringGuide, drivesPlayer: Bool = true) {
        self.guide = guide
        self.drivesPlayer = drivesPlayer
    }

    // MARK: the project

    /// Opens a project folder and watches it for changes made by other programs.
    public func open(folder url: URL, watch: Bool = true) {
        watcher?.stop()
        watcher = nil
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
        shape = .window
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

    /// Plays the shown document at `choice`; a ratio that is not a positive number is ignored.
    public func setShape(_ choice: ShapeChoice) {
        if case let .ratio(r) = choice, !(r > 0 && r.isFinite) { return }
        shape = choice
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

    // MARK: shapes

    /// The shapes the Shape menu offers to preview for the shown document (EXP-17).
    public var previewShapes: [PreviewShape] {
        guard let shown = selected, let doc = shown.document else { return [] }
        return Shapes.previews(doc, problem: problem(for: shown.name))
    }

    /// The ratio of the area the shown document is laid out for, once the window has given it one.
    public var shownRatio: Double? { shaped?.shown.areaUse.flatMap { Shapes.ratio($0.used) } }

    /// What the status line says of the shape: a preview, or a shape the document does not
    /// declare and the declared shape it is shown at instead. Nil for a declared window shape,
    /// and for a document without a declaration in the window.
    public var shapeStatus: String? {
        guard let s = shaped, let use = s.shown.areaUse, let given = Shapes.ratio(use.given), let used = Shapes.ratio(use.used) else { return nil }
        let name = s.ratio == nil ? "Window \(Shapes.text(given))" : Shapes.text(given)
        if !Shapes.fills(use) { return "\(name) is not a declared shape; shown as \(Shapes.text(used))" }
        return s.ratio == nil ? nil : "Previewing \(name) · \(s.shown.resolved.layout)"
    }

    /// Whether the shape shown is outside the shown document's declaration, so that Declare This
    /// Shape can widen the nearest range to it.
    public var canDeclareShownShape: Bool {
        guard let use = shaped?.shown.areaUse else { return false }
        return !Shapes.fills(use)
    }

    /// Declares the shape shown by moving the nearest end of the nearest declared range to it,
    /// as one patch. Returns why it was refused, or nothing.
    @discardableResult
    public func declareShownShape() -> [DocumentFinding] {
        guard let shown = selected, let doc = shown.document, let use = shaped?.shown.areaUse, let r = Shapes.ratio(use.given),
              let ops = Shapes.declaring(doc, ratio: r) else { return [] }
        return apply(ops, to: shown.name, base: doc.shortHash, actionName: "Declare This Shape")
    }

    /// Makes the shown document's declaration `rows`, as one patch through the patch engine, so
    /// that it is checked, saved and one step of Undo. Returns why the patch was refused; throws
    /// when a row cannot be written.
    @discardableResult
    public func declareShapes(_ rows: [DeclaredRow]) throws(ShapeError) -> [DocumentFinding] {
        guard let shown = selected, let doc = shown.document else { return [] }
        guard let ops = try Shapes.patch(doc, rows: rows) else { return [] }
        return apply(ops, to: shown.name, base: doc.shortHash, actionName: "Declare Shapes")
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
            if case let .ratio(r) = shape { ratio = r }
            let p = ExplainerPlayer(explainer: ShapedExplainer(e, ratio: ratio), voice: SilentVoice(), drivesItself: drivesPlayer)
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
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { try? model.replace(name, with: before, actionName: actionName) }
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

    func existing(_ name: String) throws(MethodError) -> StudioDocument {
        guard folder != nil else { throw MethodError.noProject }
        guard let d = document(named: name) else { throw MethodError.noDocument(name, in: self) }
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
            shape = .window
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

/// A request the studio cannot carry out, as an error code of the helper protocol and one
/// sentence for the agent.
struct MethodError: Error {
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
