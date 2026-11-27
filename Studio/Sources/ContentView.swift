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
        .frame(minWidth: 560, minHeight: 600)
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

/// The documents of the project, by name, with a mark on any that has an error.
struct DocumentList: View {
    let model: StudioModel

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
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([d.url]) }
                        Button("Open in Text Editor") { NSWorkspace.shared.open(d.url) }
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

    var body: some View {
        VStack(spacing: 0) {
            if let shown = model.selected {
                OptionsBar(model: model, document: shown, arrangement: $arrangement, appearance: appearance)
                Divider()
                if let player = model.player {
                    ExplainerView(player: player, labels: .studio, arrangement: arrangement)
                        .id(model.playerSerial)
                        .environment(\.colorScheme, appearance.wrappedValue)
                        .padding(16)
                } else {
                    RefusalView(document: shown, findings: model.refusal)
                }
                Divider()
                FindingsPanel(model: model, document: shown)
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
