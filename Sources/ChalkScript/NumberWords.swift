import Foundation

/// The spoken form of a number (EXP-10): "twenty-eight" for 28. A spoken line says each number
/// as words, so that the words a voice says are fixed by the wording rather than left to the
/// voice's reading of digits; a consuming app can check every spoken line against its shown
/// numbers with `replacingNumerals(in:)`.
///
/// The words come from the system's spell-out rules (`NumberFormatter.Style.spellOut`) for US
/// English, so no number word is typed into code.
public enum NumberWords {
    /// The locale the numbers are spelled in.
    public static let locale = Locale(identifier: "en_US")

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .spellOut
        return f
    }()

    private static let lock = NSLock()

    /// `n` in words: 0 is "zero", 28 is "twenty-eight".
    public static func spoken(_ n: Int) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// The number `words` names, read back with the same rules: nil when they name none.
    public static func number(from words: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return formatter.number(from: words)?.intValue
    }

    /// `text` with every run of digits replaced by its words: what a spoken line should be when
    /// its shown line differs from it only in how the numbers are written.
    public static func replacingNumerals(in text: String) -> String {
        var out = ""
        var digits = ""
        func flush() {
            if let n = Int(digits) { out += spoken(n) }
            digits = ""
        }
        for c in text {
            if c.isASCII, c.isNumber {
                digits.append(c)
            } else {
                flush()
                out.append(c)
            }
        }
        flush()
        return out
    }
}
