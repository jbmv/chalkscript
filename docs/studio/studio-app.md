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
- **Shapes.** The Shape menu in the options chooses the shape of drawing area the document is
  shown at (EXP-17). **Window**, the default, uses whatever area the pane gives the drawing. For a
  document that declares the shapes it is made for (`areas`, the format reference, section 8.2),
  the menu also lists each declared range's two ends and the ratio midway between them in ln r,
  in increasing order and each once, labelled with its ratio and the layout chosen there, such as
  "0.90 · tall". **Other Ratio…** previews a ratio typed in. A preview lays the player out for
  the largest area of that ratio inside the pane, centred, and changes nothing in the document;
  choosing another document returns to Window.
- **Arrangement.** The Arrangement menu beside the Shape menu chooses how the engine's screen is
  arranged round the drawing, as an app that plays the document would choose it (EXP-17):
  **Automatic**, the default, puts the caption and controls below the drawing in a pane taller
  than wide and in a column beside it in a wider one; **Caption Below** and **Caption Beside**
  keep that arrangement whatever the pane's shape, except that a pane too narrow for the
  column takes the caption below. The drawing area changes with it, so a
  document that lays itself out for its area is laid out again, and the Shape menu's preview is
  taken inside the new area. The arrangement is not part of the document and is kept when another
  document is chosen.
- **Undeclared shapes.** When the window's shape, or a ratio previewed, is not one the document
  declares, the document is shown as a player lays it out, at the nearest declared shape, and the
  status line says so: "Window 0.45 is not a declared shape; shown as 0.60". Wherever the area
  used does not fill the pane, it is framed with a thin line in the `line` role, so that the
  margin is seen. **Declare This Shape** then widens the nearest range to include the shape, by
  moving its nearest end, rounded outward to two decimals.
- **Declare Shapes.** **Declare Shapes…** in the Shape menu opens a sheet with one row per
  declared range: a menu of `stage` and the document's layouts, and fields for the least and
  greatest ratio, with buttons to add and remove a row. For a document without a declaration the
  rows start from a suggestion: one range for each run of ratios from 0.5 to 2.5, in steps of
  0.05, at which the layout rule chooses the same layout for the first sample. Saving writes the
  whole declaration as one patch through the same path as an agent's edit, so it is checked,
  saved at once and one step of Edit > Undo; a patch that is refused leaves the sheet open with
  the reason. Saving with no rows removes the declaration.
- **Findings.** Below the player are the document's findings: the reader's, and what refuses any
  sample in any wording when the document is played. Each shows its line in the file and its JSON
  Pointer; clicking one on a step plays that step.
- **The agent's edits.** An accepted patch is saved to the file at once, the window plays the step
  it was on again, and the edit is one step of Edit > Undo. A file changed by another program is
  read again within a moment. The status line under the window says what the agent last asked, and
on its right the shape shown when it is a preview or is not declared.
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
timeline or inspector, editing in the window other than the Declare Shapes sheet, a document's own
palette, and notarisation.
