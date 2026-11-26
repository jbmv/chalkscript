import ChalkScript
import Foundation

/// The model of a two-digit addition (EXP-2): a two-digit number plus a one- or two-digit number,
/// the total under 100, with or without making a new ten. Every number the explainer draws, shows
/// or says is computed from these two.
public struct AdditionProblem: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The numbers the template accepts: a first number from 10 to 98
    /// and a number to add from 1 up to what keeps the total under 100.
    public static let firstNumbers = 10...98

    public static func secondNumbers(for first: Int) -> ClosedRange<Int> { 1...(99 - first) }

    public enum RangeError: Error, Equatable, Sendable {
        /// The first number is not from 10 to 98.
        case first(Int)
        /// The number to add is not from 1 to 99 less the first.
        case second(Int, first: Int)
    }

    public let first: Int
    public let second: Int

    /// Refuses values outside the template's range (EXP-2), so no explainer is offered for them.
    public init(_ first: Int, plus second: Int) throws(RangeError) {
        guard Self.firstNumbers.contains(first) else { throw .first(first) }
        guard Self.secondNumbers(for: first).contains(second) else { throw .second(second, first: first) }
        self.first = first
        self.second = second
    }

    public static func accepts(_ first: Int, plus second: Int) -> Bool {
        (try? AdditionProblem(first, plus: second)) != nil
    }

    /// Every problem the template accepts, smallest first.
    public static var all: [AdditionProblem] {
        firstNumbers.flatMap { a in secondNumbers(for: a).map { try! AdditionProblem(a, plus: $0) } }
    }

    public var firstTens: Int { first / 10 }
    public var firstOnes: Int { first % 10 }
    public var secondTens: Int { second / 10 }
    public var secondOnes: Int { second % 10 }
    /// The ones of both numbers together, before any are bundled: 13 for 38 + 25.
    public var onesTotal: Int { firstOnes + secondOnes }
    /// Whether ten ones are bundled into a new ten: there are ten or more ones.
    public var regroups: Bool { onesTotal >= 10 }
    /// The ones left over once ten are bundled (or all of them when none are).
    public var onesLeftOver: Int { regroups ? onesTotal - 10 : onesTotal }
    public var sum: Int { first + second }
    public var sumTens: Int { sum / 10 }
    public var sumOnes: Int { sum % 10 }

    public var description: String { "\(first) + \(second)" }

    /// The steps, which depend on the values (EXP-2): no ones step when no ones are added, no
    /// bundle when there are fewer than ten ones, no tens step when no tens are added.
    public enum Step: String, CaseIterable, Sendable {
        /// The first number drawn as tens and ones.
        case show
        /// The second number's ones drawn, counted on from the ones already there.
        case addOnes
        /// The ones looked at: ten or more make a ten, fewer stay ones.
        case check
        /// Ten ones bundled into a new ten.
        case bundle
        /// The second number's tens drawn.
        case addTens
        /// Every piece counted, tens first.
        case count
    }

    /// The steps of the watched problem (`doing` false) or of do it with me (true), where the
    /// separate check step is left out: the learner has just counted the ones on, so the adding
    /// step ends with the loop round them and how many there are.
    public func steps(doing: Bool = false) -> [Step] {
        var out: [Step] = [.show]
        if secondOnes > 0 { out.append(.addOnes) }
        if secondOnes > 0 && !doing { out.append(.check) }
        if regroups { out.append(.bundle) }
        if secondTens > 0 { out.append(.addTens) }
        out.append(.count)
        return out
    }
}

extension AdditionProblem {
    /// What makes two problems the same kind (EXP-3): whether a ten is made, whether tens
    /// and ones are added, whether the first number is a whole number of tens, and whether the
    /// total has ones.
    var kind: [Bool] {
        [regroups, secondTens > 0, secondOnes > 0, firstOnes == 0, sumOnes > 0]
    }

    /// Another problem of the same kind (EXP-3): `n` 1 for do it with me, 2 for try one. Never
    /// this problem's first number, number added or total, with both numbers' tens within two of
    /// this one's; the second is also a different total and first number from the first. The pick
    /// is fixed for a problem, so the same problem always gets the same others. It is
    /// this problem itself when no other of its kind exists.
    public func isomorph(_ n: Int) -> AdditionProblem {
        var out: [AdditionProblem] = []
        for a in 11...89 {
            for b in 2...(99 - a) {
                guard let c = try? AdditionProblem(a, plus: b), c.kind == kind, a != first, b != second, c.sum != sum,
                    abs(c.firstTens - firstTens) <= 2, abs(c.secondTens - secondTens) <= 2
                else { continue }
                out.append(c)
            }
        }
        guard !out.isEmpty else { return self }
        func pick(_ k: Int) -> AdditionProblem { out[(first * 31 + second * 17 + k * 97) % out.count] }
        let one = pick(1)
        if n == 1 { return one }
        for k in 2..<40 {
            let c = pick(k)
            if c.sum != one.sum && c.first != one.first { return c }
        }
        return one
    }
}
