/// The method explainers (EXP). An explainer is a template filled from a problem's values
/// (EXP-2): it computes every step's drawing as a `Scene` at any moment of the step's motion, and
/// the paced `ExplainerPlayer` (EXP-8) plays the steps one at a time, speaking each step's line
/// through an `ExplainerVoice`. The drawing components in `Drawing/` are shared by every template
/// (EXP-13), in the colours of EXP-6 (`ExplainerPalette`).
///
/// This target is the engine: the drawing components, the players, the style and motion formats,
/// the revision of an explainer and the spoken form of numbers. The explainers are templates in other
/// targets, such as `ChalkScriptExplainers`, that depend on it.
///
/// The child version runs in parts (EXP-8, EXP-14, EXP-15, EXP-16): watch, do it with me, an
/// optional What if?, and try one, with an optional Why? on a step. `GuidedPlayer` and
/// `GuidedView` run them for any explainer that conforms to `GuidedExplainer`; how one plugs in is
/// at the top of Player/GuidedExplainer.swift.
/// The parent version plays the watched steps in `ExplainerPlayer`.
///
/// The package owns no strings. A template is given its wording by the app; the package fills in
/// only numbers, and the spoken form of each number comes from `NumberWords`.
public enum ChalkScript {
    /// Bumped when the package's public surface changes shape.
    public static let moduleVersion = 5
}
