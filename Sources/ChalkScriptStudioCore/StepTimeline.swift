#if os(macOS)
import ChalkScript
import Foundation

/// The text `step.show` returns for the step it plays (section 6.6 of the helper protocol): when
/// each line is said and each action runs, in seconds from the step's start, as the studio plays
/// it with the stand-in voice. It is worked out from the step's script and `ReadingTime`, without
/// playing the step.
enum StepTimeline {
    /// The timeline's text and the step's length as played, in seconds.
    struct Result {
        var text: String
        var length: Double
    }

    /// What the voice does with a step's lines, as the player's runner queues them: a line is said
    /// once the lines before it have been heard, and the clock holds at each wait while the voice
    /// is busy.
    private struct Played {
        struct Said {
            var start: Double
            var end: Double
            var line: Line
            var caption: Bool
        }

        var holds: [(at: Double, length: Double)] = []
        var said: [Said] = []
        var length = 0.0

        init(_ script: StepScript) {
            var offset = 0.0
            var free = 0.0
            for event in script.events {
                let now = event.time + offset
                switch event.action {
                case let .say(line, caption):
                    let start = max(now, free)
                    free = start + ReadingTime.seconds(line)
                    said.append(Said(start: start, end: free, line: line, caption: caption))
                case .waitForVoice:
                    if free > now + 1e-9 {
                        holds.append((event.time, free - now))
                        offset += free - now
                    }
                }
            }
            length = max(script.duration + offset, free)
        }

        /// The played time of step-clock time `t`. An action that starts at a wait begins after
        /// its hold; one that ends there ends before it.
        func played(_ t: Double, starting: Bool) -> Double {
            var shifted = t
            for h in holds where starting ? h.at <= t + 1e-9 : h.at < t - 1e-9 { shifted += h.length }
            return shifted
        }
    }

