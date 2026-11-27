import ChalkScript
import ChalkScriptStudioCore
import SwiftUI

/// The problem the document is played with, chosen from its samples or typed within its
/// parameters, the wording, language and playback, and whether lines are spoken; then, grouped
/// apart as view-only, the area the drawing is previewed at, the appearance it is previewed in and
/// the arrangement an app might give the screen; and, set apart from both, the ticks for the
/// shapes the explainer is made for, which change the document (EXP-17).
struct OptionsBar: View {
    let model: StudioModel
    let document: StudioDocument
    @Binding var arrangement: ScreenArrangement
    @Binding var appearance: ColorScheme
    @State private var drafts: [String: String] = [:]
    @State private var outside: String?

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
                Toggle("Speak lines", isOn: Binding(get: { model.speaksLines }, set: { on in
                    UserDefaults.standard.set(on, forKey: SystemVoice.enabledKey)
                    model.setSpeaksLines(on)
                }))
                .toggleStyle(.checkbox)
                .fixedSize()
                .help("Says each line aloud in this Mac's voice while its step plays, so you can hear a draft. It stays as you leave it and changes nothing in the document.")
                Spacer(minLength: 0)
            }
            // One row where the window is wide enough; otherwise the ticks take a row of their
            // own, and in a narrower window the view-only group takes two rows and then three, so
            // that nothing is squeezed or wrapped.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    viewOnly(rows: 1)
                    Spacer(minLength: 10)
                    madeFor(alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 8) {
                    viewOnly(rows: 1)
                    madeFor(alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 8) {
                    viewOnly(rows: 2)
                    madeFor(alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 8) {
                    viewOnly(rows: 3)
                    madeFor(alignment: .leading)
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear(perform: resetDrafts)
        .onChange(of: model.playerSerial) { resetDrafts() }
    }

    /// The Preview control, the appearance and the arrangement, in one group marked as changing
    /// only the view: in one row, in two with the arrangement under the others, or one to a row.
    private func viewOnly(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                previewMenu
                if rows < 3 { appearancePicker }
                if rows == 1 { arrangementPicker }
            }
            if rows == 3 { appearancePicker }
            if rows > 1 { arrangementPicker }
        }
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
    }

    /// The shape of area the drawing is previewed in: one of the three presets (EXP-17). Every
    /// preset is offered, whether or not the document is made for it. Any other shape is seen
    /// through an agent, whose `show` takes a ratio.
    private var previewMenu: some View {
        Picker("Preview (not saved)", selection: Binding(get: { previewedPreset }, set: { p in
            if let p { model.setPreview(.ratio(p.nominal)) }
        })) {
            ForEach(Preset.allCases) { Text($0.title).tag(Preset?.some($0)) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .help("The shape of the area the drawing is shown in, framed inside the pane. It changes nothing in the document.")
    }

    /// Whether the player is previewed as it looks in the light or in the dark. It follows the
    /// Mac until one is chosen, and is the window's, not the document's.
    private var appearancePicker: some View {
        Picker("Appearance", selection: $appearance) {
            Text("Light").tag(ColorScheme.light)
            Text("Dark").tag(ColorScheme.dark)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Shows the explainer as it looks on a screen set to light or to dark, so you can check that its colours read well in both. It starts as this Mac is set, and changes nothing in the document.")
    }

    private var previewedPreset: Preset? {
        guard case let .ratio(r) = model.preview else { return nil }
        return Preset.allCases.first { abs($0.nominal - r) < 1e-9 }
    }

    /// The shapes the document is made for: the one control here that changes the document.
    private func madeFor(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
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
        .fixedSize()
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
