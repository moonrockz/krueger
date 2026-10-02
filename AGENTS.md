# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Overview

This module (`moonrockz/krueger`) is a **parser and parsing utilities** library for
[Elm](https://elm-lang.org/) and Elm-like dialects (e.g.
[Morphir](https://github.com/finos/morphir)). It provides:

- **Scanner** — tokenization of Elm/Elm-like source. Lossless: each token's
  `trivia_before`, `lexeme` and `trivia_after` (and, for a text with no tokens,
  the stream's `trivia`) rebuild the source, and their spans tile it. Offsets
  count UTF-16 units; columns count code points (a surrogate pair is one
  column, a lone surrogate one, a lone `\r` one); a single-line literal stops
  before an unescaped line break, LF or CRLF (a `\` before a line break is an
  unknown escape, as in `elm make`)
- **Parser** — grammar-driven parsing into an AST
- **AST** — an exact mirror of [stil4m/elm-syntax](https://package.elm-lang.org/packages/stil4m/elm-syntax/7.3.9/) 7.3.9, with a JSON encoder and decoder that match elm-syntax byte for byte
- **CST** — every token and top-level declaration, with trivia (whitespace and comments)
- **Printer** — Elm source from the AST (elm-format 0.8.7 layout, width fit at 120, minimal parentheses) and from the CST (lossless, `ModuleCst::to_source`)
- **Visitor interfaces** — pluggable traversal with multiple styles (DOM, fold, SAX-style, etc.), planned

The goal is full parity with Elm 0.19.1 syntax, measured against elm-syntax output
(epic `krueger-q56`).

### Architecture Summary

```
moonrockz/krueger
├── moon.work             # Workspace: the library (.), the test harness (harness/), the cookbook (docs/cookbook/) and the layout engine (pretty/)
├── src/                  # The library (the only published module)
│   ├── lib.mbt           # Package entry point; re-exports the public types
│   ├── dialect/          # Dialect: rejection rules, operator table, extension hooks
│   ├── scanner/          # Hand-written Elm 0.19.1 lexer, trivia, diagnostics
│   ├── parser/           # Parser: tokens → AST + CST + diagnostics
│   ├── report/           # Renders diagnostics like elm make (terminal, plain, JSON)
│   ├── ast/              # elm-syntax 7.3.9 mirror: types, encode_*, decode_*
│   ├── cst/              # Concrete syntax tree
│   ├── printer/          # AST to Elm source: elm-format shapes, parentheses, PrintError
│   ├── syntax/           # Node model and traversal: NodeRef, Tree, walk, fold, Visitor, events, NodePath, TreeCursor
│   ├── lawkit/           # Property-test generators and position/report helpers (public test support)
│   └── e2e/              # End-to-end tests (test-only)
├── pretty/               # Workspace module moonrockz/pretty: Wadler-style Doc engine (to be published on its own)
├── harness/              # Unpublished module moonrockz/krueger_harness (test-only dependencies)
│   ├── bdd/              # MoonSpec step definitions for tests/features
│   ├── bench/            # Benchmarks (mise run bench; smoke check in mise run test)
│   ├── parity/           # Elm parity over the pinned corpus (mise run test:parity)
│   └── rejection/        # Rejection parity (mise run test:rejection)
├── tests/features/       # Gherkin features
├── tests/fixtures/       # Elm sources with elm-syntax JSON (ast/, parser/)
├── scripts/              # MoonBit tooling scripts (.mbtx)
├── docs/cookbook/        # Unpublished module moonrockz/krueger_cookbook: task articles (*.mbt.md), tested
├── docs/plans/           # Older committed plans (new work documents go in .dev/)
├── .dev/                 # Gitignored working area for specs, plans and scratch files
├── .beads/               # Issue tracking (optional)
└── mise-tasks/          # File-based mise tasks
```

### AST and Parser Contract

- `@ast` types, field names and JSON shape follow elm-syntax 7.3.9 exactly.
  `@ast.encode_file` output must equal `Elm.Syntax.File.encode` output byte for byte.
- elm-syntax writes an Int literal as a JSON number, so above 2^53 it writes
  the nearest Double (`9007199254740993` becomes `9007199254740992`), and so
  does `encode_file`. The AST keeps the exact `Int64`. For an exact round
  trip, `encode_file_with(file, exact_ints=true)` (also
  `encode_declaration_with`, `encode_pattern_with`, `encode_expression_with`,
  `encode_function_with` and `encode_attributes_with`) writes the exact
  digits; it differs from elm-syntax only for literals above 2^53. The
  decoder reads a number's digits when they are an Int that rounds to the
  number's Double, unless they are that Double's own shortest form (as
  elm-syntax writes 2^60, `1152921504606847000`), so it reads both forms. The
  one ambiguous text, a literal whose digits are its Double's shortest form,
  is read as that Double.
- Every list in `@ast` types and in `@parser.DocAttribute`/`AttributeGroup` is an
  `ArrayView` (read-only; `src/ast/readonly_test.mbt` and its siblings check this
  at compile time). Build a list as an `Array` and store it (an `Array` converts
  to a view where a field expects one, `arr[:]` inside generic types such as
  `Node[ModuleName]`). A value built by hand (AST values, `DocAttribute`,
  `AttributeGroup`, or a `NodeRef` such as `File` or `Declaration`) shares the
  arrays you pass in, so do not change them afterwards (on js a view of a
  shortened array reads `undefined`). Parsed and decoded ASTs share no array
  with anything.
- The parser (`src/parser`) is a recursive-descent port of elm-syntax 7.3.9's parser
  over tokens, one file per elm-syntax module (`module_level`, `declarations`,
  `type_annotation`, `patterns`, `expression`), with elm-syntax's layout rules
  (column 1 for top-level items, positively indented continuations, top indentation
  for `let` and `case` items) and its operator table. It reproduces elm-syntax's
  range quirks; each one is marked with a comment where it is implemented.
- On all 363 corpus files the output is byte-identical to elm-syntax. When something
  cannot be parsed, the declaration is left out of the AST and the CST, and
  reported. Nesting deeper than 150 levels (parentheses, lists, records,
  `let`, `case` and so on), or a declaration whose AST is more than 400 levels deep
  (for example a very long operator chain, record access chain or type arrow
  chain), is a syntax error (`TOO MUCH NESTING`), not a stack overflow:

| Code | Meaning |
|------|---------|
| `KR-SCAN-001` | Unterminated block comment |
| `KR-SCAN-002` | Malformed doc comment |
| `KR-SCAN-003` | Invalid or unknown character sequence |
| `KR-SCAN-004` | Unterminated string, char or GLSL literal |
| `KR-PARSE-001` | Malformed module header (no AST) |
| `KR-PARSE-002` | Malformed import declaration |
| `KR-PARSE-003` | Malformed type declaration |
| `KR-PARSE-004` | Malformed function declaration |
| `KR-PARSE-005` | Unsupported syntax (not emitted at the moment; reserved) |
| `KR-PARSE-006` | Missing module header (no AST) |
| `KR-PARSE-007` | Unexpected syntax that elm-syntax rejects (skipped tokens, stray doc comments) |
| `KR-PARSE-008` | Syntax error in a port or infix declaration |
| `KR-PARSE-009` | Number literal out of range (warning; the value is clamped) |
| `KR-ATTR-001` | Malformed doc attribute (warning; the attribute is skipped) |

`src/diagnostics.mbt` holds these descriptions (`diagnostic_description(code)`); the parity
summary reads them. Keep this table and that file in step when you add a code.

- Fixture JSON in `tests/fixtures/` comes from elm-syntax 7.3.9. Regenerate it with the
  oracle, never by hand.
- Doc comments follow elm-syntax:
  - The first doc comment after the module header documents the module and goes to
    `File.comments`.
  - A declaration's documentation is the last doc comment before it; regular comments
    in between do not detach it. Its range starts at that doc comment.
  - Any other doc comment (before the header, before an import, at the end of the
    file) is an error (`KR-PARSE-007`); elm-syntax rejects such files.
- `File.comments` holds every regular comment and the module documentation, in
  source order.

### Diagnostics

Every `Diagnostic` has a `code` (`KR-SCAN-*`, `KR-PARSE-*`), a `severity`, a one-line
`message`, a `span`, a `title` and a `report`:

- `title` is the `elm make` title for the same problem (`UNFINISHED LET`, `NO TABS`, …).
  The parser keeps a stack of the constructs it is inside; a failure takes its title
  from the innermost one, or from a rule on the token it found (`RESERVED WORD`,
  `EXTRA COMMA`, `MISSING EXPRESSION`, `UNKNOWN OPERATOR`, …).
- `report` is the long message as blocks: `Text`, `Excerpt(context, highlight)`,
  `Hint`, `Note` and `Example`, with styled chunks (`Chunk::code`, `Chunk::keyword`).
  Write report text in Elm's voice: first person, plain words, what was seen and what
  was expected.
- `src/report` renders diagnostics: `render_plain` and `render_terminal` (the `elm make`
  layout: `-- TITLE ---- path` header, reflow to 80 columns, source excerpt with `^`
  markers) and `render_elm_json` (the `elm make --report=json` shape). All are
  re-exported from the root package, with `encode_diagnostics` for krueger's own JSON.

### Doc-Comment Attributes

A doc comment can carry attributes. krueger reads them into
`ParseResult.attributes` (per module and declaration, with file ranges);
`encode_attributes` gives JSON. Their meaning belongs to the tools that read them.
elm-format treats doc comments as Markdown and rewrites plain text (it escapes `_`,
turns `*a*` into `_a_`, doubles backslashes and wraps URLs), but keeps code spans and
code blocks byte for byte. So there are three forms:

1. An attributes block (use it for anything non-trivial): a fenced code block with
   the info string `attributes`. Content is read verbatim; an attribute runs until
   the next `@` line or a blank line. Other code blocks are not attributes blocks.

   ````elm
   {-| A customer account.

   ```attributes
   @derive [ Json.encoder, Json.decoder ]
   @morphir
       { kind = "entity"
       , key = "account_id"
       }
   ```

   -}
   ````

2. A value in a code span: ``@morphir `{ key = "account_id" }` ``.
3. A plain value, `@unit "EUR"` — only safe when the value has no `_`, `*`, `\`
   or URL. It continues on the next lines only while brackets are open or while the
   `@` line has no value yet.

- The name is `lower ("." lower)*`. Values are Elm data in application form:
  literals, lists, records, tuples, names and constructor applications.
- `@docs a, b` is the built-in list form. Other code blocks, prose and `@` in the
  middle of a line are not attributes. A malformed attribute is warning `KR-ATTR-001`
  and is skipped. Leave a blank line before `@docs` (elm-format joins the lines after
  `@docs`).
- `Dialect.attributes` (`DocComment` or `Off`) switches them on or off.
- `mise run rejection:record` also checks `tests/attributes/compat/*.elm`: `elm make`
  must accept each file and `elm-format --validate` must pass.

### Syntax Tree

`src/syntax` (re-exported from the root) is a read-only node model over a parse
result. It is the base for the traversal APIs and queries.

- `NodeRef` points into the typed AST; nothing is copied. `category()`,
  `kind()`, `range()`, `fields()`, `field(name)`, `children()` (source order),
  `children_with_fields()` (each child with its `PathStep`) and
  `field_of(child)` give generic access; typed code matches the cases.
  `field_of` looks through all the fields on each call; to get the field of
  every node, use `children_with_fields` or `Tree::field_of`.
- Kinds and field names are the elm-syntax JSON vocabulary. elm-syntax reuses
  tags (`record`, `list`, `unit`, …), so `(category, kind)` identifies a node
  type. Values that are not nodes (operator symbols, literal values, name
  qualifiers) are properties of their node, not children.
- Doc attributes of a declaration are children of that declaration (field
  `attributes`); module attributes and all comments are children of the file.
- `Tree::new(result)` builds a parent index once. `parent`, `step` (field and
  index in the parent) and `field_of` read it in constant time; `ancestors`
  (nearest first), `path` (root first) and `node_path(node)` (its `NodePath`
  from the root) are linear in the depth. `node_at(location)` (the innermost
  node that contains it) and `tokens_in(range)`.
- The walks in `src/syntax` use explicit stacks, not recursion, because wasm
  overflows at a few hundred frames and trees can be 400 levels deep. Nodes from
  the tree compare by identity first (`same`), so `parent` and `ancestors` do not
  compare whole subtrees.
- No shared mutable state: every returned array is new, and `Tree` keeps its own
  copies of the tokens (with their trivia arrays) and attribute groups;
  `tokens_in` returns new copies. Nodes point into the parse
  result's AST (nothing is copied), and every list in the AST, in doc
  attributes and in node payloads is a read-only `ArrayView`, so nothing
  reachable from a node can be changed.
- A declaration's range starts at its first doc attribute when that comes
  first (a port's doc comment is not part of its elm-syntax range).

The kind table below is checked against `kind_table()` by
`tests/features/syntax.feature`. When you add a kind or a field, update it.

<!-- kinds:start -->
| Category | Kind | Fields |
|---|---|---|
| `file` | `file` | moduleDefinition, imports, declarations, comments, attributes |
| `module` | `normal` | moduleName, exposingList |
| `module` | `port` | moduleName, exposingList |
| `module` | `effect` | moduleName, exposingList, command, subscription |
| `module_name` | `module_name` | — |
| `exposing` | `all` | — |
| `exposing` | `explicit` | explicit |
| `expose` | `infix` | — |
| `expose` | `function` | — |
| `expose` | `typeOrAlias` | — |
| `expose` | `typeexpose` | — |
| `import` | `import` | moduleName, moduleAlias, exposingList |
| `declaration` | `function` | documentation, signature, declaration, attributes |
| `declaration` | `typeAlias` | documentation, name, generics, typeAnnotation, attributes |
| `declaration` | `typedecl` | documentation, name, generics, constructors, attributes |
| `declaration` | `port` | name, typeAnnotation, attributes |
| `declaration` | `infix` | operator, function |
| `declaration` | `destructuring` | pattern, expression |
| `documentation` | `documentation` | — |
| `signature` | `signature` | name, typeAnnotation |
| `implementation` | `implementation` | name, arguments, expression |
| `constructor` | `constructor` | name, arguments |
| `let_declaration` | `function` | documentation, signature, declaration |
| `let_declaration` | `destructuring` | pattern, expression |
| `case_branch` | `case_branch` | pattern, expression |
| `record_setter` | `record_setter` | field, expression |
| `record_field` | `record_field` | name, typeAnnotation |
| `name` | `name` | — |
| `comment` | `comment` | — |
| `attribute` | `attribute` | name, arguments |
| `attribute` | `docs` | names |
| `expression` | `unit` | — |
| `expression` | `application` | application |
| `expression` | `operatorapplication` | left, right |
| `expression` | `functionOrValue` | — |
| `expression` | `ifBlock` | clause, then, else |
| `expression` | `prefixoperator` | — |
| `expression` | `operator` | — |
| `expression` | `hex` | — |
| `expression` | `integer` | — |
| `expression` | `float` | — |
| `expression` | `negation` | negation |
| `expression` | `literal` | — |
| `expression` | `charLiteral` | — |
| `expression` | `tupled` | tupled |
| `expression` | `list` | list |
| `expression` | `parenthesized` | parenthesized |
| `expression` | `let` | declarations, expression |
| `expression` | `case` | cases, expression |
| `expression` | `lambda` | patterns, expression |
| `expression` | `recordAccess` | expression, name |
| `expression` | `recordAccessFunction` | — |
| `expression` | `record` | record |
| `expression` | `recordUpdate` | name, updates |
| `expression` | `glsl` | — |
| `pattern` | `all` | — |
| `pattern` | `unit` | — |
| `pattern` | `char` | — |
| `pattern` | `string` | — |
| `pattern` | `hex` | — |
| `pattern` | `int` | — |
| `pattern` | `float` | — |
| `pattern` | `tuple` | value |
| `pattern` | `record` | value |
| `pattern` | `uncons` | left, right |
| `pattern` | `list` | value |
| `pattern` | `var` | — |
| `pattern` | `named` | patterns |
| `pattern` | `as` | name, pattern |
| `pattern` | `parentisized` | value |
| `type` | `generic` | — |
| `type` | `typed` | args |
| `type` | `unit` | — |
| `type` | `tupled` | values |
| `type` | `function` | left, right |
| `type` | `record` | value |
| `type` | `genericRecord` | name, values |
<!-- kinds:end -->

#### Traversal

- `walk(root, enter, leave?)` is the engine: pre-order over `children()` (source
  order), an explicit stack, `enter` returns a `Control`. `Continue` visits the
  children; `SkipChildren` does not (the node is still left); `Stop` ends the
  walk with no further `leave` calls. `leave` gets the same node object as its
  `enter`.
- `fold(root, init, enter, leave?)` threads an accumulator through the same walk,
  in callback order.
- `accept(root, visitor)` calls one `Visitor` method per node: `visit_function`
  (functions, top-level or `let`), `visit_declaration` (other declarations),
  `visit_expression`, `visit_pattern`, `visit_type`, `visit_case` (case
  branches), `visit_import`, `visit_comment`, `visit_attribute`, and
  `visit_other` for the rest (doc comments included). Every method defaults to
  `Continue`; `leave` to nothing.
- `EventReader::new(root)` gives the same walk as pull events: `next()` returns
  `Enter(EnterEvent)` or `Leave(LeaveEvent)`, then `None` after the root's
  `Leave`. An `EnterEvent` has only what a streaming parser knows when a node
  starts: `category`, `kind`, `field` (in the parent; `None` for the root),
  `start`, `depth` and `path`. A `LeaveEvent` has the finished `node` and the
  `depth` and `path` of its `Enter`. `skip_children()` right after an `Enter`
  makes the next event that node's `Leave`; elsewhere it does nothing. To stop,
  stop calling `next()`. `iter()` gives the remaining events as an
  `Iter[Event]` that reads from the same reader, so `skip_children()` on the
  reader still steers it.
- A `NodePath` is the list of steps (field and index in that field) from the
  start node, like a path into elm-syntax's JSON:
  `declarations[0].declaration[0].expression[0].application[1]`. It is
  immutable (a child's path shares its parent's steps); `depth()`, `steps()`,
  `last()`, `parent()` and `resolve(start)` read it. `from_steps(steps)`
  builds one, and `a.append(b)` is `a`'s steps followed by `b`'s. Its `Debug`
  form is `{ steps: [...] }`, root first.
- `push_events(source, handler)` drives any `EventSource` and calls
  `Handler::on_enter(EnterEvent)` (its `Control` steers the run) and
  `on_leave(LeaveEvent)`. Both default to `Continue` and nothing. A future
  streaming parser can implement `EventSource`; callers do not change. Code
  outside `src/syntax` reads event fields and matches them, and builds events
  with `EnterEvent::new` and `LeaveEvent::new` (which set `depth` from the
  path), so new fields need not break it.
- `TreeCursor::new(node)` is a tree-sitter-style cursor driven by the caller:
  `goto_first_child`, `goto_last_child`, `goto_next_sibling`,
  `goto_previous_sibling`, `goto_parent` and `goto_first_child_for(location)`
  (the innermost child that contains it, or else the first child after it)
  each return `false` and leave the cursor in place when there is nowhere to
  go. `goto_node_at(location)` moves to `node_at(location)` within the
  cursor's node (the rule of `Tree::node_at`, also where children overlap);
  it returns `false` and stays when the node does not contain the location.
  A plain `goto_first_child_for` loop goes one node too far when that node
  has children after the location. `node()`, `field_name()`
  (the role in the parent, `None` at the start node), `depth()`, `path()`,
  `reset(node)` and `copy()` (an independent cursor at the same place).
- With equivalent `Control` decisions, `walk`, `fold`, `accept`, an
  `EventReader` and `push_events` produce the same enter and leave sequence,
  and a full cursor navigation enters the same nodes. With `Continue` throughout, enters follow
  `children()` pre-order. Traversal state is private to each call; accumulator
  and visitor state remain the caller's and are not cloned. Nodes share the
  parse result's read-only AST.
- Laws: `src/syntax/*_law_test.mbt` (see "Property-Based Testing (Laws)").

### Printer

`src/printer` (re-exported from the root) prints an AST as Elm source:
`print_file`, `print_declaration`, `print_expression`, `print_pattern`
and `print_type_annotation`, each with `width?` (default 120) and
`dialect?` (default `elm-0.19.1`).

- Layout: the elm-format 0.8.7 shapes. Declaration bodies, custom types,
  `if`, `case` and `let` are always on several lines; lists, tuples,
  records, applications, operator chains, lambdas, signatures and
  exposing lists stay on one line when they fit in `width`.
- Parentheses: the printer adds only the parentheses that the parser
  needs (operator precedence and associativity from the dialect,
  arguments, negations, record access targets) and keeps the ones in the
  AST. For a parsed AST, `print_file` then `parse_module` gives the same
  AST without ranges and regular comments.
- Comments: documentation fields, the module documentation and port doc
  comments (both in `File.comments`) print; regular comments do not yet.
- An AST that cannot print as valid Elm raises `PrintError(path~,
  problem~)`. `path` is a `NodePath` from the printed node.
- Operator symbols (prefix operators, exposed operators, infix
  declarations) must be in the dialect's operator table; Elm 0.19 has no
  user-defined operators. Any other symbol raises `InvalidName(Operator,
  symbol)`.
- Expression printing uses an explicit work stack, so it is stack-safe on
  all targets. More than 400 nested printer levels raise `TooDeep`.
- The layout engine is the workspace module `pretty/` (`moonrockz/pretty`):
  `Doc`, the `Doc` builders (`text`, `verbatim`, `line`, `nest`, `tab`,
  `align`, `group`, `if_break`, ...) and `render`. It has no Elm
  knowledge. Krueger cannot publish a release that imports it until
  `moonrockz/pretty` is on mooncakes.io.
- `ModuleCst::to_source()` rebuilds the scanned text byte for byte.
- `mise run test:parity` checks the round trip, idempotence and the
  lossless CST on the corpus, and compares the printed text with
  `tests/printer/elm_format.lock`. Of the 363 corpus files, 150 are stable
  under elm-format 0.8.7. `tests/printer/pending.json` lists the 213 files
  that elm-format still changes; 196 of them differ because elm-format
  groups the module exposing list by the `@docs` lines (bd `krueger-iji`).
  Each pending file has a bd issue, and the list only shrinks: a fix
  removes entries, and the check fails when a listed file becomes stable.
  Differences that are known and not yet fixed are in bd `krueger-sou`
  (elm-format adds parentheses around a multi-line operand after an
  operator) and in the issues that the pending list names.
- After a printer change, run `mise run printer:record` (needs
  elm-format through `mise x`) and commit the lock. Give a pending path to
  reset the list: `mise run printer:record tests/printer/pending.json`. Use
  that only to start or reset the list.

### Dialects

A `Dialect` (`src/dialect`) selects what krueger accepts and rejects, and carries
extension data for Elm-like languages:

- `Dialect::elm_0_19_1()` is the default: it rejects what `elm make` 0.19.1 rejects as
  syntax. `Dialect::elm_syntax_7_3_9()` rejects exactly what elm-syntax 7.3.9 rejects.
- Fields: `rules` (the rejection `Rule`s that run), `operators` (the infix operator
  table), `reserved_words` and `operator_symbols` (extra keywords and operator symbols
  for the lexer), `attributes` (doc-comment attributes on or off).
- `tokenize`, `parse_module`, `parse_tokens` and `DefaultScanner::new` take an optional
  `dialect` argument; without it they use `elm-0.19.1`. Build the scanner and the parser
  with the same dialect.
- The AST shape is elm-syntax 7.3.9 in every dialect.
- Rejection rules (`Rule`, named in diagnostics as `[rule: <name>]`):

| Rule | elm-0.19.1 | elm-syntax-7.3.9 | Rejects |
|------|------------|------------------|---------|
| `indented-continuation` | on | on | a token not right of the current indent (except item starts) |
| `let-declaration-column` | on | on | a let declaration at or left of its `let` |
| `module-level-column` | on | on | a module header or import not in column 1 |
| `char-length` | on | on | a char literal with more than one character |
| `empty-hex` | on | on | `0x` without digits |
| `spaced-operator-name` | on | on | `( + )` in an exposing list |
| `leading-zero` | on | off | `007`, `01` |
| `uppercase-hex-prefix` | on | off | `0X1F` |
| `exponent-without-digits` | on | off | `1e` |
| `bad-unicode-escape` | on | off | a code point above `10FFFF` |
| `import-column` | on | off | an import after the first that does not start in column 1 |
| `non-ascii-digit-in-name` | on | off | a non-ASCII number in a name (`x٣`) |
| `titlecase-name-start` | off | on | a name that starts with a title-case letter (`ǅx`) |
| `effect-module` | on | off | an effect module outside an `elm/*` or `elm-explorations/*` package |
| `infix-declaration` | on | off | an infix declaration outside an `elm/*` or `elm-explorations/*` package |
| `duplicate-effect-key` | on | off | a repeated `command` or `subscription` in an effect module |
| `port-in-normal-module` | on | off | a `port` in a module that is not a `port module` |

  `Dialect.core_package` marks a file of an `elm/*` or `elm-explorations/*` package
  (`elm make` lets only those declare infix operators and effect modules); the parity
  harness sets it for those
  corpus files.
- Names follow Unicode: a lower-case name starts with a lower-case letter, an upper-case
  name with an upper-case or title-case letter, and later characters are letters,
  numbers or `_`. The table is `src/scanner/unicode_table.mbt`, generated from
  UnicodeData.txt by `mise run unicode:generate`.
- A number too big to store exactly is accepted with warning `KR-PARSE-009` (integers
  become `Int64` max, floats infinity).
  Both built-in dialects reject what both oracles reject; a rule that only one oracle
  enforces is on only in that dialect. The rejection check (`tests/rejection`) decides
  membership.

## Library Dependencies

### MoonBit Core Library

Treat these three official `moonbitlang` modules together as the MoonBit core library.
Look in them first before you write a helper or add a third-party dependency.

| Module | Purpose |
|--------|---------|
| `moonbitlang/core` | Standard library that ships with the toolchain (builtin, debug, collections, strings, etc.) |
| [`moonbitlang/x`](https://mooncakes.io/docs/moonbitlang/x) | Official standard library extensions (fs, sys, path, time, json5, crypto, codec, encoding, uuid, decimal, etc.) |
| [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async) | Official async runtime (tasks, task groups, I/O, process, HTTP); native target preferred |

`moonbitlang/core` comes with the toolchain. `moonbitlang/x` and `moonbitlang/async` are
versioned on mooncakes.io, so keep them on the latest release when you bump the toolchain.

### Third-Party Dependencies

| Module | Purpose |
|--------|---------|
| [moonrockz/moonspec](https://mooncakes.io/docs/moonrockz/moonspec) | BDD test framework (`harness/bdd`, test-only) |
| [moonrockz/expect](https://mooncakes.io/docs/moonrockz/expect) | Fluent test assertions (scripts; new tests) |

Module dependencies are declared in the `import` block of `moon.mod`. Each package lists
what it uses in its `moon.pkg`. Use `import { ... } for "test"` or `for "wbtest"` for
test-only dependencies.

MoonBit has no module-level test-only dependencies: every module in `moon.mod` is
downloaded by every user of krueger. So the published module (`moon.mod` at the root)
depends only on `moonrockz/expect` (used by the library packages' own tests); `expect`
itself imports `moonbitlang/async` and `moonbitlang/x`, so users still download those
two. Test
harnesses that need more (`moonspec`, `moonbitlang/async`, `moonbitlang/x`) live in the
unpublished workspace module `harness/` (`moonrockz/krueger_harness`), as
`moonbitlang/async` keeps its `examples/` and `test_programs/`:

- `moon.work` lists the library, `harness/` and `docs/cookbook/` (see
  "Documentation"); `harness/moon.mod` imports `moonrockz/krueger@0.0.0`,
  which the workspace resolves to the local module (the version is ignored).
- Run harness tests from the root: `moon test harness/parity`. They run with `harness/`
  as the working directory, so they reach repository files as `../tests/...`,
  `../.corpus` and `../_build/reports/...` (BDD steps take feature paths from the
  repository root and resolve them with `repo_path`).
- Put a new test that needs a harness-only dependency in `harness/`, not in `src/`.
- `.moonignore` keeps the harness, test data, docs and tooling out of the published
  package (`options(exclude: ...)` in `moon.mod` is deprecated); `moon package --list`
  shows what ships.

### Toolchain

- Supported targets: wasm, wasm-gc, js and native. Library packages (`src`, `scanner`,
  `parser`, `ast`, `cst`) must build and pass their tests on all four
  (`mise run test:targets`, CI job `targets`). llvm is left out because the toolchain does
  not ship `moonbitlang/core` for it.
- `moonbitlang/x` and `moonbitlang/async` count as core, but library code uses only
  `moonbitlang/core`; platform-specific packages (for example `async/fs`, which has no js
  implementation) belong in test-only or tooling code.

- The MoonBit toolchain version is pinned in `.github/workflows/*.yml` (`MOONBIT_VERSION`).
  Keep your local toolchain on the same version (`moon version --all`, `moon upgrade`).
- To upgrade: run `moon upgrade`, bump `MOONBIT_VERSION`, bump the `import` versions in
  `moon.mod`, `harness/moon.mod` and the pinned imports in `scripts/*.mbtx`, then run
  `moon update && moon check && mise run test`. Fix all new warnings, not only errors.
- Use `derive(Debug)` (not `derive(Show)`) for data types. `assert_eq` requires `Debug`.
  Implement `Show` by hand only for real text formats.

## Project Structure

- MoonBit packages are organized per directory; each has a `moon.pkg` listing dependencies.
- Blackbox tests: `*_test.mbt`; whitebox tests: `*_wbtest.mbt`. In blackbox tests,
  qualify names from the package under test (for example `@scanner.TokenKind`).
- Top-level `moon.mod` describes the module and metadata (the legacy `moon.mod.json`
  format is deprecated).

## Design Philosophy

This project follows **functional design principles** (aligned with moonrockz/gherkin and moonrockz/cucumber-expressions):

- **Algebraic data types (ADTs)** for domain concepts (enums + structs).
- **Make invalid states unrepresentable** — use the type system to prevent illegal states.
- **Avoid primitive obsession** — use domain types (e.g. `Token`, `Span`) instead of raw strings/ints.
- **Prefer immutability** — minimal `mut`; favor returning new values.
- **Pattern matching over conditionals** — exhaustive `match` on enums.
- **Total functions** — use `Option`/`Result` or typed `raise` for failures; avoid panic.

Visitor and AST design will aim for **flexibility** similar to moonrockz/gherkin (multiple traversal styles, composable visitors).

## Test-Driven Development (TDD)

- **Red–Green–Refactor**: Write a failing test first, then minimal implementation, then refactor.
- Use `#declaration_only` to sketch public APIs before implementation.
- Specify behavior as Gherkin features run by
  [moonrockz/moonspec](https://mooncakes.io/docs/moonrockz/moonspec)
  (`tests/features/` for the library, `scripts/features/` for scripts).
- Write assertions with [moonrockz/expect](https://mooncakes.io/docs/moonrockz/expect):
  `@expect.expect(actual).to_equal(expected)`, `.to_be_true()`, `.to_contain(...)`.
- Use soft assertions when a test or a step checks more than one fact: put the
  checks in one `@expect.expect_all(s => { ... })` block and write
  `s.expect(...)`, so a failure reports every failed check at once (needs
  `moonrockz/expect` 0.6.0 or later). Keep a precondition hard: a check that
  later code depends on (a length before indexing, a value before `unwrap`)
  uses `@expect.expect(...)` or `guard ... else { fail(...) }`, which stops the
  block. A single assertion needs no block, and a law returns a `Bool` instead.
  Use `inspect(...)` for snapshot tests. Existing `assert_eq` tests may stay; use
  `@expect` in new tests.
- Gherkin `{string}` parameters keep backslash escapes literally; use a
  single-quoted string (`'a"b\c'`) to pass `"` or `\`.
- Run `mise run test:unit` for tests; `moon test --update` to refresh snapshots.

### Property-Based Testing (Laws)

Property-based tests are a supplemental strategy. They do not replace the
example tests and features above; they add evidence of correctness by stating
**laws**: rules that hold for every input, checked against many generated
inputs.

- **When to write laws.** For every new type, feature or capability, ask which
  laws it must obey, and write them down in the plan next to the example tests.
  Typical laws:
  - invariants (every child's range lies inside its parent's range);
  - round trips (decode after encode gives the value back);
  - equivalences (two APIs give the same result: `walk`, `fold` and `accept`
    visit the same nodes);
  - algebraic rules (identity, idempotence, associativity, order preservation);
  - a model (a small, obviously correct reference implementation agrees with
    the real one).
- **Tooling.** Use `moonbitlang/core/quickcheck` (part of core; import it and
  `moonbitlang/core/quickcheck/splitmix` for `"test"` only). Check a law with
  `@quickcheck.check(law, count=…, max_size=…, seed=…)`. Always set `seed`, so
  a run is repeatable and CI failures reproduce locally.
- **Generators.** For domain inputs, wrap the value in a test-only newtype and
  implement `@quickcheck.Arbitrary` (and `@quickcheck.Shrink`, the default
  impl is fine to start):

  ```moonbit
  struct ElmModule(String) derive(Debug)

  impl @quickcheck.Arbitrary for ElmModule with fn arbitrary(size, rs) {
    ElmModule(gen_module(size, rs)) // the gen_* helpers halve `size` per level
  }

  impl @quickcheck.Shrink for ElmModule

  test "law: every child's range lies inside its parent's range" {
    @quickcheck.check(
      (m : ElmModule) => {
        let root = elm_root(m) // fails the law on any parse diagnostic
        let mut ok = true
        @syntax.walk(root, n => {
          let r = n.range()
          for c in n.children() {
            let cr = c.range()
            ok = ok && before_or_at(r.start, cr.start) && before_or_at(cr.end, r.end)
          }
          Continue
        })
        ok
      },
      count=100,
      max_size=24,
      seed=2026,
    )
  }
  ```

  Shared generators are `pub` types in `src/lawkit`:
  `elm_module.mbt` has the full `ElmModule` generator, and
  `src/syntax/gen_elm_test.mbt` has `elm_root` and the traversal `Policy`.
  Keep generated depth bounded by `size`, so
  generators do not overflow the stack on wasm.
- **Valid input fails loudly.** A generator of valid input must make the law
  fail on any diagnostic (as `elm_root` does), never skip or filter the case:
  otherwise a broken generator makes every law pass without testing anything.
  Generate arbitrary text only for laws that must hold for any text (the
  parser never crashes; a diagnostic is reported instead).
- **Name laws as laws.** Test names start with `law:` and state the rule, for
  example `law: fold with a logging accumulator gives walk's events`.
- **Boundary values.** Most bugs live at edges, and random input rarely reaches
  them. A law lists its edge values (in a comment or in its generator), and its
  generator reaches them: none, one and many; equal, nested, adjacent and empty
  ranges; the start and end of every range, one column before each; line and
  file ends; non-ASCII text (surrogate pairs); limits ± 1. A boundary bug found
  by hand becomes a law, not only an example.
- **Shared generators.** Use and extend the test-support package
  `src/lawkit` (`ElmModule`, `edge_positions`, `Ranges`, …), so every
  package's laws reach the same edges; add a new edge there, not in one
  package's tests. It is public (the harness module and krueger's users can
  write laws with it), so its names are part of krueger's versioned API. It
  is test support and unstable: generators, constructs and edge values change
  as the laws need them, also in minor releases.
  `lawkit` imports only the MoonBit core library and `@ast`, so black-box
  tests of any package, and white-box tests of any package except `ast`, can
  import it. Generators: `ElmModule` (valid Elm), `ElmText` (any
  text: fragments, unclosed literals and comments, edge characters, valid
  modules cut short or changed; it shrinks), `Nesting` and `nested(construct,
  depth)` (each nesting construct at any depth, biased to the limits ± 2),
  `ElmAst` (an AST built directly, for printer laws; every range is zero),
  `DocAttributes` (doc-comment attributes with Unicode names and values,
  continued values, `overflow_literal()`, LF, CRLF and mixed line ends),
  `Ranges`, and `units` (a string of UTF-16 units, for lone surrogates). Edge
  lists: `edge_chars()` and `literal_forms()`. Position helpers:
  `at_or_before`, `contains`, `within`, `range_edges`, `edge_positions`,
  `end_of_text`, `offset_of` (row/column to UTF-16 offset), `position_of` and
  `positions_of` (the inverse, for one offset or for sorted offsets in one
  pass) and `between_characters` (not inside a CRLF or a surrogate pair),
  which count columns exactly as the scanner does. Report helpers:
  `excerpt_lines` (the gutter lines of a rendered report), `shows_source`
  (the excerpts number the expected lines and show those source lines),
  `source_lines`, `line_count`, `strip_ansi`, `range_in_source` and
  `elm_json_problems` (the regions and messages of an `elm make` JSON
  report). `without_ranges` gives an AST's elm-syntax JSON with every range
  removed (`all` and `open` ranges become `true`), to compare ASTs that
  differ only in ranges.
- **Reach the success branch.** A law that returns `true` on an error (`Err(_)
  => true`) tests nothing for inputs that fail. Measure how often its
  generator reaches the success branch for each edge, and add a generator or
  an exhaustive test where it does not.
- **Enumerate small edge products.** When edges combine into a small product
  (every literal form × every edge character × every ending), test all of
  them in one example test with soft assertions instead of sampling.
- **Boundaries between characters.** A position law checks that every span
  boundary lies between characters (`between_characters`), not only that its
  row and column agree with its offset: an offset inside a surrogate pair maps
  to the same row and column as the offset after it.
- **Corpus as a law check.** A law that holds for generated input should also
  hold for the pinned corpus; add it to the corpus check where it is cheap.
  In parity mode (`mise run test:parity`) the corpus checks the lossless scan
  (LF and CRLF), the node model, the AST round trip through JSON text, and
  the never-crash laws for the scanner, the parser and the renderers on
  prefixes cut at token boundaries (0, each token's start, end and one unit
  in, and the end: all of them, or 50 evenly spaced ones per file).
- **Run on every target.** Laws run in `mise run test:unit` and
  `mise run test:targets` like other tests. Keep `count` and `max_size` small
  enough that a package's tests stay fast (a few seconds).

## Documentation

Two kinds of user documentation, both tested:

- **API reference**: `///` doc comments on public items, shown on
  mooncakes.io. The first line says what the item does; then the details a
  user needs (defaults, edge cases, errors). Entry points and items whose use
  is not obvious get an example in a fenced block with the info string
  `mbt check` that holds a `test { ... }`. `moon test` runs these examples as
  black-box tests of the package, so refer to the package by its alias
  (`@syntax.walk`). Use `debug_inspect` for `derive(Debug)` values. A doc
  comment block can hold only `test` blocks: with a `struct` or `impl` in it,
  moon skips the block (warning 4191). For such an example, use a block with
  the info string `mbt nocheck`, check it once in a scratch test, and point
  to a tested example (a cookbook article, by its GitHub URL). When you
  add or change a public item, update its doc comment and example.
- **Cookbook** (`docs/cookbook/`): one article per user task
  (`<slug>.mbt.md`), indexed in `docs/cookbook/README.md`. The directory is
  the unpublished workspace module `moonrockz/krueger_cookbook` with one
  package; `mise run test:docs` runs every `mbt check` block (CI job
  `unit-tests`). All articles share one namespace, so prefix each article's
  top-level names (`ax_`, `un_`, `tr_`, …). Use an `mbt nocheck` block only
  for code that cannot run as a test, such as a `main` that writes a file.
- `README.mbt.md` is the mooncakes.io landing page. It is not in a package,
  so its examples are not run: keep them short and copy them from tested
  code.
- Write documentation in ASD-STE100 Simplified Technical English: short
  sentences, active voice, one word for one meaning.

## Coding Convention

- MoonBit block style: blocks separated by `///|`; block order irrelevant.
- Deprecated code in `deprecated.mbt` per directory.

## Conventional Commits

All commits MUST use **[Conventional Commits](https://www.conventionalcommits.org)**:

```
type(scope): description
```

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `style`.
Breaking changes: add `!` after type (e.g. `feat(parser)!: change return type`).

Scopes (examples): `scanner`, `parser`, `ast`, `visitor`, `ci`, `build`.

## Mise Tasks

All operations use **file-based mise tasks** in `mise-tasks/`. Do not add inline `[tasks]` to `.mise.toml`.

| Task                | Purpose                                        |
|---------------------|------------------------------------------------|
| `hooks:install`     | Install project git hooks via lefthook         |
| `info:generate`     | Run `moon info` to generate interfaces         |
| `lint:check`        | Run lint/type checks (`moon check`)            |
| `format:check`      | Run formatting checks (`moon fmt --check`)     |
| `check`             | Run all checks (lint + format + tests)         |
| `test:unit`         | Run MoonBit unit tests                         |
| `test:bdd`          | Run MoonSpec BDD tests                         |
| `test:e2e`          | Run end-to-end tests                           |
| `test:scripts`      | Run MoonBit script tests (`scripts/*.mbtx`)    |
| `test:docs`         | Run the cookbook articles (`docs/cookbook/*.mbt.md`) |
| `test:targets`      | Check and test the library on wasm, wasm-gc, js and native |
| `test:parity`       | Score Elm parity against the golden lock (needs `corpus:fetch`) |
| `parity:ratchet`    | Raise `tests/corpus/baseline.json` to the current counts |
| `corpus:fetch`      | Download and verify the pinned corpus into `.corpus/` |
| `corpus:manifest`   | Rebuild `tests/corpus/manifest.json` from `packages.txt` |
| `corpus:goldens`    | Regenerate elm-syntax goldens and `goldens.lock` (needs Elm and Node) |
| `test:rejection`    | Check accept/reject verdicts against `tests/rejection/verdicts.json` |
| `unicode:generate`  | Regenerate the Unicode identifier table from UnicodeData.txt |
| `printer:record`    | Print the corpus and record elm-format verdicts in `tests/printer/elm_format.lock` |
| `rejection:record`  | Record `elm make` and elm-syntax verdicts for the rejection fixtures (needs Elm and Node) |
| `test:bench`        | Run every benchmark case once on small input (smoke check) |
| `bench`             | Measure the benchmarks (`--target t[,t...]`; all targets by default) |
| `bench:compare`     | Compare the last measurement with a run from the `benchmarks` branch |
| `test`              | Run all tests (unit + bdd + e2e + scripts + rejection + docs + bench) |
| `release:prepare`   | Open the release pull request (version bump and changelog section) |
| `release:version`   | Compute next version from conventional commits |
| `release:plan`      | Decide whether a Release workflow run releases (CI) |
| `release:notes`     | Print a version's GitHub release notes from `CHANGELOG.md` |
| `release:status`    | Check that main, the tags, the GitHub release and mooncakes.io agree |
| `release:credentials` | Set up mooncakes.io credentials (CI only)    |
| `release:publish`   | Publish package to mooncakes.io               |

## Scripts

Project tooling logic is written in MoonBit, not bash, `jq` or `awk`.

- Put tooling logic in standalone scripts: `scripts/<name>.mbtx`.
- Keep each mise task a one-line launcher:
  `exec moon run -q --target wasm scripts/<name>.mbtx -- <args>`.
  `-q` hides dependency manifest warnings; errors and output still show.
  Do not use `moonx`; the CI toolchain does not include it.
- In a script, put logic in pure functions. `async fn main` does only I/O.
- Specify each script's behavior in `scripts/features/<name>.feature`. The script
  runs its feature with moonspec from an `async test`; `moon test` runs with
  `scripts/` as the working directory, so load `features/<name>.feature`.
- Pin module imports in each script (`moonbitlang/async@<version>`,
  `moonbitlang/x@<version>/sys`, `moonrockz/moonspec@<version>`,
  `moonrockz/expect@<version>`) to the versions used by the module.
- Test the scripts with `mise run test:scripts`. `moon test` and `moon fmt`
  handle a `.mbtx` file only when you give its path.
- Do not add new logic to bash task files. A task that calls one `moon`
  command can stay bash.

| Script | Task | Purpose |
|--------|------|---------|
| `scripts/coverage.mbtx` | `coverage:ci-gate`, `coverage:ci-warn` | Coverage summary and threshold |
| `scripts/credentials.mbtx` | `release:credentials` | Write mooncakes.io credentials (CI only) |
| `scripts/release.mbtx` | `release:prepare`, `release:version`, `release:plan`, `release:notes`, `release:status` | Release pull request, next version, release decision in CI, release notes, release health check |
| `scripts/publish.mbtx` | `release:publish` | Publish to mooncakes.io; a release tag must match `moon.mod`'s version; an already published version (a second run for the tag) succeeds |
| `scripts/printer.mbtx` | `printer:record` | Record elm-format 0.8.7 verdicts for the printed corpus |
| `scripts/hooks_install.mbtx` | `hooks:install` | Install lefthook hooks |
| `scripts/corpus.mbtx` | `corpus:manifest`, `corpus:fetch` | Pin, download and verify the parity corpus |
| `scripts/goldens.mbtx` | `corpus:goldens` | Run the elm-syntax oracle over the corpus |
| `scripts/bench.mbtx` | `bench`, `bench:compare` | Measure, compare with the history, write the summary and the HTML report, add a run to the history |

## Elm Parity

krueger measures parity with Elm 0.19.1 against stil4m/elm-syntax 7.3.9 on a pinned
corpus of real packages (`tests/corpus/`).

- `tests/corpus/packages.txt` lists the packages; `manifest.json` pins each zip (SHA-1)
  and each `.elm` file (SHA-256).
- `tests/corpus/goldens.lock` holds, per file, the SHA-256 of the canonical elm-syntax
  JSON (or `PARSE_ERROR`). Only hashes are committed; the full JSON stays local in
  `.dev/out/goldens/raw/`.
- `mise run test:parity` prints the scoreboard: files, tokenized, parsed (no
  diagnostics), matched (krueger's `@ast.encode_file` hash equals the golden). It fails
  when a count drops below `tests/corpus/baseline.json`. CI runs it in the `parity` job.
- Scoring parses in the `elm-syntax-7.3.9` dialect. A second pass parses every corpus
  file in the default `elm-0.19.1` dialect and fails on any error, because `elm make`
  accepts published packages.
- `test:parity` and `parity:ratchet` write reports to `_build/reports/parity/`:
  `parity.html` (open in a browser; filter by status), `parity.json` (full results),
  `parity.xml` (JUnit: one testsuite per package; unmatched files are `skipped`, only
  a baseline regression is a `failure`) and `summary.md`. CI uploads them as the
  `parity-report` artifact and adds `summary.md` to the job summary.
- When a change raises the counts, run `mise run parity:ratchet` and commit
  `baseline.json`.
- To see why a file does not match, run `mise run corpus:goldens` once (needs Elm and
  Node; `mise x` installs them), then `mise run test:parity`: it prints the first
  differing node path and both values for up to 20 files.
- To add a package: add it to `packages.txt`, run `mise run corpus:manifest`, then
  `mise run corpus:goldens`, then commit the manifest and the lock.
- The oracle is `tools/elm-syntax-oracle/` (Elm worker plus Node runner). CI never runs it.

## Rejection Parity

krueger checks which Elm source it accepts and rejects against two oracles: `elm make`
0.19.1 (dialect `elm-0.19.1`) and elm-syntax 7.3.9 (dialect `elm-syntax-7.3.9`).

- `tests/rejection/<group>/<case>.elm` are small modules, each compiled as
  `src/Fixture.elm`. A negative fixture has one syntax problem and is valid otherwise.
- `mise run rejection:record` (needs Elm and Node; `mise x` installs them) runs `elm make
  --report=json` and the elm-syntax oracle on every fixture and writes
  `tests/rejection/verdicts.json`: the fixture's SHA-256, the `elm make` verdict (with
  title, region and message when it rejects; `later_error` when only a later phase such
  as naming or types fails, which means the parser accepted it) and the elm-syntax
  verdict. CI never runs `elm make`.
- `mise run test:rejection` parses each fixture in both dialects. krueger accepts a file
  when it gives no diagnostic with severity `Error`. A changed fixture fails with "run
  `mise run rejection:record`".
- Title parity: for a fixture that both `elm make` and krueger (in `elm-0.19.1`) reject,
  krueger's first error must have the same title as `elm make`'s. A mismatch is a
  `pending.json` entry with `"check": "title"`.
- `tests/rejection/messages/<fixture>.txt` holds krueger's rendered message
  (`render_plain`) for every fixture it rejects in `elm-0.19.1`. A changed, missing or
  stale message fails the check. Review the messages, then run
  `KRUEGER_REJECTION_MODE=approve mise run test:rejection`; the PR diff is the review.
- `test:rejection` writes `_build/reports/rejection/index.html`: per fixture, `elm make`'s
  and krueger's verdicts, titles and messages side by side. CI uploads it as the
  `rejection-report` artifact.
- `tests/rejection/pending.json` lists the fixture and dialect pairs that do not match yet.
  The list only shrinks: the check fails on a mismatch that is not listed and on a listed
  pair that now matches (remove it). `KRUEGER_REJECTION_MODE=write-pending` rewrites the
  list; use it only when adding fixtures.

## Benchmarks

Benchmarks measure krueger's speed over time. They are not a CI gate.

- `harness/bench` holds the cases: `corpus/*` (tokenize, parse and encode
  every corpus file) and `syntax/*` (tree queries on the corpus and on a
  generated module with 1000 declarations). A case ID is
  `<suite>/<case>/<input>`; a renamed case starts a new series. Each case
  has a `check`, which runs before the case is measured.
- `mise run bench` measures every case on `native`, `js`, `wasm-gc` and
  `wasm` (`mise run bench --target native,js` for a subset; needs
  `mise run corpus:fetch`) and writes
  `_build/reports/bench/benchmark-results.json` (the results file). Times
  are microseconds per call (from 10 batches).
- `mise run bench:compare` compares the results file with a run from the
  history (default: the latest `main` run; `--against <sha|run:<id>|file>`)
  and writes `summary.md` and `report.html` (the tables and a trend of the
  last 20 `main` runs per case).
- A case is marked `slower` or `faster` only when the median changes by
  more than 10% and the interquartile ranges do not overlap. GitHub runners
  vary by 10 to 20 percent between runs; the summary warns when the
  baseline ran on another CPU or toolchain.
- The history is the orphan branch `benchmarks`: one run file per run under
  `runs/YYYY/MM/`. Never merge it. Local runs are not added.
- The Benchmarks workflow (Actions > Benchmarks > Run workflow) takes
  `targets` (empty: all four), `compare_to`, `record` and `force_record`.
  It adds the summary to the job summary, uploads `_build/reports/bench/`
  as the `bench-report` artifact (90 days) and adds runs on `main` to the
  history.
- `mise run test` runs every case once on small input (`test:bench`), so
  the cases stay correct.
- To add a case, add it to `corpus_cases` or `syntax_cases` in
  `harness/bench`, with a `check` that fails on a wrong result.
- For a performance change, compare a run before and after the change
  (locally, or with the workflow) and put the summary in the pull request.

## Tooling

- `moon fmt` — format code.
- `moon info` — update generated `.mbti` interface.
- `moon check` — typecheck.
- Run `moon info && moon fmt` before committing when API or formatting may have changed.

## The `.dev/` Working Area

`.dev/` is a gitignored scratch area for AI-assisted development: temporary scripts, agent and
script outputs, and working documents. Nothing in it is committed. Layout:

- Specs from the superpowers `brainstorming` skill: `.dev/docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
- Plans from the superpowers `writing-plans` skill: `.dev/docs/superpowers/plans/YYYY-MM-DD-<topic>-plan.md`
- Scratch scripts and their outputs: `.dev/scripts/`, `.dev/out/`

This layout overrides the default location of any skill or tool. Never place specs, plans or
other working documents under `docs/`, and never `git add` anything under `.dev/`. When a
design is final and meant for readers, write it up in a committed location on purpose.

## Release Process

- Publishes to **mooncakes.io** and **GitHub Releases**, and records every release in
  `CHANGELOG.md`.
- The release-manager skill (`.claude/skills/release-manager/`) walks an agent through
  a release, troubleshooting (`TROUBLESHOOTING.md`) and improving the process after
  each release. Agents other than Claude Code can read its `SKILL.md` directly.
- `mise run release:status` checks that main, the tags, the GitHub release and
  mooncakes.io agree; each problem it prints names the command that fixes it.
- To release, run `mise run release:prepare` on a clean working tree. It fetches
  `origin/main`, computes the next version with git-cliff (pinned in `.mise.toml`,
  configured in `cliff.toml`; on 0.x a `feat` or a breaking change bumps the minor,
  anything else the patch), sets `version` in `moon.mod`, prepends the version's
  section to `CHANGELOG.md`, commits `chore(release): v<version>` on branch
  `release/v<version>`, pushes it and opens the pull request. It also sets the
  string that `version()` in `src/lib.mbt` returns; `harness/bdd/version_wbtest.mbt`
  checks that it equals `moon.mod`'s version. Give a version to
  override git-cliff (`mise run release:prepare 1.0.0`); `--local` stops before the
  push.
- In the pull request, replace the highlights comment at the top of the new section
  with a few sentences on what the release brings, and reword the generated lines
  where needed. Then merge. Do not bump the version in any other pull request.
- Merge the release pull request before other pull requests. A pull request that
  merges first is not in the new section and goes into no later section either (the
  tag covers it). If that happens, close the release pull request, delete its branch
  and run `mise run release:prepare` again.
- The merge changes `moon.mod` on `main`, so the Release workflow runs:
  - `plan` (`mise run release:plan`) releases when `v<version>` has no tag yet and
    `CHANGELOG.md` has the version's section; otherwise it skips, or fails when the
    section is missing.
  - `validate` runs `moon fmt`, `moon check`, `mise run test:unit` and
    `mise run test:scripts`; `publish` publishes to mooncakes.io (needs the
    `MOONCAKES_USER_TOKEN` org secret).
  - `release` creates the tag on the merge commit and the GitHub release. Its notes
    (`mise run release:notes <version>`) are an install line followed by the
    changelog section: highlights, breaking changes, grouped changes with PR links
    and authors, and the compare link.
- A pushed `v*` tag (it must match `moon.mod`'s version) and a manual run also work.
- A release run is safe to repeat: release runs never overlap (a concurrency group),
  an already published version and an existing GitHub release are skipped. The tag is
  created with `GITHUB_TOKEN`, which starts no second run.
- Write commit and pull request titles for the changelog: the squash-merge title is
  the changelog line. `chore(release)` and `chore(beads)` commits are left out.

## Work Tracking

**bd (beads) is the primary tracker for all work.** GitHub Issues are the
public intake for reports from outside contributors.

- Track every task, bug, feature and epic in bd. Do NOT use markdown TODO
  lists or other tracking methods.
- Mirror each GitHub issue into bd with `--external-ref gh-<number>`, and keep
  the two in step: when the bd issue closes, close the GitHub issue.
- A pull request that resolves a GitHub issue says `Closes #<number>` in its
  body. Name the bd issue in the body too.
- Work lands on `main` through pull requests (squash merge). Branch first;
  do not push to `main` unless the user says so for that change.
- bd runs with `agent.profile: team-maintainer` (`.beads/config.yaml`):
  commit, `bd sync` and push are routine parts of the work. An explicit
  "do not commit" or "do not push" from the user still wins, and pushes go to
  your branch, not to `main`.

## Persistent Memory

Store knowledge that must outlive the session with `bd remember`. Do not use
`MEMORY.md` files or any agent's own memory store for this project; bd
memories sync through `refs/dolt/data`, so every machine and agent sees them.

```bash
bd remember "insight" --key <slug>   # store, or update the memory with that key
bd memories <keyword>                # search
bd recall <key>                      # read one
```

`bd prime` (the SessionStart hook) injects the memories into each session.

<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT
use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: syncs through a Dolt remote on the Git origin
  (`refs/dolt/data`), separate from source branches
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:krueger-123 --json
bd create "Issue title" --description="..." --external-ref gh-12 --json   # mirror a GitHub issue
```

**Claim and update:**

```bash
bd update krueger-42 --status in_progress --json
bd update krueger-42 --priority 1 --json
```

**Complete work:**

```bash
bd close krueger-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task**: `bd update <id> --status in_progress`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Storage and Sync

- bd stores issues in an embedded Dolt database at `.beads/embeddeddolt/`
  (not committed).
- Git worktrees share the database of the main checkout. Do not create a
  database inside a worktree.
- Cross-machine sync uses a Dolt remote on the GitHub origin. Dolt keeps issue
  history under `refs/dolt/data`, separate from source branches:
  - `bd sync` — pull, check for conflicts, and push in one step.
  - `bd dolt pull` / `bd dolt push` — the individual steps.
- Issue changes need no commit or pull request: `bd sync` publishes them to
  `refs/dolt/data`.
- `.beads/issues.jsonl` is a passive export (`bd export -o .beads/issues.jsonl`)
  for viewers and interchange. It is gitignored; do not commit it.

### Setup on a Fresh Clone

```bash
bd bootstrap            # clones refs/dolt/data from origin and wires the Dolt remote
mise run hooks:install  # installs lefthook git hooks (these call `bd hooks run <hook>`)
git config beads.role maintainer   # or contributor
```

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT duplicate tracking systems (GitHub issues are mirrored, not tracked twice)

<!-- END BEADS INTEGRATION -->

## Landing the Plane (Session Completion)

When you end a work session, complete ALL steps below. Work is NOT complete
until the pushes succeed.

1. **File issues for remaining work** in bd.
2. **Run quality gates** if code changed: `mise run check`,
   `moon info && moon fmt`.
3. **Update issue status**: close finished work, update in-progress items.
4. **Push** (mandatory):
   ```bash
   bd sync                  # publish issue changes to refs/dolt/data
   git pull --rebase
   git push                 # your branch; open or update its pull request
   git status               # MUST show "up to date with origin"
   ```
5. **Clean up**: clear stashes, prune merged branches.
6. **Hand off**: give context for the next session.

Never stop before pushing; that leaves work stranded on one machine. If a push
fails, resolve the cause and retry.
