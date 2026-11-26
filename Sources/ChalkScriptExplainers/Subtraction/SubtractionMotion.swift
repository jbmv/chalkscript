import ChalkScript
import CoreGraphics
import Foundation

/// The timed values of subtraction's steps, as its motion file names them (EXP-19,
/// `Resources/subtraction-motion.json`), each with the kind of motion it times. The bundled file
/// gives their values, so the code holds no timings of its own.
enum SubtractionTiming: String, CaseIterable, Sendable {
    // show: the tens drop in one after another, then the ones grow in.
    case tenDrop, tenEvery, oneGrow, oneEvery, onesAfterTens, showTail
    // short, enough, take ones, take tens: the digit acted on is marked.
    case mark
    // short, enough: the pencil loop round the ones, and the hold after it.
    case hint, hintHold, noOnesHold
    // trade: the arrow, the ten splitting into ones, its fade and cross-out, the ones' journey
    // into the box, and the box drawn round them.
    case arrow, cubeAppear, cubeEvery, tenFade, crossDelay, crossDraw, travelDelay, travelEvery, travel, boxDraw, ghostFade
    // take ones, take tens: each piece crossed out and faded, one after another.
    case takeCross, takeFade, takeEvery, takeTail
    // count: what is left copied to the count area and counted, the total and the answer; and,
    // in do it with me, how long a touched piece shows its count and the pause after the last.
    case copy, copyEvery, tenTag, oneTag, perTen, perOne, beforeJoin, pulse, answerFade, nothingLeft, tapTag, afterLast

    var kind: MotionKind {
        switch self {
        case .tenDrop, .oneGrow, .cubeAppear, .tenTag, .oneTag, .pulse, .answerFade, .tapTag: .appear
        case .mark, .hint, .arrow, .crossDraw, .boxDraw, .takeCross: .draw
        case .tenFade, .ghostFade, .takeFade: .fade
        case .travel, .copy: .travel
        case .tenEvery, .oneEvery, .cubeEvery, .travelEvery, .takeEvery, .copyEvery, .perTen, .perOne: .lag
        case .onesAfterTens, .showTail, .hintHold, .noOnesHold, .crossDelay, .travelDelay, .takeTail, .beforeJoin,
            .nothingLeft, .afterLast:
            .hold
        }
    }

    /// The values each step reads.
    static func used(by step: SubtractionProblem.Step) -> [SubtractionTiming] {
        switch step {
        case .show: [.tenDrop, .tenEvery, .oneGrow, .oneEvery, .onesAfterTens, .showTail]
        case .short, .enough: [.mark, .hint, .hintHold, .noOnesHold]
        case .trade: [.arrow, .cubeAppear, .cubeEvery, .tenFade, .crossDelay, .crossDraw, .travelDelay, .travelEvery, .travel, .boxDraw, .ghostFade]
        case .takeOnes, .takeTens: [.mark, .takeCross, .takeFade, .takeEvery, .takeTail]
        case .count: [.copy, .copyEvery, .tenTag, .oneTag, .perTen, .perOne, .beforeJoin, .pulse, .answerFade, .nothingLeft, .tapTag, .afterLast]
        }
    }
}

/// The regions of a subtraction drawing a shot may frame (EXP-18).
public enum SubtractionPart: String, CaseIterable, Sendable {
    /// The worksheet: the tens, the ones, the trade's arrow and box, and the labels under them.
    case worksheet
    /// Every ten on the worksheet.
    case tens
    /// The loose ones and, when a ten is traded, the box its ones go into.
    case ones
    /// The ten the watched explainer breaks (the last), when one is traded.
    case tradedTen
    /// The trade's arrow, from the ten over to the box.
    case arrow
    /// The count area: what is left, copied and counted, and the total under it.
    case count
}

extension SubtractionExplainer {
    /// What subtraction's motion file may hold: its steps' timed values and its parts.
    public static let motionVocabulary = MotionVocabulary(
        steps: Step.allCases.map { step in
            MotionVocabulary.StepValues(step.rawValue, SubtractionTiming.used(by: step).map { ($0.rawValue, $0.kind) })
        },
        parts: SubtractionPart.allCases.map(\.rawValue))

    /// Subtraction's bundled motion file, read against the bundled style.
    public static let standardMotion = ExplainerMotion.bundled("subtraction", vocabulary: motionVocabulary, bundle: ContentBundle.bundle)

    /// Reads a motion file for subtraction against `style` (for tuning in an authoring tool).
    public static func motion(_ data: Data, style: ExplainerStyle = .standard) -> ExplainerMotion {
        ExplainerMotion.read(data, explainer: "subtraction", vocabulary: motionVocabulary, style: style)
    }

    /// Step `s`'s value `n`, in seconds, from the motion file.
    func sec(_ s: Step, _ n: SubtractionTiming) -> Double { motion.seconds(s.rawValue, n.rawValue) }

    /// The curve step `s`'s value `n` is eased along.
    func ease(_ s: Step, _ n: SubtractionTiming) -> Easing { motion.easing(s.rawValue, n.rawValue) }
}
