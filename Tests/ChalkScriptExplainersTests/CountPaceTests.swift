import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

/// A voice on a clock the test moves: each line lasts as long as its clip, and the speech in it
/// begins `lead` seconds after it starts (the silence before it).
@MainActor
final class ClipVoice: ExplainerVoice {
    struct Clip {
        var lead: Double
        var length: Double
    }

    private(set) var now = 0.0
    private(set) var started: [(line: Line, at: Double)] = []
    private let clip: (Line) -> Clip
    private var current: (end: Double, onFinish: @MainActor () -> Void)?

    init(_ clip: @escaping (Line) -> Clip) { self.clip = clip }

    func length(_ line: Line) -> Clip { clip(line) }

    func say(_ line: Line, onFinish: @escaping @MainActor () -> Void) {
        started.append((line, now))
        current = (now + clip(line).length, onFinish)
    }

    func stop() { current = nil }

    /// Moves the clock to `t`, finishing the line being said once its clip has played.
    func move(to t: Double) {
        now = t
        if let c = current, now >= c.end - 1e-9 {
            current = nil
            c.onFinish()
        }
    }
}

/// In Watch each counted number starts as its piece is lit, at the motion file's
/// pace (perTen, perOne), and waits only while the number before it is still heard.
@MainActor
struct CountPaceTests {
    static let frame = 1.0 / 240

    /// The counted numbers' clips as Kokoro's af_heart plays them trimmed: 0.03 s of silence at
    /// each end.
    static let trimmed: [String: Double] = [
        "one": 0.485, "two": 0.464, "three": 0.526, "four": 0.512, "five": 0.546, "six": 0.528, "seven": 0.574,
        "eight": 0.473, "nine": 0.596, "ten": 0.513, "twenty": 0.676, "thirty": 0.595, "forty": 0.613, "fifty": 0.660,
        "sixty": 0.673, "seventy": 0.712, "eighty": 0.525, "ninety": 0.605,
    ]
    /// The same numbers as made, before trimming: about 0.4 s of silence before the speech.
    static let made: [String: Double] = [
        "one": 1.275, "two": 1.300, "three": 1.350, "four": 1.325, "five": 1.350, "six": 1.250, "seven": 1.400,
        "eight": 1.225, "nine": 1.500, "ten": 1.375, "twenty": 1.525, "thirty": 1.425, "forty": 1.450, "fifty": 1.500,
        "sixty": 1.500, "seventy": 1.575, "eighty": 1.400, "ninety": 1.450,
    ]

    struct Count {
        /// When each number's line started, when its speech was heard, and when its piece was lit.
        var said: [Double] = []
        var heard: [Double] = []
        var lit: [Double] = []
    }

    /// Plays subtraction's watched count step of `a` - `b` in the child version's player, laid
    /// out for an iPad mini's drawing area, and notes each count.
    func watchCount(_ a: Int, _ b: Int, _ voice: ClipVoice) throws -> (Count, SubtractionExplainer) {
        let problem = try SubtractionProblem(a, minus: b)
        let player = GuidedPlayer(
            lesson: SubtractionExplainer.lesson(watching: problem, wording: Fixture.guidedWording()), voice: voice,
            labels: Fixture.guidedLabels, drivesItself: false)
        let area = CGSize(width: 660, height: 760)
        player.layOut(for: area)
        let e = SubtractionExplainer(problem: problem, version: .child, wording: Fixture.guidedWording()).laidOut(for: area)
        let step = try #require(e.steps.firstIndex(of: .count))
        player.jump(toStep: step)
        let counts = SubtractionExplainer.counts(problem).map { NumberWords.replacingNumerals(in: String($0)) }
        let ids = (0..<counts.count).map { $0 < problem.differenceTens ? "count.ten.\($0)" : "count.one.\($0 - problem.differenceTens)" }
        var out = Count(lit: Array(repeating: -1, count: counts.count))
        var t = 0.0
        while player.phase == .playing(step), t < 60 {
            t += Self.frame
            voice.move(to: t)
            player.advance(by: Self.frame)
            for (i, id) in ids.enumerated() where out.lit[i] < 0 {
                if case let .one(_, style)? = player.scene.element(id)?.kind, style == .counted { out.lit[i] = t }
                if case let .ten(_, style)? = player.scene.element(id)?.kind, style == .counted { out.lit[i] = t }
            }
        }
        #expect(player.phase == .paused(step), "the count step plays to its end")
        var from = 0
        for word in counts {
            guard let i = voice.started[from...].firstIndex(where: { $0.line.spoken == word }) else {
                Issue.record("\(word) is never said")
                break
            }
            out.said.append(voice.started[i].at)
            out.heard.append(voice.started[i].at + voice.length(voice.started[i].line).lead)
            from = i + 1
        }
        return (out, e)
    }

    /// Seconds from count `i` to the next at the motion file's pace.
    func per(_ e: SubtractionExplainer, _ i: Int) -> Double {
        e.sec(.count, i < e.problem.differenceTens ? .perTen : .perOne)
    }

    /// A count's lines with `lengths`, and the other lines a long sentence, all with `lead`
    /// seconds of silence before the speech.
    func voice(_ lengths: [String: Double], lead: Double) -> ClipVoice {
        ClipVoice { line in
            ClipVoice.Clip(lead: lengths[line.spoken ?? ""] == nil ? 0.4 : lead, length: lengths[line.spoken ?? ""] ?? 2.0)
        }
    }

