# The helper protocol, version 1

ChalkScript Studio is the macOS app in which an explainer is made. An agent in Claude's desktop app
or Claude Code reaches it through `chalkscript-mcp`, a small helper that the client launches and
speaks the Model Context Protocol (MCP) to over stdio. The helper keeps no state and reads no
document. It forwards each tool call to the running studio over a Unix domain socket, in the
protocol this document defines, and writes the studio's reply as a short tool result. The studio
owns every document, applies every edit and plays every step.

This document is written so that the studio's end can be implemented from it alone. The helper's
end is `Sources/ChalkScriptMCP`, and the library also holds an implementation of the studio's end
(section 10). The document format it refers to is defined in
[explainer-1.0.md](../format/explainer-1.0.md), cited below as "the format reference".

## Contents

1. The socket
2. Messages
3. A connection
4. Versions and extension
5. Errors
6. Methods
7. Findings
8. Timing, cancellation and a call that is cut off
9. What the helper does with each reply
10. The Swift interface
11. Connecting a client

## 1. The socket

The studio listens on a Unix domain socket (`AF_UNIX`, `SOCK_STREAM`) at

```
~/Library/Application Support/ChalkScript Studio/studio.sock
```

where `~` is the home folder of the user the process runs as, read from the user database
(`getpwuid`) rather than from `HOME`, so that both ends find the same path whatever environment
the client gives the helper. The helper takes another path from its `--socket PATH` argument, or
from the environment variable `CHALKSCRIPT_STUDIO_SOCKET`, in that order.

- The studio creates the folder with mode `0700` if it is missing, and the socket with mode
  `0600`.
- A socket file may be left at the path by a studio that quit without removing it. Before binding,
  the studio tries to connect to it: if that succeeds, another studio is running and this one must
  not take the path; if it fails, the studio removes the file and binds.
- The studio removes the socket file when it quits.
- The studio accepts a connection only from a process of the same user, which it checks with
  `getpeereid`. The helper connects only to a socket owned by its own user, which it checks with
  `lstat`.
- A path in `sockaddr_un` holds at most 103 bytes on macOS. A longer path is refused by both ends.

The location is outside any sandbox container, because the helper is launched by the client, not
by the studio, and must find the socket without knowing the studio's container. A studio that is
later sandboxed would need an exception for this folder, or both ends would move to an app group
container; either is a change of the default path, not of the protocol.

The helper treats a missing socket file, a path that is not a socket, and a refused connection
alike: the studio is not running.

## 2. Messages

Messages are JSON-RPC 2.0, one message per line: UTF-8 text, terminated by a line feed, with no
line feed inside it (a line feed inside a string is written `\n`). This is the framing of MCP's
stdio transport, which that specification recommends for custom transports over a byte stream.

- A request has `jsonrpc: "2.0"`, an `id`, a `method` and `params`, an object. The helper's ids are
  integers.
- A response has `jsonrpc: "2.0"`, the request's `id`, and either `result` or `error`. An `error`
  has an integer `code`, a `message` and optionally `data`.
- A notification has a `method` and no `id`. The helper sends none in version 1. The studio may
  send them, and the helper ignores them.
- An empty line is ignored, and a carriage return before the line feed is removed.
- A line longer than 32 MiB is discarded by the helper; the studio may set its own limit and answer
  such a line with a parse error.
- An object must not have two members with the same key. Both ends keep the order of an object's
  members and the text of every number as received, because a patch's values become part of a
  stored document (the format reference, section 19).

## 3. A connection

The helper opens one connection per tool call:

1. It connects, and sends `hello` with id 1.
2. It waits for the reply to `hello`.
3. It sends the call's request with id 2.
4. It waits for the reply, then closes the connection.

The studio answers each request on a connection in the order received, with exactly one response
carrying the request's `id`. The first request on a connection must be `hello`; the studio answers
any other first request with error `-32600` and closes the connection. A connection may carry
further requests after the first call, and the studio must accept them, although the helper sends
only one.

Connections are independent: several may be open at once, from one helper or from several (one per
client conversation). The studio must therefore apply edits to a document one at a time. The base
hash of `document.patch` makes this safe: of two edits made against the same hash, the second is
refused as stale, and its agent reads the document again.

## 4. Versions and extension

`hello` carries the protocol's version, an integer, which this document defines as `1`.

Within a version, either end may add:

- an optional key to the params or result of a method, which the other end ignores when it does
  not know it;
