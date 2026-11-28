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
- `show {doc, step?, problem?, ratio?, appearance?, at?, image?}`: plays a step in the window and
  returns the step's timeline (below). `problem` is an object of parameter values, such as
  `{"a": 54, "b": 26}`; without it the window's current problem is played. Ask for `image` only
  when the person cannot see the window. `ratio`, the drawing area's width over its height, is the shape the
  picture is laid out for, with a longer side of 480 points; without it, the window's shape.
  `appearance` is `light` or `dark`; without it, the appearance the window is previewing. A
  document that is not made for the appearance asked for is drawn in the one it is made for, and
  the result says so.
  `at` is a moment of the step in the timeline's seconds; with `image`, the picture is of that
  moment and not of the step's end.
- `guide {topic?}`: this guide.

The timeline is the text that comes after `show`'s first line, for the step and problem shown. Its
header gives the step's place among the problem's steps, the problem, and the step's length as
the studio plays it, with the length on the step's own clock when that differs. A row gives a
span in seconds from the step's start, then what happens: each line said, with its spoken form;
each time the clock holds for the voice; each action, with its verb, its targets as runs such as
`nums[0-11]`, and the text a `tag`, `set` or `appear` shows. An `each` has a row, then one
indented row for each iteration, and consecutive iterations that do nothing are one row that says
so. The times use the studio's stand-in voice, so the end of a line is an estimate. Read it
instead of asking for an `image` when the question is when something happens, how long a step
lasts, or whether anything is left at its end.

When the question is how something looks part-way through a step, such as where a number is
while it grows, take a moment from the timeline and ask for one picture at it: `show` with
`image` and `at`. A moment while the clock is held for the voice shows the picture as it stands
before the wait, and a moment past the step's length is refused with the length. One picture at a
chosen moment answers more than several taken blind.

An `at`, a `dur`, `hold` or `duration` in a document is on the step's own clock, which stops
while the clock is held for the voice. The timeline's times are the played ones, so a second read
from it is not an `at`: where the two differ, the header gives the own length, and an action that
should follow a line takes `wait: "voice"` instead of a number of seconds.

Practice:

1. `list`, then `read` the steps or entries the request is about.
2. Make the smallest patch that does what was asked. Several operations may go in one patch.
3. `show` the step you changed, so the person sees it, and say in a sentence what you did.
4. When the person asks for an explainer that is not in the project, make it with `create`; do
   not rebuild another document into it, which destroys that document.
5. Keep ids stable. Renaming an element, step or entry is allowed, but every reference to the
   old name must be changed in the same patch.
6. In a `maths` document the colour of an operation (`subtract`, `trade`, `result`, `add`,
   `multiply`, `divide`) is fixed. When the person asks to change one, read topic `colour` first:
   say why it is fixed and ask before the edit.

Editing outside the studio is picked up too: the person may change a file in an editor, and the
hash changes. A stale base means someone else edited; read again before retrying.

## new: making an explainer from nothing

`create {title}` writes a small document that already checks with no findings, so every patch
after it starts from a document that plays. It holds `params` of `{}` with one sample `{}`, one
`text` element `note`, one step `start` with its line, the wording `placeholder` (shown) and
`start` (said) in `en-US`, and one layout, `stage`, of 880 by 800, declared in `areas` for the
Square range, 0.9 to 1.35. It declares both appearances (topic `colour`). The studio names the file and the document's `id` from the title
("Reading the clock" is `reading-the-clock`, and `-2` is added when that is taken), shows it in
the window and returns it. With `from` the document is a copy of that one, with its own `id`
and `title`; use it when the person wants to start from an example. `name` sets the name when
the person has asked for one; a name that is taken or is not lower case letters, digits and
hyphens is refused, and nothing is made.