    static func make(_ explainer: DocumentExplainer, step k: Int) -> Result {
        let step = explainer.resolved.steps[k]
        let played = Played(explainer.script(for: k))
        var rows: [(time: Double, text: String)] = []
        func add(_ time: Double, _ text: String) { rows.append((time, text)) }

        // The lines the script says, matched in order to the resolved lines that name their action.
        let lines = step.lines.filter { $0.spoken || $0.caption }
        var said: [(line: ResolvedLine, said: Played.Said)] = []
        for (line, s) in zip(lines, played.said) where line.entry.entry == s.line.key { said.append((line, s)) }
        var inIterations = Set<String>()
        func collectSays(_ actions: [ResolvedAction]) {
            for a in actions {
                for it in a.iterations {
                    for x in it.actions where x.verb == "say" { inIterations.insert(x.path) }
                    collectSays(it.actions)
                }
            }
        }
        collectSays(step.actions)
        var counted: [String: [Played.Said]] = [:]
        for (line, s) in said {
            guard let path = line.action else {
                add(s.start, lineText(s, who: "line"))
                continue
            }
            if inIterations.contains(path) {
                counted[path, default: []].append(s)
            } else {
                add(s.start, lineText(s, who: name(of: path)))
            }
        }

        let iterationStarts = Set(step.actions.filter { $0.verb == "each" }.flatMap { $0.iterations.map { millis($0.start) } })
        for h in played.holds where h.at == 0 || !iterationStarts.contains(millis(h.at)) {
            let at = played.played(h.at, starting: false)
            add(at, "\(f(at))-\(f(at + h.length)) held for the voice")
        }

        for a in step.actions where a.verb != "say" {
            let start = played.played(a.start, starting: true)
            let end = played.played(a.end, starting: false)
            guard a.verb == "each" else {
                add(start, actionText(a, played))
                continue
            }
            var head = "\(f(start))-\(f(end)) \(a.name) each \(targets(a.targets)), \(a.iterations.count) times"
            if a.waitsForVoice { head += ", each waiting for the voice" }
            add(start, head)
            var empty: [Int] = []
            func flush(until next: Double) {
                guard let first = empty.first, let last = empty.last else { return }
                let from = played.played(a.iterations[first].start, starting: true)
                let span = first == last ? "\(first)" : "\(first)-\(last)"
                add(start, "  \(f(from))-\(f(next)) [\(span)] nothing: every when is false")
                empty = []
            }
            for it in a.iterations {
                let said = it.actions.filter { $0.verb == "say" }.compactMap { x -> String? in
                    guard let s = counted[x.path]?.first else { return nil }
                    counted[x.path]?.removeFirst()
                    return countText(s, who: x.name)
                }
                let parts = it.actions.filter { $0.verb != "say" }.map { actionText($0, played) }
                if it.actions.isEmpty {
                    empty.append(it.index)
                    continue
                }
                let at = played.played(it.start, starting: true)
                flush(until: at)
                let held = it.start > 0 ? played.holds.first { abs($0.at - it.start) < 1e-6 }?.length : nil
                let hold = held.map { "held \(f($0)) for the voice; " } ?? ""
                add(start, "  \(f(at)) [\(it.index)] " + hold + (said + parts).joined(separator: "; "))
            }
            flush(until: end)
        }

        // Rows at one moment keep the order they were added in; an `each`'s rows follow its own.
        let ordered = rows.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element.text)
        var head = "step \(step.name) (\(k + 1) of \(explainer.stepCount))"
        let problem = explainer.problem.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        if !problem.isEmpty { head += ", " + problem }
        head += ": \(f(played.length)) s as played"
        if abs(played.length - step.duration) > 0.05 {
            head += played.holds.isEmpty
                ? ", \(f(step.duration)) s on its own clock; the step ends when its last line has been said"
                : ", \(f(step.duration)) s on its own clock, which stops while held for the voice"
        }
        head += "; ends of lines estimated"
        return Result(text: ([head] + ordered).joined(separator: "\n"), length: played.length)
    }

    private static func actionText(_ a: ResolvedAction, _ played: Played) -> String {
        let start = played.played(a.start, starting: true)
        let end = played.played(a.end, starting: false)
        var row = "\(f(start))" + (end > start ? "-\(f(end))" : "") + " \(a.name) \(a.verb)"
        if !a.targets.isEmpty { row += " " + targets(a.targets) }
        if a.stagger > 0 { row += ", one every \(f(a.stagger))" }
        if let text = a.text, ["tag", "set", "appear"].contains(a.verb) { row += " " + quoted(text.shown) }
        return row
    }

    private static func lineText(_ s: Played.Said, who: String) -> String {
        guard let spoken = s.line.spoken else { return "\(f(s.start)) \(who) shows \(quoted(s.line.display)), not said" }
        return "\(f(s.start))-\(f(s.end)) \(who) says \(quoted(spoken))" + (s.caption ? "" : ", not captioned")
    }

    /// A line said in an `each`'s iteration, whose row already gives its start.
    private static func countText(_ s: Played.Said, who: String) -> String {
        guard let spoken = s.line.spoken else { return "\(who) shows \(quoted(s.line.display)), not said" }
        return "\(who) says \(quoted(spoken)) \(f(s.start))-\(f(s.end))"
    }

    /// The action's name: the last part of its pointer.
    private static func name(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// The targets as names with their runs of indices: `nums[0-11]`, `dot[1,4]`.
    private static func targets(_ instances: [DocumentInstance]) -> String {
        var groups: [(name: String, indices: [Int])] = []
        for t in instances {
            var key = t.element
            switch t.part {
            case let .run(r)?: key += "." + r
            case .cross?: key += ".cross"
            case nil: break
            }
            if groups.last?.name == key, let i = t.index {
                groups[groups.count - 1].indices.append(i)
            } else {
                groups.append((key, t.index.map { [$0] } ?? []))
            }
        }
        return groups.map { g -> String in
            switch g.indices.count {
            case 0: return g.name
            case 1: return "\(g.name)[\(g.indices[0])]"
            default:
                let run = zip(g.indices, g.indices.dropFirst()).allSatisfy { $1 == $0 + 1 }
                return run ? "\(g.name)[\(g.indices[0])-\(g.indices[g.indices.count - 1])]" : "\(g.name)[" + g.indices.map(String.init).joined(separator: ",") + "]"
            }
        }.joined(separator: " + ")
    }

    private static func quoted(_ text: String) -> String { "\"" + text + "\"" }

    private static func millis(_ t: Double) -> Int { Int((t * 1000).rounded()) }

    /// Seconds to a tenth, without a trailing zero.
    private static func f(_ t: Double) -> String {
        let r = (t * 10).rounded() / 10
        return r == r.rounded() ? String(format: "%.0f", r) : String(format: "%.1f", r)
    }
}
#endif