    /// With Kokoro's trimmed clips, each number is heard within 0.1 s of its piece being lit,
    /// and the count goes at the motion file's pace: from one number to the next is perTen or
    /// perOne, or the number's own clip where it is longer (seven, by 0.014 s).
    @Test(arguments: [(54, 26), (99, 1), (83, 12), (91, 9), (20, 1), (98, 20)])
    func kokorosCountKeepsTheMotionsPace(a: Int, b: Int) throws {
        let (c, e) = try watchCount(a, b, voice(Self.trimmed, lead: 0.03))
        #expect(c.said.count == c.lit.count && !c.lit.isEmpty)
        for i in c.lit.indices where i < c.heard.count {
            #expect(c.lit[i] >= 0 && abs(c.heard[i] - c.lit[i]) <= 0.1, "\(a) - \(b): count \(i) heard \(c.heard[i]), lit \(c.lit[i])")
        }
        let words = SubtractionExplainer.counts(e.problem).map { NumberWords.replacingNumerals(in: String($0)) }
        for i in 1..<c.said.count {
            let expected = max(per(e, i - 1), Self.trimmed[words[i - 1]] ?? 0)
            #expect(abs(c.said[i] - c.said[i - 1] - expected) <= 2 * Self.frame,
                "\(a) - \(b): \(words[i - 1]) to \(words[i]) took \(c.said[i] - c.said[i - 1]) s, the pace \(expected) s")
        }
        let paced = (0..<(c.said.count - 1)).reduce(0) { $0 + per(e, $1) }
        #expect(c.said.last! - c.said.first! <= paced + 0.05, "\(a) - \(b): the count keeps the motion's pace")
    }

    /// The clips as made, untrimmed, start their speech 0.4 s after the piece is lit: why a
    /// count's clips are trimmed.
    @Test func untrimmedClipsWouldBeHeardLate() throws {
        let (c, _) = try watchCount(54, 26, voice(Self.made, lead: 0.4))
        #expect(zip(c.heard, c.lit).allSatisfy { $0 - $1 > 0.3 })
    }

    /// With the device voice, whose numbers may take longer than the pace allows, the same
    /// rule holds: a number waits only while the one before it is still heard, and its piece is
    /// lit as it is said, never before.
    @Test func theDeviceVoiceKeepsTheSameRule() throws {
        // Longer than perOne (0.56 s) for some ones, shorter than perTen (0.85 s) for the tens.
        let device: [String: Double] = [
            "ten": 0.5, "twenty": 0.6, "one": 0.45, "two": 0.7, "three": 0.75, "four": 0.5, "five": 0.9, "six": 0.4,
            "seven": 0.8, "eight": 0.6,
        ]
        let (c, e) = try watchCount(54, 26, voice(device, lead: 0))
        let words = SubtractionExplainer.counts(e.problem).map { NumberWords.replacingNumerals(in: String($0)) }
        #expect(c.said.count == words.count)
        for i in c.lit.indices where i < c.heard.count {
            #expect(c.lit[i] >= 0 && abs(c.heard[i] - c.lit[i]) <= 0.1, "count \(i) heard \(c.heard[i]), lit \(c.lit[i])")
        }
        var waited = 0
        for i in 1..<c.said.count {
            let pace = per(e, i - 1)
            let line = device[words[i - 1]] ?? 0
            #expect(abs(c.said[i] - c.said[i - 1] - max(pace, line)) <= 2 * Self.frame,
                "\(words[i - 1]) to \(words[i]): \(c.said[i] - c.said[i - 1]) s; pace \(pace), line \(line)")
            if line > pace { waited += 1 }
        }
        #expect(waited == 4, "two, three, five and seven are longer than a one's pace")
    }

    /// The paced player plays the child's count by the same rule: the runner is shared.
    @Test func thePacedPlayerKeepsTheSameRule() throws {
        let problem = try SubtractionProblem(54, minus: 26)
        let e = SubtractionExplainer(problem: problem, version: .child, wording: Fixture.wording())
        let v = voice(["ten": 0.5, "twenty": 0.6, "one": 0.9, "two": 0.4], lead: 0)
        let player = ExplainerPlayer(explainer: e, voice: v, drivesItself: false)
        let step = try #require(e.steps.firstIndex(of: .count))
        // The child's dots are not controls: Watch, then Next after each step, up to the count.
        var t = 0.0
        player.primary()
        while player.currentStep != step, t < 600 {
            while case .playing = player.phase, t < 600 {
                t += Self.frame
                v.move(to: t)
                player.advance(by: Self.frame)
            }
            player.primary()
        }
        #expect(player.phase == .playing(step))
        var lit: [Double] = [-1, -1, -1, -1]
        let ids = ["count.ten.0", "count.ten.1", "count.one.0", "count.one.1"]
        while player.phase == .playing(step), t < 600 {
            t += Self.frame
            v.move(to: t)
            player.advance(by: Self.frame)
            for (i, id) in ids.enumerated() where lit[i] < 0 {
                switch player.scene.element(id)?.kind {
                case let .ten(_, style)?, let .one(_, style)?: if style == .counted { lit[i] = t }
                default: break
                }
            }
        }
        let said = v.started.filter { ["ten", "twenty", "one", "two"].contains($0.line.spoken ?? "") }.map(\.at)
        #expect(said.count == 4)
        for i in 0..<min(4, said.count) { #expect(abs(said[i] - lit[i]) <= 0.1, "count \(i) said \(said[i]), lit \(lit[i])") }
        // "one" is longer than a one's pace: "two" waits for it, and is lit with it.
        if said.count == 4 { #expect(abs(said[3] - said[2] - 0.9) <= 2 * Self.frame) }
    }
}
