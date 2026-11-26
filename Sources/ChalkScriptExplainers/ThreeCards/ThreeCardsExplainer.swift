import ChalkScript
import CoreGraphics
import Foundation

/// Three cards closest to a target. Cards are lifted into the sum and
/// lowered out of it, as cards in a hand are, and one equation above them shows the sum of the
/// cards that are up. The work is written as the three lines the format's "show your work" asks
/// for: add them all, how many too many, and the two cards put back. Its steps and timings, in
/// seconds:
///
/// - read: the question with the plan; the picture holds.
/// - add (counts aloud): the line is said first; then each card rises in turn and the new total
///   is said as it does; the first written line fades in.
/// - over: the second written line fades in (Why? is offered here, EXP-16).
/// - drop: the two cards that make how many too many (or come closest) go down one after the
///   other, filled in take-away's colour; the third written line fades in, their numbers in
///   take-away's ink.
/// - check: the three still up turn the answer's colour, as does the equation above them, and the
///   answer is said.
///
/// Colour (EXP-6): a card that is up is outlined in add's colour (its second cue: it is lifted
/// and joined into the sum, with a plus sign); a card put back is filled in take-away's soft fill
/// with take-away's outline (second cue: it is down while the others are up, and the Put back
/// line names it); the chosen three and the equation above them take the answer's colour (second
/// cue: the equals sign, and the answer line).
///
/// Every picture is drawn from a `ThreeCardsState`, so the child's own taps in do it with me are
/// drawn as made (ThreeCardsGuided.swift).
public struct ThreeCardsExplainer: Sendable {
    public typealias Step = ThreeCardsProblem.Step
    typealias L = ThreeCardsLayout

    public let problem: ThreeCardsProblem
    public let wording: ThreeCardsWording
    public let steps: [Step]

    public init(problem: ThreeCardsProblem, wording: ThreeCardsWording) {
        self.problem = problem
        self.wording = wording
        self.steps = problem.steps
    }

    func line(_ l: ThreeCardsLine) -> Line { wording.line(l, problem) }
    func doLine(_ l: ThreeCardsDoLine) -> Line { wording.doLine(l, problem) }
    func text(_ t: ThreeCardsText) -> String { wording.text(t, problem) }

    // MARK: timing (in seconds)

    enum T {
        /// A card going up or down.
        static let lift = 0.26
        /// Watched adding: the pause after each card rises, while its total is said.
        static let afterLift = 0.52
        static let readHold = 0.5
        /// A written line fading in.
        static let workFade = 0.4
        static let overHold = 0.5
        /// Watched putting back: the pause after each card goes down.
        static let afterDrop = 0.45
        static let checkHold = 0.5
        /// Do it with me: the pause after the fifth card before the first line is written.
        static let beforeWork = 0.4
        /// After the swap, before the line about the two put back.
        static let afterSwap = 0.3
        // Why?
        static let barGrow = 0.9
        static let whyGap = 0.25
        static let dropLine = 0.5
        static let gapGrow = 0.7
    }

    // MARK: state

    /// The state before the first step.
    public var start: ThreeCardsState { ThreeCardsState() }

    /// The state after `step` with every step played as watched; -1 is the state before the first.
    public func state(after step: Int) -> ThreeCardsState {
        var s = start
        if step >= 0 { for k in 0...step { s = apply(steps[k], s) } }
        return s
    }

    /// Step `s` as the watched explainer does it, from `state`: every card lifted in order, then
    /// the two that come closest to how many too many put back.
    public func apply(_ s: Step, _ state: ThreeCardsState) -> ThreeCardsState {
        var n = state
        switch s {
        case .read: break
        case .add:
            n.up = state.up + (0..<ThreeCardsProblem.cardCount).filter { !state.up.contains($0) }
            n.added = n.up
            n.work = max(n.work, 1)
        case .over: n.work = max(n.work, 2)
        case .drop:
            let pair = [problem.best.i, problem.best.j]
            n.down = pair
            n.up = state.up.filter { !pair.contains($0) }
            n.work = 3
        case .check: n.done = true
        }
        return n
    }

