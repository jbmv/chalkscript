import ChalkScriptStudioCore
import SwiftUI

/// Whether the window is asking for a new document's title, set by the File menu and read by
/// the window.
@MainActor
@Observable
final class NewDocumentRequest {
    var isShown = false
}

/// Asks for a title and makes a document from it. The document's name and `id` come from the
/// title, so the sheet asks for nothing else.
struct NewDocumentSheet: View {
    let model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var refusal: String?
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Explainer").font(.headline)

            LabeledContent("Title:") {
                TextField("Title", text: $title, prompt: Text("What the explainer is about"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
                    .onSubmit(create)
            }

            if let refusal {
                Text(refusal)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { titleFocused = true }
        .onChange(of: title) { refusal = nil }
    }

    private func create() {
        guard !trimmedTitle.isEmpty else { return }
        do {
            try model.createDocument(title: trimmedTitle)
            dismiss()
        } catch {
            refusal = "The explainer was not made. \(error.localizedDescription)"
        }
    }
}
