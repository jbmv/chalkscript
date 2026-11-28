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
  does so is `StudioModel.createDocument(title:name:from:)`.
- **New Explainer.** File > New Explainer (Command-N) makes the same starter document from the
  window. Its sheet asks for a title and nothing else; the document's name and `id` are made
  from the title, with `-2` added when the name is taken. Create is unavailable while the title
  is empty, Return in the field creates, and Cancel or Escape makes nothing. If the document
  cannot be made, the sheet stays open and says why.
- **Rename, Duplicate and Move to Trash.** A document's context menu in the sidebar holds the
  three commands, with Show in Finder and Open in Text Editor. **Rename** opens a sheet that
  asks for a title, with the present one filled in. The title, the file's name and the
  document's `id` change together: the name is made from the title as New Explainer makes it,
  the file keeps its folder, and a name another document has gets a number added. The document
  stays selected if it was, on the step and with the problem it was shown with. An agent that
  holds the old name is told that no document has it. **Duplicate** makes a copy at the project
  folder's top level, titled as the original with "copy" added, and "copy 2" and so on when
  that title is in use, with the name and `id` made from that title, and selects it. **Move to
  Trash** asks first, then moves the file to the Mac's Trash, from which Finder's Put Back
  returns it to the project, where the studio lists it again. If the document was selected, the
  one after it in the sidebar is selected, or the one before it when it was the last. Rename
  and Duplicate are unavailable for a file that cannot be read as a document. None of the three
  is a step of Edit > Undo, and Rename and Move to Trash clear its steps, since an earlier step
  would otherwise write a document under a name it no longer has. The code is
  `StudioModel.renameDocument(_:title:)`, `duplicateDocument(_:)` and `trashDocument(_:)`. An
  agent has no tool for renaming or removing a document.
- **Playing.** The window plays the selected document's watched steps with the engine's player and
  view (`ExplainerView`), for a problem chosen from the document's samples or typed within its
  parameters, in a chosen wording and language, paced or skippable. Lines are shown, and are
  spoken only when Speak lines is ticked. Without it the window plays with `EstimatedVoice`, a
  stand-in that says nothing and finishes each line once its estimate has passed on the player's clock: 0.3 seconds
  and a third of a second for each word of the spoken form (`ReadingTime.seconds`), divided by
  the player's pace, and nothing for a line with no spoken form. A `wait: "voice"` therefore
  holds and a step lasts about as long as it would spoken. The estimate was fitted to the system
  voice at its default rate and is not the time of any particular voice. The voice is chosen in
  one place, `StudioModel.makeVoice`.
- **Speak lines.** The tick labelled "Speak lines", beside Playback, makes the window say each
  line aloud while its step plays. It is off when the studio is first used, and is kept from one
  launch to the next in the app's settings, not in any document. With it on, the window plays
  with `SystemVoice` (`Studio/Sources/SystemVoice.swift`), which speaks a line's spoken form
  with the Mac's system voice (`AVSpeechSynthesizer`) for the language the document is played
  in, at the voice's own rate and the Mac's volume, and finishes the line when it has been heard
  to its end. A `wait: "voice"` action therefore starts when the line before it has been heard.
  A line with no spoken form says nothing. Again, another step, another document, an edit, and
  closing the window each stop what is being said at once. Ticking or unticking plays the step
  shown again. A Mac with no voice for the document's language speaks in its own voice. The
  system voice is for hearing a draft while it is made. It is not the voice of anything sent to
  others: an export is to be spoken by another voice, and is not built yet. What an agent reads
  through the helper does not change with the tick.
