import ChalkScript
import CoreGraphics
import Foundation

/// The two tens-and-ones explainers (EXP-2, EXP-5, EXP-7): "47 is how many tens and
/// ones?" (`TensOnesQuestion.reading`) and "What number do these make?" (`.writing`), each drawn
/// in the style of the child's own assignment, rectangles and squares or sticks and circles in a
/// Tens | Ones chart. Their steps and timings, in seconds:
///
/// - Each step's line is said first; on the tens and ones steps a pencil ring is drawn round the
///   digit read (on its ink) or the place written (on its slot) as it is said, with the place's
///   name under it, and stays while the step is paused.
/// - bundle (writing, ten or more ones): a box is drawn round ten ones, then an arrow from it to
///   where a new ten will stand; the ten ones fade to ghosts as copies of them, in the trade
///   colour, rise to the arrow, follow it and stack into the new ten one after another; the new
///   ten appears in the trade colour and the copies fade.
/// - tens, ones: each piece in turn (drawn as it is read, when reading) shows its count on
///   itself in a tag ("10, 20 …", then "1, 2 …"), then keeps the counted fill, while the count
///   on the right runs "40" and then "40 + 7". When writing, the digit counted is then written
///   in its place and said ("4 tens."). With no ones, nothing is counted and the line says so.
/// - total: "40 + 7" becomes 47, which pulses, with "40 + 7" left under it; the last line says the
///   whole answer. The parent version counts at 0.4 of the child's pace and shows the counts
///   without saying them (EXP-9).
public struct TensOnesExplainer: Explainer {
    public typealias Step = TensOnesQuestion.Step

    public let question: TensOnesQuestion
    public let version: ExplainerVersion
    public let wording: TensOnesWording
    public let layout: TensOnesLayout
    public let steps: [Step]

    public init(question: TensOnesQuestion, version: ExplainerVersion, wording: TensOnesWording) {
        self.question = question
        self.version = version
        self.wording = wording
        self.layout = TensOnesLayout(question)
        self.steps = question.steps
    }

    public init(reading: TensOnesReading, version: ExplainerVersion, wording: TensOnesWording) {
        self.init(question: .reading(reading), version: version, wording: wording)
    }

    public init(writing: TensOnesWriting, version: ExplainerVersion, wording: TensOnesWording) {
        self.init(question: .writing(writing), version: version, wording: wording)
    }

    public var stepCount: Int { steps.count }
    public var intro: Line { line(.intro) }
    /// The child hears each count; the parent sees the counts and hears the lines (EXP-9).
    public var speaksCounts: Bool { version == .child }

    /// How long counting takes against the child's pace (EXP-9), as the subtraction explainer.
    public static func countPace(_ version: ExplainerVersion) -> Double {
        SubtractionExplainer.countPace(version)
    }

    func line(_ l: TensOnesLine) -> Line { wording.line(l, question) }

    /// The counts shown on the pieces of a step: 10, 20 … for the tens, 1, 2 … for the ones.
    public static func counts(_ q: TensOnesQuestion, _ step: Step) -> [Int] {
        switch step {
        case .tens: (0..<q.tens).map { ($0 + 1) * 10 }
        case .ones: (0..<q.ones).map { $0 + 1 }
        case .bundle, .total: []
        }
    }

    /// The first one counted in the ones step: past the ten ones bundled.
    var onesOffset: Int { question.bundles ? 10 : 0 }

    // MARK: timing (in seconds)

    enum T {
        static let ringDraw = 0.45, wordDelay = 0.3, wordFade = 0.3, lead = 0.6
        static let appear = 0.32, perTen = 0.85, perOne = 0.6, tenTag = 0.8, oneTag = 0.56
        static let beforeWrite = 0.2, write = 0.4, tail = 0.25
        static let box = 0.7, arrow = 0.8, ghostFade = 0.5, travelDelay = 0.2, travelEvery = 0.15, travel = 1.5
        static let tenAppear = 0.45, copiesFade = 0.4, bundleTail = 0.3
        static let beforeJoin = 0.4, pulse = 0.5, workedFade = 0.4
    }

