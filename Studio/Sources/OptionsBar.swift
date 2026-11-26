import ChalkScript
import ChalkScriptStudioCore
import SwiftUI

/// The problem the document is played with, chosen from its samples or typed within its
/// parameters, and the wording, language, playback, the shape of drawing area it is shown at and
/// the arrangement of the screen round the drawing.
struct OptionsBar: View {
    let model: StudioModel
    let document: StudioDocument
    @Binding var arrangement: ScreenArrangement
    @State private var drafts: [String: String] = [:]
    @State private var outside: String?
    @State private var asksRatio = false
    @State private var ratioText = ""
    @State private var declaring = false

    private var doc: ExplainerDocument? { document.document }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                samplesMenu
                ForEach(doc?.parameterOrder ?? [], id: \.self) { name in parameterField(name) }
                Spacer(minLength: 0)
            }
            if let outside {
                Text(outside).font(.caption).foregroundStyle(.red)
            }
            HStack(spacing: 10) {
                if let doc, doc.wordings.count > 1 {
                    Picker("Wording", selection: Binding(get: { model.playedWording ?? "" }, set: { model.setWording($0) })) {
                        ForEach(doc.wordings, id: \.self) { Text($0).tag($0) }
                    }
                    .fixedSize()
                }
                if let doc, doc.locales.count > 1 {
                    Picker("Language", selection: Binding(get: { model.locale ?? doc.sourceLocale }, set: { model.setLocale($0) })) {
                        ForEach(doc.locales, id: \.self) { Text($0).tag($0) }
                    }
                    .fixedSize()
                }
                Picker("Playback", selection: Binding(get: { model.control }, set: { model.setControl($0) })) {
                    Text("Paced").tag(DocumentPlayback.Control.paced)
                    Text("Skippable").tag(DocumentPlayback.Control.skippable)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help("Paced plays as a learner sees it; skippable lets you jump to any step with the dots.")
                shapeMenu
                arrangementPicker
                Spacer(minLength: 0)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear(perform: resetDrafts)
        .onChange(of: model.playerSerial) { resetDrafts() }
        .alert("Preview Another Ratio", isPresented: $asksRatio) {
            TextField("Ratio", text: $ratioText)
            Button("Preview") { previewTypedRatio() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The drawing area's width over its height, such as 0.75. The preview is not saved in the document.")
        }
        .sheet(isPresented: $declaring) { DeclareShapesSheet(model: model) }
    }

    /// Window, the shapes the document declares, another ratio, and declaring (EXP-17).
    private var shapeMenu: some View {
        Menu {
            Toggle("Window", isOn: Binding(get: { model.shape == .window }, set: { _ in model.setShape(.window) }))
            let previews = model.previewShapes
            if !previews.isEmpty {
                Divider()
                ForEach(previews) { p in
                    Toggle(p.label, isOn: Binding(get: { model.shape == .ratio(p.ratio) }, set: { _ in model.setShape(.ratio(p.ratio)) }))
                }
            }
            Divider()
            Button("Other Ratio…") {
                ratioText = model.shownRatio.map(Shapes.text) ?? ""
                asksRatio = true
            }
            Divider()
            if model.canDeclareShownShape {
                Button("Declare This Shape") { report(model.declareShownShape()) }
            }
            Button("Declare Shapes…") { declaring = true }
                .disabled(doc == nil)
        } label: {
            Text(shapeTitle)
        }
        .fixedSize()
        .help("The shape of drawing area the document is shown at: the window's, or a shape to preview")
    }

    /// The arrangement is the app's, not the document's, so it is kept from one document to the
    /// next (EXP-17).
    private var arrangementPicker: some View {
        Picker("Arrangement", selection: $arrangement) {
            Text("Automatic").tag(ScreenArrangement.automatic)
            Text("Caption Below").tag(ScreenArrangement.captionBelow)
            Text("Caption Beside").tag(ScreenArrangement.captionBeside)
        }
        .fixedSize()
        .help("How the screen is arranged round the drawing, as an app that plays the document chooses it")
    }

    private var shapeTitle: String {
        switch model.shape {
        case .window: "Shape: Window"
        case let .ratio(r): "Shape: \(Shapes.text(r))"
        }
    }

    private func previewTypedRatio() {
        guard let r = Double(ratioText.trimmingCharacters(in: .whitespaces)), r > 0, r.isFinite else {
            outside = "A ratio is a number greater than 0, such as 0.75."
            return
        }
        outside = nil
        model.setShape(.ratio(r))
    }

    private func report(_ refused: [DocumentFinding]) {
        outside = refused.isEmpty ? nil : refused.prefix(3).map(\.message).joined(separator: "; ")
    }

    private var problem: [String: DocumentValue] { model.problem(for: document.name) }

    private var samplesMenu: some View {
        Menu("Samples") {
            ForEach(Array((doc?.samples ?? []).enumerated()), id: \.offset) { _, sample in
                Button(describe(sample)) { apply(sample) }
            }
        }
        .fixedSize()
        .help("Play one of the problems the document gives as samples")
    }

    @ViewBuilder private func parameterField(_ name: String) -> some View {
        let declaration = doc?.json.value(at: "/params/\(name)")
        let type = declaration?["type"]?.string ?? ""
        switch type {
        case "bool":
            Toggle(name, isOn: Binding(
                get: { problem[name] == .truth(true) },
                set: { on in var p = problem; p[name] = .truth(on); apply(p) }))
        case "choice":
            let values = declaration?["values"]?.array?.compactMap { DocumentValue(json: $0) } ?? []
            Picker(name, selection: Binding(
                get: { problem[name].map { "\($0)" } ?? "" },
                set: { text in
                    var p = problem
                    p[name] = values.first { "\($0)" == text }
                    apply(p)
                })) {
                ForEach(values.map { "\($0)" }, id: \.self) { Text($0).tag($0) }
            }
            .fixedSize()
        default:
            HStack(spacing: 2) {
                Text(name).foregroundStyle(.secondary)
                TextField(name, text: Binding(get: { drafts[name] ?? "" }, set: { drafts[name] = $0 }))
                    .frame(width: 44)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(applyDrafts)
                    .help(range(declaration))
                if type == "int" {
                    Stepper("", onIncrement: { step(name, by: 1) }, onDecrement: { step(name, by: -1) })
                        .labelsHidden()
                }
            }
        }
    }

    private func range(_ declaration: JSONValue?) -> String {
        func bound(_ key: String) -> String {
            switch declaration?[key] {
            case let .number(n)?: Canonical.number(n)
            case let .string(s)?: s
            default: "?"
            }
        }
        return "From \(bound("min")) to \(bound("max"))"
    }

    private func describe(_ values: [String: DocumentValue]) -> String {
        (doc?.parameterOrder ?? values.keys.sorted()).compactMap { k in values[k].map { "\(k) = \($0)" } }.joined(separator: ", ")
    }

    private func resetDrafts() {
        drafts = problem.mapValues { "\($0)" }
    }

    private func step(_ name: String, by delta: Double) {
        guard case let .number(n)? = problem[name] else { return }
        var p = problem
        p[name] = .number(n + delta)
        apply(p)
    }

    private func applyDrafts() {
        var p = problem
        for (name, text) in drafts {
            guard let current = p[name] else { continue }
            if case .number = current {
                guard let n = Double(text.trimmingCharacters(in: .whitespaces)) else {
                    outside = "\(name) must be a number."
                    return
                }
                p[name] = .number(n)
            }
        }
        apply(p)
    }

    private func apply(_ values: [String: DocumentValue]) {
        let refused = model.setProblem(values, for: document.name)
        outside = refused.isEmpty ? nil : refused.map(\.message).joined(separator: "; ")
        if !refused.isEmpty { resetDrafts() }
    }
}
