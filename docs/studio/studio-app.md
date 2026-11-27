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
- **Making a document.** The studio makes documents. The agent's `create` tool, which the person
  asks for by saying what the explainer is to be about, writes a small starter document to the
  project folder's top level, named from its title, as the helper protocol's section 6.8 says; or
  a copy of another document of the project, with its own `id` and title. The studio reads the
  folder again at once, lists the new document, selects it and shows it in the Square preview,
  where it draws "Ask Claude to make this explainer." until the agent builds it. The code that
  does so is `StudioModel.createDocument(title:name:from:)`, which the window can call with a
  title alone.
- **Playing.** The window plays the selected document's watched steps with the engine's player and
  view (`ExplainerView`), for a problem chosen from the document's samples or typed within its
  parameters, in a chosen wording and language, paced or skippable. Lines are shown, not spoken.
- **What the studio authors.** A document holds the drawing and its words. The arrangement of
  the question, the line and the controls round the drawing belongs to the app that plays the
  document (EXP-17), and nothing the studio's view controls choose is saved in the document or
  has any bearing on an app that plays it. The options bar therefore keeps two kinds of control
  apart: the Preview and Arrangement controls sit in one group, with Preview labelled "not saved",
  and the ticks for the shapes the explainer is made for, which change the document, stand at
  the end of the row above the line "Saved to document — tells the player app which views it
  can use."
- **Presets.** The studio names three ranges of the drawing area's ratio of width to height:
  **Tall**, 0.6 to 0.9; **Square**, 0.9 to 1.35; **Wide**, 1.35 to 2.2. Each has a nominal ratio,
  0.75, 1.1 and 1.78, at which it is previewed and for which an agent arranges. Square is the
  common case, since an app that puts the caption beside or below the drawing leaves an area
  about as wide as it is high. The format has no presets: a document stores ranges in `areas`
  (the format reference, section 8.2), and the studio reads an entry whose range is exactly one
  preset, or several that follow one another, as those presets.
- **Preview.** The Preview control chooses the shape of area the drawing is shown in: Tall,
  Square or Wide, each at its nominal ratio, whether or not the document is made for it. A
  document is first shown in Square, so the bounds of the drawing are always seen. The
  window previews no other ratio; an agent sees any ratio with the helper's `show`. A preview lays the player out for the largest area of
  that ratio inside the pane, centred and framed with a thin line in the `line` role, and
  changes nothing in the document.
- **Arrangement.** The menu labelled "App arrangement" previews how an app that plays the
  explainer might arrange the screen round the drawing (EXP-17): **Automatic**, the default,
  puts the caption and controls below the drawing in a pane taller than wide and in a column
  beside it in a wider one; **Caption Below** and **Caption Beside** keep that arrangement
  whatever the pane's shape, except that a pane too narrow for the column takes the caption
  below. The drawing area changes with it, so a document that lays itself out for its area is
  laid out again, and a preview is taken inside the new area. It is not a setting of the
  document, and it is kept when another document is chosen.
- **Made for.** Three ticks, Tall, Square and Wide, say which shapes the explainer is made
  for. A preset is ticked when the document's `areas` declares its nominal ratio; a document
  without `areas` has none ticked and is laid out for whatever area it is given. Ticking or
  unticking one writes one patch through the same path as an agent's edit, so it is checked,
  saved at once and one step of Edit > Undo. The patch writes `areas` and nothing else: each
  ticked preset's range names the layout the document's own rule (`suits`) chooses there,
  split where the rule changes layout, with neighbouring ranges in the same layout joined. No
  layout is made, removed or given another rule; a different arrangement of the scene for one
  shape is a layout the agent adds to the document. A declared range that lies wholly outside
  the presets' ratios is kept. Unticking the last preset removes `areas`.
- **The status line.** On its right, the status line names the layout the document is drawn in
  and the area shown: "Layout tall · pane 1.04", or "Layout tall · previewing Square at 1.10".
  When that area is not one the document is made for, the document is drawn as a player draws
  it, at the nearest declared shape, and the status line says so, such as "Layout tall · pane
  0.40 is not a shape the document is made for; drawn at 0.60". A document without `areas` is
  laid out for any area it is given, so for it the status line names the layout only.
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
it and shows a step, and, in the phase `create`, makes a new document, patches it and shows it.
Both edit the open project, so run it against a temporary folder: the app's launch arguments
`-StudioProjectFolder` and `-StudioSocketPath` open a folder and listen on a socket of your choice
without changing the app's saved settings. In a Debug build, posting the distributed notification
`org.chalkscript.studio.windowPicture` with a file path as its object makes the app write a
picture of its window to that path, for a session that cannot capture the screen.

## Not built yet

Narration (lines are shown, not spoken), do it with me, What if? and try one, export to video, a
timeline or inspector, editing in the window other than the ticks for the shapes an explainer is made for,
making a document in the window (File > New Explainer), renaming, duplicating and removing a document
there, a document's own palette, and notarisation.