- a method, which an end that does not know it answers with `-32601`;
- an error code, which the helper reports through its message.

Anything else, such as a change to what an existing key means, or a key that a receiver must
understand, needs a new version. A studio that speaks several versions answers `hello` with the one
the helper asked for, or refuses it with error `1` and the versions it speaks.

The later work this protocol was designed for needs no new version: the studio's reader supplies
the findings of `document.check` and `documents.list`, its patch engine answers `document.patch`,
and its player answers `step.show`, each in the shapes below. Until they exist, a studio may
answer `document.check` with no findings and omit the counts from `documents.list`.

## 5. Errors

The studio answers a request it cannot carry out with an error. Its `message` is one sentence for
the agent to read, and should say what to do differently, such as "No document named
`subtraction` is in the project; `list` gives the names." The helper passes the message to the
agent as a tool error.

| Code | Meaning |
|---|---|
| `-32700` | The line is not JSON. |
| `-32600` | The message is not a request, or the first request is not `hello`. |
| `-32601` | The method is unknown. |
| `-32602` | A parameter is missing or has the wrong type. |
| `-32603` | The studio failed in a way it cannot describe. |
| `1` | `hello` asked for a version the studio does not speak; `data` is `{"supported": [<int>, ...]}`. |
| `2` | No project is open in the studio. |
| `3` | No document of that name is in the project, including a `from` of `document.create` that names none. |
| `4` | The JSON Pointer names no value in the document. |
| `5` | No step of that name is in the document. |
| `6` | Any other failure the person or the agent can act on, said in the message, such as a name for a new document that is taken or malformed, or a `from` that cannot be read. |

A refused patch is not an error: it is a result with `applied: false` (section 6.4), because it
carries findings in the same form as an accepted one.

## 6. Methods

In the tables, a key marked "no" may be absent. Names of documents and steps are strings. A
*hash* is a document's short hash: the first 12 lowercase hexadecimal digits of the SHA-256 digest
of its canonical form (the format reference, section 19).

### 6.1 `hello`

Opens a connection.

| Param | Required | Holds |
|---|---|---|
| `protocol` | yes | The version the helper speaks: `1`. |
| `helper` | yes | `{"name": "chalkscript-mcp", "version": "<semver>"}`. |
| `client` | no | The MCP client's `{"name", "version"}`, as it declared them, which the studio may show to the person. |

| Result | Required | Holds |
|---|---|---|
| `protocol` | yes | The version the studio will speak on this connection: `1`. |
| `app` | yes | `{"name", "version"}` of the studio. |

```
→ {"jsonrpc":"2.0","id":1,"method":"hello","params":{"protocol":1,"helper":{"name":"chalkscript-mcp","version":"0.1.0"},"client":{"name":"claude-code","version":"2.1.310"}}}
← {"jsonrpc":"2.0","id":1,"result":{"protocol":1,"app":{"name":"ChalkScript Studio","version":"0.1.0"}}}
```

A studio that does not speak the version answers error `1` and closes the connection.

### 6.2 `documents.list`

Lists the documents of the project open in the studio. No params.

| Result | Required | Holds |
|---|---|---|
| `project` | yes | The project's name, for the agent to mention. |
| `documents` | yes | An array of document summaries, in the order the studio shows them. |

A document summary:

| Key | Required | Holds |
|---|---|---|
| `doc` | yes | The document's name, which the other methods take. The studio chooses it; the file's name without `.explainer`, relative to the project folder, is recommended. |
| `title` | no | The document's `title`. |
| `hash` | yes | The document's hash. |
| `errors`, `warnings` | no | The counts of its findings. Both are absent when the studio has not checked it. |

Errors: `2`.

### 6.3 `document.read`

Reads a document, or the part of it at a JSON Pointer (RFC 6901), so that an agent can read one
step or one locale without the rest (the format reference, section 20).

| Param | Required | Holds |
|---|---|---|
| `doc` | yes | A name from `documents.list`. |
| `pointer` | yes | A JSON Pointer; `""` is the whole document. |

| Result | Required | Holds |
|---|---|---|
| `hash` | yes | The hash of the whole document as read. |
| `value` | yes | The value at the pointer, with its keys in the document's order. |

The studio reads the document as it currently stands in the app, including edits made in the app
and not yet saved. Errors: `2`, `3`, `4`.

### 6.4 `document.patch`

