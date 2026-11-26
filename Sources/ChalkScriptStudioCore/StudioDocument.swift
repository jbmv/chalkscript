#if os(macOS)
import ChalkScript
import CryptoKit
import Foundation

/// One `.explainer` file of the open project as it was last read from disk, with its findings.
public struct StudioDocument: Sendable {
    /// The name the protocol's methods take: the file's path in the project folder without
    /// `.explainer`.
    public let name: String
    public let url: URL
    /// The file's bytes as read.
    public let data: Data
    /// The document, or nil when the file is not a JSON object the reader can keep.
    public let document: ExplainerDocument?
    /// The reader's findings and those of playing each sample, errors first.
    public let findings: [DocumentFinding]
    /// The line of the file on which the value at each JSON Pointer begins.
    public let lines: [String: Int]

    public init(name: String, url: URL, data: Data) {
        self.name = name
        self.url = url
        self.data = data
        let reading = ExplainerDocument.read(data)
        document = reading.document
        findings = DocumentCheck.findings(of: reading)
        lines = LineIndex.lines(of: String(decoding: data, as: UTF8.self))
    }

    /// The short hash of the document (section 19 of the format reference); for a file that
    /// cannot be read as a document, of its bytes.
    public var hash: String {
        if let document { return document.shortHash }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    public var title: String? { document.map(\.title).flatMap { $0.isEmpty ? nil : $0 } }
    public var errors: Int { findings.errors.count }
    public var warnings: Int { findings.warnings.count }

    /// The line on which the value at `pointer`, or the nearest value holding it, begins.
    public func line(of pointer: String) -> Int? {
        var p = pointer
        while true {
            if let l = lines[p] { return l }
            guard let slash = p.lastIndex(of: "/") else { return nil }
            p = String(p[..<slash])
        }
    }
}

/// The findings a studio shows and reports for a document.
public enum DocumentCheck {
    /// The reader's findings, then, for a document without an error, what refuses any sample in
    /// any wording: an evaluation error or something the player does not draw (section 6.6). A
    /// fault at one path is reported once, for the first problem it is found with. Errors come
    /// first; otherwise the order is the reader's, then the samples'.
    public static func findings(of reading: DocumentReading) -> [DocumentFinding] {
        var out = reading.findings
        if let document = reading.document, !reading.findings.hasErrors {
            var seen = Set<String>()
            for sample in document.samples {
                for wording in document.wordings.isEmpty ? [""] : document.wordings {
                    do {
                        _ = try DocumentExplainer(document: document, problem: sample, wording: wording.isEmpty ? nil : wording)
                    } catch {
                        for f in error.findings where seen.insert(f.code.rawValue + " " + f.path).inserted {
                            out.append(f)
                        }
                    }
                }
            }
        }
        return out.errors + out.warnings
    }
}

/// The `.explainer` files of a project folder.
public enum ProjectFolder {
    public static let fileExtension = "explainer"

    /// Each document's name and file, by name. Hidden files and folders are skipped, and so are
    /// folders more than four deep.
    public static func scan(_ folder: URL) -> [(name: String, url: URL)] {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard let walk = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var out: [(name: String, url: URL)] = []
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        for case let url as URL in walk {
            if walk.level > 4 { walk.skipDescendants() }
            guard url.pathExtension == fileExtension,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            out.append((String(relative.dropLast(fileExtension.count + 1)), url))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Copies each example into `folder` that is not already there, creating the folder if it is
    /// missing. Returns the files copied.
    @discardableResult
    public static func addExamples(_ examples: [URL], to folder: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var copied: [URL] = []
        for example in examples {
            let target = folder.appendingPathComponent(example.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            try FileManager.default.copyItem(at: example, to: target)
            copied.append(target)
        }
        return copied
    }
}
#endif
