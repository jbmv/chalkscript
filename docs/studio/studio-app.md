# ChalkScript Studio, the app

ChalkScript Studio is the macOS app in which an explainer is made. A person keeps it open beside
Claude's desktop app or Claude Code, asks the agent for a change, and sees the change played in the
studio's window. The agent reaches the studio through the helper, `chalkscript-mcp`, in the
protocol of [helper-protocol.md](helper-protocol.md). This document says how the app is built,
what it does and what it does not do yet.

## Building

XcodeGen and Xcode are needed. From a checkout of this repository:

```
Studio/build.sh
```

It generates `Studio/ChalkScriptStudio.xcodeproj` from `Studio/project.yml`, builds the app into
`Studio/build/`, builds the desktop extension from the app's helper, and prints the paths of both.
The generated project and `Studio/build/` are not committed. Run `xcodegen generate` in `Studio/`
to open the project in Xcode instead.

The script builds the Debug configuration by default. The Release configuration does not build
with Swift 6.4.2, whose optimiser crashes on the engine (`swift build -c release` fails the same
way).

**Signing.** The signing team is read from `Studio/Config/Local.xcconfig`, which is not committed.
Copy `Studio/Config/Local.xcconfig.template` to that name and give your team id. Without the file,
the app is signed ad hoc and runs only on the Mac that built it.

## Where things are

| Path | Holds |
|---|---|
| `Sources/ChalkScriptStudioCore/` | Everything that is not user interface: the open project and its documents, checking, applying and saving an edit, watching the folder, and the studio's end of the helper protocol. `swift test` covers it. |
| `Studio/Sources/` | The window, in SwiftUI. |
| `Studio/Extension/` | The desktop extension's `manifest.json` and the script that packs it. |
| `Studio/Scripts/drive-helper.py` | An MCP client that drives the helper over stdio, for testing the loop without Claude. |
| `docs/format/authoring-guide.md` | The guide the helper's `guide` tool returns. |

The app carries the helper at `Contents/Helpers/chalkscript-mcp`, and the example documents of
`docs/format/examples/` as resources.

## What it does

- **A project folder.** The app opens a folder of `.explainer` documents, by default
  `~/Documents/ChalkScript`. The first time, it makes the folder and copies the example documents
  into it. File > Open Project Folder chooses another, and File > Add Example Documents copies any
  example that is missing. A document is named by its path in the folder without `.explainer`.
- **Playing.** The window plays the selected document's watched steps with the engine's player and
  view (`ExplainerView`), for a problem chosen from the document's samples or typed within its
  parameters, in a chosen wording and language, paced or skippable. Lines are shown, not spoken.
- **What the studio authors.** A document holds the drawing and its words. The arrangement of
  the question, the line and the controls round the drawing belongs to the app that plays the
  document (EXP-17), and nothing the studio's view controls choose is saved in the document or
  has any bearing on an app that plays it. The options bar therefore keeps two kinds of control
  apart: the Preview menu and the Arrangement menu sit in a group marked "View only, not saved",
  and the Layouts button, which changes the document, stands at the end of the row.
- **Presets.** The studio names three ranges of the drawing area's ratio of width to height:
  **Tall**, 0.6 to 0.9; **Square**, 0.9 to 1.35; **Wide**, 1.35 to 2.2. Each has a nominal ratio,
  0.75, 1.1 and 1.78, at which it is previewed and for which an agent arranges. Square is the
  common case, since an app that puts the caption beside or below the drawing leaves an area
  about as wide as it is high. The format has no presets: a document stores ranges in `areas`
  (the format reference, section 8.2), and the studio reads an entry whose range is exactly one
  preset, or several that follow one another, as those presets.
- **Preview.** The Preview menu chooses the area the drawing is shown in. **None**, the default,
  plays it in the pane's own area, as an app would, with no frame. The menu also lists each
  preset the document is made for, at its nominal ratio, and each custom range at the ratio
  midway between its ends in ln r. **Test Ratio…** previews a ratio typed in. A preview lays the
  player out for the largest area of that ratio inside the pane, centred and framed with a thin
  line in the `line` role, and changes nothing in the document; choosing another document
  returns to None.
