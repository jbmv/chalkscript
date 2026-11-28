import AppKit
import ChalkScript
import ChalkScriptStudioCore
import SwiftUI
import UniformTypeIdentifiers

/// One use of File > Export Video, from the sheet's choices to the saved file: what the sheet
/// shows, and the task that makes the video.
@MainActor
@Observable
final class VideoExportRun {
    enum Phase: Equatable {
        case choosing
        case making(made: Double, whole: Double)
        case finished(URL)
        case failed(String)
    }

    /// Whether the window shows the sheet.
    var isShown = false
    private(set) var phase: Phase = .choosing
    /// The document as the window showed it when the sheet was opened.
    private(set) var source: VideoExportSource?
    /// The problems offered: the document's samples, after the problem shown when it is not one of them.
    private(set) var problems: [[String: DocumentValue]] = []
    var problemIndex = 0 { didSet { refresh() } }
    var settings = VideoExportSettings() { didSet { refresh() } }
    /// The custom shape's two numbers as typed.
    var widthText = "" { didSet { typedShape() } }
    var heightText = "" { didSet { typedShape() } }
    /// The video the choices give, or nil with `refusal` saying why there is none.
    private(set) var plan: VideoExportPlan?
    private(set) var refusal: String?
    /// False while the sheet writes the custom shape's numbers itself.
    @ObservationIgnored private var typing = true
    @ObservationIgnored private var destination: URL?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// The user default that holds the folder the last video was saved in.
    static let folderKey = "ExportVideoFolder"

    /// Does what File > Export Video does: opens the sheet on the document shown, with the
    /// choices last used and the problem shown.
    ///
    /// - Parameter destination: A file to make the video at straight away, with those choices
    ///   and without the save panel, for a test that cannot press Export.
    func begin(_ model: StudioModel, destination: URL? = nil) {
        guard !isShown, let source = model.videoExportSource else { return }
        self.source = source
        let samples = source.document.samples
        problems = samples.contains(source.problem) ? samples : [source.problem] + samples
        problemIndex = problems.firstIndex(of: source.problem) ?? 0
        let remembered = VideoExportSettings(defaults: .standard)
        // Both numbers are written before either is read back as typed.
        typing = false
        widthText = Self.text(remembered.customWidth)
        heightText = Self.text(remembered.customHeight)
        typing = true
        settings = remembered
        phase = .choosing
        refresh()
        isShown = true
        if let destination, let plan { make(plan, to: destination) }
    }

    /// The source with the problem chosen in the sheet.
    private var chosen: VideoExportSource? {
        guard var source, problems.indices.contains(problemIndex) else { return nil }
        source.problem = problems[problemIndex]
        return source
    }

    private func refresh() {
        guard let chosen else { return }
        do {
            plan = try VideoExportPlan(chosen, settings: settings)
            refusal = nil
        } catch {
            plan = nil
            refusal = error.localizedDescription
        }
    }

    /// The video's shape, which starts the drawing's shape again at the one nearest it.
    var shapeChoice: VideoExportSettings.ShapeChoice {
        get { settings.shapeChoice }
        set {
            var next = settings
            next.shapeChoice = newValue
            next.drawingShape = nil
            settings = next
        }
    }

    private func typedShape() {
        guard typing else { return }
        var next = settings
        next.customWidth = Self.number(widthText)
        next.customHeight = Self.number(heightText)
        guard next != settings else { return }
        next.drawingShape = nil
        settings = next
    }

    /// A typed number, whole or decimal; not a number when it cannot be read as one.
    private static func number(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? .nan
    }

    private static func text(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }

    /// What the Problem menu calls a problem.
    func title(of problem: [String: DocumentValue]) -> String {
        guard let source else { return "" }
        let text = VideoExportSource.describe(problem, in: source.document)
        return text.isEmpty ? "The explainer's only problem" : text
    }

