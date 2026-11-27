# The explainer document format, version 1.0

**Version 1.0 is a draft.** It will change while a player and an authoring app are built against
it. A document's meaning is fixed only from the release of this reference that declares the format
stable. Until then, a revision of this reference may change the meaning of a 1.0 document, and the
versioning rules of section 2.2 apply from that release on.

An *explainer* shows a method or an idea one step at a time, with a drawing, motion and a spoken
line, on one problem whose values it is given. This reference defines the document that holds one
explainer: what is drawn, the steps, their timing and easing, the camera, the narration in every
wording and language the document carries, and what a viewer may do on a step. It is written so
that a reader (which parses and checks a document) and a player (which plays it) can be built from
it alone.

The JSON Schema for this version is [explainer-1.0.schema.json](explainer-1.0.schema.json). Two
complete documents are in [examples/](examples/): `subtraction.explainer` (two-digit subtraction,
with a trade of a ten where one is needed) and `equal-groups.explainer` (multiplication as equal
groups). Section 22 describes these files and the script that checks them.

## Contents

1. Conventions
2. The file: identification, versioning and capabilities
3. Names
4. The top-level keys
5. The problem: `params`, `let`, `vars`, `samples` and `kind`
6. Expressions
7. Selections
8. Layouts and coordinates
9. Elements
10. Parts, shots and the camera
11. Steps
12. Actions and timing
13. The verbs
14. Narration and wording
15. Interaction
16. Style
17. Playback options
18. State, stills and what a player is given
19. The canonical form, the hash and the revision
20. Patches
21. Findings
22. Conformance, and the files beside this reference
23. Prior art

## 1. Conventions

"Must" and "must not" state requirements on a document, a reader or a player; "should" states a
recommendation. A *document* is one explainer in this format. A *reader* parses a document and
reports findings (section 21). A *player* plays a document for one problem. A *validator* is a
reader that also evaluates the document over many problems; its further checks are outside this
reference except where they are named. A *viewer* is whoever watches or acts on the explainer.

A path such as `/steps/trade/actions/travel/dur` is a JSON Pointer (RFC 6901). Times are in seconds.
Lengths are in the drawing's units (section 8).

## 2. The file: identification, versioning and capabilities

### 2.1 The file

A document is a JSON text (RFC 8259) encoded in UTF-8 without a byte order mark, whose value is an
object. Its file name ends in `.explainer`. A reader identifies a document by its content, not its
name: the object has `"format": "chalkscript-explainer"` and a `version`.

Duplicate keys in one object make the document unreadable. A reader must refuse such a document,
since JSON parsers disagree about which value wins.

### 2.2 Versioning

`version` is a string `"MAJOR.MINOR"`, such as `"1.0"`.

- A minor version adds and never changes. It may add verbs, element kinds, inputs, functions and
  optional keys. An optional key added in a minor version is one whose absence keeps the earlier
  meaning, so a player that ignores it plays the document as the earlier version defines. A key
  whose effect must not be lost is added with a capability instead (section 2.3). A function added
  in a minor version is not reserved as a name (section 3), so that no earlier document gains an
  error; a reader that lacks it reports an `expr` error for a call and refuses the document.
- A major version may change meaning. It comes with a converter from the previous major version.
- A reader refuses a document whose major version it does not implement.
- A reader that meets a document with a higher minor version than its own reads it, lists the
  version as a warning, and refuses only what it cannot play: a verb, element kind or input it does
  not know is an error (section 2.4).

### 2.3 Capabilities and `requires`

A *capability* is a named set of element kinds, verbs, keys and functions beyond the core.
`requires` lists the capabilities a document uses, as an array of unique names; it may be absent
or empty. A capability name is two or more lowercase dot-separated words, such as
`components.arithmetic`.

A player that does not implement every capability in `requires` must refuse the document and name
each missing capability. It must not draw an approximation. A document that uses a kind, verb, key
or function of a capability it does not list is in error.

This version defines two capabilities: `components.arithmetic` (section 9.4) and `drawing.turn`
(section 9.5). Later versions are expected to add capabilities for other kinds of drawing, such as
parts placed in a projected space for exploded views, and imported vector artwork with named parts.
Each will be listed in `requires` by the documents that use it, so it cannot change the meaning of
a document that does not.

### 2.4 Unknown keys and extensions

A reader lists every key that this version, the document's required capabilities and the
reader's own minor version do not define, as a warning with its path, and otherwise ignores it.
A value of the wrong type, a missing required key, an unknown verb, an unknown element kind, an
unknown input and a reference to a name that does not exist are errors. A document with an error is
not played.

The JSON Schema is stricter than a reader: it refuses unknown keys, so that a misspelt key is
caught when a document is written.

`extensions` holds keys a tool needs that this reference does not define. Each key is named
`vendor.feature` (a lowercase word, a dot, then letters, digits, dots or hyphens), and its value is
any JSON value. A reader does not report what is under `extensions`. A tool that edits a document
must keep every extension it does not understand unchanged. An extension must not change what a
player draws or says; anything that does is a capability.

## 3. Names

Element, step, action, part, shot, layout, parameter, `let`, `vars` and wording-section names
match `^[a-z][A-Za-z0-9]{0,47}$`. Wording entry names match
`^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)*$` and have at most 64 characters, such as `do.trade`.
Neither pattern contains `/` or `~`, so a JSON Pointer to any named thing needs no escaping.

There are four separate namespaces:

- **Values and elements**: `params`, `let` (including the names a layout adds), `vars` and
  `elements`. These are the names an expression can use, and they must be distinct from one
  another.
- **Parts**, named in shots only.
- **Shots**, **layouts** and **steps**, each its own map.
- **Actions**, one namespace per step (and per `each`, for the actions in its `then`).

The following are reserved and must not name a parameter, a `let`, a `vars` value, an element or a
local: `and`, `or`, `not`, `true`, `false`, the function names of section 6.4 that the first draft
of this version defined (`div`, `mod`, `min`, `max`, `abs`, `floor`, `round`, `str`, `first`,
`last`, `slice`, `whole`, `start`, `end` and `split`), and the locals `i`, `x0`, `y0`, `left`,
`areaW` and `areaH`. The local `n` is reserved in the first namespace; an `each` may define it
(section 13.13). A call always names a function and a bare name never does, so a function added
later, such as `sin` and `cos`, is not reserved, and an element or a value may be named `sin`.

The names of an element's `let` (section 9.1) are locals, and must not be any other name of the
first namespace: a parameter, a `let` of the document, a `vars` value or an element. A reader that
does not know the key then reports every use of one as an unknown name, and never plays the
document with a document value of the same name.

An id is stable for the life of the thing it names. Renaming is an edit like any other; the reader
then reports every reference the rename broke.

## 4. The top-level keys

| Key | Required | Holds |
|---|---|---|
| `format` | yes | `"chalkscript-explainer"`. |
| `version` | yes | `"1.0"` (section 2.2). |
| `requires` | no | Capability names (section 2.3). |
| `id` | yes | The explainer's id, matching `^[a-z][a-z0-9-]{0,63}$`. |
| `title` | yes | A title, for people choosing or reviewing explainers. It is not shown by a player. |
| `about` | no | An object of information that changes nothing seen or heard, such as `licence`, `authors` (an array of strings) and `notes`. Any keys are allowed. |
| `sourceLocale` | yes | The locale the document was written in, a BCP 47 tag (section 14.7). |
| `params` | yes | The problem's values (section 5.1). |
| `let` | no | Values computed from the parameters (section 5.2). |
| `vars` | no | Values a viewer's actions may change (section 5.3). |
| `samples` | yes | The problems a reviewer is shown (section 5.4). |
| `kind` | no | Which other problems are of the same kind (section 5.5). |
| `areas` | no | The shapes of drawing area the document is made for (section 8.2). |
| `layouts` | no | The drawing's size, and alternative layouts (section 8). |
| `elements` | yes | What is drawn (section 9). |
| `parts` | no | Named selections, which shots frame (section 10). |
| `shots` | no | The regions the camera frames (section 10). |
| `opening` | no | The shot before the first step. |
| `intro` | no | The lines said before the first step (section 14.8). |
| `sequence` | yes | The step names in order; at least one, each once. |
| `steps` | yes | Each step, by name (section 11). Every name in `sequence` is a step, and every step is in `sequence`. |
| `try` | no | The problem the viewer tries alone (section 15.5). |
| `whatIf` | no | A part in which the viewer drags a value toward goals (section 15.6). |
| `style` | no | Overrides of the standard style (section 16). |
| `plays` | no | The wording a document suggests for each playback control (section 17). |
| `wording` | yes | Every line, by locale and wording (section 14). |
| `extensions` | no | Section 2.4. |

