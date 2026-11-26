#if os(macOS)
import Foundation

/// The authoring guide that `guide.read` returns (`docs/format/authoring-guide.md`), divided into
/// topics at its second-level headings, each written `## name: what it covers`.
public struct AuthoringGuide: Sendable {
    public struct Topic: Sendable, Equatable {
        public var name: String
        public var summary: String
        /// The topic's text, its heading included.
        public var text: String
    }

    /// The topic that returns the whole guide.
    public static let all = "all"

    /// The text before the first topic.
    public let preface: String
    public let topics: [Topic]
    public let text: String

    public init(text: String) {
        self.text = text
        var preface: [Substring] = []
        var topics: [Topic] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                let heading = line.dropFirst(3)
                let parts = heading.split(separator: ":", maxSplits: 1)
                let name = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`"))
                let summary = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                topics.append(Topic(name: name, summary: summary, text: String(line)))
            } else if topics.isEmpty {
                preface.append(line)
            } else {
                topics[topics.count - 1].text += "\n" + line
            }
        }
        self.preface = preface.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        self.topics = topics.map {
            var t = $0
            t.text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t
        }
    }

    public init(contentsOf url: URL) throws {
        self.init(text: try String(contentsOf: url, encoding: .utf8))
    }

    /// The reply to `guide.read` without a topic: the preface, then each topic on one line.
    public var contents: String {
        var lines = [preface, ""]
        lines += topics.map { "- \($0.name): \($0.summary)" }
        lines.append("- \(Self.all): the whole guide, \(text.count) characters")
        return lines.joined(separator: "\n")
    }

    /// The text of a topic, or nil when there is no topic of that name.
    public func topic(_ name: String) -> String? {
        if name == Self.all { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return topics.first { $0.name == name }?.text
    }

    public var names: [String] { topics.map(\.name) + [Self.all] }
}
#endif
