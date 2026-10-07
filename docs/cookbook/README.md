# krueger cookbook

Each article shows how to do one task with krueger. Every code block marked
`mbt check` is a test. `mise run test:docs` compiles and runs the articles,
so the code stays in step with the API.

## Start here

- [Parse your first Elm module](getting-started.mbt.md): add krueger,
  parse a module, check diagnostics, read the AST, tokenize.
- [Report syntax errors](error-reports.mbt.md): read a `Diagnostic` and
  render it like `elm make` (terminal, plain text, JSON).

## Walk the syntax tree

- [Choose a traversal](traversal.mbt.md): when to use `walk`, `fold`,
  `Visitor`, `EventReader`, `push_events` or `TreeCursor`, and one task for
  each of the first five (find a call, count nodes, a lint rule, an outline,
  collect imports).
- [Build editor features](editor-features.mbt.md): the node under the
  cursor, breadcrumbs, the enclosing function, cursor moves, stable node
  paths, the tokens and comments of a node.

## Convert to other formats

- [Build an AST explorer](ast-explorer.mbt.md): a JSON tree with types,
  fields, ranges and UTF-16 offsets, and a self-contained HTML viewer page
  ([example](ast-explorer.example.html)).
- [Build a unist tree](unist.mbt.md): a [unist](https://github.com/syntax-tree/unist)
  tree for unified tools such as `unist-util-visit`.
- [Read and write elm-syntax JSON](elm-syntax-json.mbt.md): encode and
  decode the elm-syntax 7.3.9 JSON format, with exact Int literals.

## Format Elm

- [Format Elm source](format-elm-source.mbt.md): format a file as
  elm-format 0.8.7 does, with comments in place; choose a layout; report
  syntax errors.

## Generate Elm

- [Generate Elm code](generate-elm.mbt.md): build an AST in code and print
  it as Elm source in the elm-format layout; handle `PrintError`.

## Elm-like languages

- [Choose a dialect](dialects.mbt.md): `elm make` rules or elm-syntax
  rules, core packages, a custom dialect with new keywords and operators.
- [Read doc-comment attributes](doc-attributes.mbt.md): structured data in
  doc comments, as Morphir uses it.

## Write an article

Add `<slug>.mbt.md` to this directory and a link to this index. Put
runnable code in `mbt check` blocks. All articles are one MoonBit package,
so start every top-level name with a short prefix for the article (`ax_`,
`un_`, `tr_`, …). Run `mise run test:docs`. To fill in snapshot values, run
`moon test docs/cookbook/<slug>.mbt.md --target js --update` and check each
value by hand.
