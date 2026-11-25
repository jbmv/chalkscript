# Comments

The standard for comments in this repository's Swift. A comment describes the code as it is and
explains what the code cannot show. History belongs in commit messages. Here "one comment" means
one paragraph of a comment, or one part of a doc comment: its summary, one further paragraph, or
one parameter's description.

## Types

A type's summary is one sentence stating its purpose. Further paragraphs are for constraints the
code cannot show: threading, units, what a caller must not do.

## Members and parameters

A member gets a summary only when its name and signature do not say what it does or what it
guarantees. A parameter's description states only what the type cannot: units, ranges, what nil
or empty means, and errors a caller must handle. A comment never lists a member's callers or the
members it calls.

## Length

A comment is as short as its point. Cut what the code shows and what the cited requirement
already holds; an inline comment is usually one or two lines.

## Why, not what

An inline comment gives the reason for the code, not a restatement of it.

```swift
// Before
// Set the dim amount to the style's value.

// After
// What is out of shot is dimmed, not cropped, so the child keeps the whole picture (EXP-18).
```

## No history and no dates

A comment does not say what the code used to be or when it changed: no "was X, now Y",
"previously", "no longer", "as of", and no date. A measured value may be stated without the
occasion it was measured on.

## References

A comment may cite one requirement of the spec by id, such as `(EXP-6)`, or one GitHub issue,
such as `(#12)`. It cites nothing a reader of this repository cannot open. A research source is
cited by author and year.