    /// The card a touch at `point` lands on, as the cards stand in `s`.
    func card(at point: CGPoint, _ s: ThreeCardsState) -> Int? {
        (0..<ThreeCardsProblem.cardCount).first {
            MarkGeometry.inside(point, L.card($0, lift: s.up.contains($0) ? 1 : 0), pad: L.touchPad)
        }
    }

    // MARK: pictures

    enum Look: Equatable {
        /// Resting on the tray, in pencil.
        case plain
        /// Lifted into the sum: outlined in add's colour.
        case up
        /// Put back: take-away's soft fill and outline.
        case back
        /// One of the three chosen: the answer's soft fill and outline.
        case chosen
    }

    /// A number or a sign in a written line, and its ink.
    struct Token: Equatable {
        var text: String
        var ink: Ink
        var sign: Bool
    }

    /// Everything a three-cards picture shows, as values; `scene` turns it into elements.
    struct Pose {
        var lift: [Double]
        var look: [Look]
        /// The cards in the equation above them, in the order they went up.
        var sum: [Int]
        var sumAnswer: Bool
        var work: [[Token]]
        var workOpacity: [Double]
    }

    /// The still pose of `s`.
    func pose(_ s: ThreeCardsState) -> Pose {
        let n = ThreeCardsProblem.cardCount
        return Pose(
            lift: (0..<n).map { s.up.contains($0) ? 1 : 0 },
            look: (0..<n).map { i in
                if s.up.contains(i) { return s.done ? .chosen : .up }
                return s.down.contains(i) ? .back : .plain
            },
            sum: s.up, sumAnswer: s.done,
            work: (0..<3).map { workTokens($0, s) },
            workOpacity: (0..<3).map { $0 < s.work ? 1 : 0 })
    }

    /// The cards at `places` as an equation: one card alone until there are two, then the cards
    /// joined with plus signs and their sum.
    func equation(_ places: [Int], number: Ink, sum: Ink) -> [Token] {
        guard !places.isEmpty else { return [] }
        var out: [Token] = []
        for (n, k) in places.enumerated() {
            if n > 0 { out.append(Token(text: text(.plus), ink: .text, sign: true)) }
            out.append(Token(text: String(problem.cards[k]), ink: number, sign: false))
        }
        if places.count > 1 {
            out.append(Token(text: text(.equals), ink: .text, sign: true))
            out.append(Token(text: String(problem.sum(places)), ink: sum, sign: false))
        }
        return out
    }

    /// Written line `n`: all five added in the order they went up; the total less the target;
    /// the cards put back, their numbers in take-away's ink as the cards are filled. The too-many
    /// number stays in ink: Why? draws it as the dashed part in the answer's colour.
    func workTokens(_ n: Int, _ s: ThreeCardsState) -> [Token] {
        switch n {
        case 0:
            return equation(s.added.isEmpty ? Array(0..<ThreeCardsProblem.cardCount) : s.added, number: .text, sum: .text)
        case 1:
            let p = problem
            return [
                Token(text: String(p.total), ink: .text, sign: false), Token(text: text(.minus), ink: .text, sign: true),
                Token(text: String(p.target), ink: .text, sign: false), Token(text: text(.equals), ink: .text, sign: true),
                Token(text: String(p.over), ink: .text, sign: false),
            ]
        default:
            return equation(s.down, number: .ink(.subtract), sum: .text)
        }
    }

