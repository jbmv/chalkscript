import ChalkScript
import ChalkScriptStudioCore
import SwiftUI

/// The shapes of drawing area the shown document declares (EXP-17), one row per range: the
/// layout it is drawn in and the least and greatest ratio of width to height. Saving writes the
/// whole declaration as one patch, which is checked, saved and one step of Undo; saving with no
/// rows removes the declaration.
struct DeclareShapesSheet: View {
    let model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [DeclaredRow] = []
    @State private var problem: String?

    private var doc: ExplainerDocument? { model.selected?.document }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Declare Shapes").font(.headline)
            Text(intro)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Layout")
                    Text("Least ratio")
                    Text("Greatest ratio")
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach($rows) { $row in
                    GridRow {
                        Picker("Layout", selection: $row.layout) {
                            ForEach(layoutNames, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                        TextField("Least", text: $row.min)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        TextField("Greatest", text: $row.max)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Button { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove this range")
                    }
                }
            }
            if rows.isEmpty {
                Text("No ranges. Saving removes the declaration, and the document is shown at the window's shape.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button { addRow() } label: { Label("Add Range", systemImage: "plus") }
                .buttonStyle(.borderless)
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(doc == nil)
            }
        }
        .controlSize(.regular)
        .padding(20)
        .frame(minWidth: 440)
        .onAppear { if let doc { rows = Shapes.rows(doc) } }
    }

    private var intro: String {
        if doc?.declaresAreas == true {
            return "Each range is the least and greatest ratio of the drawing area's width to its height, and the layout the document is drawn in at those shapes. Ranges may meet at an end."
        }
        return "This document declares no shapes. The ranges below are a suggestion: one for each run of ratios from 0.5 to 2.5 at which the same layout is chosen. Narrow them to the shapes the document is made for."
    }

    /// `stage`, the document's layouts, and any layout a row names that the document lacks, so
    /// that the row shows what it holds.
    private var layoutNames: [String] {
        let names = doc.map(Shapes.layoutNames) ?? ["stage"]
        return names + rows.map(\.layout).filter { !names.contains($0) }
    }

    private func addRow() {
        guard let last = rows.last, let hi = Double(last.max), hi > 0 else {
            rows.append(DeclaredRow(layout: "stage", min: "0.9", max: "2.2"))
            return
        }
        rows.append(DeclaredRow(layout: last.layout, min: last.max, max: Canonical.number((hi * 150).rounded() / 100)))
    }

    private func save() {
        do {
            let refused = try model.declareShapes(rows)
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
