import ChalkScript
import ChalkScriptStudioCore
import SwiftUI

/// The window: the project's documents in a sidebar that can be hidden, and the shown document
/// played beside them, with its problem, its findings and what the agent last did.
struct ContentView: View {
    let model: StudioModel
    let delegate: StudioDelegate
    @Environment(\.undoManager) private var undoManager
    @State private var showsConnect = false

    var body: some View {
        NavigationSplitView {
            DocumentList(model: model)
                .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 260)
        } detail: {
            DocumentPane(model: model)
        }
        .navigationTitle(model.selected?.title ?? "ChalkScript Studio")
        .navigationSubtitle(model.folder?.lastPathComponent ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsConnect = true } label: { Label("Connect an Agent", systemImage: "link") }
                    .help("How to connect Claude's desktop app or Claude Code to the studio")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { delegate.chooseProject() } label: { Label("Open Project Folder", systemImage: "folder") }
                    .help("Open another project folder")
            }
        }
        .sheet(isPresented: $showsConnect) { ConnectView(model: model) }
        .sheet(isPresented: Bindable(delegate.newDocument).isShown) { NewDocumentSheet(model: model) }
        // The least in which the document's pane is whole beside the sidebar at its ideal width,
        // and in which the player has its least height above the first of the notes.
        .frame(minWidth: 660, minHeight: 720)
        .onAppear {
            model.undoManager = undoManager
            model.speakingVoice = { SystemVoice(locale: $0) }
            model.setSpeaksLines(UserDefaults.standard.bool(forKey: SystemVoice.enabledKey))
        }
        // A closed window is heard no longer.
        .onDisappear { model.player?.stop() }
        .onChange(of: undoManager) { model.undoManager = undoManager }
    }
}

/// The documents of the project, by name, with a mark on any that has an error. A document's
/// context menu renames it, duplicates it and moves it to the Trash.
struct DocumentList: View {
    let model: StudioModel
    @State private var renaming: DocumentSubject?
    @State private var trashing: DocumentSubject?
    @State private var failure: CommandFailure?

    var body: some View {
        List(selection: Binding(get: { model.selectedName }, set: { model.select($0) })) {
            Section(model.folder?.lastPathComponent ?? "No project") {
                ForEach(model.documents, id: \.name) { d in
                    HStack(spacing: 6) {
                        Text(d.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if d.errors > 0 {
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                                .help(d.errors == 1 ? "1 error" : "\(d.errors) errors")
                        }
                    }
                    .tag(d.name)
                    .contextMenu {
                        // A file that cannot be read has no title to change and nothing to copy.
                        Button("Rename…") { renaming = DocumentSubject(d) }
                            .disabled(d.document == nil)
                        Button("Duplicate") { duplicate(d) }
                            .disabled(d.document == nil)
                        Divider()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([d.url]) }
                        Button("Open in Text Editor") { NSWorkspace.shared.open(d.url) }
                        Divider()
                        Button("Move to Trash", role: .destructive) { trashing = DocumentSubject(d) }
                    }
                }
            }
        }
        .overlay {
            if model.folder != nil && model.documents.isEmpty {
                ContentUnavailableView("No documents", systemImage: "doc",
                                       description: Text("Choose New Explainer or Add Example Documents from the File menu, or ask the agent to make one."))
            }
        }
        .sheet(item: $renaming) { RenameSheet(model: model, subject: $0) }
        .confirmationDialog(
            "Move “\(trashing?.title ?? "")” to the Trash?",
            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }),
            presenting: trashing
        ) { subject in
            Button("Move to Trash", role: .destructive) { trash(subject) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You can put it back from the Trash in Finder.")
        }
        .alert(
            failure?.title ?? "",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
            presenting: failure
        ) { _ in
            Button("OK") {}
        } message: {
            Text($0.reason)
        }
    }

    private func duplicate(_ d: StudioDocument) {
        do {
            try model.duplicateDocument(d.name)
        } catch {
            failure = CommandFailure(title: "The explainer was not duplicated.", reason: error.localizedDescription)
        }
    }

    private func trash(_ subject: DocumentSubject) {
        do {
            try model.trashDocument(subject.name)
        } catch {
            failure = CommandFailure(title: "The explainer was not moved to the Trash.", reason: error.localizedDescription)
        }
    }
}

