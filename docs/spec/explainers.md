# ChalkScript specification (EXP)

ChalkScript makes step-by-step visual explanations, called explainers. This document states the requirements that an explainer and the package meet, with the reason for each.

## Scope

- **Covered:** what an explainer shows, how it moves, how it speaks, how it is paced, how the learner takes part, how it is laid out, how its style and motion are stored as data, and how its revision is computed.
- **Not covered:** the application around an explainer. How a learner reaches an explainer, how practice is scored, who an explainer is shown to, and whether it has been reviewed or approved belong to the app that uses it, or to the repository that holds the content.
- **Generality:** the requirements are written for any subject. The explainers in the package today, in the `ChalkScriptExplainers` target, are for early elementary arithmetic; the `ChalkScript` target holds the engine they share. Notes headed *In the package* describe that case, and a requirement worked out only for that case says so.
- **Ids:** each requirement has a stable id, which the code and commit messages cite. The sections are grouped by topic, not by number. A requirement that is replaced or withdrawn stays as a tombstone.
- **Metadata:** `status` and `governs` are `key: value` lines under a heading. `governs` lists the files a requirement chiefly describes.

## Terms

- **Explainer:** a sequence of steps that shows a method or an idea on one problem.
- **Template:** an explainer written once and filled from a problem's values (EXP-2).
- **Style:** a set of design values that every explainer shares and that can be replaced as a whole: colours, easing curves, default durations, and the camera's defaults, including how strongly the rest of the picture is dimmed (EXP-6, EXP-19). A style is not a template.
- **Step:** one change to the picture, with one spoken line.
- **Learner:** the person the explainer is for.
- **Revision:** a fingerprint of everything an explainer shows and says (EXP-1).
- **Part:** a stage of the learner's version: watch, do it with me, What if?, try one (EXP-8, EXP-14, EXP-15).
- **Shot:** a region of the drawing that the camera frames (EXP-18).

## EXP-2. An explainer is a template filled from a problem's values

status: draft
governs: Sources/ChalkScriptExplainers/Subtraction/SubtractionProblem.swift, Sources/ChalkScriptExplainers/PlaceValue/TensOnesProblem.swift

An explainer is written once as a template. Its drawing, motion, narration and numbers all come from a small model of the problem. The template declares the values it accepts, and its steps may depend on them.

**Why:** one template serves every problem of its kind. A value that is computed cannot disagree with the problem.

**Acceptance:**
- Every number drawn, shown or spoken is computed from the model. A template has no typed numbers.
- A value outside the declared range is refused, and no explainer is made for it.
- A template's tests play every step for values at the edges of its range.

*In the package:* the subtraction template takes two numbers and shows a trade only when one is needed.

## EXP-3. A template can make another problem of the same kind

status: draft

A template can produce a problem of the same kind and the same case as a given one, with different numbers and a different answer.

**Why:** a worked example followed by an attempt on an equivalent problem is a studied sequence (Renkl, Atkinson and colleagues 2000 to 2003).

**Acceptance:**
- A template can produce another problem of the same kind and case, with different numbers and a different answer.
- In the guided presentation, the problems watched, done together and tried alone differ from one another.

*In the package:* `isomorph(_:)` on a problem model, and `GuidedLesson`, which holds the problems of the parts. Which problem an app shows, and when it offers an explainer, are the app's.

## EXP-7. An explainer can use the representation its learners already work with

status: draft

Where learners already work with a representation, an explainer can animate that representation as they are asked to draw it, rather than substitute a different model. Where material shows one idea in more than one way, the template takes the representation as one of its values.

**Why:** the explainer then rehearses the work the learner will do.

**Acceptance:**
- A template whose subject has more than one common representation takes the representation as a value.
- Each representation a template offers follows a stated convention for its pieces, marks and layout.

*In the package:* base-ten drawings in the common worksheet convention (a tall rectangle for a ten, a small square for a one, a crossed line for taking away, a box for a traded ten), tape diagrams and bar graphs. Tens and ones are drawn either as rectangles and squares or as sticks and circles in a chart. Which representation a learner sees is chosen by the author or the app.

## EXP-5. Every motion shows what happens to which quantity

status: draft
governs: Sources/ChalkScriptExplainers/Subtraction/SubtractionExplainer.swift, Sources/ChalkScriptExplainers/Subtraction/SubtractionLayout.swift, Sources/ChalkScriptExplainers/PlaceValue/TensOnesExplainer.swift, Sources/ChalkScriptExplainers/PlaceValue/TensOnesLayout.swift

