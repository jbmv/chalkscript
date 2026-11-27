import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

/// What the subtraction explainer asks of the paced player (EXP-9, EXP-10), on 54 − 26 (six
/// steps). The player's own behaviour is tested in the engine's tests, on a synthetic explainer.
@MainActor
struct PlayerTests {
    /// The parent's count runs at least twice as fast as the learner's, and its counts
    /// are shown, not said; nothing waits on them.
    @Test func theParentsCountIsFasterAndNotSpoken() {
        func count(_ version: ExplainerVersion) -> (frames: Int, said: [String]) {
            let v = RecordingVoice()
            v.instant = true
            let p = ExplainerPlayer(explainer: Fixture.explainer(54, 26, version), voice: v, drivesItself: false)
            // The learner's dots are not controls, so the learner's count is reached step by step.
            if version == .child {
                for _ in 0..<5 {
                    p.primary()
                    p.playToPause(v)
                }
            }
            v.said = []
            if version == .child { p.primary() } else { p.jump(to: 5) }
            return (p.playToPause(v), v.said.map(\.display))
        }
        let child = count(.child)
        let parent = count(.parent)
        #expect(Double(parent.frames) <= Double(child.frames) / 2, "parent \(parent.frames) frames, child \(child.frames)")
        #expect(child.said.contains("10") && child.said.contains("8"))
        #expect(parent.said == ["Let's count what's left.", "20 plus 8 is 28.", "54 minus 26 is 28!"])
    }
}