- **Arrangement.** The menu labelled "App arrangement" previews how an app that plays the
  explainer might arrange the screen round the drawing (EXP-17): **Automatic**, the default,
  puts the caption and controls below the drawing in a pane taller than wide and in a column
  beside it in a wider one; **Caption Below** and **Caption Beside** keep that arrangement
  whatever the pane's shape, except that a pane too narrow for the column takes the caption
  below. The drawing area changes with it, so a document that lays itself out for its area is
  laid out again, and a preview is taken inside the new area. It is not a setting of the
  document, and it is kept when another document is chosen.
- **Layouts.** **Layouts…** opens a sheet that lists Tall, Square and Wide, each with a tick for
  whether the document is made for it, and any custom ranges, each given by its least and
  greatest ratio and added with **Custom…**. Each shape the document is made for is drawn in its
  own layout or in the same layout as another shape; a layout of the document that no shape is
  drawn in can also be chosen. A shape given a layout of its own when it has none gets a new
  layout, named after it, that starts as a copy of a layout of the document, by default the one
  it was drawn in. For a document without `areas` the sheet starts from a suggestion: every
  preset ticked, each drawn in the layout the document chooses at its nominal ratio. Saving
  writes one patch through the same path as an agent's edit, so it is checked, saved at once and
  one step of Edit > Undo. The patch writes `areas`, with neighbouring ranges in the same layout
  joined; adds each new layout; and writes the `suits` of each layout whose part of the ratio
  axis changed, so that the layout chosen at every declared shape is the one its range names.
  Between two ranges that leave a gap, the boundary is a ratio near the middle of the gap. The
  sheet refuses to save when a custom range is not two positive numbers, least first, when two
  ranges in different layouts overlap, when a layout of the document would be drawn at no shape,
  or when the result would carry an `areas` warning the document does not have. Saving the sheet
  unchanged writes nothing, whether its ranges are presets or custom. The sheet does not
  otherwise edit a layout; that is done in the document, by the agent or in a text editor.
- **The status line.** On its right, the status line names the layout the document is drawn in
  and the area shown: "Layout tall · pane 1.04", or "Layout tall · previewing Square at 1.10".
  When that area is not one the document is made for, the document is drawn as a player draws
  it, at the nearest declared shape, and the status line says so, such as "Layout tall · pane
  0.40 is not a shape the document is made for; drawn at 0.60", with one button that adds it.
  The button adds the preset that holds the area's ratio, drawn in the layout it is drawn in
  now, when the document is not made for that preset; otherwise it widens the nearest range to
  the ratio, rounded outward to two decimals. A document without `areas` is laid out for any
  area it is given, so for it the status line names the layout only.
- **Findings.** Below the player are the document's findings: the reader's, and what refuses any
  sample in any wording when the document is played. Each shows its line in the file and its JSON
  Pointer; clicking one on a step plays that step.
- **The agent's edits.** An accepted patch is saved to the file at once, the window plays the step
  it was on again, and the edit is one step of Edit > Undo. A file changed by another program is
  read again within a moment. The status line under the window says what the agent last asked.
- **Connecting.** The toolbar's link button shows how to install the extension in Claude's desktop
  app and the command that adds the helper to Claude Code, with the path of the helper inside this
  copy of the app.

A saved document keeps its keys in their order. It is written with two-space indentation and an
object or array kept on one line where it fits in 100 columns, so a file laid out by hand changes
little after an edit.

## Testing without Claude

With the app running, `Studio/Scripts/drive-helper.py HELPER` launches the helper and speaks MCP
to it as a client would: it lists the documents, reads and edits the equal-groups example, checks
it and shows a step. In a Debug build, posting the distributed notification
`org.chalkscript.studio.windowPicture` with a file path as its object makes the app write a
picture of its window to that path, for a session that cannot capture the screen.

## Not built yet

Narration (lines are shown, not spoken), do it with me, What if? and try one, export to video, a
timeline or inspector, editing in the window other than the Layouts sheet, a document's own
palette, and notarisation.
