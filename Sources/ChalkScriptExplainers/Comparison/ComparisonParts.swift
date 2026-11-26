import ChalkScript
import CoreGraphics
import Foundation

// What the two comparing explainers share: the tape diagram of a comparing word problem
// (TapeDiagram.swift) and the bar graph (BarGraph.swift).
// Both find a difference the same way: the shorter bar is drawn on, dashed, until it is as long as
// the longer one, and the dashed part is the difference. Here are the parts both use:
// the question with its comparison words tinted, the dashed part and its brace, reading the
// learner's draw-on line, the two equation cards and the adding card's join, and
// What if?'s dragged bar with its goals, snapping and Show me (EXP-15).

/// The word a comparing question asks with: "How many fewer ...", "How many more ...". It
/// follows the amounts (the first-named amount smaller: fewer), except while What if? holds two
/// equal bars, when it stays as it was.
public enum CompareWord: String, CaseIterable, Sendable {
    case fewer
    case more

    /// The word for a first amount `a` against a second `b`; `held` when they are equal.
    public static func asking(_ a: Int, than b: Int, held: CompareWord = .more) -> CompareWord {
        a == b ? held : a < b ? .fewer : .more
    }

    public var flipped: CompareWord { self == .fewer ? .more : .fewer }
}

/// One run of a question set across the drawing. A `tinted` run carries the comparison ("fewer",
/// "than") and sits on take-away's pale tint (EXP-6: the tint comes from the problem's structure,
/// never from its words).
public struct Phrase: Equatable, Sendable {
    public var text: String
    public var tinted: Bool

    public init(_ text: String, tinted: Bool = false) {
        self.text = text
        self.tinted = tinted
    }
}

/// Splits a filled string into phrases at `open` and `close` marks: the text between a pair is
/// tinted. The app fills a question's word and "than" between the marks; the marks never show.
public enum PhraseMarks {
    public static let open = "\u{E010}"
    public static let close = "\u{E011}"

    public static func wrap(_ s: String) -> String { open + s + close }

    public static func phrases(_ marked: String) -> [Phrase] {
        var out: [Phrase] = []
        var rest = Substring(marked)
        while let o = rest.range(of: open) {
            if o.lowerBound > rest.startIndex { out.append(Phrase(String(rest[..<o.lowerBound]))) }
            let after = rest[o.upperBound...]
            guard let c = after.range(of: close) else {
                out.append(Phrase(String(after), tinted: true))
                return out
            }
            out.append(Phrase(String(after[..<c.lowerBound]), tinted: true))
            rest = after[c.upperBound...]
        }
        if !rest.isEmpty { out.append(Phrase(String(rest))) }
        return out
    }
}

// MARK: drawing

/// Builds a picture from the shared components and from shapes and text in palette roles, in
/// scene units, keeping each element's id so tests can follow it.
struct Pen {
    var elements: [SceneElement] = []

    mutating func add(_ id: String, _ kind: SceneElement.Kind, opacity: Double = 1, transform: CGAffineTransform = .identity) {
        elements.append(SceneElement(id, kind, opacity: opacity, transform: transform))
    }

    mutating func shape(_ id: String, _ outline: Outline, _ paint: Paint, opacity: Double = 1, transform: CGAffineTransform = .identity) {
        add(id, .shape(outline, paint), opacity: opacity, transform: transform)
    }

    mutating func line(_ id: String, _ from: CGPoint, _ to: CGPoint, _ paint: Paint, opacity: Double = 1) {
        add(id, .shape(.lines([from, to]), paint), opacity: opacity)
    }

    mutating func words(
        _ id: String, _ text: String, at: CGPoint, size: Double, ink: Ink = .text, display: Bool = true,
        anchor: Typeset.Anchor = .center, opacity: Double = 1, transform: CGAffineTransform = .identity
    ) {
        add(id, .words(text, Typeset(at: at, size: size, ink: ink, display: display, anchor: anchor)), opacity: opacity, transform: transform)
    }

    /// A question across the top: the tints behind its comparison words first, then the words
    /// over them in the text colour. Each
    /// tint is the stage's digit mark on a copy of the line whose runs are all transparent, so it
    /// sits exactly behind its words.
    mutating func question(_ id: String, _ phrases: [Phrase], center: CGPoint, size: Double, tinted: Bool = true) {
        let runs = phrases.map { EquationLine.Run($0.text) }
        if tinted {
            for (i, p) in phrases.enumerated() where p.tinted {
                let hidden = runs.map { EquationLine.Run($0.text, opacity: 0) }
                add("\(id).tint.\(i)", .equation(EquationLine(runs: hidden, mark: .init(run: i, op: .subtract, progress: 1), center: center, size: size)))
            }
        }
        add(id, .equation(EquationLine(runs: runs, center: center, size: size)))
    }

