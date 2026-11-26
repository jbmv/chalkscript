import ChalkScript
import ChalkScriptStudioCore
import SwiftUI

/// The shapes of drawing area the shown document is made for, and the layout it is drawn in at
/// each (EXP-17): the presets Tall, Square and Wide, each ticked or not, and any custom ranges.
/// Each shape is drawn in its own layout or in the same layout as another. Saving writes `areas`,
/// any new layout and the layouts' `suits` as one patch, which is checked, saved and one step of
/// Undo. The sheet does not otherwise edit a layout.
struct LayoutsSheet: View {
    let model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var plan: LayoutPlan
    @State private var problem: String?

    init(model: StudioModel, plan: LayoutPlan) {
        self.model = model
        _plan = State(initialValue: plan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layouts").font(.headline)
            Text(intro)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Made for")
                    Text("Ratio of width to height")
                    Text("Drawn in")
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(plan.rows) { row in
                    GridRow {
                        if let preset = row.preset {
                            Toggle(preset.title, isOn: Binding(get: { row.isOn }, set: { plan.setOn(row.id, $0) }))
                            Text("\(Shapes.text(preset.range.lowerBound)) to \(Shapes.text(preset.range.upperBound))")
                                .monospacedDigit()
                                .foregroundStyle(row.isOn ? .primary : .secondary)
                        } else {
                            Text("Custom")
                            HStack(spacing: 4) {
                                TextField("Least", text: binding(row.id, \.min))
                                    .frame(width: 56)
                                    .multilineTextAlignment(.trailing)
                                Text("to")
                                TextField("Greatest", text: binding(row.id, \.max))
                                    .frame(width: 56)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        if row.isOn {
                            layoutChoice(row)
                        } else {
                            Text("Not made for this shape").foregroundStyle(.secondary)
                        }
                        if row.preset == nil {
                            Button { plan.removeCustom(row.id) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help("Remove this range")
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
            Button { plan.addCustom() } label: { Label("Custom…", systemImage: "plus") }
                .buttonStyle(.borderless)
                .help("Add a range of shapes given by its least and greatest ratio")
            if plan.included.isEmpty {
                Text("No shapes. Saving removes the declaration, and the document is laid out for whatever area it is given.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.regular)
        .padding(20)
        .frame(minWidth: 520)
    }

    private var intro: String {
        let layouts = "A layout is the document's setup of the scene for a shape: its size, its camera and what is placed where. A shape's own layout starts as a copy of another, which you or the agent then change. In an area of a shape the document is not made for, a player draws it at the nearest shape it is made for, scaled and centred, with margins."
        if plan.declared {
            return "Tick the shapes of drawing area the document is made for, and choose the layout it is drawn in at each. Saving changes the document. " + layouts
        }
        return "This document does not say which shapes it is made for, so it is laid out for whatever area it is given. The presets are ticked as a suggestion, each drawn in the layout the document chooses at it now. " + layouts
    }

    /// The layout a row is drawn in: its own, or another row's, or a layout of the document that
    /// no shape uses; and, for a new layout, the layout it starts as a copy of.
    @ViewBuilder private func layoutChoice(_ row: LayoutRow) -> some View {
        let others = plan.included.filter { $0.id != row.id }
        let shared = plan.sharing(row.id)
        HStack(spacing: 6) {
            Menu {
                Toggle("Its Own Layout", isOn: Binding(get: { shared.isEmpty }, set: { _ in plan.useOwn(row.id) }))
                if !others.isEmpty {
                    Divider()
                    ForEach(others) { other in
                        Toggle("Same as \(other.name)", isOn: Binding(get: { other.layout == row.layout }, set: { _ in plan.useSame(row.id, as: other.id) }))
                    }
                }
                let unused = plan.unused
                if !unused.isEmpty {
                    Divider()
                    Section("Layouts no shape is drawn in") {
                        ForEach(unused, id: \.self) { name in
                            Button(name) { plan.use(row.id, layout: name) }
                        }
                    }
                }
            } label: {
                Text(menuTitle(row, shared: shared))
            }
            .fixedSize()
            if let source = plan.copies[row.layout] {
                Picker("a copy of", selection: Binding(get: { source }, set: { plan.setCopySource(of: row.layout, to: $0) })) {
                    ForEach(plan.layouts, id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()
                .help("The layout the new layout starts as a copy of")
            }
        }
    }

    private func menuTitle(_ row: LayoutRow, shared: [LayoutRow]) -> String {
        if plan.copies[row.layout] != nil { return "Own layout: \(row.layout), new" }
        if shared.isEmpty { return "Own layout: \(row.layout)" }
        return "\(row.layout), with " + shared.map(\.name).joined(separator: " and ")
    }

    private func binding(_ id: String, _ key: WritableKeyPath<LayoutRow, String>) -> Binding<String> {
        Binding(
            get: { plan.rows.first { $0.id == id }?[keyPath: key] ?? "" },
            set: { text in
                if let i = plan.rows.firstIndex(where: { $0.id == id }) { plan.rows[i][keyPath: key] = text }
            })
    }

    private func save() {
        do {
            let refused = try model.saveLayouts(plan)
            if refused.isEmpty {
                dismiss()
            } else {
                problem = "The studio refused the change: " + refused.prefix(3).map(\.message).joined(separator: "; ") + "."
            }
        } catch {
            problem = error.message
        }
    }
}