Applies a patch as the format reference's section 20 defines it: atomically, against a base hash,
never to `""`, `/format` or `/version`.

| Param | Required | Holds |
|---|---|---|
| `doc` | yes | A name from `documents.list`. |
| `base` | yes | The hash the patch was made against. |
| `ops` | yes | A JSON Patch (RFC 6902) array. The helper checks only that it is an array of objects; the studio checks the operations. |

| Result | Required | Holds |
|---|---|---|
| `applied` | yes | Whether the document changed. |
| `hash` | yes | The hash after the patch if it applied, or the current hash if it did not. |
| `errors`, `warnings` | yes | The counts of the document's findings after the patch, or of the refused result's. |
| `findings` | no | When refused: why, as findings (section 7), with code `patch` for a stale base, a protected path or an operation that failed, and the reader's own codes for an error in the result. When applied: omitted, or the warnings. |

A stale base is refused with the current hash in `hash` and a `patch` finding, so that an edit made
meanwhile, in the app or by another conversation, is never overwritten unseen. An accepted patch
is shown in the studio's window at once, and joins the app's undo history as one step. The
studio does not return the document. Errors: `2`, `3`, and `-32602` when `ops` is not an array.

```
→ {"jsonrpc":"2.0","id":2,"method":"document.patch","params":{"doc":"subtraction","base":"3f2a9c1b7e04","ops":[{"op":"replace","path":"/steps/trade/hold","value":0.5}]}}
← {"jsonrpc":"2.0","id":2,"result":{"applied":true,"hash":"8d01e2c4b6a9","errors":0,"warnings":1}}
```

### 6.5 `document.check`

Gives a document's findings.

| Param | Required | Holds |
|---|---|---|
| `doc` | yes | A name from `documents.list`. |
| `pointer` | no | Only findings whose `path` is this pointer or lies under it. |

| Result | Required | Holds |
|---|---|---|
| `hash` | yes | The hash of the document checked. |
| `errors`, `warnings` | yes | The counts of all the document's findings, whatever `pointer` selects. |
| `findings` | yes | The findings selected, most severe first, then in document order. |

Errors: `2`, `3`, `4`.

### 6.6 `step.show`

Plays a step of a document in the studio's window, for the person to watch. The studio opens the
document if it is not already shown, and answers once the step has started, not when it ends.

| Param | Required | Holds |
|---|---|---|
| `doc` | yes | A name from `documents.list`. |
| `step` | no | A step's name; without it, the first step of the problem. |
| `problem` | no | The values of the document's `params`; without it, the studio's current problem for the document, or its first sample. |
| `ratio` | no | A number greater than 0: the width over the height of the drawing area the picture is laid out for. Without it, the shape the window is showing. It changes only the picture, not the window. |
| `image` | no | `true` to return a picture of the step's still (the format reference, section 18). |

| Result | Required | Holds |
|---|---|---|
| `step` | yes | The name of the step shown. |
| `index`, `count` | no | Its place among the problem's steps, from 1, and their number. |
| `timeline` | no | The step's timeline, as text (below). The studio gives it with every answer; a client that predates it ignores the key. |
| `image` | no | Present only when asked for: `{"data": "<base64>", "mimeType": "image/png"}`. It is small, because it is sent to a model: laid out for the area of the shape asked for whose longer side is 480 points, so never more than 480 by 480, at one pixel per point. |
| `ratio`, `layout` | no | Present with `image`: the ratio of the area the picture is of, to two decimals, and the layout drawn there. |
| `drawn` | no | Present with `image` only when the document declares shapes and not `ratio`: the ratio of the shape the document is drawn at inside the area, to two decimals. |

The timeline is the step as the window plays it for the problem shown, on the clock of the studio's
stand-in voice, which says nothing and finishes each line after the time `ReadingTime` estimates
for it (0.3 s and a third of a second for each word of its spoken form). It is worked out from the
step's lines and waits, without playing the step, and its length is the time the player takes with
that voice, to within a frame. It is a few lines of text:

- A header line: `step <name> (<index> of <count>), <problem>: <length> s as played`. When the
  length on the step's own clock (the format reference, section 12.4) differs, the header gives
  that too, and says whether the clock is held for the voice or the step only waits for its last
  line. It ends `; ends of lines estimated`. The times are seconds from the step's start, to a
  tenth.
- A row for each line said, `<start>-<end> <action> says "<spoken form>"`, where a line is said
  from when the voice reaches it, after the lines queued before it; the step's own line is
  `line`. A visual line is `shows` and not said. A count word is in its iteration's row.