    /// When the tens or the ones step's phases start, counting at `pace` times the child's.
    struct PlaceTimes {
        let pace: Double
        let ticks: [Double]
        let countEnd: Double
        /// When the digit counted is written (writing only).
        let write: Double?
        /// When the digit written is said ("4 tens."), when anything was counted.
        let said: Double?
        let end: Double

        init(_ q: TensOnesQuestion, _ step: Step, pace: Double) {
            self.pace = pace
            let per = pace * (step == .tens ? T.perTen : T.perOne)
            let n = TensOnesExplainer.counts(q, step).count
            ticks = (0..<n).map { T.lead + Double($0) * per }
            countEnd = T.lead + Double(n) * per
            if q.isReading {
                write = nil
                said = nil
                end = countEnd + T.tail
            } else {
                let w = countEnd + T.beforeWrite
                write = w
                said = n > 0 ? w + T.write : nil
                end = w + T.write + T.tail
            }
        }
    }

    /// When the bundle's phases start.
    struct BundleTimes {
        let arrow = T.box
        let copies = T.box + T.arrow
        let ten: Double
        let copiesFade: Double
        let end: Double
        init() {
            ten = copies + T.travelDelay + 9 * T.travelEvery + T.travel
            copiesFade = ten + T.tenAppear
            end = copiesFade + T.copiesFade + T.bundleTail
        }
        func travelStart(_ i: Int) -> Double { copies + T.travelDelay + Double(i) * T.travelEvery }
    }

    /// When "40 + 7" becomes 47 in the total step, and when the step ends.
    struct TotalTimes {
        let join: Double
        let end: Double
        init(_ q: TensOnesQuestion) {
            join = q.ones > 0 ? T.beforeJoin : 0
            end = join + T.pulse
        }
    }

    func placeTimes(_ step: Step) -> PlaceTimes { PlaceTimes(question, step, pace: Self.countPace(version)) }

    public func script(for step: Int) -> StepScript {
        let s = steps[step]
        switch s {
        case .bundle:
            // The line is heard before the box is drawn.
            return StepScript(
                duration: BundleTimes().end,
                events: [StepEvent(0, .say(line(.bundle), caption: true)), StepEvent(0, .waitForVoice)])
        case .tens, .ones:
            let times = placeTimes(s)
            // The ring is drawn as the line is said; the counting waits for the line.
            var events = [StepEvent(0, .say(line(s == .tens ? .tens : .ones), caption: true)), StepEvent(T.lead, .waitForVoice)]
            // Each spoken count waits for the one before it, so the voice counts in time with the
            // pieces (EXP-10). Counts that are only shown (the parent's) wait for nothing.
            if speaksCounts {
                for (n, at) in zip(Self.counts(question, s), times.ticks) {
                    events.append(StepEvent(at, .waitForVoice))
                    events.append(StepEvent(at, .say(line(.tick(n)), caption: false)))
                }
            }
            if let said = times.said {
                events.append(StepEvent(said, .waitForVoice))
                events.append(StepEvent(said, .say(line(.written(s)), caption: false)))
            }
            return StepScript(duration: times.end, events: events)
        case .total:
            let times = TotalTimes(question)
            var events = [StepEvent(0, .say(line(.total), caption: true)), StepEvent(0, .waitForVoice)]
            events.append(StepEvent(times.join, .say(line(question.ones > 0 ? .join : .number), caption: false)))
            events.append(StepEvent(times.end, .waitForVoice))
            events.append(StepEvent(times.end, .say(line(.answer), caption: true)))
            return StepScript(duration: times.end, events: events)
        }
    }

    // MARK: pictures

    public func still(after step: Int) -> Scene { stillPicture(after: step).scene(self) }

    public func scene(step: Int, at t: Double) -> Scene {
        if t >= script(for: step).duration { return still(after: step) }
        return motion(step: step, at: t).scene(self)
    }

    func done(_ s: Step, by step: Int) -> Bool { steps.firstIndex(of: s).map { $0 <= step } ?? false }