Each step changes one thing and shows what the change does to the quantities. Nothing is erased: what is traded or taken away stays as a faded ghost with its mark. A result is built in view, by moving and counting the pieces that make it. The part of the problem a step acts on is marked while the step runs.

**Why:** marking what matters, and little else, directs attention (the signalling principle; Mayer).

**Acceptance:**
- A piece that is traded divides into its parts, which travel to their new place. The original stays as a crossed-out ghost.
- A piece that is taken away is crossed out and fades to a ghost. It is not removed.
- A result is counted in view, and each counted piece stays marked as counted.
- A step marks at most two things, or three when it compares two amounts.
- A mark stays while its step is paused.

## EXP-6. Colour means an operation, the same in every explainer

status: draft
governs: Sources/ChalkScript/Drawing/Palette.swift, Sources/ChalkScript/Resources/style.json

Each operation has one colour and a second cue that does not depend on colour. A colour always says which operation is happening. The roles are fixed. Their values come from the style file (EXP-19).

| Meaning | Light (fill) | Light (ink) | Dark | Second cue |
|---|---|---|---|---|
| subtract, take away | #D55E00 | #D55E00 | #F08A4B | the cross-out line; the minus sign |
| trade, regroup | #CC79A7 | #A04676 | #D28CA9 | the arrow and the box |
| what is left, the answer | #0072B2 | #0072B2 | #5AA7E0 | the count area; the equals sign |
| add, join | #4D6B43 | #4D6B43 | #95E3A5 | a joining motion; the plus sign |
| multiply, groups of | #6B4301 | #6B4301 | #FED252 | rings around equal groups |
| divide, share | #3937A2 | #3937A2 | #6A72D8 | dealing into equal groups |

Subtract, the answer and the fill for trade are Okabe-Ito colours. Add, multiply and divide leave that set. A thin stroke must keep 3:1 contrast with the sheet, and within that range the set's remaining colours could not be told apart from the others under a simulated deficiency.

**Why:** a colour with one meaning is learned once. Red-green colour vision deficiency is common, so the palette is checked with a simulation and every colour has a second cue. Colour follows the problem's structure and not its words, because key-word rules fail ("5 more than" can require addition).

**Acceptance:**
- An operation's colour comes from the problem's structure, never from its wording.
- Every coloured mark has its second cue. An explainer reads correctly in greyscale.
- Pieces are drawn in pencil and are not coloured by place value.
- Thin strokes and text use the ink value, which keeps at least 3:1 contrast with the paper.
- Any two colours shown together stay at least 20 apart (CIE76 in CIELAB, D65), with normal vision and under simulated protanopia, deuteranopia and tritanopia (Machado, Oliveira and Fernandes 2009), in light and dark. A test checks this for the colours each explainer draws.
- Every colour drawn is one of these roles, resolved from the style. A style with other values changes every colour, with no change to an explainer's code, and is held to the same checks.

*In the package:* `ExplainerStyle` reads `Resources/style.json`; `ExplainerPalette.light` and `.dark` are the bundled values.

## EXP-13. One visual language across explainers

status: draft
governs: Sources/ChalkScript/Drawing/Components.swift, Sources/ChalkScript/Drawing/Scene.swift, Sources/ChalkScript/Drawing/Stage.swift, Sources/ChalkScript/Drawing/Timing.swift

Explainers share their drawing components. How a drawn representation looks (in the package, pencil on paper) is set by the components and the style, not by each explainer. Colour follows EXP-6.

**Why:** explainers are designed one at a time, and shared components keep them consistent.

**Acceptance:**
- An explainer uses the shared components and does not define its own versions of them.

*In the package:* pencil pieces, stick, circle, ghost, cross-out, arrow, box, count area, number tag, the written number and its ring, and block. Type faces are given by the app (`ExplainerFonts`).

## EXP-11. Motion is slow enough to follow and has a still alternative

status: draft

One change happens at a time. A piece moves only where the motion carries meaning, which is where a quantity changes form or place. Everything else appears or fades in place. With Reduce Motion on, each step shows its finished picture with the change marked.

**Why:** animation rarely improves on equivalent still pictures unless it shows a change the stills cannot (Tversky, Morrison and Bétrancourt 2002).

