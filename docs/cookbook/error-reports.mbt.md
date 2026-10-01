# Report syntax errors

This article shows how to find syntax errors in Elm source and show them to a
user. You read the fields of a `Diagnostic`, render it as text like
`elm make` does, render it as `elm make --report=json` output, and encode it as
krueger's own JSON. You also see how the parser recovers: it leaves out a
declaration that does not parse and continues with the next one.

## Parse broken code

This module has three declarations. The second one is not complete.

```mbt check
///|
fn er_source() -> @krueger.SourceText {
  @krueger.SourceText::new(
    (
      #|module Main exposing (..)
      #|
      #|
      #|add a b =
      #|    a + b
      #|
      #|
      #|broken =
      #|    (1 +
      #|
      #|
      #|double x =
      #|    x * 2
      #|
    ),
    module_name="Main",
  )
}

///|
test "parse broken code" {
  let result = @krueger.parse_module(er_source())
  inspect(result.diagnostics.length(), content="1")
}
```

## Read a diagnostic

Each `Diagnostic` has these fields:

| Field | What it holds |
|---|---|
| `code` | krueger's code, for example `KR-PARSE-004`. |
| `severity` | `Error`, `Warning` or `Info`. |
| `title` | The `elm make` title for the same problem, for example `UNFINISHED PARENTHESES`. |
| `message` | A one-line summary. |
| `span` | Where the problem is: start and end `Position` (offset, line, column). |
| `report` | The long message as blocks (`Text`, `Excerpt`, `Hint`, `Note`, `Example`). |

```mbt check
///|
test "read a diagnostic" {
  let result = @krueger.parse_module(er_source())
  let d = result.diagnostics[0]
  inspect(d.code, content="KR-PARSE-004")
  debug_inspect(d.severity, content="Error")
  inspect(d.title, content="UNFINISHED PARENTHESES")
  inspect(
    d.message,
    content=(
      #|Malformed function declaration: `double` must be indented more [rule: indented-continuation]
    ),
  )
  debug_inspect(
    d.span,
    content=(
      #|{
      #|  start: { offset: 70, line: 12, column: 1 },
      #|  end: { offset: 76, line: 12, column: 7 },
      #|}
    ),
  )
}
```

Lines and columns in a `Position` start at 1. The offset counts UTF-16 code
units from the start of the text.

The `span` is the token where the parser stopped: here `double`, which is
not indented. The excerpt in the `report` shows the construct that is not
complete, as `elm make` does. Use the first `Excerpt` block of the report
when you need the same place that `elm make` shows.

## Know the codes

A code starts with `KR-SCAN` for a problem that the scanner finds, and with
`KR-PARSE` for a problem that the parser finds. `KR-ATTR-001` is a warning
about a doc-comment attribute. `diagnostic_description` gives a short
description of each code:

```mbt check
///|
test "describe the codes" {
  let describe = @krueger.diagnostic_description
  debug_inspect(
    describe("KR-SCAN-004"),
    content=(
      #|Some("Unterminated string, char or GLSL literal")
    ),
  )
  debug_inspect(
    describe("KR-PARSE-004"),
    content=(
      #|Some("Malformed function declaration")
    ),
  )
  debug_inspect(
    describe("KR-PARSE-009"),
    content=(
      #|Some("Number literal out of range (warning)")
    ),
  )
  debug_inspect(describe("KR-NONE-000"), content="None")
}
```

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
| `KR-PARSE-005` | Unsupported syntax (reserved; not emitted at the moment) |
| `KR-PARSE-006` | Missing module header (no AST) |
| `KR-PARSE-007` | Unexpected syntax that elm-syntax rejects (skipped tokens, stray doc comments) |
| `KR-PARSE-008` | Syntax error in a port or infix declaration |
| `KR-PARSE-009` | Number literal out of range (warning; the value is clamped) |
| `KR-ATTR-001` | Malformed doc attribute (warning; the attribute is skipped) |

