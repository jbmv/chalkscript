import ChalkScript
import ChalkScriptStudioCore
import SwiftUI

/// The problem the document is played with, chosen from its samples or typed within its
/// parameters, and the wording, language and playback; then, grouped apart as view-only, the
/// area the drawing is previewed at and the arrangement an app might give the screen; and, set
/// apart from both, the Layouts sheet, which changes the document (EXP-17).
struct OptionsBar: View {
    let model: StudioModel
    let document: StudioDocument
    @Binding var arrangement: ScreenArrangement
    @State private var drafts: [String: String] = [:]
    @State private var outside: String?
    @State private var asksRatio = false
    @State private var ratioText = ""

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
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                viewOnly
                Spacer(minLength: 0)
                madeFor
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear(perform: resetDrafts)
        .onChange(of: model.playerSerial) { resetDrafts() }
        .alert("Test a Ratio", isPresented: $asksRatio) {
            TextField("Ratio", text: $ratioText)
            Button("Preview") { previewTypedRatio() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The drawing area's width over its height, such as 0.75. The preview changes nothing in the document.")
        }
    }

    /// The Preview menu and the arrangement, in one group marked as changing only the view.
    private var viewOnly: some View {
        HStack(spacing: 10) {
            previewMenu
            arrangementPicker
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
    }

    /// The shape of area the drawing is previewed in: one of the three presets, or a typed ratio
    /// (EXP-17). Every preset is offered, whether or not the document is made for it.
    private var previewMenu: some View {
        HStack(spacing: 6) {
            Picker("Preview (not saved)", selection: Binding(get: { previewedPreset }, set: { p in
                if let p { model.setPreview(.ratio(p.nominal)) }
            })) {
                ForEach(Preset.allCases) { Text($0.title).tag(Preset?.some($0)) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("The shape of the area the drawing is shown in, framed inside the pane. It changes nothing in the document.")
            Button(previewedPreset == nil ? "Test Ratio: \(model.shownRatio.map(Shapes.text) ?? "…")" : "Test Ratio…") {
                ratioText = model.shownRatio.map(Shapes.text) ?? ""
                asksRatio = true
            }
            .fixedSize()
            .help("Preview any other shape by its width over its height.")
        }
    }

    private var previewedPreset: Preset? {
        guard case let .ratio(r) = model.preview else { return nil }
        return Preset.allCases.first { abs($0.nominal - r) < 1e-9 }
    }

    /// The shapes the document is made for: the one control here that changes the document.
    private var madeFor: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 8) {
                Text("Explainer is made for:")
                ForEach(Preset.allCases) { preset in
                    Toggle(preset.title, isOn: Binding(get: { model.madeFor.contains(preset) }, set: { on in
                        let refused = model.setMadeFor(preset, on)
                        outside = refused.isEmpty ? nil : "The studio refused the change: " + refused.prefix(2).map(\.message).joined(separator: "; ")
                    }))
                    .toggleStyle(.checkbox)
                }
            }
            Text("Saved to document — tells the player app which views it can use.")
                .font(.caption)
                .italic()
                .foregroundStyle(.secondary)
        }
        .disabled(doc == nil)
        .help("Tick the shapes of drawing area this explainer is meant to be shown in. Edit > Undo takes a change back. In any other shape, a player shows it at the nearest ticked shape, scaled and centred.")
    }

    /// The arrangement is an app's choice, not the document's, so it is kept from one document to
    /// the next (EXP-17).
    private var arrangementPicker: some View {
        Picker("App arrangement", selection: $arrangement) {
            Text("Automatic").tag(ScreenArrangement.automatic)
            Text("Caption Below").tag(ScreenArrangement.captionBelow)
            Text("Caption Beside").tag(ScreenArrangement.captionBeside)
        }
        .fixedSize()
        .help("A preview of how an app that plays the explainer might arrange the screen round the drawing. The app chooses its own arrangement; this is not a setting of the document.")
    }

    private func previewTypedRatio() {
        guard let r = Double(ratioText.trimmingCharacters(in: .whitespaces)), r > 0, r.isFinite else {
            outside = "A ratio is a number greater than 0, such as 0.75."
            return
        }
        outside = nil
        model.setPreview(.ratio(r))
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
