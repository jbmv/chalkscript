import AppKit
import ChalkScriptStudioCore
import SwiftUI
import UniformTypeIdentifiers

/// One export of a video, from File > Export Video to the saved file: what the sheet shows of
/// it, and the task that makes it.
@MainActor
@Observable
final class VideoExportRun {
    enum Phase: Equatable {
        case making(made: Double, whole: Double)
        case finished(URL)
        case failed(String)
    }

    /// Whether the window shows the sheet.
    var isShown = false
    private(set) var phase: Phase = .making(made: 0, whole: 1)
    @ObservationIgnored private var task: Task<Void, Never>?

    /// The user default that holds the folder the last video was saved in.
    static let folderKey = "ExportVideoFolder"

    /// Does what File > Export Video does: asks where to save a video of the document shown, and
    /// makes it while the sheet shows how far it has got.
    func begin(_ model: StudioModel) {
        guard !isShown, let source = model.videoExportSource else { return }
        let panel = NSSavePanel()
        panel.title = "Export Video"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = source.fileName
        panel.directoryURL = UserDefaults.standard.string(forKey: Self.folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: Self.folderKey)
        make(source, to: url)
    }

    /// Makes the video at `url` and shows the sheet.
    func make(_ source: VideoExportSource, to url: URL) {
        task?.cancel()
        isShown = true
        do {
            let plan = try VideoExportPlan(source)
            phase = .making(made: 0, whole: plan.length)
            task = Task { [weak self] in
                do {
                    let result = try await VideoExport.write(plan, to: url) { made, whole in
                        self?.phase = .making(made: made, whole: whole)
                    }
                    self?.phase = .finished(result.url)
                } catch is CancellationError {
                    self?.isShown = false
                } catch {
                    self?.phase = .failed(error.localizedDescription)
                }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Stops the video being made, which leaves no file, and closes the sheet.
    func cancel() {
        guard case .making = phase, let task else {
            isShown = false
            return
        }
        task.cancel()
    }
}

/// How far a video has got, with Cancel; then where it was saved, or why it was not.
struct ExportVideoSheet: View {
    let run: VideoExportRun

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Video").font(.headline)
            switch run.phase {
            case let .making(made, whole):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Making the video…")
                    ProgressView(value: min(made, whole), total: max(whole, 0.001))
                    Text("\(Int(made)) of \(Int(whole.rounded())) seconds")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Spacer()
                    Button("Cancel") { run.cancel() }.keyboardShortcut(.cancelAction)
                }
            case let .finished(url):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .symbolRenderingMode(.multicolor)
                    Text(url.lastPathComponent)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(url.path)
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("Done") { run.isShown = false }.keyboardShortcut(.defaultAction)
                }
            case let .failed(reason):
                VStack(alignment: .leading, spacing: 4) {
                    Text("The video could not be saved.")
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Close") { run.isShown = false }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .interactiveDismissDisabled()
    }
}

extension View {
    /// Shows the Export Video sheet over the window while a video is made.
    func exportVideoSheet(_ run: VideoExportRun) -> some View {
        sheet(isPresented: Bindable(run).isShown) { ExportVideoSheet(run: run) }
    }
}