The person has three commands on a document in the sidebar of the studio's window, and you have
no tool for any of them. Rename takes a new title and changes the file's name and the `id` to
the name made from it, so "Telling the time" becomes `telling-the-time`. Duplicate makes a copy
titled with "copy" added, under its own name and `id`. Move to Trash removes the document from
the project. When the person asks you for another title, replace `/title` by a patch, which
leaves the name and the `id` as they were, and tell the person that Rename in the sidebar
changes the name as well. After a rename or a removal the old name answers "No document named";
`list` gives the names there are now. For a copy, use `create` with `from`.

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
    "nums": {"kind": "text", "repeat": "howMany", "let": {"k": "i + 1"}, "style": "label", "anchor": "middle",
             "at": ["470 - 50 * howMany + 100 * i", 450], "text": "numEntry", "start": {"opacity": 0}},
    "total": {"kind": "text", "style": "total", "anchor": "middle", "at": [440, 600],
              "text": "totalText", "ink": "result", "start": {"opacity": 0}}
  }},
  {"op": "replace", "path": "/sequence", "value": ["dots", "count", "total"]},
  {"op": "replace", "path": "/steps", "value": {
    "dots": {"say": "dots", "actions": {"put": {"do": "appear", "target": "dots", "each": 0.2, "rise": 20}}},
    "count": {"say": "count", "actions": {"num": {"do": "appear", "target": "nums", "each": 0.2}}},
    "total": {"say": "total", "actions": {"show": {"do": "appear", "target": "total"}}}
  }},
  {"op": "replace", "path": "/wording", "value": {"en-US": {
    "shared": {"numEntry": {"text": "{k}", "visual": true},
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
| `requires` | Capabilities used: `components.arithmetic` for tens, ones and counters, and `drawing.turn` to turn a line, arrow, shape or group (topic `elements`). |
| `profile` | `open` when absent, or `maths`. Colours of the document's own go under `colours` (topic `colour`). |
| `id`, `title` | Required. Identity. `id` is the document's name as the studio made it, the same as its file's name; leave it alone in a patch. |
| `about` | Information that changes nothing seen or heard. |
| `sourceLocale` | Required. The locale written in, such as `en-US`. |
| `params`, `samples` | Required. The problem (topic `problem`). |
| `let`, `vars`, `kind` | Optional parts of the problem. |
| `appearances` | `["light"]`, `["dark"]` or both; both when absent (topic `colour`). |
| `areas` | The shapes of drawing area the document is made for (topic `camera`). |
| `layouts`, `parts`, `shots`, `opening` | The drawing and camera (topics `elements`, `camera`). |
| `elements` | Required. What is drawn (topic `elements`). |
| `intro` | The lines before the first step. |
| `sequence`, `steps` | Required. The step names in order, and the steps (topic `steps`). |
| `try`, `whatIf` | Later parts; not played (below). |
| `colours` | Colours the document names for itself (topic `colour`). |
| `style` | Overrides of the standard style: `easings`, `motion`; and `overrides`, an operation's colour changed at a person's request (topic `colour`). |
| `plays` | The wording suggested for `paced` and `skippable` playback. |
| `wording` | Required. Every line, by locale and wording (topic `wording`). |
| `extensions` | Keys named `vendor.feature`; keep any you do not understand. |

Names of elements, steps, actions, parts, shots, layouts, parameters, `let` and `vars` match
`^[a-z][A-Za-z0-9]{0,47}$`; entry names may have dots, as `do.trade`. Parameters, `let`, `vars`
and elements share one namespace. Reserved: `and`, `or`, `not`, `true`, `false`, function names,
and `i`, `n`, `x0`, `y0`, `left`, `areaW`, `areaH`. Steps and elements are maps; order comes from
`sequence` and from `z`. Colour values are written only under `colours` (topic `colour`); elsewhere name a role (topic `elements`).

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
  `appear`'s `place`; `sin(a)` and `cos(a)` with *a* in degrees, exact at 0, ±0.5 and ±1, so that
  `sin(30)` is 0.5 and `cos(90)` is 0.
- A point at angle *a* clockwise from twelve o'clock and distance *r* from `[cx, cy]` is
  `[cx + r * sin(a), cy - r * cos(a)]` (*y* is down). Mark *i* of sixty round a clock is at
  `a = 6 * i`, and numeral *i* + 1 of twelve at `a = 30 * i + 30`. Write no approximation of a sine.
- At most 256 nodes and 24 levels. Division by zero, an index outside a family, or a selection
  function asked for more than there is, is an error for that problem.
- Selections: `ten` is every instance of `ten`; `ten[k]` one instance; `equation.ans` a run of
  a text element; `ten[k].cross` a piece's cross-out; `s + t` joins without repeats; `whole(s)`
  drops what is crossed out or ghosted. A step's selections are evaluated as it begins, so
  `last(bT, whole(ten))` names the tens still standing.

## elements: what is drawn, and where

The drawing's units start at the top left, *y* down. The layout `stage` is `[1000, 540]` unless
`layouts.stage.size` says otherwise. The core kinds are `text`, `line`, `arrow`, `outline`, `shape` and
`group`. There are two capabilities: `components.arithmetic`, whose pieces are the last row of
the table, and `drawing.turn` (below); draw anything else from the core kinds. Every element has `kind`, and may have `repeat` (count of
instances; `i` is the index in other keys), `let` (below), `when`, `z`, `fixed` (outside the
camera, never dimmed) and `start` (`opacity`, and `progress` for a stroked kind).

| Kind | Keys |
|---|---|
| `text` | `at` (baseline point), `text` (an entry), `runs`, `style` (`equation` 44, `total` 54, `label` 18, `note` 22, `body` 26), `ink`, `size`, `anchor` (`start`, `middle` or `end`: which point of the baseline `at` is). |
| `line` | `from`, `to`; `style` `rule` or `divider`; `ink`; `width`. |
| `arrow` | `from`, `to` (points, or a selection of one instance); `y` to run over the top; `ink` (required); `width`. |
| `outline` | `rect` `[x, y, w, h]` or `around` (a selection); `pad`; `style` `box`, `ring`, `hint` or `target`; `ink` for `box` and `ring`; `width`. |
| `shape` | `rect` (with `corner`), `ellipse` (the rectangle `[x, y, w, h]` it fills) or `points` (with `closed`); `fill` and/or `ink`; `width`. |
| `group` | `members` (a selection of whole instances of other elements; required), `pivot`, `turn`; `start` has `opacity` only. Below. |
| `ten`, `one`, `stick`, `circle` | Pieces of `components.arithmetic`: `rect`, and `look` `pencil`, `traded` or `counted`. Each has a cross-out, `.cross`. |

An outline's `around` fits text as drawn, so a single digit gets a tall, narrow box, and `pad` is one number for every side. To make boxes round one- and two-digit numbers alike, give each outline a `rect` of one size, centred on the numeral.

`width` is the stroke's width in drawing units, a number above 0 or an expression, and is scaled with the drawing; without it a stroke keeps the renderer's, 2.4 for most. A clock's hour hand is a `line` or `arrow` of `"width": 14` and its minute hand one of `"width": 5`, not a filled shape. An arrow's head grows with a width above 2.4.

A shape's `points` may hold arcs among its points: `{"arc": [cx, cy, r], "from": a, "to": b}` (or `[cx, cy, rx, ry]`) draws the curve of the angles `a` to `b`, in degrees clockwise from twelve, in the direction the numbers go. An arc is joined to the entry before it by a straight line, a negative radius mirrors it and the sweep is at most 360. A circle drawn from elsewhere than three o'clock, where an `ellipse`'s stroke starts, is an arc. The orbit of a moon, drawn anticlockwise from nine o'clock, with no list of points:

```json
"orbit": {"kind": "shape", "ink": "line", "points": [{"arc": [440, 270, 170], "from": 270, "to": -90}]}
```

Roles. Without a capability: `paper`, `sheet`, `text`, `muted`, `line`, `pencil`, `onResult` and
`result`. With `components.arithmetic` in `requires`, in any form (a bare `add` too): `subtract`,
`trade`, `add`, `multiply`, `divide`. An operation role is bare (`add`) or has `.fill`, `.ink` or
`.soft`; the others have no suffix. Each operation keeps its role in every explainer; do not use
`subtract` for adding. A key takes these forms, and anything else is an error:

| Key | Accepts |
|---|---|
| `ink` of `text`, `line` and `shape`; `fill` of `shape` | `text`, `muted`, `line`, `pencil`, `sheet`, or an operation role or a colour of the document's own, bare or with a suffix (bare is the ink, or the fill for `fill`) |
| `ink` of `arrow`, of `outline` (`box` and `ring`; the others take none), of `tint` and of `tag` | an operation role or a colour of the document's own, bare: `add`, not `add.ink` |
| `ink` of a run | `result`, `text` or a colour of the document's own, in an `equation` text only |

No key draws `paper` or `onResult`, and a document with `style.palette` is refused with a `schema` error. A `total` text
is centred in `result`, and an `equation` text centred in `text`; leave `ink` and `anchor` out of
both. `label`, `note` and `body` take any `ink` of the first row.

An element's `let` names values computed for each instance, with `i` in scope. The names may be
used in the element's other keys, except `repeat` and `when`, and as placeholders in its entry;
they must not be a parameter, `let`, `vars` value, element or reserved name, and a name of
another element's `let` is unknown. Twelve numerals round a clock, and sixty marks with every
fifth longer, need no approximation and no `each`:

```json
"nums": {"kind": "text", "repeat": 12, "let": {"k": "i + 1"}, "text": "numEntry",
         "at": ["440 + 318 * sin(30 * i + 30)", "388 - 318 * cos(30 * i + 30)"]},
"ticks": {"kind": "line", "repeat": 60, "let": {"r": "mod(i, 5) == 0 ? 254 : 268"},
          "from": ["440 + r * sin(6 * i)", "380 - r * cos(6 * i)"],
          "to": ["440 + 280 * sin(6 * i)", "380 - 280 * cos(6 * i)"]}
```

with the entry `"numEntry": {"text": "{k}", "visual": true}`; `{i}` is also shown, from 0.

A line, arrow, shape or group may have a `pivot`, a point `[x, y]` that it grows and pulses about (and turns about), so a bar that grows up from its base has a `pivot` at the base. A `pivot` needs no capability. To make a hand come out from a hub and turn to an angle, draw
the hand pointing at twelve with no trigonometry, give it a `pivot` at the hub, list `drawing.turn` in `requires` (the key `turn` and the verb need it), and turn it in a
step. The angle is in degrees clockwise from twelve, and the hand turns the way the numbers go: from
0, `to: 150` is clockwise, and `to: -30` is anticlockwise. `grow: 0` on `appear` brings it out of the
`pivot`. A `line`, `arrow`, `shape` or `group` turns; text and pieces do not, and a group turns only if all its members do. A `turn` on the element draws
it at that angle with no motion.

```json
"hand": {"kind": "shape", "closed": true, "fill": "muted", "pivot": [440, 380], "start": {"opacity": 0},
         "points": [[448, 380], [440, 155], [432, 380], [440, 405]]},
"out":  {"do": "appear", "target": "hand", "grow": 0},
"turn": {"do": "turn", "target": "hand", "to": "6 * minute", "at": "end(out)"}
```

A `group` draws the instances its `members` selects as one layer: they appear, fade, move, grow, pulse and turn as one thing, about the middle of their bounds or the group's `pivot`, and none shows through another while the group fades. An instance is in one group at most, groups do not nest and members are not `fixed`. Hide the group, not its members, when they appear together: a member's opacity is multiplied by the group's. A label does not go in a group that travels. A moon of a dark disc, a lit part and a facing arc:

```json
"moon": {"kind": "group", "repeat": 8, "members": "moonDark[i] + moonLit[i] + faceArc[i]", "start": {"opacity": 0}},
"in":   {"do": "appear", "target": "moon[phase]", "from": "moonDark[phase]", "grow": 0.25, "dur": 1.1}
```

A text element's runs are its entry's placeholders: in `"{a} − {b} = {ans}"` the runs are `a`,
`b` and `ans`, and `runs.ans.text` fills `ans` from an entry until a verb sets it. A piece is a
quantity: it is never faded below a ghost (0.28), and nothing removes an element.

## colour: profiles, the colours a document names, and changing an operation's colour

A document is made for a profile. With no `profile` it is `open`, which fixes no colour's meaning. Write `"profile": "maths"` for an explainer on arithmetic that draws the operation roles (`components.arithmetic`), whose colours then mean what the profile fixes. An operation role stays drawable in either profile, and an operation's colour is not used for anything else in `maths`. A profile the studio does not have is a `ref` error.

For a colour that is not an operation's, give the document its own, under `colours`, one entry for each, and name it wherever a role is taken (topic `elements`):

```json
"colours": {
  "hour": {"light": "#CF6900", "dark": "#FCA200", "cue": "the short, wide hand, and the hours on the left"},
  "minute": {"suggested": "purple", "cue": "the long, thin hand, and the minutes on the right"}
}
```

A colour has a value under `light` and under `dark` for each appearance the document is made for (below), or `suggested` with `orange`, `green` or `purple` (the `open` profile's own values, which differ a little from the table's), and a `cue`: what tells its marks apart without colour, such as length, width or place. A `tag` beside a colour of the document's takes that colour as its `ink`, since `result`, its default, may be too near it. `colour` warnings follow (topic `findings`).

Colours that keep 3:1 contrast with each sheet and with their own tint, and are 20 apart from `text`, `pencil` and `line`:

| Colour | Light | Dark |
|---|---|---|
| orange | `#CF6900` | `#FCA200` |
| teal | `#1B8A8A` | `#4EBABA` |
| green | `#189042` | `#5AC672` |
| purple | `#995DE1` | `#C67EFF` |
| pink | `#D54290` | `#FF6CB7` |
| blue | `#247BEA` | `#6390FF` |

- A colour the person names in words: use its row of the table. `muted` is within 20 of teal and of pink in some conditions; if the document draws `muted`, `check` says so.
- Values the person gives: use them, and report each `colour` warning in plain words. When a colour is hard to see, say on which background and offer the nearest value that shows, which the warning names. A person's choice stands.
- The person wants different colours and names none: offer orange and purple, and say that they stay apart for colour-blind viewers and on both backgrounds.

### Changing an operation's colour

In `maths` the six operation colours are fixed. Change one only when the person asks for it, never on your own, and never to colour something that is not an operation (that is a colour under `colours`). Before the edit, say why the colour is fixed, in your own words and in a few lines, then ask:

> The colour for taking away is the same in every ChalkScript explainer, so that a child who has learned what it means can rely on it. The colours were chosen with research on colour vision in mind, and they are checked so that colour-blind children can still tell them apart. I can change it for this explainer. The studio will check the new colour against the others, and an app that plays the explainer may show the standard colour instead. Shall I change it?

Name the operation by what it means: taking away (`subtract`), trading or regrouping (`trade`), the answer (`result`), adding or joining (`add`), groups of (`multiply`), sharing (`divide`). Make the edit only after the person says yes:

```json
"style": {
  "overrides": {
    "subtract": {"light": "#995DE1", "dark": "#C67EFF", "asked": "Make taking away purple, like our worksheets."}
  }
}
```

`asked` is required and holds the person's request, in their words. Give a value for each appearance the document is made for: the table's row for a colour named in words, or the person's own values. Every `check` and `edit` then returns an `override` warning for the operation, which is expected and stays; do not try to clear it. Report any `colour` warning on the new colour in plain words, as for a colour of the document's own, and offer the nearest colour that shows or a colour that stays apart; the person's choice stands. The studio's window shows a notice with a button, "Use the Standard Colour", which removes the override. To restore the colour yourself, remove the operation's entry, and `overrides` when it is left empty. In `open` nothing is fixed and an override is an error: use `colours`.

### Appearances

A document is made for both appearances, light and dark, unless `appearances` says otherwise. Keep both unless the person says that the explainer is only for one, or has chosen colours by looking at one and does not want to tune the other; then write `"appearances": ["dark"]` (or `["light"]`) and give each colour only that value. A value given for the other appearance is kept and not checked. Do not drop an appearance to silence a warning: offer the nearest colour first, and drop the appearance only if the person prefers. Tell a person who asks that a player whose screen is in the other appearance still draws the explainer in the one it is made for, with its caption and controls. Look at a colour in each appearance the document is made for with `show`, `image` and `appearance`. The person can also tick Light or Dark in the studio; ticking one writes a value for each colour that has none there, which `check` then measures like any other.

## steps: steps, actions, timing and the verbs

A step is one change to the picture with one line. Keys: `say` (the step's line, an entry name),
`actions` (name to action), `when`, `shot`, `duration` (replaces the end of the last action),
`hold` (seconds after), `counts` (the step counts aloud), `like` (copy another step's keys,
replacing those given), and `act` and `why` (not played; see `document`).

An action has `do` (the verb), `target`, `at` (start, seconds or an expression such as
`"end(arrow) + 0.2"`), `dur` (per instance), `each` (stagger between instances), `reverse`,
`ease` (a curve name), `when`, `wait: "voice"` and `mark: true` (undone when the next step
begins, as a tinted digit). An action ends at `at + (n − 1) · each + dur`; the step's timeline
is the latest end, plus `hold`. An action with no `at` starts at 0, with the step's line: chain it
with `"at": "end(name)"`. Default durations: appear 0.3, draw 0.4, fade 0.35, travel 1.2
seconds. `wait: "voice"` holds the step's clock at that action's start until the lines said before
it have been heard (on an `each`, at each instance): use it on an action that should follow the
line, not seconds guessed for it. The studio plays with a stand-in voice that says nothing and takes the time a line would take to say: 0.3 seconds and a third of a second for each word of its spoken form, at the player's pace. `wait: "voice"` therefore holds in the studio for about as long as it would with a spoken line, which is an estimate and not the time of any particular voice.

| Verb | Kind | Does |
|---|---|---|
| `appear` | appear | From opacity 0; `rise` (a distance: it starts this far below its place, so a negative number drops in), `grow` (a scale from 0 to 1 that it grows from, about its `pivot` if it has one, and else about its middle: a text's, of the text as drawn, so it needs no `rise`), `from` (a point `[x, y]`, or one instance such as `moonDark[phase]`: it starts with its middle, or `pivot`, there and travels to its place as it grows; not with `rise`), `place` (`split(ten[k])`), `text`. The target may be a group. |
| `fade` | fade | To `to`, 0 to 1 or `"ghost"`. A crossfade from one arrangement to another is two groups, one faded to 0 and the other appeared in the same action time. |
| `draw` | draw | Draws the stroke of a `line`, `arrow`, `outline` or `shape` with `ink` from progress 0 to 1. A `shape` with only `fill` is whole from the start: use `appear`, `fade` or `move`. A `width` thickens the stroke (topic `elements`); do not draw a thick line as a filled `shape`. |
| `cross` | draw | Draws a piece's cross-out; `fade` seconds then ghost it. |
| `tint` | draw | A pale `ink` role behind a run of an `equation` text; with `mark`, marks a digit. The studio refuses `tint` on an element, or on a run of a text in another style, as `capability`: to mark a numeral or a word, draw an `outline` round it. |
| `move` | travel | To `to`, or back to its place. `to` places the instance's reference point (a text's `at`, the `from` of a line or arrow, a shape's first point, a group's middle, else the top-left corner of its bounds) and the geometry goes with it, so elements moved to one point each go by their own point and do not keep their places relative to each other. `via` keyframes `[offset, x, y]` with `x0`, `y0`. |
| `gather` | travel | From the positions of `from` to their places. |
| `turn` | travel | Needs `drawing.turn`. Turns a `line`, `arrow`, `shape` or group of them about its `pivot` to `to`, an angle in degrees, by the difference from its angle now; from 150, `to: 360` carries on round to twelve. Without `to`, back to its place's angle. |
| `look` | instant | Sets a piece's `value` look. |
| `set` | instant | Sets a text or run to the entry `text`. |
| `tag` | appear | A small card with the entry `text` over each target, as wide as its text; its `dur` is how long it is shown, at full strength for the middle half (0.3 by default, so give `dur: 2` for a card to be read); its `ink` is `result` unless given. |
| `pulse` | appear | Grows to 1.15 and back, about its `pivot` if it has one, and else its middle; a group pulses as one. |
| `say` | instant | Queues the entry `line`; `count: true` for a count; `caption`. |
| `each` | none | For each instance of `target`, runs `then` every `gap` seconds, with `i` and its `let`. |

`each` counts instances, or sets a number that changes within the step. It names a `target`, a
`gap` in seconds, optional `let` locals evaluated with `i`, the instance's position from 0, in
scope, and `then`, the actions run for each instance; an action in `then` without a `target` acts
on the current instance. Count over `first(n, s)`, not over every instance with a `when` in `then`: an iteration it skips still takes
its `gap`. Numerals that do not change are not set by a verb: number repeated text
elements with the element's own `let` (topic `elements`) and bring them in with `appear` and
`each: 0.24`, a stagger. A step whose `when` is false for the problem is not among that problem's
steps, so `show` of it names the steps the problem has.

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
- A caption that differs from the speech is a phrase entry, which is a text entry and may have `spoken`.
  With the `let` values `"tens": "div(minute, 10)"` and `"ones": "mod(minute, 10)"`, `{tens}{ones}` pads a
  number (05, 00), and is said "seven:zerofive" without `spoken`. These show "Make the clock say 7:05."
  and say "seven oh five":

  ```json
  "clockOh": {"text": "{hour}:{tens}{ones}", "spoken": "{hour} oh {n}"},
  "goal": "Make the clock say {clockOh:minute}."
  ```
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
layout with `camera: true`. A step with no `shot` keeps the shot of the step before it, the first
the `opening` shot, and with neither frames the whole drawing. When a step's shot frames
differently from the one before, the camera moves first (0.9 seconds in the standard style) and the
step's actions start after the move, so an action at 0 starts at 0.9, as `show` lists it; the
step's line still begins at 0. What lies outside the shot is dimmed, not hidden; a group is dimmed as one, by its middle. A shot's `up`
turns the picture so that a direction in the drawing, in degrees clockwise from twelve, points to
the top, with text kept level: to look along a sight line drawn at angle `a`, write
`"fromEarth": {"frame": ["home", "chosen"], "up": "a"}`. The camera turns the shorter way during its
move, and the next shot without `up` turns it back. Another layout has `suits` (an expression of `areaW` and
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
| `colour` | A warning, made in each appearance the document is made for: a colour that is hard to see (on the light or dark background, or on its own tint), two colours drawn together that may look alike to some colour-blind viewers, in `maths` a colour near an operation's, or a colour with no `cue`. The message gives the measurement and, for contrast, the nearest colour that shows. |
| `override` | A warning that the document changes an operation's colour in `maths` (topic `colour`). It stays while the override does; it is the person's choice, made after the explanation. |
| `capability` | A kind, verb or key used without its capability in `requires` (`components.arithmetic` or `drawing.turn`), or one this studio does not draw. |