/// The document a command of the sidebar is about: its name, for the model, and its title, or
/// its name when it has none, for what the person is asked.
struct DocumentSubject: Identifiable {
    let name: String
    let title: String
    var id: String { name }

    init(_ d: StudioDocument) {
        name = d.name
        title = d.title ?? d.name
    }
}

/// Why a command of the sidebar did nothing, for an alert.
struct CommandFailure {
    let title: String
    let reason: String
}

/// Asks for a document's new title. The file's name and the document's `id` follow the title, so
/// the sheet asks for nothing else.
struct RenameSheet: View {
    let model: StudioModel
    let subject: DocumentSubject
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var refusal: String?
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Explainer").font(.headline)

            LabeledContent("Title:") {
                TextField("Title", text: $title, prompt: Text("What the explainer is about"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
                    .onSubmit(rename)
            }

            Text(refusal ?? "The name in the sidebar changes to match the title.")
                .font(.callout)
                .foregroundStyle(refusal == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename", action: rename)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            title = subject.title
            titleFocused = true
        }
        .onChange(of: title) { refusal = nil }
    }

    private func rename() {
        guard !trimmedTitle.isEmpty else { return }
        do {
            try model.renameDocument(subject.name, title: trimmedTitle)
            dismiss()
        } catch {
            refusal = "The explainer was not renamed. \(error.localizedDescription)"
        }
    }
}

/// The shown document: its options, its player and its findings. The player alone is drawn in
/// the appearance chosen in the options bar, or, when the document is not made for that one, in
/// the one it is made for (EXP-20); the rest of the window keeps the Mac's.
struct DocumentPane: View {
    let model: StudioModel
    @State private var arrangement: ScreenArrangement = .automatic
    /// The appearance chosen for the preview; nil until one is chosen, when the Mac's is used.
    /// It is the window's, like the arrangement: no document holds it and it is not kept.
    @State private var chosenAppearance: ColorScheme? = DocumentPane.startingAppearance
    @Environment(\.colorScheme) private var macAppearance

    private var appearance: Binding<ColorScheme> {
        Binding(get: { chosenAppearance ?? macAppearance }, set: { chosenAppearance = $0 })
    }

    /// In a debug build, the launch argument `-StudioPreviewAppearance light` or `dark` starts
    /// the preview in that appearance, for a session that cannot click the control.
    private static var startingAppearance: ColorScheme? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "StudioPreviewAppearance") {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
        #else
        return nil
        #endif
    }

    static let playerMargin: CGFloat = 16
    /// The least height the player is given. In less than 400 points the player's screen scrolls
    /// rather than show its drawing, line and controls together.
    static let playerLeast: CGFloat = 400 + 2 * playerMargin

    var body: some View {
        VStack(spacing: 0) {
            if let shown = model.selected {
                OptionsBar(model: model, document: shown, arrangement: $arrangement, appearance: appearance)
                Divider()
                PlayerFirstLayout(playerLeast: Self.playerLeast, notesLeast: 72) {
                    if let player = model.player {
                        ExplainerView(player: player, labels: .studio, arrangement: arrangement)
                            .id(model.playerSerial)
                            .environment(\.colorScheme, appearance.wrappedValue)
                            .padding(Self.playerMargin)
                    } else {
                        RefusalView(document: shown, findings: model.refusal)
                    }
                    DocumentNotes(model: model, document: shown)
                }
            } else {
                ContentUnavailableView("No document", systemImage: "rectangle.on.rectangle",
                                       description: Text("Choose a document in the sidebar."))
            }
            StatusLine(model: model)
        }
        // The model answers an agent's picture in the appearance previewed, and says in the
        // status line when the document is not made for it.
        .onChange(of: appearance.wrappedValue, initial: true) { _, now in
            model.previewAppearance = now == .dark ? .dark : .light
        }
    }
}

