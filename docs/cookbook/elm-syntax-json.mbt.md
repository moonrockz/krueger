# Read and write elm-syntax JSON

This article shows how to move a krueger AST to and from the JSON format of
[stil4m/elm-syntax](https://package.elm-lang.org/packages/stil4m/elm-syntax/7.3.9/)
7.3.9. You encode a parsed file, decode the JSON back, keep big Int literals
exact, and exchange the JSON with Elm tools that use elm-syntax.

The `@ast` types are a mirror of elm-syntax 7.3.9. `@ast.encode_file` writes
the same JSON as `Elm.Syntax.File.encode`, byte for byte. `@ast.decode_file`
reads what `Elm.Syntax.File.encode` writes.

## Encode a file

Parse the source, then call `@ast.encode_file`. The result is a `Json`
value. Call `stringify()` to get the text.

```mbt check
///|
fn ej_parse(text : String) -> @krueger.File raise {
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard result.ast is Some(file) else { fail("no AST") }
  file
}

///|
test "encode a file" {
  let file = ej_parse("module Main exposing (x)\n\n\nx =\n    1\n")
  let json = @ast.encode_file(file)
  guard json is Object(fields) else { fail("not an object") }
  debug_inspect(
    fields.keys().collect(),
    content=(
      #|["moduleDefinition", "imports", "declarations", "comments"]
    ),
  )
  guard fields.get("moduleDefinition") is Some(header) else {
    fail("no module definition")
  }
  inspect(
    header.stringify(),
    content=(
      #|{"range":[1,1,1,25],"value":{"type":"normal","normal":{"moduleName":{"range":[1,8,1,12],"value":["Main"]},"exposingList":{"range":[1,13,1,25],"value":{"type":"explicit","explicit":[{"range":[1,23,1,24],"value":{"type":"function","function":{"name":"x"}}}]}}}}}
    ),
  )
}
```

Each node is an object with a `range` (`[startRow, startColumn, endRow,
endColumn]`) and a `value`. A case of an Elm custom type is an object with a
`type` tag and a field that has the same name as the tag. The field names
and tags are the elm-syntax names, for example `moduleDefinition`,
`functionOrValue` and `operatorapplication`.

## Encode a part of the AST

There is an encoder for each AST type, for example `encode_declaration`,
`encode_expression`, `encode_pattern` and `encode_type_annotation`. Each one
writes the JSON of the matching elm-syntax `encode` function.

```mbt check
///|
test "encode one expression" {
  let file = ej_parse("module Main exposing (x)\n\n\nx =\n    a + 1\n")
  guard file.declarations[0].value is FunctionDeclaration(f) else {
    fail("not a function")
  }
  let body = f.declaration.value.expression.value
  inspect(
    @ast.encode_expression(body).stringify(),
    content=(
      #|{"type":"operatorapplication","operatorapplication":{"operator":"+","direction":"left","left":{"range":[5,5,5,6],"value":{"type":"functionOrValue","functionOrValue":{"moduleName":[],"name":"a"}}},"right":{"range":[5,9,5,10],"value":{"type":"integer","integer":1}}}}
    ),
  )
}
```

## Decode the JSON

`@ast.decode_file` reads a `Json` value and gives the `File` back. Parse JSON
text with `@json.parse` first. A decoded file is equal to the file that was
encoded.

```mbt check
///|
test "decode the JSON" {
  let file = ej_parse(
    (
      #|module Main exposing (main)
      #|
      #|import Html
      #|
      #|
      #|main =
      #|    Html.text "hi"
      #|
    ),
  )
  let text = @ast.encode_file(file).stringify()
  let decoded = @ast.decode_file(@json.parse(text))
  inspect(decoded == file, content="true")
}
```

JSON that does not have the elm-syntax shape raises a `DecodeError`. The
error gives the path to the bad value and a message:

```mbt check
///|
test "a decode error" {
  let bad : Json = { "moduleDefinition": 1 }
  try @ast.decode_file(bad) catch {
    e =>
      inspect(
        e,
        content=(
          #|$.moduleDefinition: Expecting an OBJECT with a field named `range` but got a NUMBER
        ),
      )
  } noraise {
    _ => fail("expected a decode error")
  }
}
```

## Keep big Int literals exact

elm-syntax writes an Int literal as a JSON number. Above 2^53 a JSON number
(a Double) cannot hold every integer, so elm-syntax writes the nearest
Double: `9007199254740993` becomes `9007199254740992`. `encode_file` does the
same, so that its output equals the output of elm-syntax. The AST keeps the
exact `Int64`.

For an exact round trip, use `encode_file_with(file, exact_ints=true)`. It
writes the exact digits. Its output differs from elm-syntax only for
literals above 2^53. `encode_declaration_with`, `encode_expression_with`,
`encode_pattern_with` and `encode_function_with` take the same flag. So does
`encode_attributes_with` (doc attributes; in `@parser` and the root package).

```mbt check
///|
test "keep big Int literals exact" {
  let file = ej_parse(
    "module Main exposing (n)\n\n\nn =\n    9007199254740993\n",
  )
  guard file.declarations[0].value is FunctionDeclaration(f) else {
    fail("not a function")
  }
  let body = f.declaration.value.expression.value
  debug_inspect(body, content="Integer(9007199254740993)")
  let like_elm = @ast.encode_file(file).stringify()
  inspect(like_elm.contains("9007199254740992"), content="true")
  let exact = @ast.encode_file_with(file, exact_ints=true).stringify()
  inspect(exact.contains("9007199254740993"), content="true")
  inspect(@ast.decode_file(@json.parse(exact)) == file, content="true")
  inspect(@ast.decode_file(@json.parse(like_elm)) == file, content="false")
}
```

The JSON from `encode_file` decodes to `9007199254740992`, so that file is
not equal to the original. The JSON from `exact_ints=true` decodes to the
original.

The decoder reads both forms. It reads the digits of a number when they are
an Int that rounds to the Double of the number. The one exception is a
number whose digits are the shortest form of its Double: the decoder reads
that number as its Double. elm-syntax writes 2^60 as `1152921504606847000`,
so the decoder reads `1152921504606847000` as the Int 2^60
(`1152921504606846976`).

## Exchange JSON with Elm tools

An Elm program that uses elm-syntax 7.3.9 reads the output of `encode_file`
with `Elm.Syntax.File.decoder`. For example, a MoonBit tool parses the
source and writes the JSON:

```mbt check
///|
fn ej_to_elm_syntax_json(text : String) -> String? {
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard !result.diagnostics.iter().any(d => d.severity is Error) else { None }
  result.ast.map(file => @ast.encode_file(file).stringify())
}

///|
test "write JSON for an Elm tool" {
  let valid = "module Main exposing (..)\n\n\nx =\n    1\n"
  let json = ej_to_elm_syntax_json(valid)
  inspect(json is Some(_), content="true")
  let broken = ej_to_elm_syntax_json("module Main exposing (..)\n\n\nx = (\n")
  inspect(broken is None, content="true")
}
```

The Elm side decodes it:

```elm
import Elm.Syntax.File
import Json.Decode

readFile : String -> Result Json.Decode.Error Elm.Syntax.File.File
readFile json =
    Json.Decode.decodeString Elm.Syntax.File.decoder json
```

In the other direction, an Elm tool writes a file with
`Elm.Syntax.File.encode`, and `@ast.decode_file` reads it.

An Elm program can read both encodings. JavaScript reads a JSON number as a
Double, so Elm gets the nearest Double for a big literal in both cases. Use
the default `encode_file` when you compare the output with elm-syntax byte
for byte. Use `exact_ints=true` when krueger reads the JSON back.

## Complete code

```mbt check
///|
test "round trip through elm-syntax JSON" {
  let file = ej_parse(
    (
      #|module Shapes exposing (Shape(..), area)
      #|
      #|
      #|type Shape
      #|    = Circle Float
      #|    | Square Float
      #|
      #|
      #|area : Shape -> Float
      #|area shape =
      #|    case shape of
      #|        Circle r ->
      #|            pi * r * r
      #|
      #|        Square s ->
      #|            s * s
      #|
    ),
  )
  let text = @ast.encode_file_with(file, exact_ints=true).stringify()
  let decoded = @ast.decode_file(@json.parse(text))
  inspect(decoded == file, content="true")
}
```

## See also

- [Parse your first Elm module](getting-started.mbt.md)
- [Build an AST explorer](ast-explorer.mbt.md)
- [Report syntax errors](error-reports.mbt.md): `encode_diagnostics` and
  `render_elm_json` write JSON for diagnostics.
- [Read doc-comment attributes](doc-attributes.mbt.md): `encode_attributes`
  and `encode_attributes_with`.
- API: `@ast.encode_file`, `@ast.encode_file_with`, `@ast.decode_file`,
  `@ast.DecodeError`, `@ast.encode_declaration`, `@ast.encode_expression`
