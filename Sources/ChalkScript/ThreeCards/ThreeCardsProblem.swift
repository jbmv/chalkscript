import Foundation

/// The model of a three-cards problem (EXP-2): five number cards and a target, and the three cards whose total
/// is closest to it. Every number the explainer draws, shows or says is computed from these six.
///
/// The method: add all five, take the target from the total to find
/// how many too many, and put back the two cards that make that much (or come closest to it).
/// The three left up are the answer.
public struct ThreeCardsProblem: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The numbers the template accepts: cards from 1 to 9, a target from 10
    /// to 30, and five cards that add to more than the target, so two can be put back.
    public static let cardValues = 1...9
    public static let targets = 10...30
    public static let cardCount = 5

    public enum RangeError: Error, Equatable, Sendable {
        /// Not five cards.
        case count(Int)
        /// A card outside 1 to 9.
        case card(Int)
        /// A target outside 10 to 30.
        case target(Int)
        /// The five cards add to no more than the target, so none can be put back.
        case notOver(total: Int, target: Int)
    }

    /// Two cards, by their places (0 to 4), and what they make.
    public struct Pair: Equatable, Hashable, Sendable {
        public let i: Int
        public let j: Int
        public let sum: Int
    }

    public let cards: [Int]
    public let target: Int

    /// Refuses values outside the template's range (EXP-2), so no explainer is offered for them.
    public init(_ cards: [Int], target: Int) throws(RangeError) {
        guard cards.count == Self.cardCount else { throw .count(cards.count) }
        if let bad = cards.first(where: { !Self.cardValues.contains($0) }) { throw .card(bad) }
        guard Self.targets.contains(target) else { throw .target(target) }
        let total = cards.reduce(0, +)
        guard total > target else { throw .notOver(total: total, target: target) }
        self.cards = cards
        self.target = target
    }

    public static func accepts(_ cards: [Int], target: Int) -> Bool {
        (try? ThreeCardsProblem(cards, target: target)) != nil
    }

    public var description: String { cards.map(String.init).joined(separator: " ") + " -> \(target)" }

    /// All five cards added.
    public var total: Int { cards.reduce(0, +) }
    /// How many too many: the total less the target.
    public var over: Int { total - target }

    /// Every pair of cards, closest to `over` first; among pairs equally close, the one with the
    /// earlier first card, then the earlier second card.
    public var pairs: [Pair] {
        var out: [Pair] = []
        for i in 0..<Self.cardCount {
            for j in (i + 1)..<Self.cardCount { out.append(Pair(i: i, j: j, sum: cards[i] + cards[j])) }
        }
        let over = over
        // A stable sort on (distance, first card), so pairs that tie keep their order.
        return out.enumerated().sorted {
            let (a, b) = (abs($0.element.sum - over), abs($1.element.sum - over))
            if a != b { return a < b }
            if $0.element.i != $1.element.i { return $0.element.i < $1.element.i }
            return $0.offset < $1.offset
        }.map(\.element)
    }

    /// The two cards put back.
    public var best: Pair { pairs[0] }
    /// How far what the two put back make is from `over`: 0 when two cards make it exactly.
    public var bestDiff: Int { abs(best.sum - over) }
    /// Whether two cards make exactly how many too many, so the three left make the target.
    public var exact: Bool { bestDiff == 0 }
    /// Whether more than one pair comes equally close.
    public var bestIsShared: Bool { pairs.filter { abs($0.sum - over) == bestDiff }.count > 1 }

    /// The places of the three cards kept, in order.
    public var keep: [Int] { (0..<Self.cardCount).filter { $0 != best.i && $0 != best.j } }
    /// What the three cards kept make.
    public var result: Int { keep.reduce(0) { $0 + cards[$1] } }

    /// What the cards at `places` make.
    public func sum(_ places: [Int]) -> Int { places.reduce(0) { $0 + cards[$1] } }

    /// The steps: the question read with the plan, all five lifted and
    /// added, how many too many, two put back, and the three checked.
    public enum Step: String, CaseIterable, Sendable {
        case read
        case add
        case over
        case drop
        case check
    }

    public var steps: [Step] { Step.allCases }

    // MARK: other problems of the same kind (EXP-3)

    /// Another problem of the same kind (EXP-3): `n` 1 for do it with me, 2 for try one. Five
    /// different cards from 1 to 9 and a target from 15 to 20, with an exact answer when this
    /// problem has one (and none when it has none), one pair that comes closest, and a different
    /// total from this problem's; the second also has a different total from the first. The
    /// pick is seeded, so the same problem always gets the same others;
    /// this problem itself when no other of its kind is found.
    public func isomorph(_ n: Int) -> ThreeCardsProblem {
        let first = search(seedOffset: 1, avoiding: [])
        if n <= 1 { return first ?? self }
        return search(seedOffset: n, avoiding: [first?.total].compactMap { $0 }) ?? first ?? self
    }

    private func search(seedOffset n: Int, avoiding totals: [Int]) -> ThreeCardsProblem? {
        let c = cards
        var seed = UInt64(c[0] * 7 + c[1] * 11 + c[2] * 13 + c[3] * 17 + c[4] * 19 + target + n * 101)
        // A linear congruential generator, kept in whole numbers so it gives the
        // same sequence on every device.
        func random() -> Double {
            seed = (seed &* 1_103_515_245 &+ 12345) % 2_147_483_648
            return Double(seed) / 2_147_483_648
        }
        for _ in 0..<400 {
            var pool = Array(Self.cardValues)
            var drawn: [Int] = []
            while drawn.count < Self.cardCount { drawn.append(pool.remove(at: Int(random() * Double(pool.count)))) }
            let t = 15 + Int(random() * 6)
            guard let p = try? ThreeCardsProblem(drawn, target: t), p.exact == exact, p.total != total,
                !totals.contains(p.total), !p.bestIsShared
            else { continue }
            return p
        }
        return nil
    }
}
