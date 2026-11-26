#if os(macOS)
import Foundation

/// What the studio shows a person who connects an agent to it (section 11 of the helper
/// protocol).
public enum ConnectCommand {
    /// The name the helper is added under in Claude Code.
    public static let serverName = "chalkscript"

    /// The helper inside an app bundle.
    public static func helper(inApp bundle: URL) -> URL {
        bundle.appendingPathComponent("Contents/Helpers/chalkscript-mcp")
    }

    /// The command that adds the helper to Claude Code for every project of the user, with the
    /// helper's path quoted for a POSIX shell.
    public static func claudeCode(helper: URL) -> String {
        "claude mcp add --transport stdio --scope user \(serverName) -- \(quoted(helper.path))"
    }

    static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
#endif