- **What the studio authors.** A document holds the drawing and its words. The arrangement of
  the question, the line and the controls round the drawing belongs to the app that plays the
  document (EXP-17), and nothing the studio's view controls choose is saved in the document or
  has any bearing on an app that plays it. The options bar therefore keeps two kinds of control
  apart: the Preview, Appearance and Arrangement controls sit in one group, with Preview labelled
  "not saved",
  and the ticks for the shapes and the appearances the explainer is made for, which change the
  document, stand at the end of the row above the line "Saved to document — tells the player app which views it
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
- **Appearance.** The control labelled "Appearance", beside Preview, draws the player in the
  light or the dark appearance: the sheet, the drawing, the line and the player's controls. It
  starts at the Mac's own appearance and follows the Mac until Light or Dark is chosen. The
  sidebar, the options bar and the findings keep the Mac's appearance. A colour that reads well
  on one sheet may not on the other, so both can be checked without changing the Mac's setting.
  A document that is not made for the appearance chosen is drawn as a player draws it, in the
  appearance it is made for, with the line and the controls, and the status line says why:
  "Previewing Light; the explainer is made for dark only, so it is drawn dark." To see such a
  document in the other appearance, tick it under "Made for", which is one step of Edit > Undo.
  The choice is the window's: it changes nothing in the document, is not one of Edit > Undo's
  steps, and is not kept from one launch to the next. In a narrow window the group takes two
  rows, and then three.
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
- **Made for: Light and Dark.** Two more ticks, after the shapes and a little apart from them,
  say which appearances the explainer is made for (EXP-20). Each is ticked when the document is
  made for that appearance; a document without `appearances` is made for both, so both are
  ticked. Ticking or unticking one writes one patch through the same path as an agent's edit,
  so it is checked, saved at once and one step of Edit > Undo. The patch writes `appearances`,
  placed just before `areas` when it is new. Unticking leaves each colour's value for that
  appearance in place, unchecked and not drawn, so that ticking again restores it; the
  warnings about that appearance leave the findings. The last ticked appearance cannot be
  unticked, since a document is made for at least one.
- **A value the studio derives.** Ticking an appearance for which a colour of the document's own
  has no value writes one for each such colour in the same patch, and the status line says so:
  "Added light values for hour and minute; preview Light to see them." The value keeps the hue
  and chroma of the colour's value in the other appearance, at a CIELAB lightness of 52 for
  light or 72 for dark, and is then moved to the nearest colour that keeps 3:1 with the sheet
  and with its own soft form and is 20 apart from `text`, `pencil` and `line` for every kind of
  colour vision the reader checks. It is an aid at the moment of ticking: the value is written
  to the document, where it is checked and can be changed like any other. A colour that names a
  suggested colour has both values already. No player derives a value.
- **The status line.** On its left, the status line says what an agent last asked, or, while
  there is something to say of the document's appearances, that instead: the values a tick has
  just added, until the document changes or another is shown, or why the preview is not drawn
  in the appearance chosen. On its right, the status line names the layout the document is drawn in
  and the area shown: "Layout tall · pane 1.04", or "Layout tall · previewing Square at 1.10".
  When that area is not one the document is made for, the document is drawn as a player draws
  it, at the nearest declared shape, and the status line says so, such as "Layout tall · pane
  0.40 is not a shape the document is made for; drawn at 0.60". A document without `areas` is
  laid out for any area it is given, so for it the status line names the layout only.
- **A document that cannot be played.** In place of the player, the window lists the document's
  first errors under "Ask Claude to fix it; Claude sees the same errors.", since the agent's
  tools report the same findings.
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
without changing the app's saved settings. In a Debug build, the launch argument
`-StudioPreviewAppearance` with `light` or `dark` starts the preview in that appearance, for a
session that cannot click the control. In a Debug build, posting the distributed notification
`org.chalkscript.studio.windowPicture` with a file path as its object makes the app write a
picture of its window to that path, for a session that cannot capture the screen. For a session
that cannot send keys to another app, `org.chalkscript.studio.newExplainer` opens the New
Explainer sheet, and `org.chalkscript.studio.keys` presses the keys its object names, `return`,
`escape` or text to type, in the sheet if one is open. Neither brings the app to the front, so
the menu item and its shortcut are tried by hand.

## Not built yet

Narration in a voice fit to send to others (the window speaks lines with the system voice, for
drafts only), do it with me, What if? and try one, export to video, a
timeline or inspector, editing in the window other than the ticks for the shapes an explainer is made for
and a document's title, a document's own palette, and
notarisation.
