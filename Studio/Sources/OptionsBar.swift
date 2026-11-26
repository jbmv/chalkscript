import ChalkScript
import ChalkScriptStudioCore
import SwiftUI

/// The problem the document is played with, chosen from its samples or typed within its
/// parameters, and the wording, language and playback.
struct OptionsBar: View {
    let model: StudioModel
    let document: StudioDocument
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
                Spacer(minLength: 0)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear(perform: resetDrafts)
        .onChange(of: model.playerSerial) { resetDrafts() }
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
