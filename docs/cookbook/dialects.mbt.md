# Choose a dialect

This article shows how to select what krueger accepts and rejects. You
compare the two built-in dialects on one input, mark a file of a core
package, and build a custom dialect for an Elm-like language with an extra
keyword and an extra operator. You also see why the scanner and the parser
must use the same dialect.

A `Dialect` holds:

| Field | What it does |
|---|---|
| `name` | A name for the dialect, for example `elm-0.19.1`. |
| `rules` | The rejection rules (`Rule`) that run. |
| `operators` | The infix operator table: symbol, precedence (1 to 9), direction. |
| `reserved_words` | Extra keywords for the scanner. |
| `operator_symbols` | Extra operator symbols for the scanner. |
| `attributes` | Doc-comment attributes on (`DocComment`) or off (`Off`). |
| `core_package` | Whether the file belongs to an `elm/*` or `elm-explorations/*` package. |

The AST shape is elm-syntax 7.3.9 in every dialect.

## Compare the built-in dialects

There are two built-in dialects:

- `Dialect::elm_0_19_1()` rejects what `elm make` 0.19.1 rejects as syntax.
  It is the default.
- `Dialect::elm_syntax_7_3_9()` rejects exactly what elm-syntax 7.3.9
  rejects.

`elm make` rejects an Int literal with a leading zero, such as `007`.
elm-syntax accepts it. The `leading-zero` rule is on only in `elm-0.19.1`:

```mbt check
///|
fn di_codes(text : String, dialect : @krueger.Dialect) -> Array[String] {
  let source = @krueger.SourceText::new(text)
  @krueger.parse_module(source, dialect~).diagnostics.map(d => d.code)
}

///|
test "one input, two dialects" {
  let text = "module Main exposing (..)\n\n\nx =\n    007\n"
  let elm = @krueger.Dialect::elm_0_19_1()
  let elm_syntax = @krueger.Dialect::elm_syntax_7_3_9()
  debug_inspect(
    di_codes(text, elm),
    content=(
      #|["KR-PARSE-004"]
    ),
  )
  debug_inspect(di_codes(text, elm_syntax), content="[]")
  inspect(elm.has(LeadingZero), content="true")
  inspect(elm_syntax.has(LeadingZero), content="false")
}
```

The message names the rule that rejects the input:

```mbt check
///|
test "the rule is in the message" {
  let source = @krueger.SourceText::new(
    "module Main exposing (..)\n\n\nx =\n    007\n",
  )
  let d = @krueger.parse_module(source).diagnostics[0]
  inspect(
    d.message,
    content=(
      #|Malformed function declaration: numbers cannot start with zeros [rule: leading-zero]
    ),
  )
  inspect(@krueger.Rule::LeadingZero.name(), content="leading-zero")
}
```

The `Rule` type lists every rule, and `Rule::name` gives its name.
`Dialect::has(rule)` tells whether a dialect enables a rule.

## Mark a file of a core package

`elm make` lets only the packages `elm/*` and `elm-explorations/*` declare
infix operators and effect modules. The `elm-0.19.1` dialect rejects them in
other files. Set `core_package` to `true` when you parse a file of such a
package:

```mbt check
///|
test "core_package allows infix declarations" {
  let text =
    #|module List exposing ((::))
    #|
    #|
    #|infix right 5 (::) = cons
    #|
  let elm = @krueger.Dialect::elm_0_19_1()
  debug_inspect(
    di_codes(text, elm),
    content=(
      #|["KR-PARSE-008"]
    ),
  )
  let core = { ..elm, core_package: true, }
  debug_inspect(di_codes(text, core), content="[]")
}
```

## Turn a rule off

`{ ..d, field: value }` makes a new dialect, but the new dialect shares
`rules` and `operators` with `d`. Copy them before you change them:

```mbt check
///|
test "turn a rule off" {
  let elm = @krueger.Dialect::elm_0_19_1()
  let rules = elm.rules.copy()
  rules.remove(LeadingZero)
  let relaxed = { ..elm, name: "elm-0.19.1-relaxed", rules, }
  let text = "module Main exposing (..)\n\n\nx =\n    007\n"
  debug_inspect(di_codes(text, relaxed), content="[]")
  inspect(elm.has(LeadingZero), content="true")
}
```

## Build a dialect for an Elm-like language

An Elm-like language can have more keywords and more operators than Elm.
This dialect adds the keyword `forall` and the operator `<=>`:

- `reserved_words` makes the scanner read `forall` as a keyword, not as a
  name.
- `operator_symbols` makes the scanner read `<=>` as one token.
- An entry in `operators` gives `<=>` a precedence and a direction, so the
  parser can use it.

```mbt check
///|
fn di_custom() -> @krueger.Dialect {
  let elm = @krueger.Dialect::elm_0_19_1()
  {
    ..elm,
    name: "my-elm",
    reserved_words: ["forall"],
    operator_symbols: ["<=>"],
    operators: [
      ..elm.operators,
      { symbol: "<=>", precedence: 4, direction: Non, },
    ],
  }
}

///|
test "check a custom dialect" {
  debug_inspect(di_custom().validate(), content="[]")
}
```

