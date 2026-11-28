import ChalkScript
import ChalkScriptStudioCore
import SwiftUI

/// The document's findings, each with its place: the line of the file and the JSON Pointer.
/// Clicking one on a step plays that step. It is a section for a lazy stack in a scroll view,
/// which sets the height: the heading, which opens and closes the list, and a row for each finding.
struct FindingsPanel: View {
    let model: StudioModel
    let document: StudioDocument
    @State private var expanded = true

    var body: some View {
        Section {
            if expanded {
                ForEach(Array(document.findings.enumerated()), id: \.offset) { _, f in
                    row(f)
                    Divider()
                }
            }
        } header: {
            Button { expanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2)
                    Text(summary).font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            // Opaque, since the rows pass under the heading while it is held at the top.
            .background(.background)
        }
    }

    private var summary: String {
        let e = document.errors, w = document.warnings
        if e == 0 && w == 0 { return "No findings" }
        var parts: [String] = []
        if e > 0 { parts.append(e == 1 ? "1 error" : "\(e) errors") }
        if w > 0 { parts.append(w == 1 ? "1 warning" : "\(w) warnings") }
        return parts.joined(separator: ", ")
    }

    private func row(_ f: DocumentFinding) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: f.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(f.severity == .error ? Color.red : Color.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                Text(place(f)).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { if let step = step(of: f) { model.play(stepNamed: step) } }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(f.description, forType: .string)
            }
        }
    }

    /// The line, the pointer, and the code, with the problem's values when it has them.
    private func place(_ f: DocumentFinding) -> String {
        var parts: [String] = []
        if let line = document.line(of: f.path) { parts.append("line \(line)") }
        parts.append(f.path.isEmpty ? "/" : f.path)
        parts.append(f.code.rawValue)
        if let values = f.values {
            parts.append(values.keys.sorted().map { "\($0) = \(values[$0]!)" }.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private func step(of f: DocumentFinding) -> String? {
        let parts = f.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[1] == "steps" else { return nil }
        return String(parts[2])
    }
}