    func ring(_ s: Step, progress: Double, word: Double) -> Numeral.Ring? {
        switch s {
        case .tens: Numeral.Ring(digit: 0, progress: progress, word: wording.tensLabel, wordOpacity: word)
        case .ones: Numeral.Ring(digit: 1, progress: progress, word: wording.onesLabel, wordOpacity: word)
        case .bundle, .total: nil
        }
    }

    func stillPicture(after step: Int) -> PlaceValuePicture {
        var p = PlaceValuePicture(self)
        guard step >= 0 else { return p }
        let q = question
        if done(.bundle, by: step) {
            for i in 0..<10 { p.ones[i].opacity = Components.ghostOpacity }
            p.tens[q.tens - 1].opacity = 1
            p.arrow = 1
            p.box = 1
            for i in p.copies.indices { p.copies[i].frame.origin = layout.intoTen(i) }
        }
        if done(.tens, by: step) {
            for i in p.tens.indices {
                p.tens[i].opacity = 1
                p.tens[i].style = .counted
            }
            p.total = String(q.tensValue)
            if !q.isReading { p.digits[0] = written(0) }
        }
        if done(.ones, by: step) {
            for i in onesOffset..<(onesOffset + q.ones) {
                p.ones[i].opacity = 1
                p.ones[i].style = .counted
            }
            p.total = q.ones > 0 ? wording.runningTotal(q.tensValue, q.ones) : String(q.tensValue)
            if !q.isReading { p.digits[1] = written(1) }
        }
        if done(.total, by: step) {
            p.total = String(q.number)
            p.worked = q.ones > 0 ? wording.runningTotal(q.tensValue, q.ones) : nil
        }
        p.ring = ring(steps[step], progress: 1, word: 1)
        return p
    }

    /// Digit `place` (0 tens, 1 ones) written as the answer in its slot.
    func written(_ place: Int, opacity: Double = 1) -> Numeral.Digit {
        let value = place == 0 ? question.tens : question.ones
        return Numeral.Digit(
            text: String(value), role: .answer, opacity: opacity,
            centerX: place == 0 ? layout.tensDigitX : layout.onesDigitX,
            slot: Components.slot(centerX: place == 0 ? layout.tensDigitX : layout.onesDigitX, top: layout.slotTop))
    }

    /// The picture `t` seconds into step `step`, computed from its motion. At the step's
    /// duration it is the step's still picture (EXP-11); `scene(step:at:)` returns the still
    /// itself from then on.
    func motion(step: Int, at t: Double) -> PlaceValuePicture {
        var p = stillPicture(after: step - 1)
        p.ring = nil
        let t = max(0, t)
        let s = steps[step]
        switch s {
        case .bundle: animateBundle(&p, t)
        case .tens, .ones:
            p.ring = ring(s, progress: progress(t, start: 0, duration: T.ringDraw, .easeOut),
                word: progress(t, start: T.wordDelay, duration: T.wordFade))
            animateCount(&p, t, s)
        case .total: animateTotal(&p, t)
        }
        return p
    }

    // MARK: motion, step by step

    func animateBundle(_ p: inout PlaceValuePicture, _ t: Double) {
        let times = BundleTimes()
        let side = Components.oneSide
        guard let ten = layout.bundledTen else { return }
        p.box = progress(t, start: 0, duration: T.box, .easeOut)
        p.arrow = progress(t, start: times.arrow, duration: T.arrow, .easeOut)
        let ghost = progress(t, start: times.copies, duration: T.ghostFade)
        for i in 0..<10 { p.ones[i].opacity = mix(1, Components.ghostOpacity, ghost) }
        let up = CGPoint(x: layout.box.midX - side / 2, y: layout.arrowY - side / 2)
        let over = CGPoint(x: ten.midX - side / 2, y: layout.arrowY - side / 2)
        for i in p.copies.indices {
            let q = progress(t, start: times.travelStart(i), duration: T.travel, .easeInOut)
            p.copies[i].frame.origin = keyframes([(0, layout.ones[i].origin), (0.3, up), (0.65, over), (1, layout.intoTen(i))], q)
            p.copies[i].opacity = t < times.copies ? 0 : 1 - progress(t, start: times.copiesFade, duration: T.copiesFade)
        }
        p.tens[question.tens - 1].opacity = progress(t, start: times.ten, duration: T.tenAppear)
    }

