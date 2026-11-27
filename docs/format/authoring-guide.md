# Authoring guide

How an agent writes and edits explainer documents through ChalkScript Studio's tools. An
explainer shows a method one step at a time, with a drawing, motion and one line per step, for a
problem whose values it is given. The full definition is the format reference,
`docs/format/explainer-1.0.md`; this guide is the part an agent needs. Read `editing` before the
first edit, and other topics when a change needs them. A document that does not exist yet is made
with `create`; read `new` before building one.

## editing: the tools, and how to make a change

The person watches the studio window. It shows one document, plays it for one problem, and
redraws as soon as an edit is saved, so an image is rarely needed.

- `list`: each document's name, hash, counts of errors and warnings, and title.
- `read {doc, pointer}`: the value at a JSON Pointer, such as `/steps/trade` or
  `/wording/en-US/everyday/make`. The first line is the document's hash. Read the part you will
  change, not the whole document.
- `edit {doc, base, ops}`: a JSON Patch (RFC 6902: `add`, `remove`, `replace`, `move`, `copy`,
  `test`) made against `base`, the hash you read. Every operation applies or none does. A patch
  is refused when the base is stale (read again), when a path is `""`, `/format` or `/version`,
  when an operation fails, or when the result has an error; the refusal lists why, one finding
  per line. Warnings do not refuse a patch. An accepted edit returns the new hash: use it as the
  next base without reading again.
- `check {doc, pointer?}`: the findings, one per line. Counts include problems found by playing
  each sample, so an edit can be accepted and still report an error for some sample.
- `create {title, name?, from?}`: makes a new document in the project and shows it in the window
  (topic `new`). The result gives the document, so it need not be read.
- `show {doc, step?, problem?, ratio?, image?}`: plays a step in the window. `problem` is an
  object of parameter values, such as `{"a": 54, "b": 26}`; without it the window's current
  problem is played. Ask for `image` only when the person cannot see the window. `ratio`, the drawing area's width over its height, is the shape the
  picture is laid out for, with a longer side of 480 points; without it, the window's shape.
- `guide {topic?}`: this guide.

Practice:

1. `list`, then `read` the steps or entries the request is about.
2. Make the smallest patch that does what was asked. Several operations may go in one patch.
3. `show` the step you changed, so the person sees it, and say in a sentence what you did.
4. When the person asks for an explainer that is not in the project, make it with `create`; do
   not rebuild another document into it, which destroys that document.
5. Keep ids stable. Renaming an element, step or entry is allowed, but every reference to the
   old name must be changed in the same patch.

Editing outside the studio is picked up too: the person may change a file in an editor, and the
hash changes. A stale base means someone else edited; read again before retrying.

## new: making an explainer from nothing

`create {title}` writes a small document that already checks with no findings, so every patch
after it starts from a document that plays. It holds `params` of `{}` with one sample `{}`, one
`text` element `note`, one step `start` with its line, the wording `placeholder` (shown) and
`start` (said) in `en-US`, and one layout, `stage`, of 880 by 800, declared in `areas` for the
Square range, 0.9 to 1.35. The studio names the file and the document's `id` from the title
("Reading the clock" is `reading-the-clock`, and `-2` is added when that is taken), shows it in
the window and returns it. With `from` the document is a copy of that one, with its own `id`
and `title`; use it when the person wants to start from an example. `name` sets the name when
the person has asked for one; a name that is taken or is not lower case letters, digits and
hyphens is refused, and nothing is made.

Work in this order, one patch for each point or a few:

1. The problem. Agree with the person, in a sentence, what varies. Give `params`, `let`,
   `samples` (one for each case a step depends on) and, if a capability is used, `requires`.
2. The layout. Keep the Square stage of 880 by 800 and plan the drawing inside it. Do not add a
   layout or change `areas` yet.
3. Elements, steps and wording together. Replace `elements`, `sequence`, `steps` and the
   `en-US` wording in one patch, so that the starter's `note`, `start`, `placeholder` and
   `start` line go and nothing refers to them. Afterwards add or change one step at a time, each
   with its line.
4. Wording. Write every line in the `everyday` wording; add another wording only when asked.
5. Check. `check` once the steps are complete.
6. Show. `show` each step for the person; if you need to see it, ask for `image` with `ratio`
   1.1, and look at the narrowest and widest shape the person cares about before suggesting
   that they tick Tall or Wide.

