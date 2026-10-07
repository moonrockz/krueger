# Format Elm source

This article shows how to format Elm source with krueger. `format` writes
the text that elm-format 0.8.7 writes, and keeps every comment. It does
not need elm-format or Node.

## Format a file

`format(source)` parses the source and prints it in the elm-format
layout. The line breaks come from the source, as in elm-format: a
construct that has a line break in the source is multi-line, and one
that has none stays on one line. There is no line width.

```mbt check
///|
test "format a module" {
  let source =
    #|module Main exposing (main, Model)
    #|import Html exposing (text)
    #|-- The entry point.
    #|main = text (greeting "World") -- shown on the page
    #|greeting name = "Hello, " ++ name
    #|type alias Model = { count : Int,
    #|  step : Int }
  inspect(
    @krueger.format(source),
    content=(
      #|module Main exposing (Model, main)
      #|
      #|import Html exposing (text)
      #|
      #|
      #|
      #|-- The entry point.
      #|
      #|
      #|main =
      #|    text (greeting "World")
      #|
      #|
      #|
      #|-- shown on the page
      #|
      #|
      #|greeting name =
      #|    "Hello, " ++ name
      #|
      #|
      #|type alias Model =
      #|    { count : Int
      #|    , step : Int
      #|    }
      #|
    ),
  )
}
```

The output has elm-format's order and shapes:

- The exposed items are sorted (types, then values), and the imports are
  sorted by module name.
- Every declaration body starts on the next line, indented by 4.
- The record type was broken in the source, so it is multi-line.
- Each comment is where elm-format puts it. A comment after the last
  line of a function body goes after the declaration, between blank
  lines, as a top-level comment.

Formatting the output again gives the same text, except for a few doc
comments on which elm-format itself is not idempotent (see
`normalize_file`).

## Choose a layout

`layout=Width(n)` ignores the line breaks of the source. A construct is
multi-line only when it does not fit in `n` columns, as in `print_file`.
Comments stay in both layouts.

```mbt check
///|
let fm_source : String =
  #|module Main exposing (items)
  #|
  #|
  #|items =
  #|    [ "apple"
  #|    , "banana" -- yellow
  #|    , "cherry"
  #|    ]

///|
test "the source decides the line breaks in the ElmFormat layout" {
  inspect(
    @krueger.format(fm_source),
    content=(
      #|module Main exposing (items)
      #|
      #|
      #|items =
      #|    [ "apple"
      #|    , "banana" -- yellow
      #|    , "cherry"
      #|    ]
      #|
    ),
  )
}

///|
test "the width decides the line breaks in the Width layout" {
  inspect(
    @krueger.format(fm_source, layout=Width(80)),
    content=(
      #|module Main exposing (items)
      #|
      #|
      #|items =
      #|    [ "apple"
      #|    , "banana" -- yellow
      #|    , "cherry"
      #|    ]
      #|
    ),
  )
}
```

The line comment after `"banana"` ends its line, so the list is
multi-line in both layouts.

## Handle a syntax error

`format` raises `ParseFailed(diagnostics)` when the source has a syntax
error. The diagnostics are the errors of the parse. Render them as
`elm make` does with `render_plain` (or `render_terminal` for a terminal
with colors).

```mbt check
///|
/// The formatted text, or the syntax errors as `elm make` writes them.
fn fm_format_file(path : String, text : String) -> Result[String, String] {
  try @krueger.format(text) catch {
    ParseFailed(diagnostics) => {
      let source = @krueger.SourceText::new(text)
      Err(
        diagnostics
        .map(d => @krueger.render_plain(d, source, path))
        .join("\n\n"),
      )
    }
    Unprintable(_) => Err("\{path}: cannot print the parsed file")
  } noraise {
    formatted => Ok(formatted)
  }
}

///|
test "report a syntax error" {
  let result = fm_format_file(
    "src/Main.elm", "module Main exposing (main)\n\nmain = (1 +\n",
  )
  guard result is Err(report) else { fail("expected a syntax error") }
  inspect(
    report,
    content=(
      #|-- MISSING EXPRESSION --------------------------------------------- src/Main.elm
      #|
      #|I just saw an operator, so I am getting stuck here:
      #|
      #|3| main = (1 +
      #|              ^
      #|I was expecting to see an expression next.
      #|
    ),
  )
}
```

`format` raises `Unprintable` when the source parses but the printer
cannot print it, for example a comment that it cannot place. This is
rare. `format` never drops a comment without an error.

## Format a parse result

When you already have a parse result, `format_parsed(result)` formats it
without a second parse. Give the dialect that parsed it.

```mbt check
///|
test "format a parse result" {
  let result = @krueger.parse_module(
    @krueger.SourceText::new("module Main exposing (x)\n\nx = 1\n"),
  )
  inspect(
    @krueger.format_parsed(result),
    content=(
      #|module Main exposing (x)
      #|
      #|
      #|x =
      #|    1
      #|
    ),
  )
}
```

## What `format` changes

- Line breaks and indentation, as elm-format writes them (see
  [Choose a layout](#choose-a-layout)).
- The order of exposed items and imports; duplicate exposed items and
  duplicate imports are merged.
- Parentheses that neither the parser nor elm-format needs go
  (`case (f x) of` gives `case f x of`).
- Literals take elm-format's form (`0xff` gives `0xFF`).
- Doc comments: the Markdown is written as elm-format writes it, and Elm
  code in them is formatted.
- Block comments: the spaces after `{-` and before `-}` and the common
  indentation of the lines go (`{-a-}` gives `{- a -}`).

To get the AST that `format` prints, without the text, use
`normalize_file`. See [Generate Elm code](generate-elm.mbt.md) to print an
AST that you build in code.