    func scene(_ p: Pose) -> Scene {
        var out: [SceneElement] = []
        out.append(SceneElement("question", .words(text(.question), Typeset(at: L.questionAt, size: L.questionSize))))
        out.append(SceneElement("sum", .equation(sumLine(p))))
        out.append(SceneElement("tray", .shape(.lines([L.trayFrom, L.trayTo]), Paint(stroke: .line, width: L.trayWidth))))
        for i in 0..<ThreeCardsProblem.cardCount {
            let r = L.card(i, lift: p.lift[i])
            let paint: Paint =
                switch p.look[i] {
                case .plain: Paint(fill: .sheet, stroke: .pencil, width: L.cardWidth)
                case .up: Paint(fill: .sheet, stroke: .ink(.add), width: L.markedCardWidth)
                case .back: Paint(fill: .soft(.subtract), stroke: .ink(.subtract), width: L.markedCardWidth)
                case .chosen: Paint(fill: .soft(.result), stroke: .ink(.result), width: L.markedCardWidth)
                }
            out.append(SceneElement("card.\(i)", .shape(.rect(r, corner: L.cardCorner), paint)))
            out.append(SceneElement("card.\(i).number", .words(
                String(problem.cards[i]),
                Typeset(at: CGPoint(x: r.midX, y: r.minY + L.cardNumberBaseline), size: L.cardNumberSize))))
        }
        let labels: [ThreeCardsText] = [.addLabel, .overLabel, .backLabel]
        for n in 0..<3 {
            let y = L.workBaselines[n]
            let o = p.workOpacity[n]
            out.append(SceneElement("work.\(n).label", .words(text(labels[n]), Typeset(
                at: CGPoint(x: L.workLabelX, y: y), size: L.workLabelSize, ink: .muted, display: false, anchor: .trailing)),
                opacity: o))
            var x = L.workX
            for (k, t) in p.work[n].enumerated() {
                let room = L.room(t.text, sign: t.sign, size: L.workSize)
                out.append(SceneElement("work.\(n).\(k)", .words(t.text, Typeset(
                    at: CGPoint(x: x + room / 2, y: y), size: L.workSize, ink: t.ink)), opacity: o))
                x += room
            }
        }
        return Scene(elements: out)
    }

    /// The equation above the cards: the sum of the cards that are up, its numbers in the
    /// answer's colour once the three are chosen.
    func sumLine(_ p: Pose) -> EquationLine {
        let role: EquationLine.Role = p.sumAnswer ? .answer : .plain
        var runs: [EquationLine.Run] = []
        for (n, k) in p.sum.enumerated() {
            if n > 0 { runs.append(.init(" \(text(.plus)) ")) }
            runs.append(.init(String(problem.cards[k]), role))
        }
        if p.sum.count > 1 {
            runs.append(.init(" \(text(.equals)) "))
            runs.append(.init(String(problem.sum(p.sum)), role))
        }
        return EquationLine(runs: runs, center: L.sumCenter, size: L.workSize)
    }

    /// The still picture of `s`.
    func drawing(_ s: ThreeCardsState) -> Scene { scene(pose(s)) }

    // MARK: motion

    /// A card going up or down, starting at `at`.
    struct Move {
        var card: Int
        var up: Bool
        var at: Double
    }

    /// Sets the height of each card whose move has started by `t`, part way while it moves.
    func lift(_ p: inout Pose, _ moves: [Move], at t: Double) {
        for m in moves where t >= m.at {
            let q = progress(t, start: m.at, duration: T.lift, .easeOut)
            p.lift[m.card] = m.up ? q : 1 - q
        }
    }