A patch is refused when its result has an error, so a document cannot pass through a broken
state. Put together in one patch a step and the entries it names, an element and the `let` value
it uses, and a parameter and every expression that uses it. An accepted patch can still leave an
error for one sample, which `check` lists.

A first patch against the starter, for dots numbered one up to a number the problem gives:

```json
[
  {"op": "replace", "path": "/params", "value": {"howMany": {"type": "int", "min": 2, "max": 8}}},
  {"op": "replace", "path": "/samples", "value": [{"howMany": 3}, {"howMany": 8}]},
  {"op": "replace", "path": "/elements", "value": {
    "dots": {"kind": "shape", "repeat": "howMany", "ellipse": ["440 - 50 * howMany + 100 * i", 340, 60, 60],
             "fill": "pencil", "start": {"opacity": 0}},
    "nums": {"kind": "text", "repeat": "howMany", "style": "label", "anchor": "middle",
             "at": ["470 - 50 * howMany + 100 * i", 450], "text": "numText", "start": {"opacity": 0}},
    "total": {"kind": "text", "style": "total", "anchor": "middle", "at": [440, 600],
              "text": "totalText", "ink": "result", "start": {"opacity": 0}}
  }},
  {"op": "replace", "path": "/sequence", "value": ["dots", "count", "total"]},
  {"op": "replace", "path": "/steps", "value": {
    "dots": {"say": "dots", "actions": {"put": {"do": "appear", "target": "dots", "each": 0.2, "rise": 20}}},
    "count": {"say": "count", "actions": {"num": {"do": "each", "target": "nums", "gap": 0.2,
              "let": {"k": "i + 1"}, "then": {"put": {"do": "appear", "text": "numEntry"}}}}},
    "total": {"say": "total", "actions": {"show": {"do": "appear", "target": "total"}}}
  }},
  {"op": "replace", "path": "/wording", "value": {"en-US": {
    "shared": {"numText": {"text": "", "visual": true}, "numEntry": {"text": "{k}", "visual": true},
               "totalText": {"text": "{howMany} in all", "visual": true}},
    "everyday": {"dots": "Put down {howMany} dots, one at a time.", "count": "Count them, one for each dot.",
                 "total": "There are {howMany} dots."}
  }}}
]
```

There is no tool to rename or remove a document. To retitle one, patch `/title`; its file's name
and `id` stay as they are, so that the name you are using does not change under you.

## document: the top-level keys and names

A document is one JSON object in a `.explainer` file. Eleven keys are required, marked below;
the others are optional, and a document without them is complete.

| Key | Holds |
|---|---|
| `format`, `version` | Required. `"chalkscript-explainer"`, `"1.0"`. Never edited. |
| `requires` | Capabilities used, such as `["components.arithmetic"]` for tens, ones and counters. |
| `id`, `title` | Required. Identity. `id` is the document's name as the studio made it, the same as its file's name; leave it alone in a patch. |
| `about` | Information that changes nothing seen or heard. |
| `sourceLocale` | Required. The locale written in, such as `en-US`. |
| `params`, `samples` | Required. The problem (topic `problem`). |
| `let`, `vars`, `kind` | Optional parts of the problem. |
| `areas` | The shapes of drawing area the document is made for (topic `camera`). |
| `layouts`, `parts`, `shots`, `opening` | The drawing and camera (topics `elements`, `camera`). |
| `elements` | Required. What is drawn (topic `elements`). |
| `intro` | The lines before the first step. |
| `sequence`, `steps` | Required. The step names in order, and the steps (topic `steps`). |
| `try`, `whatIf` | Later parts; not played (below). |
| `style` | Overrides of the standard style: `palette`, `easings`, `motion`. |
| `plays` | The wording suggested for `paced` and `skippable` playback. |
| `wording` | Required. Every line, by locale and wording (topic `wording`). |
| `extensions` | Keys named `vendor.feature`; keep any you do not understand. |

Names of elements, steps, actions, parts, shots, layouts, parameters, `let` and `vars` match
`^[a-z][A-Za-z0-9]{0,47}$`; entry names may have dots, as `do.trade`. Parameters, `let`, `vars`
and elements share one namespace. Reserved: `and`, `or`, `not`, `true`, `false`, function names,
and `i`, `n`, `x0`, `y0`, `left`, `areaW`, `areaH`. Steps and elements are maps; order comes from
`sequence` and from `z`. Colours are never written: name a role (topic `elements`).