    /// Asks where to save the video, remembers the choices, and makes it.
    func export() {
        guard let plan, let chosen else { return }
        let panel = NSSavePanel()
        panel.title = "Export Video"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = chosen.fileName
        panel.directoryURL = UserDefaults.standard.string(forKey: Self.folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: Self.folderKey)
        make(plan, to: url)
    }

    /// Makes the video again where the last one could not be saved.
    func tryAgain() {
        guard let plan, let destination else { return phase = .choosing }
        make(plan, to: destination)
    }

    private func make(_ plan: VideoExportPlan, to url: URL) {
        settings.save(to: .standard)
        destination = url
        phase = .making(made: 0, whole: plan.length)
        task = Task { [weak self] in
            do {
                let result = try await VideoExport.write(plan, to: url) { made, whole in
                    self?.phase = .making(made: made, whole: whole)
                }
                self?.phase = .finished(result.url)
            } catch is CancellationError {
                self?.phase = .choosing
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Cancel: while the video is made, stops it, which leaves no file, and returns to the
    /// choices; after a failure, returns to the choices; otherwise closes the sheet.
    func cancel() {
        switch phase {
        case .making: task?.cancel()
        case .failed: phase = .choosing
        case .choosing, .finished: isShown = false
        }
    }
}

/// The Export Video sheet: the choices for a video with what they will make, then how far the
/// video has got, then where it was saved or why it was not.
struct ExportVideoSheet: View {
    @Bindable var run: VideoExportRun

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Video").font(.headline)
            switch run.phase {
            case .choosing: choices
            case let .making(made, whole): making(made, of: whole)
            case let .finished(url): finished(url)
            case let .failed(reason): failed(reason)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled()
    }

    // MARK: the choices

    @ViewBuilder private var choices: some View {
        Form {
            Picker("Problem:", selection: $run.problemIndex) {
                ForEach(Array(run.problems.enumerated()), id: \.offset) { index, problem in
                    Text(run.title(of: problem)).tag(index)
                }
            }
            .help("The problem the video is of. It starts at the one the window shows.")

            Picker("Video shape:", selection: $run.shapeChoice) {
                ForEach(VideoExportSettings.ShapeChoice.allCases) { Text($0.title).tag($0) }
            }
            .help("Widescreen suits most screens and video sites. Standard suits older projectors. Custom is any shape you type.")
            if run.shapeChoice == .custom {
                LabeledContent("") { customShape }
            }

            if let source = run.source {
                let shapes = VideoExportPlan.drawingShapes(source.document)
                if shapes.count > 1 {
                    Picker("Drawing shape:", selection: Binding(
                        get: { run.plan?.drawingShape?.title ?? run.settings.drawingShape ?? "" },
                        set: { run.settings.drawingShape = $0 })) {
                        ForEach(shapes) { Text($0.title).tag($0.title) }
                    }
                    .disabled(run.plan == nil)
                    .help("The shape the drawing is arranged for, among those the explainer is made for. It starts at the one that fits the video best.")
                }
                if source.document.appearances.count > 1 {
                    Picker("Appearance:", selection: Binding(
                        get: { run.settings.appearance ?? source.appearance },
                        set: { run.settings.appearance = $0 })) {
                        Text("Light").tag(Appearance.light)
                        Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .help("Whether the video is drawn as on a light screen or a dark one. It starts as the window shows the explainer.")
                }
            }

            Picker("Captions:", selection: $run.settings.captions) {
                ForEach(VideoCaptions.allCases) { Text($0.title).tag($0) }
            }
            .help("In the picture, each line is drawn under the drawing and everyone sees it. Subtitles are kept inside the file, and the viewer turns them on in the video player.")

            Picker("Pause between steps:", selection: $run.settings.pause) {
                ForEach(VideoExportSettings.pauses, id: \.seconds) { Text($0.title).tag($0.seconds) }
            }
            .help("How long each step's finished picture stays before the next step begins.")
        }
        .formStyle(.columns)

        VStack(alignment: .leading, spacing: 4) {
            if let plan = run.plan {
                Text(plan.summary).monospacedDigit()
            } else if run.shapeChoice != .custom, let refusal = run.refusal {
                Text(refusal).foregroundStyle(.red)
            }
            Text(run.settings.captions == .none
                ? "The video has no narration yet, and with no captions its lines are not shown."
                : "The video has no narration yet. The lines are shown as captions.")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        HStack {
            Spacer()
            Button("Cancel") { run.cancel() }.keyboardShortcut(.cancelAction)
            Button("Export…") { run.export() }
                .keyboardShortcut(.defaultAction)
                .disabled(run.plan == nil)
        }
    }

    /// The custom shape's two numbers, what to type in them, and either a small picture of the
    /// frame with its size in pixels or why the shape cannot be used.
    private var customShape: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                shapeField("Width", text: $run.widthText)
                Text(":").padding(.top, 2)
                shapeField("Height", text: $run.heightText)
            }
            Text("For example, 1 : 1 for a square video, or 9 : 16 for a phone held upright.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let plan = run.plan {
                HStack(spacing: 10) {
                    FramePicture(plan: plan)
                    Text(verbatim: "\(plan.frame.pixelWidth) × \(plan.frame.pixelHeight) pixels")
                        .font(.callout)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            } else if let refusal = run.refusal {
                Text(refusal)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shapeField(_ name: String, text: Binding<String>) -> some View {
        VStack(spacing: 2) {
            TextField(name, text: text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Text(name).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: making, finished and failed

    @ViewBuilder private func making(_ made: Double, of whole: Double) -> some View {
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
    }

    @ViewBuilder private func finished(_ url: URL) -> some View {
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
            Button("Open") { NSWorkspace.shared.open(url) }
                .help("Opens the video in this Mac's video player.")
            Button("Done") { run.isShown = false }.keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private func failed(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("The video could not be saved.", systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Spacer()
            Button("Cancel") { run.cancel() }.keyboardShortcut(.cancelAction)
            Button("Try Again") { run.tryAgain() }.keyboardShortcut(.defaultAction)
        }
    }
}

/// A small picture of a video's frame: its shape, the drawing's place in it, and the captions'
/// place under the drawing when they are in the picture.
struct FramePicture: View {
    let plan: VideoExportPlan
    /// The picture's longer side, in points.
    private static let side: CGFloat = 64

    var body: some View {
        let frame = plan.frame
        let scale = Self.side / max(frame.size.width, frame.size.height)
        let drawing = plan.drawingArea
        Canvas { context, _ in
            func scaled(_ r: CGRect) -> CGRect {
                CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
            }
            let whole = scaled(CGRect(origin: .zero, size: frame.size))
            context.fill(Path(roundedRect: whole, cornerRadius: 3), with: .color(.secondary.opacity(0.18)))
            context.stroke(Path(roundedRect: whole.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3), with: .color(.secondary.opacity(0.5)), lineWidth: 1)
            context.fill(Path(roundedRect: scaled(drawing), cornerRadius: 1.5), with: .color(.secondary.opacity(0.55)))
            if let band = frame.captionRect {
                let line = scaled(band.insetBy(dx: band.width * 0.2, dy: band.height * 0.3))
                context.fill(Path(roundedRect: line, cornerRadius: line.height / 2), with: .color(.secondary.opacity(0.4)))
            }
        }
        .frame(width: frame.size.width * scale, height: frame.size.height * scale)
        .accessibilityLabel("The video's shape, with the drawing's place in it")
    }
}

extension View {
    /// Shows the Export Video sheet over the window.
    func exportVideoSheet(_ run: VideoExportRun) -> some View {
        sheet(isPresented: Bindable(run).isShown) { ExportVideoSheet(run: run) }
    }
}