    func animateCount(_ p: inout PlaceValuePicture, _ t: Double, _ s: Step) {
        let times = placeTimes(s)
        let isTen = s == .tens
        let pace = times.pace
        let q = question
        for (j, at) in times.ticks.enumerated() {
            let i = isTen ? j : onesOffset + j
            if q.isReading {
                let a = progress(t, start: at, duration: pace * T.appear)
                if isTen {
                    p.tens[i].opacity = a
                    p.tens[i].frame = layout.tens[i].offsetBy(dx: 0, dy: mix(-14, 0, a))
                } else {
                    p.ones[i].opacity = a
                    p.ones[i].frame = scaled(layout.ones[i], mix(0.4, 1, a))
                }
            }
            if t >= at {
                if isTen { p.tens[i].style = .counted } else { p.ones[i].style = .counted }
                p.total = isTen ? String((j + 1) * 10) : wording.runningTotal(q.tensValue, j + 1)
            }
            let tq = progress(t, start: at, duration: pace * (isTen ? T.tenTag : T.oneTag))
            let opacity = keyframes([(0, 0), (0.2, 1), (0.75, 1), (1, 0)], tq)
            let scale = keyframes([(0, 0.6), (0.2, 1), (1, 1)], tq)
            if isTen {
                p.tenTags[j].opacity = opacity
                p.tenTags[j].scale = scale
            } else {
                p.oneTags[j].opacity = opacity
                p.oneTags[j].scale = scale
            }
        }
        if let w = times.write, t >= w {
            p.digits[isTen ? 0 : 1] = written(isTen ? 0 : 1, opacity: progress(t, start: w, duration: T.write))
        }
    }

    func animateTotal(_ p: inout PlaceValuePicture, _ t: Double) {
        let times = TotalTimes(question)
        guard t >= times.join else { return }
        p.total = String(question.number)
        p.totalScale = keyframes([(0, 1), (0.5, 1.15), (1, 1)], progress(t, start: times.join, duration: T.pulse))
        if question.ones > 0 {
            p.worked = wording.runningTotal(question.tensValue, question.ones)
            p.workedOpacity = progress(t, start: times.join, duration: T.workedFade)
        }
    }

    func scaled(_ r: CGRect, _ s: Double) -> CGRect {
        if s >= 1 { return r }
        return r.insetBy(dx: r.width * (1 - s) / 2, dy: r.height * (1 - s) / 2)
    }
}

/// Everything a tens-and-ones step can show, as values; `scene` turns it into elements with the
/// shared components. The same elements, in the same order, at every moment, so a piece keeps
/// its id through a step.
struct PlaceValuePicture: Equatable {
    struct Piece: Equatable {
        var frame: CGRect
        var style: PieceStyle
        var opacity: Double
    }

    struct Tag: Equatable {
        var text: String
        var rect: CGRect
        var opacity = 0.0
        var scale = 1.0
    }

    var tens: [Piece]
    var ones: [Piece]
    /// The copies of the ten ones a bundle sends into the new ten.
    var copies: [Piece]
    var tenTags: [Tag]
    var oneTags: [Tag]
    var arrow = 0.0
    var box = 0.0
    var digits: [Numeral.Digit]
    var ring: Numeral.Ring?
    var total: String?
    var totalScale = 1.0
    var worked: String?
    var workedOpacity = 1.0

