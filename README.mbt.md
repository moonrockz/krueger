# moonrockz/krueger

Parser and parsing utilities for [Elm](https://elm-lang.org/) and Elm-like
dialects (such as [Morphir](https://github.com/finos/morphir)) in MoonBit.

krueger parses Elm 0.19.1 source into an exact mirror of the
[stil4m/elm-syntax](https://package.elm-lang.org/packages/stil4m/elm-syntax/7.3.9/)
7.3.9 AST. On a corpus of 363 files from published packages, its JSON output
is byte for byte the same as elm-syntax's.

- **Scanner**: lossless tokens. The trivia (whitespace and comments) and the
  lexemes of the tokens give back the source text.
- **Parser**: tokens to AST, a concrete syntax tree (CST) and diagnostics. A
  declaration that does not parse is left out and reported; the rest of the
  file is parsed.
- **AST**: elm-syntax 7.3.9 types, with a JSON encoder and decoder that match
  elm-syntax.
- **Diagnostics**: `elm make`-style error reports (terminal, plain text, and
  the `elm make --report=json` shape).
- **Syntax tree**: a read-only node model with parent links, position lookup,
  and six traversal styles: `walk`, `fold`, `Visitor`, pull events, push
  events and a cursor.
- **Dialects**: the rules of `elm make` 0.19.1 or of elm-syntax 7.3.9, and
  hooks for Elm-like languages.
- **Doc-comment attributes**: `@name value` data in doc comments, read into
  the parse result.

## Installation

```bash
moon add moonrockz/krueger
```

Then import it in your package's `moon.pkg`:

```
import {
  "moonrockz/krueger",
}
```

## Usage

Parse a module and read the names of its declarations:

```mbt
test "parse a module" {
  let source = @krueger.SourceText::new(
    "module Main exposing (main)\n\nmain =\n    greet \"world\"\n",
  )
  let result = @krueger.parse_module(source)
  guard result.diagnostics.is_empty() else { fail("syntax errors") }
  guard result.ast is Some(file) else { fail("no AST") }
  for declaration in file.declarations {
    match declaration.value {
      FunctionDeclaration(f) => println(f.declaration.value.name.value)
      _ => ()
    }
  }
}
```

Show a syntax error the way `elm make` does:

```mbt
test "report an error" {
  let source = @krueger.SourceText::new("module Main exposing (..)\n\nx = (1, \n")
  let result = @krueger.parse_module(source)
  for diagnostic in result.diagnostics {
    println(@krueger.render_plain(diagnostic, source, "src/Main.elm"))
  }
}
```

Visit every expression with the syntax tree:

```mbt
test "count expressions" {
  let result = @krueger.parse_module(
    @krueger.SourceText::new("module Main exposing (..)\n\nx = f 1 2\n"),
  )
  guard @krueger.NodeRef::of_result(result) is Some(root) else { return }
  let count = @krueger.fold(root, 0, (n, node) => {
    (if node.category() == "expression" { n + 1 } else { n }, Continue)
  })
  println(count)
}
```

## Print Elm source

```moonbit
let result = @krueger.parse_module(@krueger.SourceText::new(source))
guard result.ast is Some(file) else { return }
let text = @krueger.print_file(file) // elm-format layout, width 120
```

`print_file` raises `PrintError` when the AST cannot print as valid Elm. The
error's `path` leads to the bad node.

See [Generate Elm code](https://github.com/moonrockz/krueger/blob/main/docs/cookbook/generate-elm.mbt.md)
for ASTs built in code.

## Documentation

- [Cookbook](https://github.com/moonrockz/krueger/blob/main/docs/cookbook/README.md):
  task articles, such as building an AST explorer, converting to a unist
  tree, writing a lint rule and editor features. Their code is tested.
- API reference: the doc comments on
  [mooncakes.io](https://mooncakes.io/docs/moonrockz/krueger). Most entry
  points have a tested example.

## Development

See [AGENTS.md](https://github.com/moonrockz/krueger/blob/main/AGENTS.md)
for the architecture, the parity and rejection checks, and the mise tasks. Install the git hooks with:

```bash
mise run hooks:install
```

## License

Apache-2.0