Only the watched part plays from a document today: the steps of `sequence`. `try`, `whatIf` and a
step's `act` and `why` are kept but not played; write none unless the person asks.

## problem: parameters, computed values and samples

- `params`: each name to `{type, ...}`. `int` and `number` need `min` and `max` (numbers, or
  expressions of other parameters, as `"max": "a"`); `bool`; `choice` with `values`.
- `let`: names to expressions of parameters and other `let` names, such as `"d": "a - b"`. No
  cycles; no `vars`, elements or locals.
- `vars`: starting values that a viewer's action may change; fixed in the watched part.
- `samples`: a non-empty array of problems, each giving every parameter. The studio plays the
  first by default and checks every sample after an edit, so add a sample for each case a change
  affects (a trade and no trade; a zero digit).
- `kind`: how other problems of the same kind are chosen (`search`, `same`, `differ`, `near`).

Every number drawn, shown or said is computed from these values. Never type a numeral into a line.

## expressions: values, operators, functions and selections

Wherever a number, truth value, selection or time is expected, a string is an expression. A
literal string inside one is in single quotes: `"bT > 0 ? str(bT) : ''"`.

- Operators, loosest first: `c ? x : y`, `or`, `and`, `not`, a comparison (`==` `!=` `<` `<=`
  `>` `>=`, not chained), `+ -`, `* /`, unary `-`, then `s[k]` and `s.m`. `and`, `or` and `?:`
  evaluate only what they need.
- Functions: `div(a, b)` (floor), `mod(a, b)` (sign of `b`), `min`, `max`, `abs`, `floor`,
  `round` (half away from zero), `str(a)`; selections `first(n, s)`, `last(n, s)`,
  `slice(s, start, n)`, `whole(s)`; times `start(action)`, `end(action)`; `split(s)` as an
  `appear`'s `place`.
- At most 256 nodes and 24 levels. Division by zero, an index outside a family, or a selection
  function asked for more than there is, is an error for that problem.
- Selections: `ten` is every instance of `ten`; `ten[k]` one instance; `equation.ans` a run of
  a text element; `ten[k].cross` a piece's cross-out; `s + t` joins without repeats; `whole(s)`
  drops what is crossed out or ghosted. A step's selections are evaluated as it begins, so
  `last(bT, whole(ten))` names the tens still standing.

## elements: what is drawn, and where

The drawing's units start at the top left, *y* down. The layout `stage` is `[1000, 540]` unless
`layouts.stage.size` says otherwise. The core kinds are `text`, `line`, `arrow`, `outline` and
`shape`. The only capability today is `components.arithmetic`, whose pieces are the last row of
the table; draw anything else from the core kinds. Every element has `kind`, and may have `repeat` (count of
instances; `i` is the index in other keys), `when`, `z`, `fixed` (outside the camera, never
dimmed) and `start` (`opacity`, and `progress` for a stroked kind).

| Kind | Keys |
|---|---|
| `text` | `at` (baseline point), `text` (an entry), `runs`, `style` (`equation` 44, `total` 54, `label` 18, `note` 22, `body` 26), `ink`, `size`, `anchor` (`start`, `middle` or `end`: which point of the baseline `at` is). |
| `line` | `from`, `to`; `style` `rule` or `divider`; `ink`. |
| `arrow` | `from`, `to` (points, or a selection of one instance); `y` to run over the top; `ink` (required). |
| `outline` | `rect` `[x, y, w, h]` or `around` (a selection); `pad`; `style` `box`, `ring`, `hint` or `target`; `ink` for `box` and `ring`. |
| `shape` | `rect` (with `corner`), `ellipse` (the rectangle `[x, y, w, h]` it fills) or `points` (with `closed`); `fill` and/or `ink`. |
| `ten`, `one`, `stick`, `circle` | Pieces of `components.arithmetic`: `rect`, and `look` `pencil`, `traded` or `counted`. Each has a cross-out, `.cross`. |

Roles. Without a capability: `paper`, `sheet`, `text`, `muted`, `line`, `pencil`, `onResult` and
`result`. With `components.arithmetic` in `requires`, in any form (a bare `add` too): `subtract`,
`trade`, `add`, `multiply`, `divide`. An operation role is bare (`add`) or has `.fill`, `.ink` or
`.soft`; the others have no suffix. Each operation keeps its role in every explainer; do not use
`subtract` for adding. A key takes these forms, and anything else is an error:

