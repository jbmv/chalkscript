import ChalkScript

/// The explainers an approval can be recorded for (EXP-1): one per explainer this package draws.
/// The raw value is the id written in the approvals file the app supplies. The order is the
/// order the consuming app lists them in.
public enum ExplainerID: String, CaseIterable, Sendable {
    case subtraction
    case addition
    case compareTape = "compare-tape"
    case compareGraph = "compare-graph"
    case makeTen = "make-ten"
    case threeCards = "three-cards"
    case tensOnesReading = "tens-ones-reading"
    case tensOnesWriting = "tens-ones-writing"

    /// Whether the explainer has a parent version (EXP-9). The others have only the child's.
    public var hasParentVersion: Bool {
        switch self {
        case .subtraction, .tensOnesReading, .tensOnesWriting: true
        case .addition, .compareTape, .compareGraph, .makeTen, .threeCards: false
        }
    }
}

extension ExplainerApprovals {
    /// Whether `version` of `explainer` for `audience` is approved.
    public func isApproved(_ explainer: ExplainerID, _ audience: ExplainerVersion, version: String) -> Bool {
        isApproved(explainer.rawValue, audience, version: version)
    }
}