**Acceptance:**
- With Reduce Motion on, each still picture shows the same ghosts, marks and counts as the end of the motion.
- No step runs two unrelated motions at once.
- A mark or a label never travels.
- A camera move (EXP-18) and a step's own motion never run at once.

## EXP-18. A camera frames what each step acts on

status: draft
governs: Sources/ChalkScript/Drawing/Camera.swift, Sources/ChalkScriptExplainers/Subtraction/SubtractionMotion.swift

An explainer may show its drawing through a camera. Each step names a shot, and the view eases to it. What is out of shot is dimmed, not cropped. The statement of the problem stays fixed outside the camera. Only the explainer moves the camera.

**Why:** on a small screen, the pieces of a whole drawing are too small to mark. Narration given with the picture it describes is better understood than narration before or after it (Mayer and Anderson 1991; Ginns 2006), so the camera moves while the line that introduces a shot is said.

**Acceptance:**
- A step's shot and the camera's move to it come from the motion file (EXP-19). A step that names no shot keeps the current one.
- The centre of the view moves in a straight line, and its size changes geometrically.
- A shot of the whole drawing dims nothing. The problem is never dimmed.
- Touches are read through the camera, in the drawing's units.
- Where the learner marks a piece, the piece and its margin are a target at least 44 points across at the moment of asking.
- No mark is read until the camera has landed. A touch on the drawing holds any camera move until it lifts.
- With Reduce Motion on, the camera cuts to each shot.

*In the package:* `Camera` and `CameraPlan`; a `Scene` carries its camera, and `ExplainerStage` draws through it. Subtraction has five shots in `subtraction-motion.json`, which is a resource of the `ChalkScriptExplainers` target. Its smallest target on an iPad mini is about 45 points, which a test checks.

## EXP-10. Every step has one spoken line, shown as it is spoken

status: draft
governs: Sources/ChalkScript/NumberWords.swift, Sources/ChalkScriptExplainers/Subtraction/SubtractionWording.swift, Sources/ChalkScriptExplainers/PlaceValue/TensOnesWording.swift

Each step has one line, which is spoken and shown as text. A template is given its lines from outside the Swift source, and the package fills in the numbers and their spoken forms.

**Why:** a learner who is still learning to read can follow a spoken line. Speech and picture are understood better together (Mayer and Anderson 1991; Ginns 2006).

**Acceptance:**
- Spoken numbers are generated for every value a template accepts.
- With narration muted, the shown line and the pacing still carry the explainer.
- A step that counts aloud says its line first and then moves, so that each number goes with the piece it counts. Other steps move while the line is said.
- A step's line is ready before the step starts. The control that starts a part waits until the part's first line can be said at once.
- Every line of a part is heard to its end.
- One voice reads every line of an explainer.

*In the package:* `ExplainerVoice` is the protocol an app's voice meets; `SilentVoice` is the muted case; `NumberWords` gives the spoken form of a number.

## EXP-8. The learner sets the pace, step by step

status: draft
governs: Sources/ChalkScript/Player/Player.swift, Sources/ChalkScript/Player/ExplainerView.swift

In the watched part, each step plays its motion and speaks its line. It then stops on its finished picture and waits. Next plays the following step. Again replays the current step, or goes back one step when pressed while a step plays. Dots show progress.

The learner's version runs in parts: watch (this requirement), do it with me (EXP-14), an optional What if? (EXP-15), and try one.

**Why:** nothing runs ahead of the learner.

**Acceptance:**
- In the watched part, no step starts until the learner asks for it.
- Next is hidden while a step plays.
- The controls are large enough for touch and are labelled for VoiceOver.
- The dots, the drawing, the line and the controls fit on one screen without scrolling (EXP-17).

## EXP-14. The learner makes the key marks, with help on request

status: draft

After watching, the learner carries out the method on a second problem of the same kind. Each step's line says what to do, and the learner makes that step's marks on the drawing. Show me plays the step instead. The part runs on without a Next control. Support fades backward: at first the learner makes only the last step's marks, and on each return makes one step more.

**Why:** worked examples that fade backward improve near transfer (Renkl, Atkinson and colleagues 2000 to 2003). Manipulatives help when the activity is guided (Carbonneau, Marley and Selig 2013).