| Key | Accepts |
|---|---|
| `ink` of `text`, `line` and `shape`; `fill` of `shape` | `text`, `muted`, `line`, `pencil`, `sheet`, or an operation role bare or with a suffix (bare is the ink, or the fill for `fill`) |
| `ink` of `arrow`, of `outline` (`box` and `ring`; the others take none) and of `tint` | an operation role bare: `add`, not `add.ink` |
| `ink` of a run | `result` or `text`, in an `equation` text only |

No key draws `paper` or `onResult`, and a document with `style.palette` is refused. A `total` text
is centred in `result`, and an `equation` text centred in `text`; leave `ink` and `anchor` out of
both. `label`, `note` and `body` take any `ink` of the first row.

There are no trigonometric functions (topic `expressions`): a point round a circle is computed
with the functions listed there, or placed by hand.

A text element's runs are its entry's placeholders: in `"{a} − {b} = {ans}"` the runs are `a`,
`b` and `ans`, and `runs.ans.text` fills `ans` from an entry until a verb sets it. A piece is a
quantity: it is never faded below a ghost (0.28), and nothing removes an element.

## steps: steps, actions, timing and the verbs

A step is one change to the picture with one line. Keys: `say` (the step's line, an entry name),
`actions` (name to action), `when`, `shot`, `duration` (replaces the end of the last action),
`hold` (seconds after), `counts` (the step counts aloud), `like` (copy another step's keys,
replacing those given), and `act` and `why` (not played; see `document`).

An action has `do` (the verb), `target`, `at` (start, seconds or an expression such as
`"end(arrow) + 0.2"`), `dur` (per instance), `each` (stagger between instances), `reverse`,
`ease` (a curve name), `when`, `wait: "voice"` and `mark: true` (undone when the next step
begins, as a tinted digit). An action ends at `at + (n − 1) · each + dur`; the step's timeline
is the latest end, plus `hold`. Default durations: appear 0.3, draw 0.4, fade 0.35, travel 1.2
seconds. `wait: "voice"` holds the step's clock at that action's start until the lines said before
it have been heard (on an `each`, at each instance): use it on an action that should follow the
line, not seconds guessed for it. The studio's voice is silent; only a speaking player shows it.

| Verb | Kind | Does |
|---|---|---|
| `appear` | appear | From opacity 0; `rise` (a distance: it starts this far below its place, so a negative number drops in), `grow` (a scale from 0 to 1 that it grows from), `place` (`split(ten[k])`), `text`. |
| `fade` | fade | To `to`, 0 to 1 or `"ghost"`. |
| `draw` | draw | Draws the stroke of a `line`, `arrow`, `outline` or `shape` with `ink` from progress 0 to 1. A `shape` with only `fill` is whole from the start: use `appear`, `fade` or `move`. `line` and `arrow` have a fixed stroke width; for a thicker one use a filled `shape` with `points`. |
| `cross` | draw | Draws a piece's cross-out; `fade` seconds then ghost it. |
| `tint` | draw | A pale `ink` role behind a run or element; with `mark`, marks a digit. |
| `move` | travel | To `to`, or back to its place; `via` keyframes `[offset, x, y]` with `x0`, `y0`. |
| `gather` | travel | From the positions of `from` to their places. |
| `look` | instant | Sets a piece's `value` look. |
| `set` | instant | Sets a text or run to the entry `text`. |
| `tag` | appear | A small card with the entry `text` over each target, which comes and goes. |
| `pulse` | appear | Grows to 1.15 and back. |
| `say` | instant | Queues the entry `line`; `count: true` for a count; `caption`. |
| `each` | none | For each instance of `target`, runs `then` every `gap` seconds, with `i` and its `let`. |

`each` counts or numbers instances. It names a `target`, a `gap` in seconds, optional `let` locals
evaluated with `i`, the instance's position from 0, in scope, and `then`, the actions run for each
instance; an action in `then` without a `target` acts on the current instance. To number twelve
repeated text elements 1 to 12, give the elements `"text": "numText"`, an entry holding nothing,
and give each the number as it appears:

```json
"num": {"do": "each", "target": "nums", "gap": 0.2, "let": {"k": "i + 1"},
        "then": {"put": {"do": "appear", "text": "numEntry"}}}
```

with the entry `"numEntry": {"text": "{k}", "visual": true}`. A step whose `when` is false for
the problem is not among that problem's steps, so `show` of it names the steps the problem has.

A duration a person asks for ("slower", "hold longer") is usually `dur`, `each`, `gap` or `hold`.

State a time once and derive the times that depend on it, so that a change is one patch. A
`let` value (`"ringTime": 0.3`) may be named in a `dur`, `at`, `each` or `gap`; `end(action)`
does the same for an action's `at` outside an `each`. In the equal-groups example the ring's
`dur` is `"ringTime"`, the dots' `at` is `"ringTime"` and the `each` gap is
`"ringTime + b * dotGap"`, so slowing the ring is
`{"op": "replace", "path": "/let/ringTime", "value": 0.5}`.

## wording: lines, placeholders and languages

`wording` maps a locale to sections: `shared`, and wordings named by the author (the examples
have `everyday` and `formal`). An entry is a string or an object with exactly one of `text`,
`forms` (plural categories, `other` required, chosen by `n`) and `select` with `cases`; and may
have `spoken`, `visual: true` (shown, never said), `emphasis` (a placeholder set in the result
colour), `pronunciation`, `notes` and `maxLength`.

- `select` and `cases` choose a text by an expression; a case's key is `true`, `false`, an
  integer's digits or a string, and `*` matches the rest (no match is an error):
  `{"select": "minute == 0", "cases": {"true": "The long hand points straight up.",
  "false": "Move the long hand to {minute} minutes."}}`.
- `{name}` inserts a value; `{groups:a}` fills the entry `groups` with `n` set to `a`.
- The text outside placeholders must contain no digit.
- In an entry that is said, a number placeholder must not touch a letter: "Count by {b}s" is an
  error, since its spoken form cannot be derived.
- An entry name is in `shared` or in a wording, never both. Each wording must provide every entry
  its watched part uses: step lines, the entries of `say`, `set`, `tag` and `appear`, runs, and
  `intro.watch`.
- A translation is another locale with the same sections and names; each entry is an object with
  `of`, the first 8 digits of the source entry's hash. Edit a translation only when asked.

To change what a step says, edit its entry in the wording being played: for example
`{"op": "replace", "path": "/wording/en-US/everyday/make", "value": "Make {groups:a} of {b}."}`.

## camera: parts, shots and layouts

`parts` names selections (`"tens": "ten"`). A shot frames parts and an optional `region`, with a
`margin`: `"trade": {"frame": ["tradedTen", "arrow", "ones"]}`. A step's `shot` is used only in a
layout with `camera: true`; the camera moves before the step's timeline begins, and what lies
outside the shot is dimmed, not hidden. Another layout has `suits` (an expression of `areaW` and
`areaH`), `size`, `camera`, `band` (the height at the top of the drawing kept for `fixed`
elements when the camera is on; 0 by default) and `let` replacements; the first that suits the
window, by name, is used, and otherwise `stage`. The studio's window chooses the layout from the area the
pane gives the drawing, or from the shape chosen in its Preview control.

The document holds the drawing and its words only. The question, the line and the controls round
the drawing are arranged by the app that plays the document, which a document cannot know; the
studio's Arrangement menu only previews what an app might do. Arrange a drawing within the area
it is laid out for, and assume nothing about what lies outside it.

The studio names three ranges of shape, its presets, each with the ratio it previews and that you
arrange for: **Tall**, 0.6 to 0.9, previewed at 0.75; **Square**, 0.9 to 1.35, at 1.1; **Wide**,
1.35 to 2.2, at 1.78. Square is the common case, since an app that puts the caption beside or
below the drawing leaves an area about as wide as it is high. A player never crops or stretches:
inside a range the drawing is scaled and centred with margins, so a layout made at the nominal
ratio is seen with margins at the range's ends. When the person is previewing a preset, arrange
within the frame the window shows, and check the shape with `show` and `ratio` set to the
preset's nominal ratio. The format has no presets; `areas` stores them as ranges.

Make an explainer for Square first (topic `new`), in one layout, and let the camera do the framing: a shot
that frames what a step is about serves most shapes. Add a layout for another shape only when
the person asks for a different arrangement there, or when the drawing sets two things side by
side or one above the other and one shape cannot hold both, as the subtraction example's `tall`
layout does. When a person asks whether an explainer works on a phone held upright or on a wide
screen, look at it with `show`, `ratio` and `image` at that preset's nominal ratio and say what
you see. If it reads well, tell them to tick that shape under "Explainer is made for" in the
studio's window, which saves it in the document. For a shape the document is not made for, the
picture is of the shape asked and the document is drawn in it at the nearest declared shape,
framed; to see the shape itself, the document needs a layout and a range for it (`areas`, below).
If it does not, say what is wrong and offer the smaller change first: a shot, a size or a place,
before a layout of its own. Tell a person who asks that Preview and App arrangement in the
studio change only what they see there, and that the app which plays the explainer decides where
the caption and the controls go.

`areas` declares the shapes of drawing area the document is made for: a list of entries, each a
`layout` (a layout's name, or `stage`) and a `ratio` `[min, max]`, the least and greatest ratio of
the area's width to its height, as plain numbers with 0 < min <= max. Ranges may meet at an end,
as the subtraction example's do at 1.35, and may leave gaps. The layout is still chosen by `suits`;
`areas` says which layout the author expects at each shape. Give each layout's `suits` the same
boundary as its range, and declare `stage` for the shapes it is scaled to fit. A document without
`areas` declares nothing. Change the declaration with an ordinary patch on `/areas`:

```json
{"op": "add", "path": "/areas", "value": [{"layout": "stage", "ratio": [0.9, 2.2]}]}
{"op": "add", "path": "/areas/-", "value": {"layout": "tall", "ratio": [0.6, 1.35]}}
{"op": "replace", "path": "/areas/1/ratio/1", "value": 2.4}
{"op": "remove", "path": "/areas/0"}
{"op": "remove", "path": "/areas"}
```

The first declares for the first time, the second adds a range, the third widens one, the fourth
removes one and the fifth removes the declaration. Removing the last entry with `remove /areas/0`
leaves an empty `areas`, which is a `schema` error; remove `/areas` instead. A range that
disagrees with the layouts is accepted with an `areas` warning, which means a declared range and
a layout's `suits` disagree; when you change a range, change the `suits` of the layouts on each
side of it in the same patch.

The rule for `areas`: the person ticks a shape that an existing layout serves, which writes
`areas` only. When you add a layout for a shape, because the person asked for a different
arrangement there, add its range to `areas` in the same patch and say so. Otherwise do not
change `areas` unasked. A layout of its own is usually a copy of the layout it was drawn in.

A layout changes the drawing only through `size`, `camera`, `band` and its `let`. A place or
size that differs between layouts is therefore a `let` value that the elements name, replaced
in the layout. With the document's `"let": {"rowY": 120}` and an element at `[100, "rowY"]`:

```json
{"op": "add", "path": "/layouts/tall/let", "value": {"rowY": 300}}
```

puts the element at 300 in `tall`. An element given a literal place stays where it is in every
layout.

The window shows an area of a shape the document is not made for at the nearest declared shape.
To see a shape, `show` with `ratio` and `image`.

## taps: the size of what a learner marks

For a step the learner taps, check at the narrowest shape the document is made for that each
target, with its `pad`, is large enough to tap. In an area *w* points wide and *h* high, the
drawing is scaled by the smaller of *w* / *W* and *h* / *H*, where *W* and *H* are the layout's
`size`, so a target *d* drawing units across is *d* times that scale in points. With `show`, *w*
is 480 times the ratio when the ratio is below 1, and 480 otherwise. A shot that frames less of
the drawing enlarges it further. EXP-18 requires a piece and its margin to be at least 44
points across where the learner marks a piece.

## findings: what the codes mean

One finding is one line: severity, code, JSON Pointer, `@offset` inside an expression or text,
the problem's values, a time, then the message.

| Code | Fix |
|---|---|
| `json`, `format`, `version` | The file itself; the person fixes a file that is not JSON in an editor. |
| `schema` | A missing key, wrong type, unknown verb or kind, or a bad name. |
| `unknown` | A key the format does not define (a warning); often a misspelling. |
| `ref` | A name that does not exist: a step, action, element, run, part, shot, entry or role. |
| `expr` | A syntax error, unknown name or function, or a cycle; `@` gives the offset. |
| `wording` | A placeholder that cannot be filled, a typed numeral, or an unsayable number. |
| `eval` | An expression failed for the problem in braces; try that problem with `show`. |
| `range` | A problem outside the parameters. |
| `areas` | A warning that a declared range and a layout's `suits` disagree, that no entry names a layout, or that `suits` depends on the area's size; change the range or the layout's `suits`, or add the missing entry. |
| `patch` | A refused patch: stale base, protected path, or an operation that failed. |
| `capability` | A kind or verb used without its capability in `requires`, or one this studio does not draw. |
