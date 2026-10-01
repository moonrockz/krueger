# Parse your first Elm module

This article shows how to add krueger to a MoonBit project and parse Elm
source. You parse a module, check the diagnostics, read the module name and
the declaration names from the AST, and tokenize the source. At the end there
is a map of the packages and links to the other articles.

## Add krueger to your project

Add the module to your project:

```bash
moon add moonrockz/krueger
```

Then import the root package in the `moon.pkg` of the package that uses it:

```
import {
  "moonrockz/krueger",
}
```

The root package `@krueger` re-exports the types and the entry points that
most programs need. Import a sub-package (for example
`moonrockz/krueger/ast`) only when you need a function that the root does
not re-export, such as `@ast.encode_file`.

## Parse a module

Make a `SourceText` from the Elm text, then call `parse_module`. The
`module_name` is optional. It is the Elm module name (for example `Main`).
`render_elm_json` writes it as `name`; the parser does not use it. Give the
file path to the renderers as their `path` argument.

```mbt check
///|
fn gs_source() -> @krueger.SourceText {
  @krueger.SourceText::new(
    (
      #|module Main exposing (main)
      #|
      #|import Html
      #|
      #|
      #|type alias Name =
      #|    String
      #|
      #|
      #|greet : Name -> String
      #|greet name =
      #|    "Hello, " ++ name
      #|
      #|
      #|main =
      #|    Html.text (greet "world")
      #|
    ),
    module_name="Main",
  )
}

///|
test "parse a module" {
  let result = @krueger.parse_module(gs_source())
  inspect(result.diagnostics.length(), content="0")
}
```

`parse_module` uses the `elm-0.19.1` dialect when you do not give one. See
[Choose a dialect](dialects.mbt.md).

## Check the diagnostics

The parser does not stop at the first error. It reports each problem as a
`Diagnostic` and continues. A diagnostic with severity `Error` means that
the dialect rejects the source. In the default dialect, `elm make` rejects
it too. A `Warning` (for example a number that is too big) does not make the
source invalid.

```mbt check
///|
fn gs_has_errors(result : @krueger.ParseResult) -> Bool {
  result.diagnostics.iter().any(d => d.severity is Error)
}

///|
test "check for errors" {
  let good = @krueger.parse_module(gs_source())
  inspect(gs_has_errors(good), content="false")
  let bad = @krueger.parse_module(
    @krueger.SourceText::new("module Main exposing (..)\n\nx = (\n"),
  )
  inspect(gs_has_errors(bad), content="true")
  inspect(bad.diagnostics[0].code, content="KR-PARSE-004")
}
```

[Report syntax errors](error-reports.mbt.md) shows how to show these
diagnostics to a user.

## Read the AST