Steps and elements are maps keyed by name because JSON gives no meaning to the order of an
object's keys. Order, where it matters, is given by an array (`sequence`) or by a stated rule.

## 5. The problem

### 5.1 `params`

`params` maps each parameter's name to its declaration:

| `type` | Further keys | A value is |
|---|---|---|
| `int` | `min`, `max` (required) | An integer from `min` to `max` inclusive. |
| `number` | `min`, `max` (required) | A number from `min` to `max` inclusive. |
| `bool` | none | `true` or `false`. |
| `choice` | `values` (required): a non-empty array of distinct strings or numbers | One of `values`. |

`min` and `max` are numbers or expressions. A bound's expression may name other parameters and
nothing else; the parameters' bounds must not depend on one another in a cycle. A *problem* is an
object giving a value for every parameter. A player given a problem with a missing, extra,
mistyped or out-of-range value refuses it and makes no explainer.

The *problem space* of a document is every problem its parameters allow. It is enumerated in
*parameter order*: parameters sorted so that each comes after every parameter its bounds name, and
otherwise by name in Unicode code point order; each `int` from `min` up to `max`, each `bool` as
`false` then `true`, and each `choice` in the order of `values`. A `number` parameter makes the
space infinite.

### 5.2 `let`

`let` maps names to expressions computed from the parameters and from other `let` names. It must
not be cyclic. A `let` expression must not name a `vars` value, an element or a local, so a `let`
value is fixed for a problem and a layout. A reader evaluates `let` values on demand and keeps each
one, so their order in the document does not matter.

### 5.3 `vars`

`vars` maps names to expressions that give their starting values, computed from parameters and
`let` values. A `vars` value changes only when a viewer's action binds it (section 15) or drags it
(section 15.6). In the watched part every `vars` value keeps its starting value.

`repeat` and `when` on an element must not depend on a `vars` value, so the instances of every
element are fixed for a problem. Other element keys may depend on `vars` values and follow them.

### 5.4 `samples`

`samples` is a non-empty array of distinct problems. They are the problems a reviewer is shown,
and the problems a validator evaluates when the problem space is too large to enumerate. A
validator reports a *step-list shape* (the list of steps a problem has, after `when`) that occurs in
the problem space and in no sample.

### 5.5 `kind`

`kind` defines, for a problem *P*, which other problems are of the same kind, and which two of them
a player uses for do it with me and for try one. It is optional; without it the player uses *P* for
both.

| Key | Holds |
|---|---|
| `search` | Parameter name to `[min, max]`, each a number or an expression of other parameters: a narrower range to search. By default each parameter's own range. |
| `same` | Expressions whose values a candidate must share with *P*. |
| `differ` | Expressions whose values a candidate must not share with *P*. |
| `near` | A parameter or `let` name to a number: the candidate's value is at most that far from *P*'s. |

`kind` may be used only when every parameter is `int`, `bool` or `choice`, and the search space
must have at most 100,000 problems.

The pick is defined so that every player makes the same one:

1. The candidates *C* are the problems of the search space, in parameter order (section 5.1), that
   are within the parameters' own ranges and satisfy `same`, `differ` and `near`.
2. If *C* is empty, both problems are *P* itself. A validator reports this.
3. Let *h* be the sum, over the parameters in parameter order with *j* counting from 0, of the
   parameter's value multiplied by the *j*-th of the weights 31, 17, 13, 11, 7, 5, 3, 2, taken
   cyclically. A `bool` counts as 0 or 1 and a `choice` as the index of its value.
4. Let *pick(k)* be the candidate at index (*h* + 97*k*) mod |*C*|.
5. The do-it-with-me problem is *pick(1)*. The try-one problem is the first *pick(k)*, for *k* from
   2 to 39, whose value for every `differ` expression differs from the do-it-with-me problem's; if
   there is none, it is *pick(1)*.

## 6. Expressions

### 6.1 Where expressions are used

Wherever this reference says a value is a number, a truth value, a selection or a time, a document
may give an *expression* instead: a JSON string in the language of this section. A plain JSON number
or boolean is also accepted where a number or truth value is expected. A JSON string is always read
as an expression in such a place; a literal string inside an expression is written in single quotes.

### 6.2 Grammar

In this grammar, quoted text is literal, `[ ]` is optional, `{ }` repeats zero or more times, and
`|` separates alternatives. Whitespace (space, tab, carriage return, line feed) may appear between
tokens and is otherwise ignored.

```
expression  = conditional ;
conditional = or [ "?" conditional ":" conditional ] ;
or          = and { "or" and } ;
and         = not { "and" not } ;
not         = "not" not | comparison ;
comparison  = sum [ ( "==" | "!=" | "<" | "<=" | ">" | ">=" ) sum ] ;
sum         = product { ( "+" | "-" ) product } ;
product     = unary { ( "*" | "/" ) unary } ;
unary       = "-" unary | postfix ;
postfix     = primary { "[" expression "]" | "." name } ;
primary     = number | string | "true" | "false" | call | name | "(" expression ")" ;
call        = name "(" [ expression { "," expression } ] ")" ;
number      = digit { digit } [ "." digit { digit } ] ;
string      = "'" { any character except "'" } "'" ;
name        = letter { letter | digit } ;
```

`letter` is an ASCII letter and `digit` an ASCII digit. A keyword (`and`, `or`, `not`, `true`,
`false`) is never a name. Precedence therefore runs, from loosest to tightest: the conditional
(which groups to the right), `or`, `and`, `not`, a comparison (which does not chain: `a < b < c` is
a syntax error), `+` and `-`, `*` and `/`, unary minus, then indexing and member access.

An expression has at most 256 nodes and is nested at most 24 deep. A node is a literal, a name, an
operator applied to its operands, a call, an index or a member access; the root is at depth 1.

### 6.3 Values and operators

A value is a number (an IEEE 754 double), a truth value, a string, a selection (section 7) or, in
`components.arithmetic`, a placement (section 9.4). There is no conversion between them.

| Operator | Operands | Result |
|---|---|---|
| `+` `-` `*` | numbers | A number. `+` on two selections is section 7's concatenation. |
| `/` | numbers | A number. Division by zero is an error. |
| unary `-` | a number | A number. |
| `==` `!=` | two values of the same type, not selections | A truth value. Numbers compare exactly. |
| `<` `<=` `>` `>=` | numbers | A truth value. |
| `and` `or` | truth values | A truth value. The right operand is evaluated only when the left does not decide the result. |
| `not` | a truth value | A truth value. |
| `c ? x : y` | `c` a truth value | `x` or `y`; only the chosen one is evaluated. |
| `s[k]` | `s` the name of an element with `repeat`, or a selection of one family; `k` an integer | Section 7. |
| `s.m` | a selection | Section 7. |

The short-circuit rules are part of the language: `dT > 1 ? room / (dT - 1) : 40` is valid when
`dT` is 1.

### 6.4 Functions

| Function | Result |
|---|---|
| `div(a, b)` | ⌊*a* / *b*⌋. Error if *b* is 0. |
| `mod(a, b)` | *a* − *b*·⌊*a* / *b*⌋, which has the sign of *b*. Error if *b* is 0. |
| `min(a, b, ...)`, `max(a, b, ...)` | The least or greatest of two or more numbers. |
| `abs(a)` | The absolute value. |
| `floor(a)` | ⌊*a*⌋. |
| `round(a)` | The nearest integer; a half rounds away from zero. |
| `str(a)` | An integer's decimal digits, with `-` if it is negative; a string unchanged. Error for any other value. |
| `first(n, s)`, `last(n, s)`, `slice(s, start, n)` | Section 7. |
| `whole(s)` | Section 7. |
| `start(a)`, `end(a)` | Times; section 12.3. |
| `split(s)` | A placement, in `components.arithmetic` (section 9.4). |
| `sin(a)`, `cos(a)` | The sine and cosine of the angle *a*, in degrees. The angle is reduced modulo 360 first, and the result is exactly 0, 0.5, −0.5, 1 or −1 at the multiples of 30 and 90 where that is the true value, so that `sin(30) == 0.5` and `floor` and `round` of such a result are never a unit out. Elsewhere a player may use its own library, and two players may differ in the last place. |

