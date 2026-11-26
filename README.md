# ChalkScript

ChalkScript is a Swift package for making step-by-step visual explanations, called explainers. An explainer shows a method or an idea one step at a time, with a drawing, motion and a spoken line.

## The problem

Research on multimedia learning describes what makes an explanation easy to follow. One thing changes at a time. What matters is marked, and little else. A line is spoken while the picture it describes is shown. The learner sets the pace. A piece moves only where the motion carries meaning.

An animation engine does not hold these findings. An author, or an agent writing for an author, has to apply them again in every explanation.

## What the project does

ChalkScript holds the findings as rules in the package and as data in its formats.

- An explainer is a template filled from a problem's values. Every number it draws, shows or speaks is computed.
- A player paces the steps. The learner watches, then carries out the method, then tries a problem alone.
- Each operation has one colour and a second cue. The palette is tested under simulated colour vision deficiencies.
- A camera frames what each step acts on and dims the rest.
- Colours, timings and camera shots are data in two JSON formats. They can be changed without changing an explainer's code.

The requirements are in [docs/spec/explainers.md](docs/spec/explainers.md), each with its reason and the research it rests on. Each has a stable id (EXP-1 to EXP-19), which the code and commit messages cite.

## Status

The project is at an early stage and its interfaces will change. The package has two targets. `ChalkScript` is the engine: the shared drawing components, the players, the style and motion formats, the reader of explainer documents, the revision of an explainer and the spoken form of numbers. It depends on nothing. The package reads documents in the explainer format ([docs/format/explainer-1.0.md](docs/format/explainer-1.0.md)): it checks a document and reports its findings, and for a problem it gives the steps, their timing and their lines in each wording and language. It plays a document's watched steps: `DocumentExplainer` draws a document with the shared components, so the package's player and view play it as they play a Swift template, and the `chalkscript-render` command writes the still picture of every step to PNG files. Do it with me, What if? and try one are not yet played from a document, and the explainers in `ChalkScriptExplainers` are still Swift templates. `ChalkScriptExplainers` depends on the engine and holds explainers for two-digit subtraction, tens and ones, two-digit addition, comparing on a tape diagram and on a bar graph, making a ten, and choosing three cards closest to a target. All are for early elementary arithmetic. The requirements are written for any subject, and other subjects are intended.

ChalkScript Studio, in `Studio/`, is a first version of the macOS authoring app. It plays the documents of a project folder in a window and takes an agent's edits: Claude's desktop app or Claude Code reaches it through a helper, `chalkscript-mcp`, which speaks the Model Context Protocol and forwards each call to the running app ([docs/studio/helper-protocol.md](docs/studio/helper-protocol.md)). The studio authors the drawing and its words. How the question, the line and the controls are arranged round the drawing is decided by the app that plays the explainer (EXP-17); the studio's Arrangement menu previews what such an app might do, is not saved in the document, and has no bearing on an app that plays it. The app's logic that is not user interface is the library target `ChalkScriptStudioCore`. It does not yet speak the lines, play do it with me, or export; [docs/studio/studio-app.md](docs/studio/studio-app.md) says what it does and how it is built.

Planned work, not yet started: a validator that checks an explainer against the rules that can be computed; export to video; and a separate library of contributed explainers.

## Requirements and use

Swift 6, iOS 27 or macOS 27. Add the package to a project by this repository's URL and import `ChalkScript`, for the engine, and `ChalkScriptExplainers`, for the explainers. The package has no dependencies. Explainers do not yet carry their wording: a template is given its lines, and the package fills in the numbers and their spoken forms.

To build and test:

```
swift build
swift test
```

To render the still pictures of an example document for one problem:

```
swift run chalkscript-render docs/format/examples/subtraction.explainer "$TMPDIR/subtraction" a=54 b=26
```

To build ChalkScript Studio and its desktop extension (XcodeGen and Xcode are needed; signing is described in [docs/studio/studio-app.md](docs/studio/studio-app.md)):

```
Studio/build.sh
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

The code is under the MIT licence ([LICENSE](LICENSE)). Documentation and explainer content that is not code are under CC BY 4.0 ([LICENSE-docs.md](LICENSE-docs.md)).
