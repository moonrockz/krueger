# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Overview

This module (`moonrockz/krueger`) is a **parser and parsing utilities** library for
[Elm](https://elm-lang.org/) and Elm-like dialects (e.g.
[Morphir](https://github.com/finos/morphir)). It provides:

- **Scanner** — tokenization of Elm/Elm-like source
- **Parser** — grammar-driven parsing into an AST
- **AST** — an exact mirror of [stil4m/elm-syntax](https://package.elm-lang.org/packages/stil4m/elm-syntax/7.3.9/) 7.3.9, with a JSON encoder and decoder that match elm-syntax byte for byte
- **CST** — every token and top-level declaration, with trivia (whitespace and comments)
- **Visitor interfaces** — pluggable traversal with multiple styles (DOM, fold, SAX-style, etc.), planned

The goal is full parity with Elm 0.19.1 syntax, measured against elm-syntax output
(epic `krueger-q56`).

### Architecture Summary

```
moonrockz/krueger
├── src/                  # The library (sole artifact for now)
│   ├── lib.mbt           # Package entry point; re-exports the public types
│   ├── dialect/          # Dialect: rejection rules, operator table, extension hooks
│   ├── scanner/          # Hand-written Elm 0.19.1 lexer, trivia, diagnostics
│   ├── parser/           # Parser: tokens → AST + CST + diagnostics
│   ├── report/           # Renders diagnostics like elm make (terminal, plain, JSON)
│   ├── ast/              # elm-syntax 7.3.9 mirror: types, encode_*, decode_*
│   ├── cst/              # Concrete syntax tree
│   ├── syntax/           # Node model and traversal: NodeRef, Tree, walk, fold, Visitor, events, NodePath, TreeCursor
│   ├── bdd/              # MoonSpec step definitions (test-only)
│   └── e2e/              # End-to-end tests (test-only)
├── tests/features/       # Gherkin features
├── tests/fixtures/       # Elm sources with elm-syntax JSON (ast/, parser/)
├── scripts/              # MoonBit tooling scripts (.mbtx)
├── docs/plans/           # Older committed plans (new work documents go in .dev/)
├── .dev/                 # Gitignored working area for specs, plans and scratch files
├── .beads/               # Issue tracking (optional)
└── mise-tasks/          # File-based mise tasks
```

### AST and Parser Contract

- `@ast` types, field names and JSON shape follow elm-syntax 7.3.9 exactly.
  `@ast.encode_file` output must equal `Elm.Syntax.File.encode` output byte for byte.
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
  `kind()`, `range()`, `fields()`, `field(name)`, `children()` (source order)
  and `field_of(child)` give generic access; typed code matches the cases.
- Kinds and field names are the elm-syntax JSON vocabulary. elm-syntax reuses
  tags (`record`, `list`, `unit`, …), so `(category, kind)` identifies a node
  type. Values that are not nodes (operator symbols, literal values, name
  qualifiers) are properties of their node, not children.
- Doc attributes of a declaration are children of that declaration (field
  `attributes`); module attributes and all comments are children of the file.
- `Tree::new(result)` builds a parent index once. `parent`, `ancestors`
  (nearest first), `path` (root first), `node_at(location)` (the innermost node
  that contains it), `node_path(node)` (its `NodePath` from the root) and
  `tokens_in(range)`.
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
  stop calling `next()`.
- A `NodePath` is the list of steps (field and index in that field) from the
  start node, like a path into elm-syntax's JSON:
  `declarations[0].declaration[0].expression[0].application[1]`. It is
  immutable (a child's path shares its parent's steps); `depth()`, `steps()`,
  `last()`, `parent()` and `resolve(start)` read it.
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
  go. To reach `node_at(location)`, descend while the new node contains the
  location and step back with `goto_parent` from the first that does not; a
  plain `goto_first_child_for` loop goes one node too far when that node has
  children after the location. `node()`, `field_name()`
  (the role in the parent, `None` at the start node), `depth()`, `path()`,
  `reset(node)` and `copy()` (an independent cursor at the same place).
- With equivalent `Control` decisions, `walk`, `fold`, `accept`, an
  `EventReader` and `push_events` produce the same enter and leave sequence,
  and a full cursor navigation enters the same nodes. With `Continue` throughout, enters follow
  `children()` pre-order. Traversal state is private to each call; accumulator
  and visitor state remain the caller's and are not cloned. Nodes share the
  parse result's read-only AST.
- Laws: `src/syntax/*_law_test.mbt` (see "Property-Based Testing (Laws)").

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
| [moonrockz/moonspec](https://mooncakes.io/docs/moonrockz/moonspec) | BDD test framework (`src/bdd`, test-only) |
| [moonrockz/expect](https://mooncakes.io/docs/moonrockz/expect) | Fluent test assertions (scripts; new tests) |

Module dependencies are declared in the `import` block of `moon.mod`. Each package lists
what it uses in its `moon.pkg`. Use `import { ... } for "test"` or `for "wbtest"` for
test-only dependencies.

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
  `moon.mod` and the pinned imports in `scripts/*.mbtx`, then run
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

  `src/syntax/gen_elm_test.mbt` has the full generator (`ElmModule`,
  `Policy`) and `elm_root`. Keep generated depth bounded by `size`, so
  generators do not overflow the stack on wasm.
- **Valid input fails loudly.** A generator of valid input must make the law
  fail on any diagnostic (as `elm_root` does), never skip or filter the case:
  otherwise a broken generator makes every law pass without testing anything.
  Generate arbitrary text only for laws that must hold for any text (the
  parser never crashes; a diagnostic is reported instead).
- **Name laws as laws.** Test names start with `law:` and state the rule, for
  example `law: fold with a logging accumulator gives walk's events`.
- **Corpus as a law check.** A law that holds for generated input should also
  hold for the pinned corpus; add it to the corpus check where it is cheap.
- **Run on every target.** Laws run in `mise run test:unit` and
  `mise run test:targets` like other tests. Keep `count` and `max_size` small
  enough that a package's tests stay fast (a few seconds).

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
| `test:targets`      | Check and test the library on wasm, wasm-gc, js and native |
| `test:parity`       | Score Elm parity against the golden lock (needs `corpus:fetch`) |
| `parity:ratchet`    | Raise `tests/corpus/baseline.json` to the current counts |
| `corpus:fetch`      | Download and verify the pinned corpus into `.corpus/` |
| `corpus:manifest`   | Rebuild `tests/corpus/manifest.json` from `packages.txt` |
| `corpus:goldens`    | Regenerate elm-syntax goldens and `goldens.lock` (needs Elm and Node) |
| `test:rejection`    | Check accept/reject verdicts against `tests/rejection/verdicts.json` |
| `unicode:generate`  | Regenerate the Unicode identifier table from UnicodeData.txt |
| `rejection:record`  | Record `elm make` and elm-syntax verdicts for the rejection fixtures (needs Elm and Node) |
| `test`              | Run all tests (unit + bdd + e2e + scripts + rejection) |
| `release:version`   | Compute next version from conventional commits |
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
| `scripts/version.mbtx` | `release:version` | Next version from conventional commits |
| `scripts/hooks_install.mbtx` | `hooks:install` | Install lefthook hooks |
| `scripts/corpus.mbtx` | `corpus:manifest`, `corpus:fetch` | Pin, download and verify the parity corpus |
| `scripts/goldens.mbtx` | `corpus:goldens` | Run the elm-syntax oracle over the corpus |

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

- Publishes to **mooncakes.io** and **GitHub Releases**.
- Trigger: push tag `v*` or workflow_dispatch.
- Requires `MOONCAKES_USER_TOKEN` org secret for publish.
- Pre-publish: `moon check`, `moon fmt`, `mise run test:unit`, `mise run test:scripts`.

## Landing the Plane (Session Completion)

When ending a work session:

1. File issues for remaining work.
2. Run quality gates (tests, fmt, check) if code changed.
3. Update issue status (e.g. bd close / bd update).
4. **PUSH TO REMOTE** — mandatory: `bd sync`, then `git pull --rebase` and `git push`. Work is not complete until both pushes succeed.
5. Clean up; verify all changes committed and pushed; hand off context for next session.


<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: syncs through a Dolt remote on the Git origin (`refs/dolt/data`), separate from source branches
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
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update bd-42 --status in_progress --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
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

- bd stores issues in an embedded Dolt database at `.beads/embeddeddolt/` (not committed).
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
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and docs/QUICKSTART.md.

<!-- END BEADS INTEGRATION -->