Only an `Error` makes the source invalid. A `Warning` such as `KR-PARSE-009`
keeps the declaration in the AST:

```mbt check
///|
test "a warning keeps the declaration" {
  let result = @krueger.parse_module(
    @krueger.SourceText::new(
      "module Main exposing (..)\n\n\nbig =\n    99999999999999999999\n",
    ),
  )
  debug_inspect(
    result.diagnostics.map(d => d.code),
    content=(
      #|["KR-PARSE-009"]
    ),
  )
  debug_inspect(result.diagnostics.map(d => d.severity), content="[Warning]")
  guard result.ast is Some(file) else { fail("no AST") }
  inspect(file.declarations.length(), content="1")
}
```

## Use the recovered AST

The parser does not stop at the first error. It leaves the bad declaration
out of the AST and the CST, and parses the rest. Here `broken` is left out,
and `add` and `double` are in the AST:

```mbt check
///|
fn er_function_names(file : @krueger.File) -> Array[String] {
  file.declarations
  .iter()
  .filter_map(d => {
    match d.value {
      FunctionDeclaration(f) => Some(f.declaration.value.name.value)
      _ => None
    }
  })
  .collect()
}

///|
test "the parser recovers" {
  let result = @krueger.parse_module(er_source())
  guard result.ast is Some(file) else { fail("no AST") }
  debug_inspect(
    er_function_names(file),
    content=(
      #|["add", "double"]
    ),
  )
}
```

The AST is `None` when the module header is missing or malformed, and when
the source does not scan (a `KR-SCAN-*` error):

```mbt check
///|
test "no AST without a module header" {
  let no_header = @krueger.parse_module(@krueger.SourceText::new("x = 1\n"))
  debug_inspect(
    no_header.diagnostics.map(d => d.code),
    content=(
      #|["KR-PARSE-006"]
    ),
  )
  inspect(no_header.ast is None, content="true")
  let no_scan = @krueger.parse_module(
    @krueger.SourceText::new("module Main exposing (..)\n\n\ns = \"abc\n"),
  )
  debug_inspect(
    no_scan.diagnostics.map(d => d.code),
    content=(
      #|["KR-SCAN-004"]
    ),
  )
  inspect(no_scan.ast is None, content="true")
}
```

## Render as plain text

`render_plain(diagnostic, source, path)` gives the `elm make` layout: a
`-- TITLE ---- path` header, the text reflowed to 80 columns, and a source
excerpt with `^` markers. `path` goes in the header.

```mbt check
///|
test "render as plain text" {
  let source = er_source()
  let result = @krueger.parse_module(source)
  let d = result.diagnostics[0]
  let text = @krueger.render_plain(d, source, "src/Main.elm")
  inspect(
    text,
    content=(
      #|-- UNFINISHED PARENTHESES ----------------------------------------- src/Main.elm
      #|
      #|I was partway through parsing an expression in parentheses, but I got stuck
      #|here:
      #|
      #|9|     (1 +
      #|           ^
      #|I was expecting double to be indented more. Try adding some spaces before it?
      #|
    ),
  )
}
```

## Render for a terminal

`render_terminal` gives the same text with ANSI colors, for a terminal that
shows them. Remove the escape codes and you get the plain text:

```mbt check
///|
fn er_strip_ansi(text : String) -> String {
  let sb = StringBuilder()
  let mut in_escape = false
  for c in text {
    if in_escape {
      if c == 'm' {
        in_escape = false
      }
    } else if c == '\u{1b}' {
      in_escape = true
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
test "render for a terminal" {
  let source = er_source()
  let d = @krueger.parse_module(source).diagnostics[0]
  let colored = @krueger.render_terminal(d, source, "src/Main.elm")
  inspect(colored.contains("\u{1b}["), content="true")
  inspect(
    er_strip_ansi(colored) == @krueger.render_plain(d, source, "src/Main.elm"),
    content="true",
  )
}
```

## Render as elm make JSON