    var scene: Scene { Scene(elements: elements) }
}

/// The comparing explainers' looks, in palette roles (EXP-6).
enum Look {
    /// A bar of the tape diagram (k-bar), and one of the bar graph (k-gbar).
    static let bar = Paint(fill: .sheet, stroke: .pencil, width: 2.4)
    static let graphBar = Paint(fill: .line, stroke: .pencil, width: 2.2)
    /// The dashed part, filled on the tape (k-gap) and open on the graph (k-gap-open), in the
    /// answer's colour: it is what the question asks for.
    static let gap = Paint(fill: .soft(.result), stroke: .ink(.result), width: 2.4, dash: [8, 6])
    static let openGap = Paint(stroke: .ink(.result), width: 2.4, dash: [8, 6])
    /// The braces under an amount and under the dashed part.
    static let brace = Paint(stroke: .muted, width: 2)
    static let gapBrace = Paint(stroke: .ink(.result), width: 2.4)
    /// The dashed pencil line down from where a bar ends.
    static let drop = Paint(stroke: .pencil, width: 2.4, dash: [6, 6])
    /// A card to choose, and the card chosen.
    static let card = Paint(fill: .sheet, stroke: .line, width: 2)
    static let chosenCard = Paint(fill: .soft(.result), stroke: .ink(.result), width: 2.6)
    /// What if?'s handle on the end of the bar the learner drags.
    static let handle = Paint(fill: .sheet, stroke: .ink(.result), width: 2.6)
    static let handleGrip = Paint(stroke: .ink(.result), width: 2)

    static let cardCorner: CGFloat = 14
    static let cardTextSize: Double = 34
    /// How strongly the adding card shows once its join has been shown (k-card.gone).
    static let goneOpacity: Double = 0.35
}

/// A curly brace over `x1`...`x2` at `y`, its point 16 from the bar, away from it: up when `dir`
/// is -1, down when 1.
func brace(_ x1: CGFloat, _ x2: CGFloat, _ y: CGFloat, dir: CGFloat) -> Outline {
    let mid = (x1 + x2) / 2, r = min(10, (x2 - x1) / 4), d = dir * 8
    return .path([
        .move(CGPoint(x: x1, y: y)),
        .quad(to: CGPoint(x: x1 + r, y: y + d), control: CGPoint(x: x1, y: y + d)),
        .line(CGPoint(x: mid - r, y: y + d)),
        .quad(to: CGPoint(x: mid, y: y + 2 * d), control: CGPoint(x: mid, y: y + d)),
        .quad(to: CGPoint(x: mid + r, y: y + d), control: CGPoint(x: mid, y: y + d)),
        .line(CGPoint(x: x2 - r, y: y + d)),
        .quad(to: CGPoint(x: x2, y: y), control: CGPoint(x: x2, y: y + d)),
    ])
}

/// A scale about `origin`, as CSS's transform-origin draws it.
func scaling(_ k: Double, about origin: CGPoint) -> CGAffineTransform {
    CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: k, y: k).translatedBy(x: -origin.x, y: -origin.y)
}

/// An equation set as runs from a format with `EquationSlot` marks ("\u{E000} − \u{E001} =
/// \u{E002}"): the first number, the sign between, the second number, the equals, and the
/// answer, so the sign can take its action's colour and the answer the result's (EXP-5, EXP-6).
/// `sign` is the index of the sign's run, `answer` of the answer's.
func equationRuns(_ format: String, first: String, second: String, answer: String) -> (runs: [String], sign: Int, answer: Int) {
    let a = format.components(separatedBy: EquationSlot.first)
    let head = a.first ?? ""
    let afterFirst = a.dropFirst().joined(separator: EquationSlot.first)
    let b = afterFirst.components(separatedBy: EquationSlot.second)
    let sign = b.first ?? ""
    let afterSecond = b.dropFirst().joined(separator: EquationSlot.second)
    let c = afterSecond.components(separatedBy: EquationSlot.answer)
    let equals = c.first ?? ""
    let tail = c.dropFirst().joined(separator: EquationSlot.answer)
    return ([head + first, sign, second, equals, answer + tail], 1, 4)
}

