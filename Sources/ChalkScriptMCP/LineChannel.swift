#if os(macOS)
import Darwin
import Foundation

/// Reads newline-delimited messages from a file descriptor: the framing of MCP's stdio transport,
/// which the studio socket uses too.
public final class LineReader {
    public enum Event: Equatable {
        case line([UInt8])
        /// A line longer than the limit, which was read to its end and discarded.
        case tooLong
        case end
        case timedOut
        case failed(Int32)
    }

    private let fd: Int32
    private let maximumLength: Int
    private var buffer: [UInt8] = []
    /// How much of the buffer is known to hold no newline.
    private var scanned = 0
    private var discarding = false
    private var ended = false

    /// - Parameter maximumLength: the longest line kept, in bytes.
    public init(fd: Int32, maximumLength: Int = 32 << 20) {
        self.fd = fd
        self.maximumLength = maximumLength
    }

    /// The next line, without its newline or a carriage return before it. Empty lines are skipped.
    /// - Parameter deadline: when to give up waiting; nil waits for as long as it takes.
    public func next(deadline: ContinuousClock.Instant? = nil) -> Event {
        while true {
            if let newline = buffer[scanned...].firstIndex(of: 0x0A) {
                var line = Array(buffer[..<newline])
                buffer.removeSubrange(...newline)
                scanned = 0
                if discarding {
                    discarding = false
                    return .tooLong
                }
                if line.last == 0x0D { line.removeLast() }
                if line.isEmpty { continue }
                return .line(line)
            }
            scanned = buffer.count
            if buffer.count > maximumLength {
                buffer.removeAll(keepingCapacity: false)
                scanned = 0
                discarding = true
            }
            if ended { return .end }
            if let deadline {
                let left = deadline - ContinuousClock.now
                if left <= .zero { return .timedOut }
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let milliseconds = Int32(clamping: left.components.seconds * 1000
                    + left.components.attoseconds / 1_000_000_000_000_000 + 1)
                let ready = poll(&pfd, 1, milliseconds)
                if ready == 0 { continue }
                if ready < 0 {
                    if errno == EINTR { continue }
                    return .failed(errno)
                }
            }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                if errno == ECONNRESET {
                    ended = true
                    continue
                }
                return .failed(errno)
            }
            if count == 0 {
                ended = true
                // A final line without a newline is still a message.
                if !buffer.isEmpty && !discarding { buffer.append(0x0A) }
                continue
            }
            buffer.append(contentsOf: chunk[..<count])
        }
    }
}

/// Writes whole lines to a file descriptor, one writer at a time.
public final class LineWriter: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()

    public init(fd: Int32) { self.fd = fd }

    /// Writes the text and a newline. Returns false when the other end has gone.
    @discardableResult
    public func write(line text: String) -> Bool {
        var bytes = Array(text.utf8)
        bytes.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + offset, $0.count - offset) }
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            offset += written
        }
        return true
    }
}

/// The Unix domain socket between the helper and the studio app.
public enum StudioSocket {
    /// Where the studio listens unless told otherwise:
    /// `~/Library/Application Support/ChalkScript Studio/studio.sock`, under the real home folder of
    /// the user the process runs as.
    public static var defaultPath: String {
        let home: String
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            home = String(cString: dir)
        } else {
            home = NSHomeDirectory()
        }
        return home + "/Library/Application Support/ChalkScript Studio/studio.sock"
    }

    /// The longest path `sockaddr_un` holds on macOS, in bytes, without its terminating zero.
    public static let maximumPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    public enum ConnectFailure: Error, Equatable {
        /// Nothing is listening: no socket file, or one left by a studio that has quit.
        case notRunning
        /// The socket belongs to another user.
        case notOwned
        case pathTooLong
        case failed(Int32)
    }

    /// Connects to the socket at `path` and returns the descriptor, which the caller closes.
    public static func connect(path: String) -> Result<Int32, ConnectFailure> {
        guard path.utf8.count <= maximumPathLength else { return .failure(.pathTooLong) }
        var info = stat()
        if lstat(path, &info) != 0 { return .failure(.notRunning) }
        if (info.st_mode & S_IFMT) != S_IFSOCK { return .failure(.notRunning) }
        // Refusing another user's socket keeps a call from reaching a process the person did not open.
        if info.st_uid != getuid() { return .failure(.notOwned) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { return .failure(.failed(errno)) }
        noSignalOnBrokenPipe(fd)
        var address = makeAddress(path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            let code = errno
            close(fd)
            if code == ECONNREFUSED || code == ENOENT { return .failure(.notRunning) }
            return .failure(.failed(code))
        }
        return .success(fd)
    }

    /// Creates the socket at `path`, readable and writable by its owner only, and listens on it. A
    /// socket file left at the path by a process that has quit is replaced.
    public static func listen(path: String) throws -> Int32 {
        guard path.utf8.count <= maximumPathLength else { throw ConnectFailure.pathTooLong }
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        if lstat(path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFSOCK else { throw ConnectFailure.failed(EEXIST) }
            if case .success(let other) = connect(path: path) {
                close(other)
                throw ConnectFailure.failed(EADDRINUSE)
            }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { throw ConnectFailure.failed(errno) }
        var address = makeAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if bound != 0 || chmod(path, 0o600) != 0 || Darwin.listen(fd, 16) != 0 {
            let code = errno
            close(fd)
            throw ConnectFailure.failed(code)
        }
        return fd
    }

    static func noSignalOnBrokenPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    private static func makeAddress(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            let bytes = Array(path.utf8)
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }
}

#endif
