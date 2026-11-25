import Foundation

/// The model of a two-digit subtraction (EXP-2): a two-digit number minus a one- or two-digit
/// number no larger than it, with or without trading a ten. Every number the explainer draws,
/// shows or says is computed from these two.
public struct SubtractionProblem: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The numbers the template accepts: a two-digit number to take from (10 to 99) and a number
    /// to take away from 1 up to it.
    public static let minuends = 10...99

    public static func subtrahends(for minuend: Int) -> ClosedRange<Int> { 1...minuend }

    public enum RangeError: Error, Equatable, Sendable {
        /// The number to take from is not two-digit.
        case minuend(Int)
        /// The number to take away is not from 1 to the number to take from.
        case subtrahend(Int, minuend: Int)
    }

    public let minuend: Int
    public let subtrahend: Int

    /// Refuses values outside the template's range (EXP-2), so no explainer is offered for them.
    public init(_ minuend: Int, minus subtrahend: Int) throws(RangeError) {
        guard Self.minuends.contains(minuend) else { throw .minuend(minuend) }
        guard Self.subtrahends(for: minuend).contains(subtrahend) else {
            throw .subtrahend(subtrahend, minuend: minuend)
        }
        self.minuend = minuend
        self.subtrahend = subtrahend
    }

    public static func accepts(_ minuend: Int, minus subtrahend: Int) -> Bool {
        (try? SubtractionProblem(minuend, minus: subtrahend)) != nil
    }

    /// Every problem the template accepts, smallest first.
    public static var all: [SubtractionProblem] {
        minuends.flatMap { a in subtrahends(for: a).map { try! SubtractionProblem(a, minus: $0) } }
    }

    public var minuendTens: Int { minuend / 10 }
    public var minuendOnes: Int { minuend % 10 }
    public var subtrahendTens: Int { subtrahend / 10 }
    public var subtrahendOnes: Int { subtrahend % 10 }
    /// The tens taken away, as a number: 20 for the 2 tens of 26.
    public var subtrahendTensValue: Int { subtrahendTens * 10 }
    /// Whether a ten is traded for ten ones: there are fewer ones than to take away.
    public var regroups: Bool { minuendOnes < subtrahendOnes }
    public var difference: Int { minuend - subtrahend }
    public var differenceTens: Int { difference / 10 }
    public var differenceOnes: Int { difference % 10 }
    /// The ones there are once a ten is traded (or not).
    public var onesAfterTrade: Int { minuendOnes + (regroups ? 10 : 0) }

    public var description: String { "\(minuend) - \(subtrahend)" }

    /// The steps, which depend on the values (EXP-2): no trade when none is needed, no ones or
    /// tens step when none are taken away.
    public enum Step: String, CaseIterable, Sendable {
        /// The number drawn as tens and ones.
        case show
        /// Not enough ones to take away.
        case short
        /// A ten traded for ten ones, into the box.
        case trade
        /// Enough ones to take away.
        case enough
        /// The ones taken away, crossed out one by one.
        case takeOnes
        /// The tens taken away.
        case takeTens
        /// What is left copied to the count area and counted.
        case count
    }

    public var steps: [Step] {
        var out: [Step] = [.show]
        if regroups { out += [.short, .trade] } else if subtrahendOnes > 0 { out.append(.enough) }
        if subtrahendOnes > 0 { out.append(.takeOnes) }
        if subtrahendTens > 0 { out.append(.takeTens) }
        out.append(.count)
        return out
    }
}