    init(_ e: TensOnesExplainer) {
        let l = e.layout
        let q = e.question
        tens = l.tens.enumerated().map { i, r in
            let bundled = q.bundles && i == q.tens - 1
            return Piece(frame: r, style: bundled ? .traded : .pencil, opacity: q.isReading || bundled ? 0 : 1)
        }
        ones = l.ones.map { Piece(frame: $0, style: .pencil, opacity: q.isReading ? 0 : 1) }
        copies = q.bundles ? l.ones.prefix(10).map { Piece(frame: $0, style: .traded, opacity: 0) } : []
        tenTags = TensOnesExplainer.counts(q, .tens).enumerated().map { j, n in
            Tag(text: e.line(.tick(n)).display, rect: Components.numberTag(on: l.tens[j], ten: true))
        }
        oneTags = TensOnesExplainer.counts(q, .ones).enumerated().map { j, n in
            Tag(text: e.line(.tick(n)).display, rect: Components.numberTag(on: l.ones[e.onesOffset + j], ten: false))
        }
        digits = [(q.tens, l.tensDigitX), (q.ones, l.onesDigitX)].map { value, x in
            q.isReading
                ? Numeral.Digit(text: String(value), role: .printed, centerX: x)
                : Numeral.Digit(
                    text: e.wording.unknown, role: .unknown, centerX: x, slot: Components.slot(centerX: x, top: l.slotTop))
        }
    }

    func scene(_ e: TensOnesExplainer) -> Scene {
        let l = e.layout
        let chart = e.question.drawing == .chart
        var out: [SceneElement] = []
        if chart {
            out.append(SceneElement("heading.tens", .text(e.wording.tensHeading, at: l.tensHeading, style: .heading)))
            out.append(SceneElement("heading.ones", .text(e.wording.onesHeading, at: l.onesHeading, style: .heading)))
            out.append(SceneElement("rule.heading", .rule(from: l.headingRuleFrom, to: l.headingRuleTo)))
            out.append(SceneElement("rule.places", .rule(from: l.placeRuleFrom, to: l.placeRuleTo)))
        } else {
            out.append(SceneElement("label.tens", .text(e.wording.tensLabel, at: l.tensLabel, style: .label)))
            out.append(SceneElement("label.ones", .text(e.wording.onesLabel, at: l.onesLabel, style: .label)))
        }
        out.append(SceneElement("divider", .divider(from: l.dividerFrom, to: l.dividerTo)))
        out.append(SceneElement("numeral", .numeral(Numeral(
            digits: digits, baseline: l.digitBaseline, size: Components.numeralSize, ring: ring,
            wordBaseline: l.placeWordBaseline))))
        func ten(_ p: Piece) -> SceneElement.Kind { chart ? .stick(p.frame, p.style) : .ten(p.frame, p.style) }
        func one(_ p: Piece) -> SceneElement.Kind { chart ? .circle(p.frame, p.style) : .one(p.frame, p.style) }
        for (i, p) in tens.enumerated() { out.append(SceneElement("ten.\(i)", ten(p), opacity: p.opacity)) }
        for (i, p) in ones.enumerated() { out.append(SceneElement("one.\(i)", one(p), opacity: p.opacity)) }
        if e.question.bundles, let newTen = l.bundledTen {
            out.append(SceneElement("box", .box(l.box, progress: box, op: .trade)))
            out.append(SceneElement("arrow", .arrow(
                points: Components.bundleArrow(from: l.box, to: newTen, y: l.arrowY), progress: arrow, op: .trade)))
            for (i, p) in copies.enumerated() { out.append(SceneElement("copy.\(i)", one(p), opacity: p.opacity)) }
        }
        for (i, t) in tenTags.enumerated() {
            out.append(SceneElement("tag.ten.\(i)", .numberTag(t.text, in: t.rect, scale: t.scale), opacity: t.opacity))
        }
        for (i, t) in oneTags.enumerated() {
            out.append(SceneElement("tag.one.\(i)", .numberTag(t.text, in: t.rect, scale: t.scale), opacity: t.opacity))
        }
        out.append(SceneElement("total", .total(total ?? "", at: l.totalAt, scale: totalScale), opacity: total == nil ? 0 : 1))
        out.append(SceneElement("worked", .text(worked ?? "", at: l.workedAt, style: .worked), opacity: worked == nil ? 0 : workedOpacity))
        return Scene(elements: out)
    }
}