`validate` gives the problems with the extension data, as messages. It is
empty when the dialect is valid. The scanner and the parser do not call it.
Call it when a dialect comes from outside your program, for example from a
configuration file. It checks these limits:

- An operator in the table must have a symbol that is not empty, and each
  symbol must be in the table only once.
- An operator precedence must be 1 to 9.
- An extra operator symbol must not be empty. It must start with a
  character that the scanner reads as a symbol (`+ - / * = . < > : & | ^ ?`).
  It must not start with `--`, because that starts a line comment.
- An extra reserved word must not be `alias`, `infix` or `effect`. The
  parser reads those words by their text.

```mbt check
///|
test "find problems in a dialect" {
  let bad = {
    ..di_custom(),
    reserved_words: ["alias"],
    operator_symbols: ["~>"],
  }
  debug_inspect(
    bad.validate(),
    content=(
      #|[
      #|  "operator symbol `~>` does not start with a symbol character",
      #|  "reserved word `alias` is a name the parser reads by its text",
      #|]
    ),
  )
}
```

The scanner reads the new keyword and the new operator:

```mbt check
///|
test "tokenize with the custom dialect" {
  let source = @krueger.SourceText::new("a <=> forall")
  guard @krueger.tokenize(source, dialect=di_custom()) is Ok(stream) else {
    fail("scan error")
  }
  debug_inspect(
    stream.tokens.map(t => t.kind),
    content=(
      #|[Identifier, Operator("<=>"), Keyword(Custom("forall"))]
    ),
  )
}
```

The parser uses the operator table:

```mbt check
///|
test "parse with the custom dialect" {
  let source = @krueger.SourceText::new(
    "module Main exposing (..)\n\n\nsame a b =\n    a <=> b\n",
  )
  let result = @krueger.parse_module(source, dialect=di_custom())
  debug_inspect(result.diagnostics, content="[]")
  guard result.ast is Some(file) else { fail("no AST") }
  guard file.declarations[0].value is FunctionDeclaration(f) else {
    fail("not a function")
  }
  guard f.declaration.value.expression.value
    is OperatorApplication(op, direction, _, _) else {
    fail("not an operator application")
  }
  inspect(op, content="<=>")
  debug_inspect(direction, content="Non")
}
```

A reserved word cannot be a name:

```mbt check
///|
test "a reserved word is not a name" {
  let text = "module Main exposing (..)\n\n\nforall =\n    1\n"
  debug_inspect(di_codes(text, @krueger.Dialect::elm_0_19_1()), content="[]")
  debug_inspect(
    di_codes(text, di_custom()),
    content=(
      #|["KR-PARSE-004"]
    ),
  )
}
```

## Use the same dialect for the scanner and the parser

`parse_module` builds the scanner and the parser with the dialect that you
give it. When you call `tokenize` and `parse_tokens` yourself, give both the
same dialect. Here the tokens come from the custom dialect, but the parser
uses the default dialect. The parser does not know `<=>`:

```mbt check
///|
test "the scanner and the parser need the same dialect" {
  let source = @krueger.SourceText::new(
    "module Main exposing (..)\n\n\nsame a b =\n    a <=> b\n",
  )
  guard @krueger.tokenize(source, dialect=di_custom()) is Ok(tokens) else {
    fail("scan error")
  }
  let mismatch = @krueger.parse_tokens(tokens)
  inspect(
    mismatch.diagnostics[0].message,
    content=(
      #|Malformed function declaration: unknown infix operator `<=>`
    ),
  )
  let matched = @krueger.parse_tokens(tokens, dialect=di_custom())
  debug_inspect(matched.diagnostics, content="[]")
}
```

The same applies to `DefaultScanner::new(dialect~)` and to
`@parser.parse_module(source, scanner, dialect~)`.

## Complete code

`my-elm` keeps the rules of `elm-0.19.1`, so it still rejects `007`:

```mbt check
///|
fn di_parse_my_elm(text : String) -> @krueger.ParseResult {
  @krueger.parse_module(@krueger.SourceText::new(text), dialect=di_custom())
}

///|
test "parse my-elm" {
  let result = di_parse_my_elm(
    (
      #|module Main exposing (..)
      #|
      #|
      #|same a b =
      #|    a <=> b
      #|
      #|
      #|count =
      #|    007
      #|
    ),
  )
  debug_inspect(
    result.diagnostics.map(d => d.code),
    content=(
      #|["KR-PARSE-004"]
    ),
  )
}
```

## See also

- [Parse your first Elm module](getting-started.mbt.md)
- [Report syntax errors](error-reports.mbt.md)
- [Read doc-comment attributes](doc-attributes.mbt.md): `Dialect.attributes`
  turns them on or off.
- API: `Dialect`, `Dialect::elm_0_19_1`, `Dialect::elm_syntax_7_3_9`,
  `Dialect::has`, `Dialect::validate`, `Rule`, `OperatorDef`,
  `standard_operators`, `tokenize`, `parse_tokens`