A call with the wrong number or types of arguments is an error.

A point at angle *a*, clockwise from twelve o'clock, and distance *r* from (*cx*, *cy*), with *y*
increasing downward, is `[cx + r * sin(a), cy - r * cos(a)]`.

### 6.5 Names and scope

A name in an expression is resolved, innermost first, in: the locals of where it is evaluated (the
table below); then the parameters, `let` values (with the layout's replacements, section 8),
`vars` values and elements of the document. A name found in none is an error.

| Local | In scope |
|---|---|
| `i` | In the keys of an element with `repeat`, other than `repeat` and `when`, and in the entries its text and runs show (section 14.3): the instance's index, from 0. In an action's per-instance keys, `rise`, `grow`, `to` and `via`: the instance's position in the action's selection, from 0. In an `each`: the position of the current instance. |
| the names of an element's `let`, such as `k` | In that element's keys other than `repeat` and `when`, which fix how many instances there are, and in the entries its text and runs show. Their expressions may name `i`, when the element has `repeat`, and one another. |
| the names of an `each`'s `let`, such as `n` | In that `each`'s `gap` and in its `then` actions and their lines. |
| `x0`, `y0` | In a `move`'s `via`: the instance's position as the move begins (section 13.6). |
| `n` | In a `forms` entry and in a phrase entry: the value it is filled with (section 14.3). |
| `left` | In a `tooMany` miss line: how many right marks the step still needs. |
| `areaW`, `areaH` | In a layout's `suits` and `size`: the width and height of the area the layout is chosen for (section 8.2). |

### 6.6 Evaluation and errors

Expressions have no side effects and no loops, and a document defines no functions, so every
evaluation ends. A reader parses every expression and reports a syntax error, an unknown name, an
unknown function, a wrong number of arguments and a cycle among `let` values, each with the
character offset at which it was found (section 21).

Evaluation for a problem can fail: division by zero, an index outside a family, a selection
function asked for more instances than there are, an operand of the wrong type, a result that is
not finite, or `start()` or `end()` of an action that does not run. Each is an error naming the
problem's values; a value never silently becomes 0. A document is *sound* for a problem when
nothing evaluated for that problem fails. A player refuses a problem for which the document is not
sound.

## 7. Selections

A *selection* is an ordered list of distinct *instances*. An element without `repeat` has one
instance, or none when its `when` is false; an element with `repeat` has as many as its `repeat`
gives, indexed from 0. A selection may also hold *sub-parts*: the runs of a text element and the
cross-out of a piece.

| Written | Selects |
|---|---|
| `ten` | Every instance of the element `ten`, in index order. |
| `ten[k]` | The instance of `ten` with index *k*; an error if there is none. |
| `equation.ans` | The run `ans` of the text element `equation` (section 9.2). |
| `ten[k].cross` | The cross-out of that instance (section 9.4). `ten.cross` selects the cross-out of every instance. |
| `s + t` | The instances of `s`, then those of `t` that are not already in `s`. |
| `first(n, s)`, `last(n, s)` | The first or last *n* of `s`, in their order in `s`. An error if *n* is negative or more than `s` holds. |
| `slice(s, start, n)` | The *n* instances of `s` from position *start*. An error if they are not all in `s`. |
| `whole(s)` | The instances of `s` that are *whole*: not crossed out by `cross` and not faded to a ghost (section 13.2). |

An action's selection is evaluated once, as its step begins, against the state the step begins in
(section 18). This is what lets one step serve both a watched playback and one in which the viewer
chose which piece to act on: `last(bT, whole(ten))` names the tens still standing, whichever were
crossed out before.

## 8. Layouts and coordinates

### 8.1 Coordinates and layouts

A drawing has its own units. The origin is the top-left corner, *x* increases to the right and *y*
downward. A player scales the drawing to fit the area it is given, keeping its shape, and centres
it; it never crops or stretches it.

`layouts` maps layout names to layouts. The layout `stage` is the default and has a `size` of
`[1000, 540]` unless it gives another. Each other layout has:

| Key | Holds |
|---|---|
| `suits` | A truth value of `areaW` and `areaH`: whether it suits a drawing area of that size, in points. Required. |
| `size` | `[width, height]`, numbers or expressions of `areaW`, `areaH` and the document's values. Required. |
| `camera` | `true` if the drawing is seen through the camera in this layout (section 10). By default `false`; `stage` may also set it. |
| `band` | The height at the top of the drawing kept for fixed elements when the camera is on (section 10.3). By default 0. |
| `let` | Values that replace, or add to, the document's `let` in this layout. |

Given the area of section 8.2, a player uses the first layout other than `stage`, by name in code point
order, whose `suits` is true, and otherwise `stage`. A name a layout adds to `let` exists only in
that layout, and may be named only by that layout's own `let` values; every other name a layout
gives must already be in `let`.

### 8.2 The areas a document is made for

`areas` lists the shapes of drawing area the document is made for, and the layout it is drawn in
at each. Each entry has `layout`, the name of a layout or `stage`, and `ratio`, `[min, max]`: the
least and greatest ratio of the area's width to its height, numbers with 0 < `min` <= `max`. The
*declared shapes* are the ratios inside any entry's range, ends included. Ranges may meet at an
end and may leave gaps; an entry whose `min` equals its `max` declares one shape. `areas` is
optional; when present it has at least one entry. A document without it declares nothing, and a
player lays it out for the area it is given, as section 8.1 says.

Given a drawing area *w* by *h*, a player finds the area it lays the document out for. Without
`areas`, it is *w* by *h*. With `areas`, if *r* = *w* / *h* is a declared shape, it is *w* by *h*.
Otherwise let *r'* be the declared shape nearest *r*, by |ln *r* - ln *r'*|, taking the greater
when two are equally near; the area is the largest of ratio *r'* inside *w* by *h*, which is
(*h* * *r'*, *h*) when *r'* < *r* and (*w*, *w* / *r'*) otherwise, centred in the area the player
was given. The layout is then chosen for that area as section 8.1 says, and `areaW` and `areaH`
are its width and height. A player that lays the document out for an area other than the one it
was given says so to whoever gave it the area (section 18).

At every declared shape, the layout section 8.1 chooses should be the one the entry names. A
reader checks this (section 21, `areas`).

## 9. Elements

### 9.1 Keys every element may have

| Key | Holds |
|---|---|
| `kind` | The element kind: a core kind (section 9.2 and 9.3) or one from a required capability. Required. |
| `repeat` | An integer from 0 to 1,000: how many instances. Without it, the element has one instance. |
| `when` | A truth value: whether the element exists for this problem. By default `true`. |
| `z` | Draw order; lower is drawn first. By default 0. Ties are drawn in the order of element names by code point, then by instance index, so every player draws the same. |
| `fixed` | `true` if the element is drawn outside the camera and never dimmed (section 10.3). By default `false`. |
| `start` | The starting `opacity` (0 to 1, by default 1) and, for a stroked kind, the starting `progress` (0 to 1, by default 1) of every instance. |
| `let` | An object of names to expressions, evaluated for each instance, each after the values it names, with `i` (when the element has `repeat`) and the document's values in scope. The names are locals of the element's other keys except `repeat` and `when`, and of the entries its text and runs show (section 6.5), and must not be any other name of the first namespace (section 3). For example, `"repeat": 12, "let": {"k": "i + 1"}` with the entry `{k}` shows the numerals 1 to 12. |

Colours are given only as *roles* (section 16.1), never as colour values.

Each instance has a *place* (where its geometry puts it) and a *position*, which is its place unless a
verb has moved it. Its position is a reference point: the top-left corner of its `rect`, its `at`,
or the `from` of a line or arrow; moving an instance moves its whole geometry with that point.

The *bounds* of an instance, used by `around`, parts, tags and the reading of marks, are: its
`rect`; the box round the points of a line, arrow or shape; and for a text element, the point `at`
with no size. The bounds of a line, arrow or shape that is turned (section 9.5) are the box round
its turned geometry.

### 9.2 Text

| Key | Holds |
|---|---|
| `at` | `[x, y]`: the anchor, on the text's baseline. Required. |
| `text` | The wording entry shown. Without it the element shows nothing until a verb gives it text. |
| `runs` | Run name to `{ink, text}`: properties of the runs named below. |
| `style` | `equation`, `total`, `label`, `note` or `body`. By default `body`. |
| `ink` | The role the text is drawn in, replacing the style's. |
| `size` | The type size in drawing units, replacing the style's. |
| `anchor` | `start`, `middle` or `end`: which point of the baseline `at` is, replacing the style's. |

| Style | Size | Anchor | Role |
|---|---|---|---|
| `equation` | 44 | middle | `text` |
| `total` | 54 | middle | `result` |
| `label` | 18 | start | `muted` |
| `note` | 22 | middle | `muted` |
| `body` | 26 | middle | `text` |

**Runs.** Every placeholder in the entry a text element shows (section 14.2) is a *run*, named by
the placeholder's name, or by the phrase entry's name for a phrase placeholder. A run can be the
target of `tint`, `appear`, `set` and `fade`, as `equation.bO`. A run listed in `runs` may give
`ink`, the role its text is drawn in, and `text`, an entry whose text fills the placeholder in place
of a value. Such a placeholder need not be a name in scope: in `"{a} − {b} = {ans}"`, `ans` is
filled from the run's `text`.

### 9.3 Lines, arrows, outlines and shapes

These are the *stroked* kinds: their `progress` is how much of the stroke is drawn, from its start.

| Kind | Keys |
|---|---|
| `line` | `from` and `to`, points (required); `style`: `rule` (solid, by default) or `divider` (dashed); `ink`, by default `pencil` for a rule and `line` for a divider. |
| `arrow` | `from` and `to`, each a point or a selection of exactly one instance; `y`, a number; `ink`, required. The head is drawn at `to` once `progress` is 1. |
| `outline` | `rect` (`[x, y, width, height]`) or `around` (a selection), one of them required; `pad`; `style`: `box`, `ring`, `hint` or `target`, required; `ink`. |
| `shape` | One of `rect` (with `corner`, a radius), `ellipse` (a rectangle it fills) or `points` (an array of points, with `closed`, by default `false`); `fill`, a role for the inside; `ink`, a role for the stroke. At least one of `fill` and `ink`. |

An arrow between two points is straight. The head points along the arrow's last segment, in the direction
the arrow travels there; a last segment of no length gives way to the nearest earlier one that has length,
and an arrow with none has a head that points down. An arrow from or to a selection starts or ends 8 units
above the middle of the top edge of the instance's bounds. With `y`, the arrow runs vertically to
height `y`, across, and vertically down to its end, as an arrow over the top of a drawing does.

An outline's `around` is the box round the bounds of the selected instances at their places, grown
by `pad` on every side; `pad` is by default 12 for `hint` and 0 otherwise. A text element, whose
bounds are a point, is enclosed as it is drawn: the box of its line of text, with the line's lower
edge at `at` and its left edge, middle or right edge there for the `anchor` `start`, `middle` or
`end`. The box is of the text the element shows before the first step. An outline with `around`
selecting nothing has no instance. The outline styles are:

| Style | Drawn as | Role |
|---|---|---|
| `box` | A solid rounded rectangle (corner 16). | `ink`, required. |
| `ring` | A solid rounded rectangle (corner 16), round a group. | `ink`, required. |
| `hint` | A dashed loop (corner 18), at 0.8 opacity, pointing at what a step looks at. | `muted`. |
| `target` | A dashed box where an answer is to be written. | `result`. |

Stroke widths, dash lengths and corner radii other than those stated are the renderer's; the
reference renderer's values are a stroke of 2.4 units, a cross-out of 3, a divider of 2 dashed 4 on
7, and a hint dashed 3 on 6.

### 9.4 The capability `components.arithmetic`

This capability adds four kinds of *piece*, one placement function and the operation roles
`subtract`, `trade`, `add`, `multiply` and `divide` of the standard style (section 16.1). The role
`result` is part of the core, since outlines, tags and text styles use it.

| Kind | Drawn as |
|---|---|
| `ten` | A tall rectangle, as a ten is drawn on a worksheet. |
| `one` | A small square. |
| `stick` | A ten drawn as a stick: a line down the middle of its `rect`, stopping 6 units short of each end. |
| `circle` | A one drawn as a circle inside its `rect`. |

A piece has `rect` (required) and `look`: `pencil` (the default: drawn in `pencil`), `traded` (in
the `trade` role's ink, as a piece that came from a traded ten) or `counted` (in the `result` role,
keeping a pale fill so that what has been counted stays visible).

Every piece instance has a sub-part, its *cross-out* (`.cross`): a line from 8 units left of and
below its `rect`'s lower-left corner to 8 units right of and above its upper-right corner (5 units
for `one` and `circle`), drawn in the `subtract` role. It has its own `progress` (starting at 0) and
`opacity`.

`split(s)` is a *placement*, used only as the value of `appear`'s `place`. `s` must select one
`ten` or `stick`, with `rect` [*x*, *y*, *w*, *h*]; the action's targets must be exactly ten `one`
instances; the *k*-th is placed at (*x* + 1, *y* + *k*·*h*/10 + 1).

A piece must never be faded below a ghost (section 13.2). A piece is a quantity, and a quantity is
never erased.

### 9.5 The capability `drawing.turn`

This capability adds two keys to lines, arrows and shapes, the verb `turn` (section 13.14), and the
growing and pulsing of an instance about a point of its own. It is a capability because a player
that ignored the keys would draw every turned instance at its unturned angle, which is a different
drawing and not a plainer one. Text elements, outlines and pieces do not turn: a numeral stays
upright, and a piece's drawing is fixed (section 9.4). A `turn` or `pivot` on one of them is a
`schema` error.

| Key | On | Holds |
|---|---|---|
| `turn` | `line`, `arrow`, `shape` | The angle, in degrees clockwise, at which each instance is drawn about its pivot, at its place. A number or an expression, with `i` and the element's `let` in scope. By default 0. |
| `pivot` | `line`, `arrow`, `shape` | The point `[x, y]` that each instance turns about, at its place. By default its reference point (section 9.1): the `from` of a line or arrow, the first of a shape's `points`, or the top-left corner of a shape's `rect` or `ellipse`. |

The geometry is given as it is at an angle of 0, and `turn` carries it to its angle. A hand that
points at twelve is drawn pointing at twelve, and is turned to the time. An arrow's head follows
the turned path: it points along the arrow's last segment as turned. An angle is not limited to one turn: 390
is drawn as 30, and a turn from 0 to 390 makes a whole turn and 30 more (section 13.14).

An instance's pivot moves with it: after `move`, it is turned, grown and pulsed about its moved
pivot. An instance that has a `pivot` grows and pulses about it (sections 13.1 and 13.11), so that
a filled hand comes out of its hub. One without a `pivot` grows and pulses about the middle of its
bounds, as every other instance does.

The *bounds* of a turned instance (section 9.1), which `around`, parts, the camera's extent and
shots use, are the box round its geometry turned about its pivot, at its place: round the turned
points of a line, arrow or shape with `points`; round the four turned corners of a `rect`; and
round the turned ellipse of an `ellipse`. The angle is the instance's place's angle (section
13.14): its `turn` until a step has left another.

## 10. Parts, shots and the camera

### 10.1 Parts and shots

`parts` maps part names to selections. A part's *region* is the box round the bounds of its
instances at their places, for the problem, the layout and the current `vars`; a part that selects
nothing has no region.

`shots` maps shot names to:

| Key | Holds |
|---|---|
| `frame` | Part names. |
| `region` | A rectangle `[x, y, width, height]`. |
| `margin` | Added on every side. By default the style's camera margin (12). |

A shot's region is the box round its parts' regions and its `region`, grown by its margin. A shot
with no region frames the drawing's extent (section 10.3). `opening` names the shot before the
first step; without it the camera starts on the drawing's extent.

### 10.2 When the camera is used

Shots take effect only in a layout with `camera: true`. In any other layout the drawing is shown
whole and a step's `shot` changes nothing.

### 10.3 Framing

The camera shows a *view* of the drawing in a *viewport*: the layout's `size` less a band of `band`
at its top. With the camera on, `size` is the shape of the picture shown, and the drawing may reach
past it; the drawing's *extent* is the box round the bounds of every instance that is not fixed, at
its place. To frame a shot, the player grows the shot's region about its middle to the viewport's
shape, then slides it, where it fits, to lie inside the box round the extent and the region, and
centres it on that box where it does not fit. It maps the view uniformly onto the viewport.

Elements whose middle lies outside the shot's region are *dimmed*: drawn toward the paper by the
style's camera `dim` (0.45), in proportion to their distance outside, reaching the full amount 24
units out. A shot whose region contains the extent dims nothing. A fixed element is drawn in
the drawing's units, outside the camera, after every other element, and is never dimmed.

### 10.4 The camera's move

When a step's shot frames differently from the shot the camera holds, the step begins with the
camera's move (section 12.5). Two shots frame differently when their views differ or the regions
outside which they dim differ (section 10.3); shots with different names may frame the same. The view's middle moves in a straight line, its size changes
geometrically, and the dimming fades between the two shots, all by the eased progress of the move.

## 11. Steps

A step is one change to the picture with one line.

| Key | Holds |
|---|---|
| `when` | A truth value: whether this problem has the step. By default `true`. |
| `shot` | The shot the step plays in. Without it, the camera keeps its shot. |
| `doShot` | The shot the viewer acts in, where that differs (section 15). |
| `say` | The step's line: an entry said and shown as the step begins. Required, here or through `like`. |
| `actions` | Action name to action (section 12). |
| `duration` | The length of the step's own timeline, replacing the end of its last action (section 12.4). |
| `hold` | Seconds added after the timeline. By default 0. |
| `counts` | `true` if the step counts aloud (section 17). |
| `like` | Another step's name. This step takes every key of that step except `when`, and replaces any it gives itself; keys are replaced whole, not merged. The named step must not itself have `like`. |
| `act` | What the viewer may do on this step (section 15). |
| `why` | An optional explanation of why the step is done (section 15.7). |

The steps a problem has are those of `sequence` whose `when` is true, in that order.

## 12. Actions and timing

### 12.1 Keys every action may have

| Key | Holds |
|---|---|
| `do` | The verb (section 13). Required. |
| `target` | The selection it acts on, where the verb takes one. |
| `at` | When it starts, in seconds from the start of the step's timeline (or of the iteration, inside an `each`), as a number or an expression. By default 0. Never negative. |
| `dur` | How long it takes on each instance. By default the style's duration for the verb's kind (section 13), and 0 for an instant verb. |
| `each` | The stagger: the seconds between one instance's start and the next. By default 0. |
| `reverse` | `true` to stagger from the last instance of the selection to the first. By default `false`. |
| `ease` | The name of a curve of the style. By default the style's curve for the verb's kind. |
| `when` | A truth value: whether the action runs for this problem. By default `true`. |
| `wait` | `"voice"`: hold the step's clock at the action's start until the voice has finished (section 12.6). |
| `mark` | `true` if the action's effect lasts only while its step is current (section 12.7). |

`dur`, `each`, `reverse` and `ease` do not apply to `say` and `each`, `say` has no `target`, and an
instant verb has no `dur`, `each`, `reverse` or `ease`.

### 12.2 An action's span

The instance at position *k* of an action's selection (or at position *n* − 1 − *k* when `reverse`
is true, with *n* instances) starts at `at` + *k* · `each` and runs for `dur`, then, for `cross`
with `fade`, for `fade` seconds more. Every instance takes its start state (section 13) as the
action starts, and holds it until its own start: a staggered `appear` keeps the instances that
have yet to start at opacity 0. An action's *end* is its start plus (*n* − 1) · `each` +
`dur` + `fade`. An action with a target that selects nothing does nothing, and its end is its
start. An action without a target ends at `at` + `dur`.

Within its `dur`, an instance's motion follows its eased progress *p*: the action's curve applied
to the fraction of `dur` elapsed. *p* is exactly 0 at the instance's start and exactly 1 at its
end, so a motion's end is the step's still picture with no rounding between them.

### 12.3 `start()` and `end()`

In an action's `at`, `start(a)` and `end(a)` are the start and end of the action `a` of the same
step. Their argument is an action's name, not an expression. An action's `at` may depend on other
actions only through these, and the dependencies must not form a cycle. `start()` or `end()` of an
action whose `when` is false is an error when it is evaluated; the conditional operator can avoid
evaluating it, as in `"dT > 0 ? end(pulse) : 0.5"`. These functions are not available inside an
`each`'s `then`.

### 12.4 The length of a step

The step's *timeline* is `duration` when it is given, and otherwise the latest end of its actions
(0 when it has none). Its *own length* is the timeline plus `hold`. An action still in progress
when the own length is reached is finished at once; a validator warns of it.

### 12.5 The camera's lead

When the camera moves on a step (section 10.4), the step's own timeline starts after a *lead* of
the style's camera `at` plus its camera `duration`. The move runs from the camera's `at` for its
`duration`, eased by its `easing`. The step's line is said at time 0, before the lead; every other
time in the step is moved later by the lead. The step's length is the lead plus its own length.

### 12.6 Waiting for the voice

Lines are queued: each is spoken after the one before it ends. `wait: "voice"` holds the step's
clock at the action's start until every line begun before that moment has been heard. While the
clock is held, the picture is the one just before that moment. On an `each`, the wait applies at the
start of every iteration, so that each number said is heard with the piece it counts. When counts
are shown (section 17), an `each` whose `then` has a `say` with `count: true` does not wait: a
count that is shown is not heard, and a step that does not count aloud moves while its line is
said. A step is finished when its clock reaches its length and every line it said has been heard.

The times this reference gives are those of a silent voice, which never holds the clock. A player
that speaks adds the holds.

### 12.7 Marks

An action with `mark: true` is undone, at once, when the next step begins: a digit tinted while
its step is current, or a loop drawn round pieces being looked at. A still picture of the step
shows it (section 18). A verb that does not erase is still never used to remove a quantity: a mark
is a pointer, not a piece.

## 13. The verbs

Each verb belongs to a *kind*, which gives its default duration and curve from the style (section
16): `appear`, `draw`, `fade` or `travel`, or *instant* (no duration and no curve). The defaults of
the standard style are, in seconds and by curve name: `appear` 0.3 `linear`, `draw` 0.4 `easeOut`,
`fade` 0.35 `linear`, `travel` 1.2 `easeInOut`. The verb `turn` (section 13.14) is part of the
capability `drawing.turn` and is of kind `travel`.

For each verb, *start* is what an instance is at the action's start and *end* is what it is at the
action's end. Anything not named is unchanged. There is no verb that removes an element.

### 13.1 `appear`

Kind `appear`. Targets: elements and runs.

| Parameter | Holds |
|---|---|
| `rise` | A distance: the instance starts this far below its position and rises to it. A negative distance starts it above its position, so that it drops in. |
| `grow` | A scale from 0 to 1: the instance starts at this size about its middle, or about its `pivot` when it has one (section 9.5), and grows to its own. |
| `place` | A placement (such as `split(...)`, section 9.4): the instance's position becomes the placement's for it as the action starts. |
| `text` | An entry: the instance (a text element or a run) takes this text as the action starts. |

Start: opacity 0, and the starting offset or scale. End: opacity 1, at its position (or the
placement's), at full size, with its new text.

### 13.2 `fade`

Kind `fade`. Targets: elements, runs and cross-outs. Parameter: `to`, a number from 0 to 1, or
`"ghost"`, which is opacity 0.28 and leaves the instance *ghosted*. In `to`, the string `"ghost"`
is this word and not an expression.

Start: its current opacity. End: opacity `to`. A piece, or anything else a capability names as a
quantity, must not end below 0.28.

### 13.3 `draw`

Kind `draw`. Targets: stroked elements (section 9.3). Start: progress 0. End: progress 1.

### 13.4 `cross`

Kind `draw`. Targets: pieces. Parameter: `fade`, seconds.

Start: the instance's cross-out at progress 0. Over `dur`, the cross-out is drawn. With `fade`,
the piece and its cross-out then fade to 0.28 together over `fade` seconds, by the style's `fade`
curve. End: crossed out, so no longer whole; with `fade`, the piece and its cross-out ghosted.

### 13.5 `tint`

Kind `draw`. Targets: runs and elements. Parameter: `ink`, a role (required).

Start: untinted. Over `dur` a pale tint of the role (its `soft` value) grows in behind the
instance; a run's text takes the role's ink at the start. End: tinted. With `mark: true`, this is
how the digit a step acts on is marked.

### 13.6 `move`

Kind `travel`. Targets: elements and pieces.

| Parameter | Holds |
|---|---|
| `to` | `[x, y]`: a new place for the instance's reference point. Without it, the instance returns to its place. |
| `via` | Keyframes `[offset, x, y]`, with offsets strictly between 0 and 1 in increasing order, and `x`, `y` positions, which may use `x0`, `y0` and `i`. |

Start: at its position (`x0`, `y0`). The instance's position at eased progress *p* is found by
straight-line interpolation between the keyframes (0, start), the `via` keyframes and (1, end),
with the easing applied to the whole move, not to each segment. End: at `to`, which becomes its
place, or at its place.

### 13.7 `gather`

Kind `travel`. Targets: elements and pieces. Parameter: `from`, a selection (required), with as
many instances as the target.

Start: the *k*-th target at the position of the *k*-th instance of `from`, at opacity 1. It travels
in a straight line. End: at its place. The instances of `from` do not change.

### 13.8 `look`

Instant. Targets: pieces. Parameter: `value`, a look (`pencil`, `traded` or `counted`), required.
End: that look.

### 13.9 `set`

Instant. Targets: text elements and runs. Parameter: `text`, an entry (required). End: the
instance shows that entry, filled at that moment with the names then in scope (section 14.3).

### 13.10 `tag`

Kind `appear`. Targets: elements and pieces. Parameter: `text`, an entry (required).

A small card in the `result` role, showing the entry, appears over each target and goes: 48 by 34
units over a ten or stick and 30 by 34 otherwise, centred on the target's bounds. Over eased progress *p* its opacity goes from 0 to 1 by *p* = 0.2, holds,
and returns to 0 from *p* = 0.75 to 1, and its scale goes from 0.6 to 1 by *p* = 0.2. Start and
end: no tag.

### 13.11 `pulse`

Kind `appear`. Targets: elements. The instance grows to 1.15 times its size by *p* = 0.5 and
returns to its size by *p* = 1, about its middle, or about its `pivot` when it has one (section 9.5).
Start and end: unchanged.

### 13.12 `say`

Instant; no target. Parameters: `line`, an entry (required); `count`, `true` if the line is a count;
`caption`, whether the line is shown as the caption, by default `true` and, for a count, `false`.

The line is queued to be spoken at the action's start (section 12.6). A count is not spoken when
counts are shown (section 17).

### 13.13 `each`

No kind. Parameters: `target` (required), `gap` (required), `let`, `then` (required).

For each instance of the target in turn, with `i` its position, `each` runs the actions of `then`,
which are timed from the iteration's start; the next iteration starts `gap` seconds later. `gap` is
evaluated for each `i`. `let` defines locals for the iteration, evaluated in order of dependency
with `i` in scope, such as the number counted: `"n": "(i + 1) * b"`. An action in `then` without a
`target` acts on the current instance; one with a `target` evaluates it with `i` and the locals in
scope. Its `when` is evaluated per iteration.

The actions of `then` must not be `each`, must not have `wait`, and must not use `start()` or
`end()`. An `each`'s end is the later of its start plus the sum of its gaps, and the end of the last
action of any iteration.

### 13.14 `turn`

Part of the capability `drawing.turn` (section 9.5). Kind `travel`. Targets: lines, arrows and
shapes; a text element, an outline or a piece is not a target.

| Parameter | Holds |
|---|---|
| `to` | An angle in degrees. Without it, the instance turns back to its place's angle. |

Start: at its current angle. At eased progress *p* its angle is the start angle plus *p* times the
difference between `to` and the start angle, so the direction and the number of turns are given by
the numbers: from 0, `to: 150` turns clockwise and `to: -30` turns anticlockwise, and from 150,
`to: 360` carries on round to twelve. End: at `to`, which becomes its *place's angle*, as `move`'s
`to` becomes its place. An instance's place's angle is its `turn` until a step in which a `turn`
with `to` that is not a mark has run, and then that `to`; it is the angle the instance's place has
as the step begins, so a turn without `to` in the same step returns to the angle before it.

The turn is about the instance's pivot (section 9.5), which stays still while it turns.

### 14.1 Lines

Every step has one line, said and shown as the step begins. Other lines are said by `say` actions,
by an interaction (section 15) and by `intro` and `try`. Each is a *wording entry*, named in the
document by its entry name, never by an expression; a choice between entries is made by an
action's `when` or by `select` in the entry (section 14.4).

### 14.2 Entries

`wording` maps a locale (section 14.7) to its *sections*: `shared`, and one or more *wordings*
named by the author, such as `everyday` and `formal`. A section maps entry names to entries. An
entry is a string, which is its `text`, or an object:

| Key | Holds |
|---|---|
| `text` | The text, with placeholders. |
| `forms` | In place of `text`: the text for each CLDR plural category of the locale (`zero`, `one`, `two`, `few`, `many`, `other`), chosen by `n`. `other` is required. |
| `select`, `cases` | In place of `text`: an expression, and a map from its value to a text. The key for a truth value is `true` or `false`, for an integer its decimal digits, for a string the string; `*` matches any value no other key matches. A value with no case is an error. |
| `spoken` | The spoken form, with the same placeholders, where it differs from the text in more than its numbers. Only with `text`. |
| `visual` | `true` if the entry is shown and never said: a label, an equation. |
| `emphasis` | A placeholder name: its value's last occurrence in the shown line is set in the `result` role. |
| `pronunciation` | Word to respelling: how the voice should say a word it needs help with. It changes nothing shown. |
| `notes` | A note for translators and reviewers. |
| `maxLength` | The length, in characters, a filled line should not exceed; for translators. |
| `of` | In a translation, section 14.7. |

Exactly one of `text`, `forms` and `select` is given.

A placeholder is `{name}`, or `{entry:name}` for a *phrase*. Braces have no other use in a text.

### 14.3 Filling an entry

A line is filled from the names in scope where it is said or shown: the document's values, the
locals of section 6.5 and, for a text element, its runs. The entries a text element shows are
filled for each instance with that instance's locals: its `i` and the names of its `let`.

- `{name}` takes the value of `name`. An integer is shown in ASCII digits, with `-` if negative and
  no grouping separator. A string is inserted unchanged. Any other value is an error.
- `{entry:name}` fills the entry `entry` (a `text` or `forms` entry, itself without phrases) with
  `n` set to the value of `name`, and inserts the result.
- A `forms` entry chooses its text by the plural category of `n` under the locale's CLDR cardinal
  plural rules. A reader that does not have a locale's rules warns of it, and uses `other`.

The text outside placeholders must not contain a decimal digit. Every number in a line is computed
from the problem.

### 14.4 The spoken form

A line's spoken form is its `spoken` text when the entry gives one and its text otherwise, filled as
in section 14.3 except that each integer placeholder is replaced by the number in words: the
locale's spell-out by CLDR's rule-based number format, rule set `spellout-numbering` (28 is
"twenty-eight" in English). For the spoken form to be derivable, a number placeholder in an entry
that is not `visual` must not be next to a letter, and a string placeholder in such an entry must
not insert a digit; "Count by {b}s" cannot be said correctly for every value of `b`, and is an
error. A `visual` entry has no spoken form.

### 14.5 Sections

An entry is looked up in the wording being played, then in `shared`. An entry name must not be in
both `shared` and a wording of the same locale, so that a line can never stand in for a phrase it
uses. The section name `shared` is reserved.

A wording must provide every entry its watched part needs: the steps' lines, the `say`, `set`,
`tag` and `appear` entries of their actions, the runs' entries and `intro.watch`. An entry needed
only by do it with me, What if? or try one may be absent from a wording; a player does not play
those parts with that wording. A reader reports, for each wording, the parts it can play and the
entries each other part lacks; this is not a finding, since a wording may be meant for the watched
part alone.

### 14.6 Wordings and languages

Wordings and languages are independent. A document may carry several wordings (for different
readers, or for different ways of playing it) and several languages. Every locale has the same
section names and, once translated, the same entry names. Rules that apply to one audience are
outside this format, and nothing in a document names an audience.

### 14.7 Locales and translations

A locale is a BCP 47 language tag, such as `en-US` or `es`. `sourceLocale` names the locale the
document was written in, and `wording` must contain it.

A translation is a further locale in `wording`, with the same sections and entry names. Each
translated entry is an object with `of`: the first 8 hexadecimal digits, in lowercase, of the hash
(section 19) of the source entry as it was when translated. A reader warns, for each locale, of the
entries missing, the entries whose source has changed since (*stale*), and the entries that have no
source. A player falls back to the source locale for a missing entry and lists the gap.

### 14.8 `intro`

`intro` has `watch`, the line said before the first step of the watched part (required), and
`guided`, the line said before do it with me (by default `watch`).

## 15. Interaction

### 15.1 Parts

A player plays a document in up to four parts: watch; do it with me, if any step has an `act`; What
if?, if the document has `whatIf`; and try one, if it has `try`. The watched part plays the steps in
order, each waiting for the viewer before the next begins. Do it with me is played on the
do-it-with-me problem of section 5.5, What if? starts from it, and try one uses the try-one problem.
Which steps the viewer does in do it with me, and how support is faded over repeated visits, is the
player's and the consuming app's to decide; the document declares which steps can be done.

### 15.2 `act`

| Key | Holds |
|---|---|
| `input` | `stroke` or `tap`. Required. |
| `say` | The instruction, said before the viewer can act; marks made while it is said are ignored. By default the step's line. |
| `targets` | The selection a right mark may take, evaluated as the step opens. Required. |
| `need` | How many right marks complete the step. By default 1 for `stroke` and every target for `tap`. |
| `many` | `true` if one stroke may take several targets. By default `false`. |
| `order` | Selections that must be marked in this order: `["cten", "cone"]` asks for tens first. |
| `bind` | A `vars` name, set to the index of the instance the first right mark takes. |
| `keep` | `true` if the viewer's stroke stays in the drawing, in the role `ink`; otherwise it fades. |
| `ink` | The role of a kept stroke. By default `pencil`. |
| `tally` | A role: the player shows how many right marks have been made, of `need`, in that role. |
| `pad` | How far round a target's bounds a tap still counts. By default 8. |
| `begin` | An action of the step, played as the step opens, which the viewer's marks wait for. |
| `then` | What a right mark plays (section 15.3). |
| `done` | When `need` is reached: an entry, said; or an array of action names of the step, played (section 15.3). |
| `interrupts` | `true` if a line said on a mark cuts off the one before, as in counting by touch. |
| `misses` | Lines for marks the step cannot use (section 15.4). |

While the viewer acts, the camera holds `doShot`, or the step's `shot`.

### 15.3 Right marks

A mark is *right* when it takes a target that has not been taken, in the order `order` requires.
A mark on a target already taken is ignored. On each right mark:

- `"watch"`: the step's own actions play from the current state, with any `bind` already set, and
  the step is done when they end.
- the name of an `each` of the step: the next iteration of that `each` runs (`i` is the number of
  right marks made before this one), with the taken instance as its current instance.
- the name of another action of the step: that action runs with the taken instance as its target.
- an action object (of the kinds allowed in an `each`'s `then`): it runs with the taken instance
  as its target.

When the step is done, a `done` line is said after any motion begun by the last mark ends; `done`
actions play in their own timing, with `start()` and `end()` of any action not among them taken as
the moment the step was done.

A tap is a mark that moves less than 14 units and ends within 0.6 seconds; any other mark is a
stroke. A tap takes a target when it lies inside the target's bounds grown by `pad`. A stroke takes
a target when, with the target's bounds grown by 4, the length of the stroke inside them is at
least 0.6 times the target's shorter side, and the stroke reaches at least half way across the
target's width or along half its height. When several targets qualify, the one the stroke runs
through furthest is taken, and, with `many`, also those it runs through at least 0.3 times as far.

### 15.4 Misses

`misses` maps a kind of miss to the line said for it:

| Key | The mark |
|---|---|
| `tap` | A tap where a stroke is asked for. |
| `stroke` | A stroke where a tap is asked for. |
| `nothing` | A mark that takes no target and falls under no selection key. |
| `tooMany` | A stroke that takes more targets than the step still needs (`left`); it takes none. |
| `order` | A mark on a target out of the order `order` asks for. |
| any other key | A selection: a mark that would take one of its instances, such as a one where a ten is asked for. |

Selection keys are tried first and must select disjoint instances. A miss with no line repeats the
instruction. A miss is never met with a sound or mark of failure; after a second miss, a player
offers to show the step.

### 15.5 `try`

`try` has `question` (an entry: the problem as written for the viewer to answer, required),
`say` (the line said, required) and `note` (an entry shown under the question). Try one shows the
question, a box where the answer is to be written, and the note, on the try-one problem.

### 15.6 `whatIf`

A What if? part lets the viewer change one value by dragging and sets goals in turn. No example
document uses it yet.

| Key | Holds |
|---|---|
| `say` | The line said as the part opens. Required. |
| `handle` | The selection the viewer drags. Required. |
| `bind` | The `vars` name the drag changes. Required. |
| `range` | `[min, max]`, the values it may take. Required. |
| `axis` | `x` or `y`, the direction of the drag. Required. |
| `per` | Drawing units per unit of the value. Required. |
| `snap` | The value is rounded to a multiple of this when the viewer lets go. By default 1. |
| `goals` | An array of goals, each with `when` (a truth value of the `vars`), `say` (the line said when it is met) and `show` (the value the player sets to show the goal). At least one. |
| `done` | A line said when every goal is met. |

Everything drawn follows the value as it is dragged. A goal is checked when the viewer lets go. The
picture holds still while a goal's line is said.

### 15.7 `why`

`why` has `say` (required), `actions` and `hold`. It is offered only while its step is paused. It
plays over the step's still picture as a step would, and when it is closed the step's picture and
line return as they were. It is not a step, and its effects do not last.

## 16. Style

### 16.1 Roles

A *role* names a colour by its meaning. The *neutral* roles are `paper`, `sheet`, `text`, `muted`,
`line`, `pencil` and `onResult`. An *operation* role has three values: `fill`, `ink` (for strokes and
text, with at least 3:1 contrast against the sheet) and `soft` (a pale tint). Where a document names
a role, it may name an operation role's value as `role.fill`, `role.ink` or `role.soft`; an
operation role named alone is its `ink` for a stroke or text and its `fill` for a fill.

The standard style defines the operation roles `subtract`, `trade`, `result`, `add`, `multiply`
and `divide`. A document may define more by giving an operation role, with all three values, in
both `palette.light` and `palette.dark` of its `style`.

### 16.2 The standard style

The standard style is the file `Sources/ChalkScript/Resources/style.json` of this repository. Its
keys are those of a document's `style` (below), with `"format": "explainer-style"` and `"version":
1`. There is one standard style; a player uses it unless it is given a replacement whole, and a
document's `style` overrides values of whichever style the player uses.

| Key | Holds |
|---|---|
| `palette.light`, `palette.dark` | Each role's colour, as `#RRGGBB`; an operation role as `{fill, ink, soft}`. |
| `easings` | Named curves, each a CSS cubic Bézier `[x1, y1, x2, y2]` with `x1` and `x2` from 0 to 1. `linear` always exists and cannot be redefined. |
| `motion.durations` | Default seconds by kind: `appear`, `draw`, `fade`, `travel`, and `lag` and `hold`, which a document's timing does not use. |
| `motion.easings` | The default curve, by name, for `appear`, `draw`, `fade` and `travel`. |
| `motion.camera` | `at`, `duration`, `easing`, `margin` and `dim` (sections 10 and 12.5). |

A curve's eased value at progress *x* is the *y* of the Bézier from (0, 0) through the two handles
to (1, 1) at that *x*, exactly 0 at 0 and exactly 1 at 1.

### 16.3 A document's `style`

A document's `style` has the keys above, without `format` and `version`, each optional. A value it
gives replaces the value at the same path; a value it omits keeps the style's. An unknown curve name
and a colour that is not `#RRGGBB` are errors. Every pair of roles drawn together must stay
distinguishable, under simulated colour-vision deficiencies, in light and dark; a validator checks
this for the roles a document draws.

## 17. Playback options

The options are chosen by whoever plays the document, not by the document:

| Option | Values |
|---|---|
| `control` | `paced`: no step starts until the viewer asks, and no step is cut short. `skippable`: the viewer may finish a playing step at once and jump to any step, and only the watched part is played. |
| `counts` | `spoken` or `shown`. When shown, a `say` with `count: true` is neither spoken nor captioned; the drawing still shows the count. |
| `countPace` | A positive number, by default 1. A step marked `counts` is timed as written, and every time on its own timeline (its actions' starts, durations, staggers, gaps and fades, its `duration` and its `hold`) is then multiplied by it, so that a time given by `start()` or `end()` is not multiplied twice. The camera's lead is not. |

When counts are spoken, a step marked `counts` holds its clock at the start of its own timeline,
after any camera lead, until its own line has been heard, so that its first count follows the line.

`plays` maps `paced` and `skippable` to a wording name: the wording the document suggests for each,
for a player that has no choice of its own.

What a viewer sees and hears depends on the document's revision, the wording, the locale and these
options together. A review of a document names all of them.

## 18. State, stills and what a player is given

A player is given the document, a problem, a wording, a locale, the playback options and the size
of the drawing area, from which it finds the area it lays the document out for and chooses the
layout (section 8). When that area is not the one it was given, it says so to whoever gave it.

The *state* of the drawing is, for every instance, its opacity, progress, position, place, angle,
size, look, text, tint, and whether it is crossed out or ghosted, with the same for each cross-out;
and the values of `vars`. The state before the first step is given by the elements' keys and `start`.
A step plays from the state the previous step ended in, and its actions' selections are evaluated
against that state as it begins.

The *still* of a step is the state at its end: every action's end, including its marks. It is what
is shown when the step pauses, and what is shown in place of the motion when motion is reduced. A
step's marks are removed as the next step begins. Tags and pulses leave nothing in a still.

## 19. The canonical form, the hash and the revision

The *canonical form* of a JSON value is its serialisation by the JSON Canonicalization Scheme (RFC
8785). The *hash* of a value is the SHA-256 digest of its canonical form's UTF-8 bytes, written in
lowercase hexadecimal; a *short hash* is its first 12 digits.

- The document's hash is the hash of the whole document. Its short hash is the `base` of a patch.
- A translated entry's `of` is the first 8 digits of the hash of its source entry.
- The *revision* of a document for a wording and a locale is the short hash of the document with
  `about` removed, `wording` reduced to that locale with only its `shared` section and that wording,
  and `notes`, `maxLength` and `of` removed from every entry left; an entry then left with only
  `text` is written as that string. A change to another language or another wording, to a note for
  translators, or to formatting leaves the revision unchanged.

How a document is laid out as text is not part of its meaning. A tool that writes a document should
keep the author's layout and key order where it can, so that a line in a stored file stays where it
was from one edit to the next.

## 20. Patches

A document is edited by a *patch*: an object with `base`, the short hash of the document it was
made against, and `ops`, a JSON Patch (RFC 6902) array of `add`, `remove`, `replace`, `move`, `copy`
and `test` operations.

- A patch whose `base` is not the document's current short hash is refused, and the refusal gives
  the current short hash, so an edit made meanwhile is never overwritten unseen.
- No operation may have the path or `from` `""`, `/format` or `/version`.
- A patch is atomic. The operations are applied in order to a copy. If any fails, or the result has
  an error (section 21), nothing changes and the refusal lists why. Warnings do not refuse a patch.
- An accepted patch's result gives the new short hash and the number of findings of each severity.
  It does not need to return the document.

A tool reading part of a document addresses it by JSON Pointer, so that an agent can read one step
or one locale without the rest.

## 21. Findings

A reader and a validator report *findings*. Each has:

| Field | Holds |
|---|---|
| `severity` | `error` or `warning`. |
| `code` | What kind of finding, below. |
| `path` | A JSON Pointer to the value at fault, as deep as can be named. |
| `at` | For a finding inside an expression or an entry's text: the offset, in Unicode code points from 0, at which it was found. |
| `values` | For a finding made by evaluating the document: the problem's values. |
| `time` | For a finding at a moment of a step: the time on the step's clock. |
| `message` | One sentence. |

| Code | Finding |
|---|---|
| `json` | The file is not JSON, is not an object, or has a duplicate key. Its path is that of the object with the duplicate key, or empty, and its message gives the line and column. |
| `format` | `format` is missing or is not `chalkscript-explainer`. |
| `version` | The major version is not implemented (error), or the minor version is newer than the reader's (warning). |
| `capability` | A required capability is not implemented, or one used is not required. |
| `schema` | A missing key, a value of the wrong type, an unknown verb, kind or input, or a name that does not match its pattern. |
| `unknown` | An unknown key (warning). |
| `ref` | A reference to a step, action, element, run, part, shot, layout, entry, `vars` value, role or curve that does not exist. |
| `expr` | A syntax error, unknown name, unknown function, wrong arguments, or a cycle. |
| `wording` | A placeholder that cannot be filled, a typed numeral, a spoken form that cannot be derived, or an entry in both `shared` and a wording. |
| `eval` | An evaluation error for a problem (section 6.6). |
| `range` | A problem outside the parameters' ranges. |
| `areas` | A declared shape at which another layout is chosen, a layout no entry names, or a `suits` that depends on the area's size (warnings). |
| `patch` | A patch refused: a stale base, a protected path, or an operation that failed. |

A validator adds its own codes for the checks it computes. One finding is written on one line as
severity, code, path, then `@` and the offset, the values in braces and `t=` and the time where they
apply, then a colon and the message:

```
error expr /steps/takeOnes/actions/cross/target @9: unknown name 'bo' (did you mean 'bO'?)
error eval /steps/takeTens/actions/cross/target {a: 20, b: 11}: ten[2] is outside ten (2 instances)
error wording /wording/en-US/everyday/skip @12: number {b} is followed by letters, so its spoken form cannot be derived
```

## 22. Conformance, and the files beside this reference

A document *conforms* when a reader finds no error in it. It is *sound* for a problem when nothing
evaluated for that problem fails. A reader conforms when it reports what sections 2 to 21 make an
error or a warning. A player conforms when, for a conforming document and a problem for which it is
sound, it lays the document out for the area section 8.2 gives and plays the steps, timing, camera, lines and interaction this reference defines, and
refuses what section 2 says it must refuse.

Beside this reference:

| File | Is |
|---|---|
| `explainer-1.0.schema.json` | The JSON Schema (draft 2020-12) of a version 1.x document. It checks structure and types; it does not parse expressions or resolve references, which a reader does. |
| `examples/subtraction.explainer` | Two-digit subtraction, trading a ten when the ones are too few, with two English wordings and do it with me. It uses a tall layout with the camera, and declares the shapes 0.6 to 1.35 (tall) and 1.35 to 2.2 (stage). |
| `examples/equal-groups.explainer` | Multiplication as equal groups, counted on group by group, with two English wordings. Its places are named values, which a tall layout replaces to stack the groups in rows; it declares the shapes 0.6 to 0.9 (tall) and 0.9 to 2.2 (stage). |
| `check-schema.py` | Checks that the schema accepts both examples and refuses documents with an unknown verb, a missing required key, a value of the wrong type and an `areas` entry whose `ratio` is not two numbers. Run it with `python3 docs/format/check-schema.py`. It uses the `jsonschema` package when it is installed and otherwise a validator of the schema keywords it uses. |

## 23. Prior art

The format borrows from the following work. No code was copied from any of them.

- **`.ani`**, the document format of [Garinmckayl/anima](https://github.com/Garinmckayl/anima)
  (MIT licence). From it come detection by content with a declared format and version; required
  capabilities that a reader refuses rather than approximates; ids that never need escaping in a
  JSON Pointer, and collections as maps keyed by id; edits as atomic patches checked against a hash
  of the canonical document; findings with a code and a path; bounded expressions with no side
  effects; namespaced extensions that tools keep; and, for a later capability for imported artwork,
  a restricted list of path commands.
- **[wheresryan22/anatomy](https://github.com/wheresryan22/anatomy)** (MIT licence). From it come
  the principle that every number shown comes from the same small model that moves the parts, which
  `params` and `let` express, and its conventions for isometric drawing and exploded views (an
  assembly moved along a vector, staggered, and closed in reverse order), as the basis of a later
  capability.
- **glTF 2.0** ([Khronos](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)): the rule that
  a minor version does not change existing behaviour, and required extensions that a client which
  lacks them does not load.
- **Manim** ([Manim Community](https://docs.manim.community/)): an animation as a verb applied to an
  object for a run time with a rate function, and a staggered start across a group, which `each`
  and an action's stagger follow.
- **RFC 6901** (JSON Pointer), **RFC 6902** (JSON Patch), **RFC 8785** (the JSON Canonicalization
  Scheme) and **RFC 8259** (JSON), at [rfc-editor.org](https://www.rfc-editor.org/).
- **Unicode Technical Standard #35** ([unicode.org](https://www.unicode.org/reports/tr35/)): CLDR's
  plural categories and rule-based number spell-out, and Message Format's selection on a value
  with a catch-all, which `forms` and `select` follow.
- **BCP 47** ([RFC 5646](https://www.rfc-editor.org/rfc/rfc5646)) for locale tags, **CSS Easing
  Functions Level 1** ([W3C](https://www.w3.org/TR/css-easing-1/)) for cubic Bézier curves, and
  **FIPS 180-4** for SHA-256.