**Acceptance:**
- A step the learner does waits for the learner's marks, or for Show me.
- The instruction is heard before the learner can act. Marks made while it is being said are ignored.
- A mark is read against the drawing: a stroke across a piece crosses it out, and a touch counts it. No handwriting is recognised.
- A wrong mark is met with a kind line and a count together. There is no mark or sound of failure. After a second miss, Show me is offered in the line.
- Which steps the learner does is computed from how many times the learner has done the explainer. The app keeps that count.
- With Reduce Motion on, Show me shows the finished picture.

*In the package:* `GuidedPlayer` and `GuidedView` run the parts for any explainer that conforms to `GuidedExplainer`.

## EXP-15. What if?: the learner changes the picture toward a few goals

status: draft

An explainer about a relationship between quantities may add a What if? part. The learner changes one quantity in the picture, and everything that depends on it follows at once. The part sets two or three goals in turn.

**Why:** linking a picture and its numbers so that they change together supports learning (Moyer-Packenham and Westenskow 2013, 2016). Varying one aspect while the rest holds still makes that aspect noticeable (Marton and Booth 1997). Guided discovery helps and unguided discovery does not (Alfieri et al. 2011), which is the reason for goals.

**Acceptance:**
- Every number shown follows the quantity the learner changes, within the template's range.
- A goal is checked when the learner lets go, not while dragging. There is no failure message.
- Show me moves the picture to the goal, and the goal then counts as met.
- Once a goal is met, the picture holds still while the line about it is said.

*In the package:* the comparison explainers, in which the learner drags the end of a bar.

## EXP-16. A step may offer an optional Why?

status: draft

A step of the watched part may offer a short explanation of why it is done. It plays over the drawing with its own pictures and lines, and returns to the step exactly as it was. It is not a step, and the dots do not change.

**Why:** guidance that helps a novice slows a learner who already understands (Kalyuga et al. 2003). Prompts to explain improve transfer from worked examples (Atkinson, Renkl and Merrill 2003). Help on demand is used when it is near and specific (Aleven et al. 2003).

**Acceptance:**
- Why? is offered only on steps that declare one, and only while the step is paused.
- Closing it restores the step's picture and line.
- A Why? meets the same requirements as a step.

## EXP-9. A second audience gets the same steps with its own wording and controls

status: draft

An explainer may have a version for a person helping the learner. It uses the same steps with wording for that reader, and may name the method by its formal term. This reader can skip: Next finishes a playing step at once, and the dots jump to any step. A count is shown and not spoken, and runs faster.

**Why:** a helper needs the method and its vocabulary, and does not need the pacing.

**Acceptance:**
- In this version the dots are controls. In the learner's version they are not.
- Next is available while a step plays and finishes it on its final picture.
- This version has no do it with me and no What if?.

*In the package:* the `parent` case of `ExplainerVersion`. Subtraction and tens and ones have this version; the other explainers do not yet. Its count runs at 0.4 of the learner's durations.

## EXP-17. The screen adapts to its space and to the writing hand

status: draft
governs: Sources/ChalkScript/Player/ScreenLayout.swift, Sources/ChalkScript/Player/GuidedView.swift

The screen is arranged by the space it is given, not by the device. In a tall space the question is at the top, the drawing in the middle, and the line and controls at the bottom. In a wide space one column holds the question, line and controls, on the side that the writing hand covers. The drawing takes the remaining space, and its size is given to the explainer.

**Why:** the drawing is where the learner works, so it gets the space. A resting palm must not press a control.

**Acceptance:**
- The arrangement is chosen from the space given. Both arrangements fit without scrolling.
- A drawing not laid out for its area is scaled to fit and centred. It is never cropped or stretched.
- Handedness is right or left, and right by default.
- While a touch is on the drawing, and for one second after, the column's controls ignore presses.

*In the package:* `ScreenLayout`, `WritingHand` and `PalmGuard`. Subtraction is laid out again for a tall area; the other explainers are scaled to fit.

## EXP-12. Explainers are drawn at run time from the template's model

status: draft

An explainer is a vector drawing, rendered and animated on the device from the template's model. It is not a recording. It plays with the network off.

**Why:** the values change with each problem (EXP-2), which a fixed recording cannot follow.

**Acceptance:**
- An explainer plays with no network.
- One template renders every version, on iOS and macOS.

Export of an explainer to a video file is not built.

## EXP-19. Motion and style are data, in one documented format

