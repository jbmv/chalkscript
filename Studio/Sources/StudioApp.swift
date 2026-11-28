import AppKit
import ChalkScriptMCP
import ChalkScriptStudioCore
import SwiftUI

/// ChalkScript Studio: one window that plays the documents of a project folder and takes an
/// agent's edits through the helper.
@main
struct StudioApp: App {
    @NSApplicationDelegateAdaptor(StudioDelegate.self) private var delegate

    var body: some Scene {
        Window("ChalkScript Studio", id: "main") {
            ContentView(model: delegate.model, delegate: delegate)
                .exportVideoSheet(delegate.exportVideo)
        }
        // Half the width of a 13-inch display, and most of its height.
        .defaultSize(width: 720, height: 860)
        .commands { StudioCommands(model: delegate.model, delegate: delegate) }
    }
}

/// Opens the project and the socket as the app starts, and closes the socket as it quits.
@MainActor
final class StudioDelegate: NSObject, NSApplicationDelegate {
    /// The user default that holds the project folder's path. Given as a launch argument
    /// (`-StudioProjectFolder PATH`), it opens that folder without being remembered.
    static let folderKey = "StudioProjectFolder"
    /// The user default that holds another socket path, for running a second studio in a test.
    static let socketKey = "StudioSocketPath"

    let model: StudioModel
    let newDocument = NewDocumentRequest()
    let exportVideo = VideoExportRun()

    override init() {
        let guide = Bundle.main.url(forResource: "authoring-guide", withExtension: "md")
            .flatMap { try? AuthoringGuide(contentsOf: $0) } ?? AuthoringGuide(text: "The authoring guide is missing from this build.")
        model = StudioModel(guide: guide)
        // A document is first shown in the Square preset, so the drawing's bounds are always seen.
        model.defaultPreview = .ratio(Preset.square.nominal)
        model.setPreview(model.defaultPreview)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        openProject(at: Self.savedFolder)
        let socket = UserDefaults.standard.string(forKey: Self.socketKey)
        try? model.startListening(path: socket ?? StudioSocket.defaultPath)
        #if DEBUG
        observeWindowPictureRequests()
        observeKeyRequests()
        #endif
    }

    #if DEBUG
    /// In a debug build, another process may ask for a picture of the window, drawn by the app
    /// itself, by posting the distributed notification below with the PNG file's path as its
    /// object. It is for testing from a terminal session, which cannot always capture the screen.
    static let windowPictureRequest = Notification.Name("org.chalkscript.studio.windowPicture")

    private func observeWindowPictureRequests() {
        DistributedNotificationCenter.default().addObserver(forName: Self.windowPictureRequest, object: nil, queue: .main) { note in
            guard let path = note.object as? String else { return }
            MainActor.assumeIsolated { Self.saveWindowPicture(to: URL(fileURLWithPath: path)) }
        }
    }

    private static func saveWindowPicture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// In a debug build, another process may open the New Explainer sheet and press keys in it,
    /// for testing from a session that is not allowed to send keys to another app. The app is
    /// not brought to the front, so its menus cannot be chosen this way: the first notification
    /// below does what File > New Explainer does, and the second presses the keys named by its
    /// object, `return`, `escape`, or text to type, in the sheet over the window if there is one.
    static let newExplainerRequest = Notification.Name("org.chalkscript.studio.newExplainer")
    static let keysRequest = Notification.Name("org.chalkscript.studio.keys")
    /// A third notification does what File > Export Video does. With a file's path as its
    /// object, it also makes the video there, with the choices the sheet opens with and without
    /// asking where to save it.
    static let exportVideoRequest = Notification.Name("org.chalkscript.studio.exportVideo")

    private func observeKeyRequests() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Self.newExplainerRequest, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.newDocument.isShown = true }
        }
        center.addObserver(forName: Self.exportVideoRequest, object: nil, queue: .main) { [weak self] note in
            let path = note.object as? String
            MainActor.assumeIsolated {
                guard let self else { return }
                self.exportVideo.begin(self.model, destination: path.map { URL(fileURLWithPath: $0) })
            }
        }
        center.addObserver(forName: Self.keysRequest, object: nil, queue: .main) { note in
            guard let keys = note.object as? String else { return }
            MainActor.assumeIsolated { Self.press(keys) }
        }
    }

    private static func press(_ keys: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { return }
        let target = window.attachedSheet ?? window
        let presses: [(characters: String, code: UInt16)] = switch keys {
        case "return": [("\r", 36)]
        case "escape": [("\u{1B}", 53)]
        default: keys.map { (String($0), 0) }
        }
        for press in presses {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: target.windowNumber, context: nil, characters: press.characters,
                    charactersIgnoringModifiers: press.characters, isARepeat: false, keyCode: press.code) else { continue }
                target.sendEvent(event)
            }
        }
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        model.stopListening()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/ChalkScript", isDirectory: true)
    }

    static var savedFolder: URL {
        UserDefaults.standard.string(forKey: folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultFolder
    }

    static var exampleFiles: [URL] {
        guard let folder = Bundle.main.url(forResource: "examples", withExtension: nil) else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "explainer" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Opens a project folder. A folder that does not exist yet is made, with the examples in it.
    func openProject(at folder: URL) {
        if !FileManager.default.fileExists(atPath: folder.path) {
            _ = try? ProjectFolder.addExamples(Self.exampleFiles, to: folder)
        }
        model.open(folder: folder)
    }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose the folder that holds your explainers."
        panel.directoryURL = model.folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: Self.folderKey)
        openProject(at: url)
    }

    func addExamples() {
        guard let folder = model.folder else { return }
        _ = try? ProjectFolder.addExamples(Self.exampleFiles, to: folder)
        model.reload()
    }
}

struct StudioCommands: Commands {
    let model: StudioModel
    let delegate: StudioDelegate

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Explainer…") { delegate.newDocument.isShown = true }
                .keyboardShortcut("n")
                .disabled(model.folder == nil)
            Divider()
            Button("Open Project Folder…") { delegate.chooseProject() }
                .keyboardShortcut("o")
            Button("Add Example Documents") { delegate.addExamples() }
                .disabled(model.folder == nil)
            Button("Show Project in Finder") {
                if let folder = model.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
            }
            .disabled(model.folder == nil)
        }
        CommandGroup(replacing: .importExport) {
            Button("Export Video…") { delegate.exportVideo.begin(model) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.videoExportSource == nil || delegate.exportVideo.isShown)
        }
    }
}
