import ChalkScript
import Foundation

/// The watched lines of the three-cards explainer (EXP-10), one per step, the total said as each
/// card goes up or down, the answer, and Why?'s lines (EXP-16). The app turns each into its
/// wording entry, filled with the problem's values; which wording a step takes (two cards
/// make exactly how many too many, or only come closest) is the app's to choose from the problem.
public enum ThreeCardsLine: Equatable, Hashable, Sendable {
    /// Before the first watched step: "Let's find three cards."
    case intro
    /// The question with the plan: "Which three cards add up to closest to 20? One way: add all
    /// five cards, then put two back."
    case read
    /// "Lifting a card adds it to the total. Lift up all five to add them all together."
    case add
    /// The sum of the cards up, said as a card goes up or down: "27".
    case total(Int)
    /// How many too many: "We have 27, but we want 20. 27 minus 20 is 7, so we have 7 too many."
    case over
    /// The two put back: "So we put back two cards that make 7: 2 and 5.", or, when no two make
    /// it exactly, the two that come closest.
    case drop
    /// The three kept, added: "7 plus 9 plus 4 is 20. Exactly 20!", or how far from the target
    /// they are when that is the closest.
    case check
    /// The last line: "The three cards are 7, 9 and 4.", the three emphasised.
    case answer
    /// Why? on the too-many step: "All five cards make 27.", "We only want 20.", and "The dashed
    /// part is how many too many: 7. So the two cards we put back must make 7."
    case whyAll
    case whyWant
    case whyDashed

    /// Every line a problem's explainer can say.
    public static func all(for p: ThreeCardsProblem) -> [ThreeCardsLine] {
        var totals = Set<Int>()
        // Watched, the cards go up one after another; in do it with me any of them may be up.
        for mask in 1..<(1 << ThreeCardsProblem.cardCount) {
            totals.insert((0..<ThreeCardsProblem.cardCount).filter { mask & (1 << $0) != 0 }.reduce(0) { $0 + p.cards[$1] })
        }
        totals.insert(0)
        return [.intro, .read, .add, .over, .drop, .check, .answer, .whyAll, .whyWant, .whyDashed]
            + totals.sorted().map { .total($0) }
    }
}

/// The child version's lines for do it with me and try one (EXP-14): the instructions that are
/// not the watched step's own line, what is said once a step is done, and what is said to cards
/// put back that are not the two wanted. None says a choice was wrong: two cards that are
/// not the pair are told what they make and what is needed, and the three answer cards put down
/// are recognised as the answer found the direct way.
public enum ThreeCardsDoLine: Equatable, Hashable, Sendable {
    /// Before the first step: "Now let's do one together."
    case intro
    /// "Lifting a card adds it to the total. Tap each card to lift it."
    case add
    /// "Now put back two cards that make 7. Tap a card to put it down.", or, when no two make it
    /// exactly, "No two cards make exactly 6. Put back the two that come closest."
    case drop
    /// Said once all five are up: "All five make 27."
    case added
    /// Said once the two are put back: "2 and 5 make 7."
    case dropped(Int, Int)
    /// The three answer cards put down: "7, 9 and 4 make 20. You found the three we want! The
    /// cards we keep stay up, so let's lift them and put the other two back.", with ", the
    /// closest to 20" when they do not make it exactly. `sum` is what the three make.
    case foundThree(Int, Int, Int, sum: Int)
    /// Said once the cards have swapped: "So 2 and 5 go back. They make 7."
    case swapped(Int, Int)
    /// More than two put back that are not the three answer cards: "Put back just two."
    case justTwo
    /// Two put back that are not the pair: "Those make 14. We need two that make 13.", or "Can
    /// you get closer to 6?" when no two make it exactly.
    case otherPair(sum: Int)
    /// Try one: "Now you try one. Which three cards add up to closest to 18?"
    case tryIntro

    /// Every do line a problem's explainer can say.
    public static func all(for p: ThreeCardsProblem) -> [ThreeCardsDoLine] {
        let n = ThreeCardsProblem.cardCount
        var out: [ThreeCardsDoLine] = [.intro, .add, .drop, .added, .justTwo, .tryIntro]
        for i in 0..<n {
            for j in (i + 1)..<n {
                let (a, b) = (p.cards[i], p.cards[j])
                out += [.dropped(a, b), .swapped(a, b), .otherPair(sum: a + b)]
            }
        }
        let k = p.keep.map { p.cards[$0] }
        out.append(.foundThree(k[0], k[1], k[2], sum: p.result))
        var seen = Set<ThreeCardsDoLine>()
        return out.filter { seen.insert($0).inserted }
    }
}

/// The text the drawing sets that is not a line: the question over the cards, the names of the
/// three written lines, the note under try one, Why?'s labels, and the signs of the equations.
public enum ThreeCardsText: Equatable, Hashable, Sendable, CaseIterable {
    /// "Which three cards add up to closest to 20?"
    case question
    /// The written lines' names: "Add them all", "Too many", "Put back".
    case addLabel
    case overLabel
    case backLabel
    /// Under try one's cards: "Your turn: add them all, find how many too many, put two back."
    case tryNote
    /// Why?'s title, "Why take away 20?", its bars' names, "All five" and "We want", and the
    /// working under the bars, "27 − 20 = 7 too many".
    case whyTitle
    case whyAllName
    case whyWantName
    case whyWork
    /// The signs in the equations: "+", "−", "=".
    case plus
    case minus
    case equals
}

/// The three-cards explainer's wording. There is one version, the
/// learner's.
public struct ThreeCardsWording: Sendable {
    public var line: @Sendable (ThreeCardsLine, ThreeCardsProblem) -> Line
    public var doLine: @Sendable (ThreeCardsDoLine, ThreeCardsProblem) -> Line
    public var text: @Sendable (ThreeCardsText, ThreeCardsProblem) -> String

    public init(
        line: @escaping @Sendable (ThreeCardsLine, ThreeCardsProblem) -> Line,
        doLine: @escaping @Sendable (ThreeCardsDoLine, ThreeCardsProblem) -> Line,
        text: @escaping @Sendable (ThreeCardsText, ThreeCardsProblem) -> String
    ) {
        self.line = line
        self.doLine = doLine
        self.text = text
    }
}
