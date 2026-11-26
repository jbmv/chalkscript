import ChalkScript

extension SubtractionExplainer {
    /// The problems whose explainers the version is computed over: the range's edges and
    /// examples of every shape of step list and the widest count.
    public static let versionSamples: [(Int, Int)] = [
        (10, 1), (10, 9), (10, 10), (11, 1), (19, 9), (20, 1), (20, 11), (50, 20), (54, 26), (83, 12),
        (44, 5), (90, 89), (91, 9), (98, 20), (99, 1), (99, 9), (99, 10), (99, 90), (99, 98), (99, 99),
    ]

    /// The current version of the subtraction explainer for `audience` with `wording` (EXP-1):
    /// its steps, timings and lines, and its motion file's shots and camera moves (EXP-19), so a
    /// change to how the camera frames a step changes the version as a change to a line does.
    public static func currentVersion(
        _ audience: ExplainerVersion, wording: SubtractionWording, motion: ExplainerMotion = SubtractionExplainer.standardMotion
    ) -> String {
        let all = versionSamples.compactMap {
            try? SubtractionExplainer(problem: SubtractionProblem($0.0, minus: $0.1), version: audience, wording: wording, motion: motion)
        }
        return ExplainerFingerprint.of(all, extra: all.map { String(describing: $0.steps) + "\n" + motion.summary })
    }
}

extension TensOnesExplainer {
    public static let readingSamples = [10, 11, 19, 20, 40, 47, 90, 99]
    public static let writingSamples: [(Int, Int)] = [
        (1, 0), (1, 1), (1, 9), (1, 10), (1, 19), (3, 5), (4, 7), (4, 0), (3, 13), (8, 19), (9, 0), (9, 9), (5, 10),
    ]

    /// The current version of the explainer `id` (one of the tens-and-ones ones) for `audience`
    /// with `wording` (EXP-1), over both drawings; nil for an `id` this template does not play.
    public static func currentVersion(_ id: ExplainerID, _ audience: ExplainerVersion, wording: TensOnesWording) -> String? {
        var all: [TensOnesExplainer] = []
        for d in PlaceValueDrawing.allCases {
            switch id {
            case .tensOnesReading:
                all += readingSamples.compactMap { try? TensOnesReading($0, drawing: d) }
                    .map { TensOnesExplainer(reading: $0, version: audience, wording: wording) }
            case .tensOnesWriting:
                all += writingSamples.compactMap { try? TensOnesWriting(tens: $0.0, ones: $0.1, drawing: d) }
                    .map { TensOnesExplainer(writing: $0, version: audience, wording: wording) }
            default: return nil
            }
        }
        return ExplainerFingerprint.of(all, extra: all.map { String(describing: $0.steps) })
    }
}