/// Places the player above the document's notes and gives the notes what the player can spare:
/// their own height where there is room for it, and less before the player would be shorter than
/// `playerLeast` or than half the height the two share. The notes keep `notesLeast`, or their own
/// height if that is less, so that what scrolls can be seen to be there.
struct PlayerFirstLayout: Layout {
    let playerLeast: CGFloat
    let notesLeast: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 400, height: playerLeast))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let notes = subviews[1]
        let wanted = notes.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
        let spare = bounds.height - max(playerLeast, bounds.height / 2)
        let height = min(max(min(wanted, spare), min(wanted, notesLeast)), bounds.height)
        subviews[0].place(
            at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height - height))
        notes.place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY - height),
            proposal: ProposedViewSize(width: bounds.width, height: height))
    }
}

/// Below the player, the notices of changed colours and the findings, which scroll together in
/// the height the player leaves them. The findings' heading stays in view while they scroll.
struct DocumentNotes: View {
    let model: StudioModel
    let document: StudioDocument

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    OverrideNotices(model: model)
                    FindingsPanel(model: model, document: document)
                }
            }
        }
    }
}

/// Above the findings, a notice for each operation whose colour the document changes (EXP-6):
/// which operation, why its colour is normally fixed, what the person asked, and a button that
/// restores the standard colour as one step of Edit > Undo. It informs and holds nothing back.
struct OverrideNotices: View {
    let model: StudioModel
    @State private var refused: String?

    var body: some View {
        ForEach(model.overrideNotices) { notice in
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "paintpalette").foregroundStyle(.secondary).frame(width: 16)
                    Text(notice.title).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(StudioModel.standardColourTitle) {
                        refused = model.useStandardColour(for: notice.operation).first.map { "The colour was not changed. \($0.message)" }
                    }
                    .controlSize(.small)
                    .help("Draw \(notice.meaning) in the colour every maths explainer uses. Edit > Undo brings the change back.")
                }
                Group {
                    Text(notice.reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let asked = notice.asked {
                        Text("Asked: “\(asked)”").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let refused {
                        Text(refused).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 24)
            }
            // The text wraps and is never cut short, so it is measured at a width the pane always
            // has: measured narrower, as a window's least size is, it would be many lines tall.
            .frame(minWidth: 270, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        }
        .onChange(of: model.playerSerial) { refused = nil }
    }
}

/// Shown in place of the player when the document cannot be played for its problem.
struct RefusalView: View {
    let document: StudioDocument
    let findings: [DocumentFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This document cannot be played", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(findings.isEmpty ? "It has an error." : "Ask Claude to fix it; Claude sees the same errors.")
                .foregroundStyle(.secondary)
            ForEach(Array(findings.prefix(6).enumerated()), id: \.offset) { _, f in
                Text(f.message).font(.callout)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What the agent last asked of the studio, or what the studio has to say of the document's
/// appearances; whether the studio can be reached; and the layout the document is drawn in and
/// the area it is shown at; when that area is not one the document is made for, it says so and
/// offers to add it (EXP-17).
struct StatusLine: View {
    let model: StudioModel
    @State private var refused: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.listening != nil ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(refused ?? said ?? status).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(refused == nil ? Color.secondary : Color.red)
                .help(refused ?? said ?? status)
                // What the studio says of the document is kept whole before the area is.
                .layoutPriority(said == nil ? 0 : 1)
            Spacer(minLength: 0)
            if let area = model.areaStatus {
                Text(area).lineLimit(1).truncationMode(.head)
                    .help(area)
            }
        }
        .onChange(of: model.playerSerial) { refused = nil }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    /// What the studio has to say of the shown document's appearances: the values a tick added,
    /// or why the preview is not drawn in the appearance chosen (EXP-20).
    private var said: String? { model.notice ?? model.appearanceStatus }

    private var status: String {
        if model.listening == nil {
            return model.listenFailure.map { "Agents cannot reach the studio: \($0)" } ?? "Agents cannot reach the studio."
        }
        return model.activity.map { "Last call: \($0)" } ?? "Ready for an agent."
    }
}

extension ExplainerLabels {
    static let studio = ExplainerLabels(
        watch: "Watch", next: "Next", watchAgain: "Watch again", again: "Again",
        progress: { "Step \($0) of \($1)" })
}