    /// Step `step` played from `s0`: its lines and timings, and the picture at any moment.
    func watchMotion(_ step: Int, from s0: ThreeCardsState, to s1: ThreeCardsState) -> Motion {
        let e = self
        switch steps[step] {
        case .read:
            return .still(drawing(s0), saying: [line(.read)], duration: T.readHold)
        case .add:
            // Each card rises and its total is said; the next waits for it to be heard, so the
            // voice counts in time with the cards (EXP-10).
            let rising = s1.up.filter { !s0.up.contains($0) }
            let every = T.lift + T.afterLift
            let starts = rising.indices.map { Double($0) * every }
            let workAt = Double(rising.count) * every
            let duration = workAt + T.workFade
            var events = [StepEvent(0, .say(line(.add), caption: true))]
            var up = s0.up
            for (n, k) in rising.enumerated() {
                up.append(k)
                if n > 0 { events.append(StepEvent(starts[n], .waitForVoice)) }
                events.append(StepEvent(starts[n] + T.lift, .say(line(.total(problem.sum(up))), caption: false)))
            }
            events.append(StepEvent(workAt, .waitForVoice))
            let moves = zip(rising, starts).map { Move(card: $0, up: true, at: $1) }
            return Motion(
                script: StepScript(duration: duration, events: events),
                picture: { t in
                    if t >= duration { return e.drawing(s1) }
                    var s = s0
                    // A card joins the sum as it starts to rise, not while the clock waits for the voice.
                    for m in moves where t > m.at { s.up.append(m.card) }
                    var p = e.pose(s)
                    e.lift(&p, moves, at: t)
                    p.work[0] = e.workTokens(0, s1)
                    p.workOpacity[0] = progress(t, start: workAt, duration: T.workFade)
                    return e.scene(p)
                })
        case .over:
            let duration = T.workFade + T.overHold
            return Motion(
                script: StepScript(duration: duration, events: [StepEvent(0, .say(line(.over), caption: true))]),
                picture: { t in
                    if t >= duration { return e.drawing(s1) }
                    var p = e.pose(s0)
                    p.work[1] = e.workTokens(1, s1)
                    p.workOpacity[1] = progress(t, start: 0, duration: T.workFade)
                    return e.scene(p)
                })
        case .drop:
            let going = s1.down.filter { !s0.down.contains($0) }
            let every = T.lift + T.afterDrop
            let moves = going.enumerated().map { Move(card: $1, up: false, at: Double($0) * every) }
            let workAt = Double(going.count) * every
            let duration = workAt + T.workFade
            return Motion(
                script: StepScript(duration: duration, events: [StepEvent(0, .say(line(.drop), caption: true))]),
                picture: { t in
                    if t >= duration { return e.drawing(s1) }
                    var s = s0
                    for m in moves where t > m.at {
                        s.up.removeAll { $0 == m.card }
                        s.down.append(m.card)
                    }
                    var p = e.pose(s)
                    e.lift(&p, moves, at: t)
                    p.work[2] = e.workTokens(2, s1)
                    p.workOpacity[2] = progress(t, start: workAt, duration: T.workFade)
                    return e.scene(p)
                })
        case .check:
            // The three turn the answer's colour at once; the answer is said after the check.
            return Motion(
                script: StepScript(duration: T.checkHold, events: [
                    StepEvent(0, .say(line(.check), caption: true)),
                    StepEvent(T.checkHold, .waitForVoice),
                    StepEvent(T.checkHold, .say(line(.answer), caption: true)),
                ]),
                picture: { _ in e.drawing(s1) })
        }
    }

    // MARK: Why? (EXP-16)