// MARK: the learner's draw-on line

/// How a line meant to draw the shorter bar on reads: from its end (`xs`) to where the longer bar
/// ends (`xb`), within `tolerance`, on either bar or along the scale. It is read along, not
/// across: it may rise or fall at most `tallest`.
enum DrawOn: Equatable {
    case drawn
    case tapped
    case notAlong
    case startOff
    case short
    case past

    static func read(_ mark: Mark, from xs: CGFloat, to xb: CGFloat, tolerance: CGFloat, tallest: CGFloat) -> DrawOn {
        guard case let .stroke(points) = mark, let first = points.first else { return .tapped }
        let xsP = points.map(\.x), ysP = points.map(\.y)
        let x0 = xsP.min() ?? first.x, x1 = xsP.max() ?? first.x
        let tall = (ysP.max() ?? first.y) - (ysP.min() ?? first.y)
        if tall > tallest { return .notAlong }
        if abs(x0 - xs) <= tolerance && abs(x1 - xb) <= tolerance { return .drawn }
        if abs(x0 - xs) > tolerance { return .startOff }
        return x1 < xb ? .short : .past
    }
}

// MARK: the equation cards

/// The two cards of the equation step: putting the amounts together, or taking one from the
/// other. Adding is the mistake the step expects, so choosing it shows what adding would
/// mean (the join) before the card greys out.
struct Cards: Equatable {
    enum Kind: Equatable { case add, subtract }

    /// Each card and where it is, left to right; which comes first follows the amounts, so the
    /// right card is not always in the same place.
    let cards: [(kind: Kind, rect: CGRect)]

    init(top: CGFloat, addFirst: Bool) {
        let kinds: [Kind] = addFirst ? [.add, .subtract] : [.subtract, .add]
        cards = kinds.enumerated().map { i, k in (k, CGRect(x: 230 + CGFloat(i) * 300, y: top, width: 240, height: 62)) }
    }

    static func == (l: Cards, r: Cards) -> Bool { l.cards.map(\.kind) == r.cards.map(\.kind) && l.cards.map(\.rect) == r.cards.map(\.rect) }

    /// The card a touch lands on, within 6 of it.
    func card(at p: CGPoint) -> Kind? { cards.first { MarkGeometry.inside(p, $0.rect, pad: 6) }?.kind }

    /// The cards drawn: `addGone` greys the adding card, `chosen` fills the take-away card.
    func draw(_ pen: inout Pen, add: String, subtract: String, addGone: Bool, chosen: Bool, transform: (Kind) -> CGAffineTransform = { _ in .identity }) {
        for (kind, r) in cards {
            let id = kind == .add ? "card.add" : "card.subtract"
            let paint = kind == .subtract && chosen ? Look.chosenCard : Look.card
            let opacity = kind == .add && addGone ? Look.goneOpacity : 1
            pen.shape(id, .rect(r, corner: Look.cardCorner), paint, opacity: opacity, transform: transform(kind))
            pen.words("\(id).text", kind == .add ? add : subtract, at: CGPoint(x: r.midX, y: r.minY + 43), size: Look.cardTextSize, opacity: opacity, transform: transform(kind))
        }
    }
}

// MARK: the adding card's join

/// The adding card chosen in a comparison: copies of the two
/// bars slide down and join end to end, outlined in the add colour (EXP-6: a joining motion),
/// with their sum written under the joined bar, so the total is seen to be longer than either bar
/// while the dashed part stays as it was. The joined bar can be up to twice the longer one, so
/// the drawing alone shrinks to fit it, about `origin`, and grows back afterwards; the question
/// and the cards stay full size.
struct Join: Sendable {
    /// The bars joined, in order: where each stands (its top) and how long it is.
    var bars: [(y: CGFloat, width: CGFloat)]
    var origin: CGPoint
    /// Where the joined bar starts, its top, and its height.
    var x0: CGFloat
    var y: CGFloat
    var height: CGFloat
    /// The joined bars' fill (the bars' own) under the add colour's outline.
    var fill: Ink
    /// The most the drawing shrinks to.
    var kMax: Double
    /// The sum written under the joined bar, as runs, and which run is the plus sign.
    var sum: [String]
    var sign: Int

    static let scaleTime = 0.45, slide = 0.9, sumFade = 0.3, hold = 0.3, fadeOut = 0.4