`render_elm_json(diagnostics, source, path)` gives the shape of
`elm make --report=json`. Tools that read Elm compiler output (editor
plugins, CI annotations) can read it. It leaves out warnings, because
`elm make` has none. The `path` field is the `path` argument. The `name`
field is the Elm module name from `SourceText.module_name` (default `Main`).

```mbt check
///|
test "render as elm make JSON" {
  let source = er_source()
  let result = @krueger.parse_module(source)
  let path = "src/Main.elm"
  let json = @krueger.render_elm_json(result.diagnostics, source, path)
  inspect(
    json.stringify(indent=2),
    content=(
      #|{
      #|  "type": "compile-errors",
      #|  "errors": [
      #|    {
      #|      "path": "src/Main.elm",
      #|      "name": "Main",
      #|      "problems": [
      #|        {
      #|          "title": "UNFINISHED PARENTHESES",
      #|          "region": {
      #|            "start": {
      #|              "line": 9,
      #|              "column": 9
      #|            },
      #|            "end": {
      #|              "line": 9,
      #|              "column": 9
      #|            }
      #|          },
      #|          "message": [
      #|            "I was partway through parsing an expression in parentheses, but I got stuck\nhere:\n\n9|     (1 +\n           ",
      #|            {
      #|              "bold": false,
      #|              "underline": false,
      #|              "color": "RED",
      #|              "string": "^"
      #|            },
      #|            "\nI was expecting ",
      #|            {
      #|              "bold": false,
      #|              "underline": false,
      #|              "color": "yellow",
      #|              "string": "double"
      #|            },
      #|            " to be indented more. Try adding some spaces before it?"
      #|          ]
      #|        }
      #|      ]
      #|    }
      #|  ]
      #|}
    ),
  )
}
```

## Encode krueger's JSON

`encode_diagnostics` gives every diagnostic, warnings too, with krueger's
codes, severities and spans:

```mbt check
///|
test "encode krueger's JSON" {
  let result = @krueger.parse_module(er_source())
  let json = @krueger.encode_diagnostics(result.diagnostics)
  inspect(
    json.stringify(indent=2),
    content=(
      #|[
      #|  {
      #|    "code": "KR-PARSE-004",
      #|    "severity": "error",
      #|    "title": "UNFINISHED PARENTHESES",
      #|    "message": "Malformed function declaration: `double` must be indented more [rule: indented-continuation]",
      #|    "span": {
      #|      "start": {
      #|        "line": 12,
      #|        "column": 1
      #|      },
      #|      "end": {
      #|        "line": 12,
      #|        "column": 7
      #|      }
      #|    }
      #|  }
      #|]
    ),
  )
}
```

## Complete code

This function parses a file and gives one text report for all its errors.
It gives `None` when the file has no errors.

```mbt check
///|
fn er_report(text : String, path : String) -> String? {
  let source = @krueger.SourceText::new(text)
  let errors = @krueger.parse_module(source).diagnostics.filter(d => {
    d.severity is Error
  })
  guard !errors.is_empty() else { None }
  Some(errors.map(d => @krueger.render_plain(d, source, path)).join("\n\n"))
}

///|
test "report all errors" {
  let valid = "module Main exposing (..)\n\n\nx =\n    1\n"
  inspect(er_report(valid, "src/Main.elm") is None, content="true")
  guard er_report(er_source().text, "src/Main.elm") is Some(report) else {
    fail("no report")
  }
  inspect(report.has_prefix("-- "), content="true")
}
```

## See also

- [Parse your first Elm module](getting-started.mbt.md)
- [Choose a dialect](dialects.mbt.md): the dialect decides what is an error.
- [Read doc-comment attributes](doc-attributes.mbt.md): `KR-ATTR-001`.
- API: `Diagnostic`, `Severity`, `Span`, `Block`, `Chunk`, `render_plain`,
  `render_terminal`, `render_elm_json`, `encode_diagnostics`,
  `diagnostic_description`