status: draft
governs: Sources/ChalkScript/Style/ExplainerStyle.swift, Sources/ChalkScript/Style/ExplainerMotion.swift, Sources/ChalkScript/Style/FormatReading.swift, Sources/ChalkScriptExplainers/Resources/subtraction-motion.json

Colours, motion defaults, shots and timings are data that the package reads. There are two kinds of file, both JSON: one style file, and a motion file for each explainer. Every value is optional. A missing value takes its default, an unknown key is ignored, and an unreadable value takes its default. Each such case is listed with its path, and none stops the file from being read.

**Why:** a person or a tool can then adjust an explainer without changing code. A wrong value is reported and does not fail silently.

The style file (`style.json`):

| Key | Holds |
|---|---|
| `format`, `version` | `"explainer-style"`, `1`. |
| `palette.light`, `palette.dark` | The roles of EXP-6 as `#RRGGBB`: `paper`, `sheet`, `text`, `muted`, `line`, `pencil`, `onResult`, and for each operation (`subtract`, `trade`, `result`, `add`, `multiply`, `divide`) its `fill`, `ink` and `soft`. |
| `easings` | Named curves, each a cubic bezier `[x1, y1, x2, y2]`. `linear` always exists. |
| `motion.durations` | Default seconds for each kind of motion: `appear`, `draw`, `fade`, `travel`, `lag`, `hold`. |
| `motion.easings` | The default curve, by name, for `appear`, `draw`, `fade` and `travel`. |
| `motion.camera` | Camera defaults (EXP-18): `at`, `duration`, `easing`, `margin`, `dim`. |

A motion file (`<explainer>-motion.json`):

| Key | Holds |
|---|---|
| `format`, `version`, `explainer` | `"explainer-motion"`, `1`, and the explainer's name. |
| `shots.<name>` | A shot: `frame` (the named parts of the drawing it shows), `region` (`[x, y, width, height]` in the drawing's units) and `margin`. |
| `opening` | The shot before the first step. |
| `steps.<step>` | `shot`; `doShot`, the shot the learner acts in where it differs; `camera` (`at`, `duration`, `easing`); `durations`; `easings`. |

**Acceptance:**
- A style with other values changes every colour drawn, with no change to code.
- A value left out of a motion file falls back to the style, and a value left out of a style to the bundled style.
- A missing, unknown or unreadable value is listed with its path.
- The bundled files name nothing unknown and nothing unreadable.

*In the package:* `ExplainerStyle`, `ExplainerMotion`, `FormatReader` and `FormatIssue`. `ExplainerMotion.bundled` reads a motion file from the bundle of the target that holds the explainer. `ChalkScript` bundles `style.json`, and `ChalkScriptExplainers` bundles `subtraction-motion.json`, the only motion file; the other explainers hold their timings in code.

## EXP-1. An explainer has a revision, which changes when what it shows changes

status: draft
governs: Sources/ChalkScript/Revision/ExplainerFingerprint.swift, Sources/ChalkScriptExplainers/Revision/ExplainerRevisions.swift

An explainer has a revision: a fingerprint computed from what it shows and says over sample values of its problem. A change to what it shows or says changes the revision. The package records no approval. A project that reviews explainers, such as a content repository or an app, ties its decision to a revision and decides who reviews and what a review checks.

**Why:** a decision tied to a revision cannot outlive a change to what was decided on, and nobody has to remember to change a number.

**Acceptance:**
- The revision is computed, never typed.
- A change to an explainer's steps, timing, lines or camera changes its revision.
- The sample values include the edges of the template's range and every shape of step list.

*In the package:* `ExplainerFingerprint` computes it. Subtraction and the two tens-and-ones explainers have a revision function; the other five do not yet. The revision covers the paced steps' lines and timings and, for subtraction, its motion file; it does not yet cover the pictures, the style or the guided parts.

## EXP-4. Withdrawn: asking for help from an explainer

status: withdrawn

This requirement described how an app passes a learner's problem to another person. It concerns the app and not the package. The id is kept so that it is not reused.

## Explainers in the package

- Two-digit subtraction, with and without trading.
- Tens and ones: reading a number into tens and ones, and writing the number that tens and ones make.
- Two-digit addition.
- Comparing two amounts on a tape diagram, and on a bar graph.
- Making a ten to add within 20.
- Choosing the three cards closest to a target.