    var length: CGFloat { bars.reduce(0) { $0 + $1.width } }
    /// How far the drawing shrinks: enough for the joined bar to end by 980.
    var k: Double { min(kMax, Double((980 - origin.x) / (x0 + length - origin.x))) }
    var shrinks: Bool { k < 1 }
    var shrunk: Double { shrinks ? Self.scaleTime : 0 }
    func slideStart(_ i: Int) -> Double { shrunk + Double(i) * Self.slide }
    /// The sum is written, and the first line waited for.
    var sumAt: Double { slideStart(bars.count) }
    var heard: Double { sumAt + Self.sumFade }
    /// The second line is heard by then; everything joined fades and the drawing grows back.
    var fadeAt: Double { heard + 0.002 + Self.hold }
    var growAt: Double { fadeAt + Self.fadeOut }
    var end: Double { growAt + shrunk }

    /// Its lines: the first as it begins, the second once the sum is written and the first heard,
    /// and `after` once everything is back as it was.
    func script(_ line1: Line, _ line2: Line, after: Line) -> StepScript {
        StepScript(duration: end, events: [
            StepEvent(0, .say(line1, caption: true)),
            StepEvent(heard, .waitForVoice),
            StepEvent(heard, .say(line2, caption: true)),
            StepEvent(heard + 0.001, .waitForVoice),
            StepEvent(end, .waitForVoice),
            StepEvent(end, .say(after, caption: true)),
        ])
    }

    /// The drawing's scale at `t`.
    func scale(_ t: Double) -> Double {
        guard shrinks else { return 1 }
        if t < growAt { return mix(1, k, progress(t, start: 0, duration: Self.scaleTime, .easeInOut)) }
        return mix(k, 1, progress(t, start: growAt, duration: Self.scaleTime, .easeInOut))
    }

    /// `picture` at `t` of the join: the elements `scaled` picks shrink about `origin`, the joined
    /// bars slide into place inside the shrunk drawing, and the sum is written under them at full
    /// size.
    func apply(to picture: Scene, at t: Double, scaled: (SceneElement) -> Bool, sumSize: Double = 32) -> Scene {
        let dia = scaling(scale(t), about: origin)
        var pen = Pen(elements: picture.elements.map { e in
            guard scaled(e) else { return e }
            var e = e
            e.transform = e.transform.concatenating(dia)
            return e
        })
        guard t < growAt else { return pen.scene }
        let gone = 1 - progress(t, start: fadeAt, duration: Self.fadeOut)
        var x = x0
        for (i, b) in bars.enumerated() {
            let start = slideStart(i)
            if t >= start {
                let p = progress(t, start: start, duration: Self.slide, .easeInOut)
                let move = CGAffineTransform(translationX: (x0 - x + 0) * (1 - p), y: (b.y - y) * (1 - p))
                pen.shape("joined.\(i)", .rect(CGRect(x: x, y: y, width: b.width, height: height), corner: 3),
                    Paint(fill: fill, stroke: .ink(.add), width: 3.2), opacity: gone, transform: move.concatenating(dia))
            }
            x += b.width
        }
        if t >= sumAt {
            let at = CGPoint(
                x: origin.x + (x0 + length / 2 - origin.x) * k, y: origin.y + (y + height - origin.y) * k + 36)
            let fade = progress(t, start: sumAt, duration: Self.sumFade) * gone
            let runs = sum.map { EquationLine.Run($0) }
            pen.add("joined.sum", .equation(EquationLine(runs: runs, mark: .init(run: sign, op: .add, progress: 0), center: at, size: sumSize)), opacity: fade)
        }
        return pen.scene
    }
}

// MARK: What if? (EXP-15)

/// What if?'s picture in both explainers: the first-named amount, which the learner drags by its
/// bar's end, and the question's word, which follows it. The other amount stays still (variation
/// theory: one amount changes, the rest holds).
public struct DraggedBar: Equatable, Sendable {
    public var a: Int
    public var word: CompareWord
    /// A drag began on the bar's row and has not ended.
    public var dragging = false
    /// The last drag ended on the bar, so letting go is checked.
    public var released = false
    /// The third goal's word: the question turned the other way.
    public var flipTo: CompareWord?

    public init(a: Int, word: CompareWord) {
        self.a = a
        self.word = word
    }

    /// Sets the amount, the word following it except at equal bars.
    mutating func set(_ v: Int, other: Int) {
        a = v
        word = CompareWord.asking(v, than: other, held: word)
    }
}