    /// Why the target is taken from the total, on the too-many step: the comparison picture the
    /// comparing explainers use (EXP-7). A bar for all five cards and a bar for what we
    /// want; the shorter is drawn on, dashed, to the longer's length, and the dashed part is how
    /// many too many, so the cards put back must make it.
    func whyMotion() -> Motion {
        let p = problem
        let scale = L.whyBarWidth / CGFloat(p.total)
        let x = L.whyBarX
        let h = L.whyBarHeight
        let xt = x + CGFloat(p.target) * scale
        let xa = x + CGFloat(p.total) * scale
        // Each part draws, then says its line, then pauses.
        let allSay = T.barGrow
        let wantAt = allSay + T.whyGap
        let wantSay = wantAt + T.barGrow
        let dropAt = wantSay + T.whyGap
        let gapAt = dropAt + T.dropLine
        let dashedSay = gapAt + T.gapGrow
        let duration = dashedSay + T.whyGap
        let events = [
            StepEvent(allSay, .say(line(.whyAll), caption: true)), StepEvent(allSay, .waitForVoice),
            StepEvent(wantSay, .say(line(.whyWant), caption: true)), StepEvent(wantSay, .waitForVoice),
            StepEvent(dashedSay, .say(line(.whyDashed), caption: true)), StepEvent(dashedSay, .waitForVoice),
        ]
        let (title, allName, wantName, work) = (text(.whyTitle), text(.whyAllName), text(.whyWantName), text(.whyWork))
        let bar = Paint(fill: .sheet, stroke: .pencil, width: Components.pencilWidth)
        return Motion(
            script: StepScript(duration: duration, events: events),
            picture: { t in
                func grown(_ y: CGFloat, _ length: CGFloat, _ start: Double, _ duration: Double) -> CGRect {
                    CGRect(x: x, y: y, width: length * progress(t, start: start, duration: duration, .easeOut), height: h)
                }
                func barElements(_ id: String, _ y: CGFloat, value: Int, name: String, at start: Double) -> [SceneElement] {
                    let shown: Double = t >= start ? 1 : 0
                    let r = grown(y, CGFloat(value) * scale, start, T.barGrow)
                    return [
                        SceneElement("why.\(id).name", .words(name, Typeset(
                            at: CGPoint(x: x - 16, y: y + h / 2 + 8), size: L.whyNameSize, anchor: .trailing)), opacity: shown),
                        SceneElement("why.\(id).bar", .shape(.rect(r, corner: L.whyBarCorner), bar), opacity: r.width > 0 ? 1 : 0),
                        SceneElement("why.\(id).value", .words(String(value), Typeset(
                            at: CGPoint(x: x + CGFloat(value) * scale - 10, y: y + h / 2 + 9), size: L.whyValueSize, anchor: .trailing)),
                            opacity: shown),
                    ]
                }
                var out = [SceneElement("why.title", .words(title, Typeset(at: L.whyTitleAt, size: L.whyTitleSize)))]
                out += barElements("all", L.whyAllY, value: p.total, name: allName, at: 0)
                out += barElements("want", L.whyWantY, value: p.target, name: wantName, at: wantAt)
                let drop = progress(t, start: dropAt, duration: T.dropLine)
                out.append(SceneElement("why.drop", .shape(
                    .lines([CGPoint(x: xa, y: L.whyAllY - 6), CGPoint(x: xa, y: L.whyWantY + h + 6)]),
                    Paint(stroke: .pencil, width: Components.pencilWidth, dash: L.dropDash, progress: drop)),
                    opacity: t >= dropAt ? 1 : 0))
                let gap = CGRect(
                    x: xt, y: L.whyWantY, width: (xa - xt) * progress(t, start: gapAt, duration: T.gapGrow, .easeOut), height: h)
                out.append(SceneElement("why.gap", .shape(
                    .rect(gap, corner: L.whyBarCorner),
                    Paint(fill: .soft(.result), stroke: .ink(.result), width: Components.pencilWidth, dash: L.dashedDash)),
                    opacity: gap.width > 0 ? 1 : 0))
                let whole = CGRect(x: xt, y: L.whyWantY, width: xa - xt, height: h)
                let done: Double = t >= dashedSay ? 1 : 0
                out.append(SceneElement("why.tag", .numberTag(String(p.over), in: Components.numberTag(on: whole, ten: true), scale: 1), opacity: done))
                out.append(SceneElement("why.work", .words(work, Typeset(at: L.whyWorkAt, size: L.workSize)), opacity: done))
                return Scene(elements: out)
            })
    }
}

/// Everything a three-cards picture can show: which cards are up and in what order, the order
/// they were added in, which are put back, how many written lines there are, and whether the
/// three are chosen.
public struct ThreeCardsState: Equatable, Sendable {
    /// The cards up, by place, in the order they went up.
    public var up: [Int] = []
    /// The order all five went up in, for the first written line.
    public var added: [Int] = []
    /// The cards put back, in the order they went down.
    public var down: [Int] = []
    /// How many of the three written lines are shown.
    public var work = 0
    /// The three are chosen: they and the equation above them take the answer's colour.
    public var done = false
    /// The child put down the three answer cards, and they swapped with the other two.
    public var swapped = false

    public init() {}
}
