import ChalkScriptStudioCore
import SwiftUI

/// How to connect an agent: the desktop extension for Claude's desktop app, and the command
/// for Claude Code, with the path of the helper inside this copy of the app.
struct ConnectView: View {
    let model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var command: String { ConnectCommand.claudeCode(helper: ConnectCommand.helper(inApp: Bundle.main.bundleURL)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect an agent").font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Claude's desktop app").font(.headline)
                Text("Install the extension ChalkScript Studio.mcpb: double-click it, or drag it onto Claude's window, and confirm. Then start a new chat and ask Claude to list the documents in ChalkScript Studio.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Claude Code").font(.headline)
                Text("Paste this into a terminal once:")
                Text(command)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                Button(copied ? "Copied" : "Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                }
            }

            Text(model.listening != nil
                 ? "The studio is answering agents. Keep it open while you work: the agent's tools reach the documents through it."
                 : "The studio cannot answer agents: \(model.listenFailure ?? "the socket is not open"). Quit any other copy of ChalkScript Studio and open this one again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
