import Foundation

/// How long a line takes to say, estimated from its words. The estimate is a pure function of
/// the line, so that the time a step takes can be worked out without playing it, and so that
/// `EstimatedVoice` and a timeline agree.
///
/// The rule is 0.3 s plus a third of a second for each word of the spoken form, and 0 for a line
/// with no words. It was fitted to the system voice at its default rate over the lines of one
/// document; it is an estimate for a stand-in, not a measure of any voice.
public enum ReadingTime {
    /// The time before the first word, in seconds.
    public static let lead = 0.3
    /// The time for each word, in seconds.
    public static let perWord = 1.0 / 3.0

    /// The words of `spoken`, split at spaces and hyphens, counting the parts that contain a
    /// letter: "twenty-five" is two.
    public static func words(in spoken: String) -> Int {
        spoken.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).filter { $0.contains(where: \.isLetter) }.count
    }

    /// The estimate for a line whose spoken form is `spoken`, in seconds; 0 when it has no words.
    public static func seconds(_ spoken: String) -> Double {
        let n = words(in: spoken)
        return n == 0 ? 0 : lead + Double(n) * perWord
    }

    /// The estimate for `line`; 0 when it has no spoken form.
    public static func seconds(_ line: Line) -> Double {
        line.spoken.map { seconds($0) } ?? 0
    }
}