- A row `<start>-<end> held for the voice` for each span in which the clock waits for the voice.
- A row for each action, `<start>-<end> <name> <verb> <targets>`, with the times mapped through the
  holds, a run of indices written as `nums[0-11]`, a stagger as `one every 0.4`, and the text a
  `tag`, `set` or `appear` shows. Rows are ordered by start.
- For an `each`, a row `<start>-<end> <name> each <targets>, <n> times`, then one indented row for
  each iteration, `<start> [<i>] ...`, that gives the lines and actions of that iteration.
  Consecutive iterations in which nothing runs are one row, `<start>-<end> [<first>-<last>] nothing:
  every when is false`.

An `at` in a document is on the step's own clock, not on the timeline's.

A document that declares the shapes of area it is made for (the format reference, section 8.2) is
pictured as a player lays it out: for a shape it does not declare, the picture is of the area
asked for, with the document laid out for the nearest declared shape and drawn in it scaled,
centred and framed in the `line` role; `ratio` is the area's and `drawn` is that shape's. The
helper says both in its text, as "0.75 is not a shape the document is made for; drawn at 0.9
inside it". At a declared shape, and for a document that declares none, there is no `drawn`. Without
`ratio` and before the window has given the drawing an area, the picture has the stage's shape.
A `ratio` that is not a number greater than 0 is error `-32602`.

A step that the problem does not have (its `when` is false) is error `5`, whose message names the
steps the problem has. A problem outside the parameters' ranges is error `6`. Errors: `2`, `3`,
`5`, `6`, `-32602`.

### 6.7 `guide.read`

Gives part of the authoring guide: how the format is written and how an agent edits it. The guide
is held by the studio so that it matches the format the studio reads.

| Param | Required | Holds |
|---|---|---|
| `topic` | no | A topic's name; without it, the guide's list of topics with one line each. |

| Result | Required | Holds |
|---|---|---|
| `text` | yes | Markdown. |

An unknown topic is error `6`, whose message lists the topics.

### 6.8 `document.create`

Makes a document in the project's folder and shows it in the window: the studio writes the file in
the folder's top level, reads the folder again at once, without waiting for any change it would
notice itself, and selects the document and plays its first step as `step.show` does, at the
studio's first preview of a document.

| Param | Required | Holds |
|---|---|---|
| `title` | yes | The new document's `title`; not empty. |
| `name` | no | The name to give it, matching `^[a-z][a-z0-9-]{0,63}$`. Without it, the studio makes one from the title: lower case, the ASCII letters and digits kept, every other run of characters turned into one hyphen, hyphens trimmed from the ends, `explainer-` put in front when the result does not begin with a letter, and cut to 64 characters; `-2`, `-3` and so on are added when the name is taken. |
| `from` | no | A name from `documents.list`; the new document is a copy of it, with its own `id` and `title`. Without it, the studio's starter. |

The name is also the new document's `id`, which the format requires to match the pattern above, so
the file's name and the `id` agree. A name that is given and is taken or does not match the pattern
is refused, never replaced by another, so that the agent is not told it made `clock` when it made
`clock-2`.

The starter is the smallest document the reader accepts without findings: one parameterless
sample (`params` of `{}` and `samples` of `[{}]`), one `text` element, one step with its line, and
one layout, `stage`, of 880 by 800 declared in `areas` for the ratios 0.9 to 1.35, which is the
studio's Square range. It is built by the studio, not read from a file of the project.

| Result | Required | Holds |
|---|---|---|
| `doc` | yes | The new document's name. |
| `hash` | yes | Its hash. |
| `errors`, `warnings` | yes | The counts of its findings, as `documents.list` gives them. |
| `value` | yes | The whole document, with its keys in order. |

Errors: `2`; `3`, for a `from` that names no document; `6`, for a `name` that is taken or does
not match the pattern, a `from` that cannot be read, or a file that cannot be written; and
`-32602`, for a `title` that is missing or empty or a parameter of the wrong type. Nothing is
written for any error. Adding the method does not change the protocol's version (section 4).

## 7. Findings

A finding is an object with the fields of the format reference's section 21:

