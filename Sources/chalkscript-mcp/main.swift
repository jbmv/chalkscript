// The MCP helper: Claude's desktop app or Claude Code launches it over stdio, and it forwards each
// tool call to the running ChalkScript Studio over a Unix domain socket.
#if os(macOS)
import ChalkScriptMCP
import Darwin
import Foundation

let usage = """
    usage: chalkscript-mcp [--socket PATH]

    Speaks MCP on stdin and stdout and forwards each tool call to ChalkScript Studio.
    The studio's socket is PATH, else $CHALKSCRIPT_STUDIO_SOCKET, else
    \(StudioSocket.defaultPath)

    """

var socketPath = ProcessInfo.processInfo.environment["CHALKSCRIPT_STUDIO_SOCKET"].flatMap { $0.isEmpty ? nil : $0 }
    ?? StudioSocket.defaultPath
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--socket":
        guard let path = arguments.popFirst() else {
            FileHandle.standardError.write(Data(usage.utf8))
            exit(64)
        }
        socketPath = path
    case "--version":
        print("\(HelperInfo.name) \(HelperInfo.version)")
        exit(0)
    case "--help", "-h":
        FileHandle.standardError.write(Data(usage.utf8))
        exit(0)
    default:
        FileHandle.standardError.write(Data("chalkscript-mcp: unknown argument \(argument)\n\n\(usage)".utf8))
        exit(64)
    }
}

// A client that closes stdout while a reply is being written must not end the process by signal.
signal(SIGPIPE, SIG_IGN)

let output = LineWriter(fd: STDOUT_FILENO)
let server = MCPServer(studio: StudioClient(socketPath: socketPath)) { output.write(line: $0) }
server.run(input: STDIN_FILENO)
// The client closing stdin is the signal to exit (the stdio transport's shutdown).
exit(0)
#else
print("chalkscript-mcp runs on macOS only.")
#endif
