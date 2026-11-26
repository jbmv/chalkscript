import Foundation
import Testing
@testable import ChalkScript

// The style file (EXP-19): EXP-6's palette roles with their colours and the motion defaults.

struct StyleFileTests {
    @Test func theStyleFileHoldsEXP6sRolesAndTheMotionDefaults() {
        let s = ExplainerStyle.standard
        #expect(s.issues.isEmpty, "\(s.issues)")
        #expect(s.light == ExplainerPalette.light && s.dark == ExplainerPalette.dark)
        #expect(s.light.colors(.subtract).fill.hex == "#D55E00" && s.dark.colors(.divide).ink.hex == "#6A72D8")
        for kind in MotionKind.allCases { #expect(s.durations[kind] != nil, "\(kind)") }
        #expect(s.easing(for: .draw) == .cubic(0, 0, 0.58, 1) && s.easing(for: .lag) == .linear)
        #expect(s.camera == CameraDefaults(at: 0, duration: 0.9, easing: "smooth", margin: 12, dim: 0.45))
        // A role the format does not have is reported, not used; a colour not written #RRGGBB
        // keeps the base's value.
        let odd = ExplainerStyle.read(Data(##"{ "palette": { "light": { "sparkle": "#FFFFFF", "pencil": "grey" } } }"##.utf8))
        #expect(odd.issues.contains(FormatIssue(.unknown, "palette.light.sparkle", "not part of the format; ignored")))
        #expect(odd.issues.contains { $0.kind == .invalid && $0.path == "palette.light.pencil" })
        #expect(odd.light.pencil == s.light.pencil)
    }
}