`ParseResult.ast` is an `@ast.File?`. It is `None` only when the module
header is missing or malformed, or when the source does not scan. The AST is
a mirror of [elm-syntax 7.3.9](https://package.elm-lang.org/packages/stil4m/elm-syntax/7.3.9/):
each part is a `Node` with a `range` and a `value`.

Read the module name from the module definition:

```mbt check
///|
fn gs_module_name(file : @krueger.File) -> String {
  let data = match file.module_definition.value {
    NormalModule(data) | PortModule(data) => data.module_name
    EffectModule(data) => data.module_name
  }
  data.value.iter().join(".")
}

///|
test "read the module name" {
  guard @krueger.parse_module(gs_source()).ast is Some(file) else {
    fail("no AST")
  }
  inspect(gs_module_name(file), content="Main")
}
```

Read the declaration names. Match the cases of `@ast.Declaration`:

```mbt check
///|
fn gs_declaration_name(decl : @krueger.Declaration) -> String {
  match decl {
    FunctionDeclaration(f) => f.declaration.value.name.value
    AliasDeclaration(type_alias) => type_alias.name.value
    CustomTypeDeclaration(t) => t.name.value
    PortDeclaration(signature) => signature.name.value
    InfixDeclaration(infix) => infix.operator.value
    Destructuring(_, _) => "(destructuring)"
  }
}

///|
test "read the declaration names" {
  guard @krueger.parse_module(gs_source()).ast is Some(file) else {
    fail("no AST")
  }
  let names = file.declarations.iter().map(d => gs_declaration_name(d.value))
  debug_inspect(
    names.collect(),
    content=(
      #|["Name", "greet", "main"]
    ),
  )
  let imports = file.imports
    .iter()
    .map(i => i.value.module_name.value.join("."))
  debug_inspect(
    imports.collect(),
    content=(
      #|["Html"]
    ),
  )
}
```

Ranges use 1-based rows and columns, as in elm-syntax:

```mbt check
///|
test "read a range" {
  guard @krueger.parse_module(gs_source()).ast is Some(file) else {
    fail("no AST")
  }
  let range = file.declarations[1].range
  debug_inspect(
    range,
    content=(
      #|{ start: { row: 10, column: 1 }, end: { row: 12, column: 22 } }
    ),
  )
}
```

The range of `greet` starts at its type signature.

## Tokenize the source

`tokenize` gives the tokens without parsing. The token stream is lossless:
whitespace and comments are trivia on the tokens, so the tokens and their
trivia rebuild the source. A scan error (for example an unterminated string)
gives `Err`.

```mbt check
///|
test "tokenize" {
  let source = @krueger.SourceText::new("main = greet \"world\" -- say hello\n")
  guard @krueger.tokenize(source) is Ok(stream) else { fail("scan error") }
  debug_inspect(
    stream.tokens.map(t => t.lexeme),
    content=(
      #|["main", "=", "greet", "\"world\""]
    ),
  )
  debug_inspect(
    stream.tokens.map(t => t.kind),
    content=(
      #|[Identifier, Equals, Identifier, StringLiteral]
    ),
  )
  let bad = @krueger.SourceText::new("s = \"abc\n")
  guard @krueger.tokenize(bad) is Err(errors) else { fail("no error") }
  inspect(errors.diagnostics[0].code, content="KR-SCAN-004")
}
```

## Map of the packages

| Package | What it holds |
|---|---|
| `moonrockz/krueger` | The entry points (`parse_module`, `tokenize`, `parse_tokens`), the traversals (`walk`, `fold`, `accept`) and the renderers. It re-exports the types of the other packages. |
| `moonrockz/krueger/ast` | The elm-syntax 7.3.9 AST types, and `encode_*` and `decode_*` for elm-syntax JSON. |
| `moonrockz/krueger/scanner` | The lexer: `SourceText`, `Token`, `Trivia`, `Span`, `Diagnostic`. |
| `moonrockz/krueger/parser` | The parser and `ParseResult`, and the doc-comment attributes. |
| `moonrockz/krueger/cst` | The concrete syntax tree: tokens and trivia per declaration. |
| `moonrockz/krueger/syntax` | The node model (`NodeRef`, `Tree`) and the traversals (`walk`, `fold`, `Visitor`, `EventReader`, `TreeCursor`). |
| `moonrockz/krueger/report` | The renderers: `render_plain`, `render_terminal`, `render_elm_json`, `encode_diagnostics`. |
| `moonrockz/krueger/dialect` | `Dialect`: the rejection rules, the operator table and extension data. |

## Complete code

```mbt check
///|
test "getting started: complete" {
  let result = @krueger.parse_module(gs_source())
  guard !gs_has_errors(result) else { fail("syntax errors") }
  guard result.ast is Some(file) else { fail("no AST") }
  inspect(gs_module_name(file), content="Main")
  let names = file.declarations.iter().map(d => gs_declaration_name(d.value))
  debug_inspect(
    names.collect(),
    content=(
      #|["Name", "greet", "main"]
    ),
  )
}
```

## See also

- [Build an AST explorer](ast-explorer.mbt.md)
- [Build a unist tree](unist.mbt.md)
- [Choose a traversal](traversal.mbt.md)
- [Build editor features](editor-features.mbt.md)
- [Report syntax errors](error-reports.mbt.md)
- [Read and write elm-syntax JSON](elm-syntax-json.mbt.md)
- [Choose a dialect](dialects.mbt.md)
- [Read doc-comment attributes](doc-attributes.mbt.md)
- API: `parse_module`, `tokenize`, `parse_tokens`, `ParseResult`, `Diagnostic`,
  `@ast.File`, `@ast.Declaration`