| Key | Required | Holds |
|---|---|---|
| `severity` | yes | `error` or `warning`. |
| `code` | yes | A code of section 21, or a validator's own. |
| `path` | yes | A JSON Pointer to the value at fault. |
| `at` | no | An offset in Unicode code points. |
| `values` | no | The problem's values, an object. |
| `time` | no | Seconds on the step's clock. |
| `message` | yes | One sentence. |

The helper writes each finding on one line as section 21 does:

```
error eval /steps/takeTens/actions/cross/target {a: 20, b: 11}: ten[2] is outside ten (2 instances)
```

## 8. Timing, cancellation and a call that is cut off

The helper waits 5 seconds for the reply to `hello` and 120 seconds for the reply to a call. The
studio should answer well within these: `step.show` answers when the step starts, and a check
that takes long should return what it has.

An MCP client may cancel a call. The helper then closes the call's connection and sends the client
nothing for it. The studio sees the connection close, may stop work on the request, and must not
leave a document half changed: a patch either applies whole or not at all, even when the
connection closes while it is being applied.

If the connection closes after the helper has sent a request and before the reply, the helper
cannot know whether the call took effect, and says so to the agent, who reads the document's hash
before trying an edit again. A retried patch made against the old hash is refused as stale if the
first one applied, so a retry never applies an edit twice.

## 9. What the helper does with each reply

The helper offers seven tools. Each maps to one method; the text in the last column is what the
agent receives.

| Tool | Method | Result text |
|---|---|---|
| `list` | `documents.list` | `project <name>`, then one line per document: name, hash, `ok`, the counts or `unchecked`, and the title. |
| `read` | `document.read` | `hash <hash>`, then the value as compact JSON on one line. |
| `edit` | `document.patch` | `applied; hash <hash>; <counts>`, or a tool error: `refused; hash <hash>` and one line per finding. |
| `check` | `document.check` | `hash <hash>; <counts>`, then one line per finding, at most 40, and how many more there are. |
| `show` | `step.show` | `showing <step> (<index> of <count>)`, then the step's timeline on the following lines when the result has one, and the picture when one was asked for. |
| `create` | `document.create` | `created <doc>; hash <hash>; <counts>`, then the new document as compact JSON on one line. |
| `guide` | `guide.read` | The text. |

The helper checks the arguments' types before forwarding and answers a wrong one with a tool error,
without connecting. It answers with a tool error, too, when the studio is not running, speaks
another version, refuses the call, closes before answering, does not answer in time, or sends a
reply this document does not allow, such as a line that is not JSON, a reply to another id, or a
result without a required key. None of these ends the helper.

## 10. The Swift interface

`ChalkScriptMCP` holds both ends.

- `StudioClient` is the helper's end. `call(_:params:client:cancellation:)` makes one connection
  and returns a `StudioOutcome`.
- `StudioListener` is the studio's end. It creates the socket as section 1 describes, accepts
  connections on background threads, checks the peer's user, answers `hello`, and passes every
  other request to a `StudioHandler`:

```swift
public protocol StudioHandler: Sendable {
    func respond(to method: String, params: JSONObject, client: Implementation?) -> StudioReply
}
```

`respond` is called on a connection's thread, so a studio that keeps its documents on the main
actor hops there itself. `JSONValue` and `JSONObject` keep key order and number text as received
(section 2); `Finding` and `DocumentSummary` build the objects of sections 6 and 7.

## 11. Connecting a client

The helper's MCP side serves revision `2026-07-28` by per-request metadata, and the `initialize`
handshake for revisions `2024-11-05` to `2025-11-25`, so that a client of either era can use it.

In Claude Code, the helper is added as a stdio server. The path below is where the studio app is to
carry it:

```
claude mcp add --transport stdio --scope user chalkscript -- \
  "/Applications/ChalkScript Studio.app/Contents/Helpers/chalkscript-mcp"
```

In a checkout of this repository, `swift build --product chalkscript-mcp` builds it at
`.build/debug/chalkscript-mcp`, which can be given in place of the app's copy.

In Claude's desktop app, the helper is installed as a desktop extension: an `.mcpb` archive holding
the `chalkscript-mcp` binary and a `manifest.json` that declares a `binary` server whose command is
`${__dirname}/server/chalkscript-mcp`, the platform `darwin`, and the seven tools by name and
description. The manifest is `Studio/Extension/manifest.json`, and
`Studio/Extension/build-extension.sh` packs it with the helper from a built studio
([studio-app.md](studio-app.md)). For distribution the binary is to be signed with a Developer ID and
notarised; a development build carries the developer's own signature.
