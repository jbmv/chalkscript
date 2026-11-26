import ChalkScript

/// The id of each explainer in this package.
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