/// One What if? goal: when it is met, where Show me slides the bar, and whether letting go within
/// 2 of that snaps to it (a goal that asks for an exact amount, EXP-15).
struct Goal {
    var met: @Sendable (_ a: Int) -> Bool
    var target: @Sendable (_ a: Int) -> Int
    var snaps: Bool
}

enum WhatIf {
    /// The three goals both explainers set: the bars the same, the dashed part exactly
    /// `exactly`, and the question turned from one word to the other. `range` is the amounts the
    /// bar can be dragged to; `flipBy` is how far past the other bar Show me slides it for the
    /// third goal (at most).
    static func goals(other: Int, exactly: Int, range: ClosedRange<Int>, flipBy: Int, snaps: Bool, flipTo: CompareWord?) -> [Goal] {
        let clamp: @Sendable (Int) -> Int = { v in min(range.upperBound, max(range.lowerBound, v)) }
        let flip = flipTo ?? .fewer
        return [
            Goal(met: { $0 == other }, target: { _ in other }, snaps: snaps),
            Goal(
                met: { abs($0 - other) == exactly },
                target: { a in
                    [other + exactly, other - exactly].filter { range.contains($0) }
                        .min { abs(a - $0) < abs(a - $1) } ?? other + exactly
                },
                snaps: snaps),
            Goal(
                met: { flip == .fewer ? $0 < other : $0 > other },
                target: { _ in
                    clamp(flip == .fewer ? other - min(flipBy, other - range.lowerBound) : other + min(flipBy, range.upperBound - other))
                },
                snaps: false),
        ]
    }

    /// A drag: one that begins on the bar's row (`onRow`) moves its end to the amount under the
    /// finger, one number at a time as the scale reads (`amount`); others are ignored.
    static func drag(_ drag: Drag, _ s: DraggedBar, other: Int, onRow: (CGPoint) -> Bool, amount: (CGPoint) -> Int) -> DraggedBar {
        var n = s
        switch drag {
        case let .began(p):
            n.released = false
            guard onRow(p) else { return n }
            n.dragging = true
            n.set(amount(p), other: other)
        case let .moved(p):
            if n.dragging { n.set(amount(p), other: other) }
        case let .ended(p):
            if n.dragging { n.set(amount(p), other: other) }
            n.released = n.dragging
            n.dragging = false
        }
        return n
    }

    /// The bar is let go (or Show me is tapped): checked against `goal`, snapping when it asks for
    /// an exact amount and the bar is within 2 of it; Show me slides it there and always meets it.
    /// `glide` is the motion from one amount to another; `met` the line once the goal is met.
    static func settle(
        _ goal: Goal, _ s: DraggedBar, showMe: Bool, other: Int, glide: (DraggedBar, DraggedBar) -> Motion,
        met: (DraggedBar) -> Line
    ) -> Settle<DraggedBar> {
        var n = s
        n.dragging = false
        let released = n.released
        n.released = false
        if showMe || (released && !goal.met(n.a) && goal.snaps && abs(n.a - goal.target(n.a)) <= 2) {
            var to = n
            to.set(goal.target(n.a), other: other)
            return Settle(to, motion: to.a == n.a ? nil : glide(n, to), met: met(to))
        }
        guard released, goal.met(n.a) else { return Settle(n) }
        return Settle(n, met: met(n))
    }

    /// The amounts a glide shows and when each appears: one number at a time from `from` to `to`,
    /// each held `hold(left)` seconds, `left` being how far it still has to go.
    static func glideTimes(from: Int, to: Int, hold: (Int) -> Double) -> (values: [Int], times: [Double], duration: Double) {
        var values: [Int] = []
        var times: [Double] = []
        var t = 0.0
        var a = from
        while a != to {
            a += to > a ? 1 : -1
            values.append(a)
            times.append(t)
            t += hold(abs(to - a))
        }
        return (values, times, t)
    }

    /// A glide as a motion over `picture`: the bar slides one number at a time.
    static func glide(_ from: DraggedBar, _ to: DraggedBar, other: Int, hold: @escaping (Int) -> Double, picture: @escaping @Sendable (DraggedBar) -> Scene) -> Motion {
        let g = glideTimes(from: from.a, to: to.a, hold: hold)
        let (values, times) = (g.values, g.times)
        let start = from
        let end = to
        return Motion(script: StepScript(duration: g.duration, events: []), picture: { t in
            guard let i = times.lastIndex(where: { $0 <= t }) else { return picture(start) }
            if i == values.count - 1 { return picture(end) }
            var s = start
            s.set(values[i], other: other)
            return picture(s)
        })
    }
}
