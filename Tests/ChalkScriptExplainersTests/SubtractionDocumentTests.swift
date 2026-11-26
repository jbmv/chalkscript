import CoreGraphics
import Foundation
import Testing
@testable import ChalkScript
@testable import ChalkScriptExplainers

/// The subtraction document (`docs/format/examples/subtraction.explainer`, EXP-19) against the
/// running `SubtractionExplainer`: for every problem the template accepts, in the learner's and
/// the parent's playback, on the stage and laid out for a tall drawing area, the document's
/// resolved steps, step durations, lines in order and count times are the template's.
struct SubtractionDocumentTests {
    static let document: ExplainerDocument = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/format/examples/subtraction.explainer")
        return ExplainerDocument.read(contentsOf: url).document!
    }()

    /// The two playbacks: the learner's, paced with counts spoken, and the parent's, skippable
    /// with counts shown at the parent's pace (EXP-9).
    static let playbacks: [(ExplainerVersion, String, DocumentPlayback)] = [
        (.child, "everyday", DocumentPlayback(control: .paced, counts: .spoken, countPace: SubtractionExplainer.countPace(.child))),
        (.parent, "formal", DocumentPlayback(control: .skippable, counts: .shown, countPace: SubtractionExplainer.countPace(.parent))),
    ]

    static let tall = CGSize(width: 660, height: 760)
    static let tolerance = 1e-9

    /// The entry a template's line is filled from, with the count it says.
    static func entry(_ key: String) -> String {
        let name = String(key.split(separator: ".").last ?? "")
        if name.hasPrefix("tick(") { return "tick:" + name.dropFirst(5).dropLast() }
        return name
    }

    @Test func theDocumentReadsWithNoFinding() {
        #expect(Self.document.findings.isEmpty, "\(Self.document.findings)")
    }

    @Test func theDocumentsProblemSpaceIsTheTemplates() {
        let space = Self.document.problemSpace() ?? []
        let template = SubtractionProblem.all.map { ["a": DocumentValue.number(Double($0.minuend)), "b": .number(Double($0.subtrahend))] }
        #expect(space == template)
    }

    @Test func everyProblemPlaysAsTheTemplateDoes() throws {
        let clock = ContinuousClock()
        let began = clock.now
        var differences: [String] = []
        var compared = 0
        for problem in SubtractionProblem.all {
            let values: [String: DocumentValue] = ["a": .number(Double(problem.minuend)), "b": .number(Double(problem.subtrahend))]
            for (version, wording, playback) in Self.playbacks {
                for area in [nil, Self.tall] {
                    compared += 1
                    var e = Fixture.explainer(problem.minuend, problem.subtrahend, version)
                    if let area { e = e.laidOut(for: area) }
                    let label = "\(problem) \(version) \(area == nil ? "stage" : "tall")"
                    let d: ResolvedExplainer
                    do {
                        d = try Self.document.resolve(problem: values, wording: wording, playback: playback, area: area)
                    } catch {
                        differences.append("\(label): refused: \(error)")
                        continue
                    }
                    if d.stepNames != e.steps.map(\.rawValue) {
                        differences.append("\(label): steps \(d.stepNames) against \(e.steps.map(\.rawValue))")
                        continue
                    }
                    if Self.entry(e.intro.key) != d.intro?.entry { differences.append("\(label): intro \(d.intro?.entry ?? "-")") }
                    for (k, step) in d.steps.enumerated() {
                        let script = e.script(for: k)
                        if abs(script.duration - step.duration) > Self.tolerance {
                            differences.append("\(label) \(step.name): duration \(step.duration) against \(script.duration)")
                        }
                        let theirs: [(String, Double)] = script.events.compactMap { ev in
                            if case let .say(line, _) = ev.action { (Self.entry(line.key), ev.time) } else { nil }
                        }
                        let ours: [(String, Double)] = step.lines.filter { $0.spoken || $0.caption }.map { l in
                            (l.count ? "tick:\(l.entry.shown)" : l.entry.entry, l.time)
                        }
                        if theirs.map(\.0) != ours.map(\.0) {
                            differences.append("\(label) \(step.name): lines \(ours.map(\.0)) against \(theirs.map(\.0))")
                        } else {
                            for (a, b) in zip(ours, theirs) where abs(a.1 - b.1) > Self.tolerance {
                                differences.append("\(label) \(step.name): line \(a.0) at \(a.1) against \(b.1)")
                            }
                        }
                        if step.name == "count" {
                            let lead = e.lead(k, from: e.state(after: k - 1).shot)
                            let ticks = e.countTimes.ticks.map { $0 + lead }
                            let counts = step.lines.filter(\.count).map(\.time)
                            if counts.count != ticks.count || zip(counts, ticks).contains(where: { abs($0 - $1) > Self.tolerance }) {
                                differences.append("\(label): count times \(counts) against \(ticks)")
                            }
                        }
                    }
                }
            }
        }
        let seconds = Double((clock.now - began).components.seconds) + Double((clock.now - began).components.attoseconds) / 1e18
        print("compared \(compared) resolutions (\(SubtractionProblem.all.count) problems × 2 playbacks × 2 layouts) in \(String(format: "%.1f", seconds)) s")
        #expect(differences.isEmpty, "\(differences.count) differences, the first: \(differences.prefix(10).joined(separator: "\n"))")
    }
}
