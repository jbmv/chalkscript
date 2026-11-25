# Contributing

## The spec comes first

[docs/spec/explainers.md](docs/spec/explainers.md) states what is true of the project now. A
change that conflicts with a requirement either changes course or changes the requirement in
the same pull request, with the reason.

- Requirement ids (`EXP-<n>`) are stable. A requirement that is replaced or withdrawn stays as
  a tombstone (`status: superseded` with `superseded-by:`, or `status: withdrawn`).
- Section metadata is `key: value` lines under the heading.
- A claim about learning cites its source by author and year, with the finding.

## Writing

Documents use a plain, academic register. State the problem, then what the project does about
it. Keep sentences short. Use exact terms. Do not sell: no slogans, no aphorisms, no sweeping
claims, and no statistics or anecdotes used for effect.

## Code

- `swift build` and `swift test` pass before a pull request is opened.
- Every number an explainer draws, shows or speaks is computed from the problem's values
  (EXP-2). Wording is given to a template by the app; it is not written in the package.
- Comments follow [docs/COMMENTS.md](docs/COMMENTS.md).

## Commit messages

- The first line says what the commit does, in the imperative, in about 70 characters.
- The body gives the reason where the first line does not.
- Cite the requirement a change serves by id, such as `(EXP-6)`, or a GitHub issue, such as
  `(#12)`. Cite nothing a reader of this repository cannot open: no ids or links from a private
  tracker. `scripts/check-public.sh` refuses the ones it knows, and a pre-push hook runs it on
  the commits being pushed. Enable the hook once per clone with
  `git config core.hooksPath scripts/hooks`.

## Children's data

Nothing from a real child goes into the repository, an issue or a pull request: no handwriting
samples, no photographs of homework, no names, no school details. Use synthetic examples.

## Licences

Contributions of code are accepted under the MIT licence, and contributions of documentation
and other content under CC BY 4.0. Contribute only work that is yours to license; do not copy
text, problems or pictures from published curricula or workbooks.
