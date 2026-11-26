import ChalkScript
import Foundation

/// The model of adding within 20 by making a ten (EXP-2): two one-digit numbers whose total is
/// more than ten, so a ten can be made. As Illustrative Mathematics teaches it, the bigger number
/// fills most of the top ten frame, the smaller one is split so that part of it completes the
/// ten, and what is left is counted on from ten. Every number the explainer draws, shows or says
/// is computed from these two.
public struct MakeTenProblem: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The numbers the template accepts: each from 2 to 9.
    public static let numbers = 2...9
    /// The smallest total: a ten is made only when the two add to more than ten.
    public static let smallestTotal = 11

    public enum RangeError: Error, Equatable, Sendable {
        /// A number is not from 2 to 9.
        case number(Int)
        /// The two add to 10 or less, so no ten is made.
        case noTen(total: Int)
    }

    public let first: Int
    public let second: Int

    /// Refuses values outside the template's range (EXP-2), so no explainer is offered for them.
    public init(_ first: Int, plus second: Int) throws(RangeError) {
        guard Self.numbers.contains(first) else { throw .number(first) }
        guard Self.numbers.contains(second) else { throw .number(second) }
        guard first + second >= Self.smallestTotal else { throw .noTen(total: first + second) }
        self.first = first
        self.second = second
    }

    public static func accepts(_ first: Int, plus second: Int) -> Bool {
        (try? MakeTenProblem(first, plus: second)) != nil
    }

    /// Every problem the template accepts, smallest first number first.
    public static var all: [MakeTenProblem] {
        numbers.flatMap { a in numbers.compactMap { try? MakeTenProblem(a, plus: $0) } }
    }

    /// Whether the first number is the bigger one (or the two are equal): it goes in the top
    /// ten frame.
    public var firstOnTop: Bool { first >= second }
    /// The number in the top ten frame, as filled counters.
    public var big: Int { max(first, second) }
    /// The number in the bottom ten frame, as open counters; it is split.
    public var small: Int { min(first, second) }
    /// What the top number needs to make ten: the part of the smaller number that moves up.
    public var need: Int { 10 - big }
    /// What is left of the smaller number once the ten is made.
    public var rest: Int { small - need }
    public var sum: Int { first + second }

    public var description: String { "\(first) + \(second)" }

    /// The steps, the same for every problem the template accepts (a ten always needs at least
    /// one more, and at least one is always left).
    public enum Step: String, CaseIterable, Sendable {
        /// The two numbers drawn in the two ten frames.
        case show
        /// The empty boxes of the top frame: what the top number needs.
        case need
        /// The number bond: the smaller number split into what the ten needs and what is left.
        case split
        /// The dots that make the ten move up into the empty boxes.
        case move
        /// The full ten frame counted as ten, then each dot left, counting on.
        case count
    }

    public var steps: [Step] { Step.allCases }

    /// Another problem of the same kind (EXP-3): `n` 1 for do it with me, 2 for try one. Both
    /// numbers from 2 to 9 with a total from 11 to 18, the bigger number first or second as in
    /// this one, never this problem or its total; the second also has a different total from the
    /// first. The pick is fixed for a problem, so the same problem always gets the same others.
    public func isomorph(_ n: Int) -> MakeTenProblem {
        var out: [MakeTenProblem] = []
        for a in Self.numbers {
            for b in Self.numbers {
                guard let c = try? MakeTenProblem(a, plus: b), c.firstOnTop == firstOnTop, c.sum != sum,
                    c != self
                else { continue }
                out.append(c)
            }
        }
        guard !out.isEmpty else { return self }
        func pick(_ k: Int) -> MakeTenProblem { out[(first * 31 + second * 17 + k * 97) % out.count] }
        let one = pick(1)
        if n == 1 { return one }
        for k in 2..<40 {
            let c = pick(k)
            if c.sum != one.sum { return c }
        }
        return one
    }
}
